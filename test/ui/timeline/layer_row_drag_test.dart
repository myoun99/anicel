import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart' show EffectKind;
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;
import 'package:anicel/src/ui/timeline/held_row_pin.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show SectionBandZone;
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';
import 'package:anicel/src/ui/timeline/timeline_row_edges.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/row_folds.dart';

/// The row-order drag, driven as a real gesture: the rail row IS the
/// handle, the caret says where the row would land, and the release commits
/// the same plan a menu step would.

Project _project() {
  return Project(
    id: const ProjectId('drag-project'),
    name: 'Drag Project',
    createdAt: DateTime.utc(2026, 8, 7),
    tracks: [
      Track(
        id: const TrackId('drag-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('drag-cut'),
            name: 'Drag Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              // Model order, bottom → top. The rail renders it reversed.
              Layer(id: const LayerId('a'), name: 'A', frames: const []),
              Layer(id: const LayerId('b'), name: 'B', frames: const []),
              Layer(id: const LayerId('c'), name: 'C', frames: const []),
              Layer(
                id: const LayerId('cam'),
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// The same stack with an attach GROUP in the middle: `over` rides `base`,
/// so the slot between them is the group's INSIDE.
Project _groupProject() {
  return Project(
    id: const ProjectId('drag-project'),
    name: 'Drag Project',
    createdAt: DateTime.utc(2026, 8, 8),
    tracks: [
      Track(
        id: const TrackId('drag-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('drag-cut'),
            name: 'Drag Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              Layer(id: const LayerId('a'), name: 'A', frames: const []),
              Layer(id: const LayerId('base'), name: 'B', frames: const []),
              Layer(
                id: const LayerId('over'),
                name: 'B+1',
                frames: const [],
                attachedToLayerId: const LayerId('base'),
              ),
              Layer(id: const LayerId('c'), name: 'C', frames: const []),
              Layer(
                id: const LayerId('cam'),
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// F-312's scene: two attach groups FACING each other, a loose row on each
/// side. Rail top-down: Camera, P, B2, B2-1, B1+1, B1, Q.
Project _facingGroupsProject() {
  return Project(
    id: const ProjectId('drag-project'),
    name: 'Drag Project',
    createdAt: DateTime.utc(2026, 10, 7),
    tracks: [
      Track(
        id: const TrackId('drag-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('drag-cut'),
            name: 'Drag Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              Layer(id: const LayerId('q'), name: 'Q', frames: const []),
              Layer(id: const LayerId('b1'), name: 'B1', frames: const []),
              Layer(
                id: const LayerId('b1up'),
                name: 'B1+1',
                frames: const [],
                attachedToLayerId: const LayerId('b1'),
              ),
              Layer(
                id: const LayerId('b2down'),
                name: 'B2-1',
                frames: const [],
                attachedToLayerId: const LayerId('b2'),
                attachedPlacement: AttachedPlacement.below,
              ),
              Layer(id: const LayerId('b2'), name: 'B2', frames: const []),
              Layer(id: const LayerId('p'), name: 'P', frames: const []),
              Layer(
                id: const LayerId('cam'),
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

Layer _layerOf(EditorSessionManager session, String id) => session
    .requireActiveCut
    .layers
    .firstWhere((layer) => layer.id == LayerId(id));

List<String> _order(EditorSessionManager session) => [
  for (final layer in session.requireActiveCut.layers)
    if (layer.kind == LayerKind.animation) layer.id.value,
];

Future<void> _pump(WidgetTester tester, {Project? project}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: project ?? _project())),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -400),
  );
  await tester.pumpAndSettle();
}

Finder _railRow(String id) =>
    find.named('timeline-layer-row-$id');

/// Where a rail row is GRABBED: its name — the part of the row that only
/// ever means the row. ⛔Not the row's centre: the rail's columns decide
/// what sits there, and when the opacity column widened to hold OPAC
/// (text-scale-rail-opac, 유저 2026-09-25) a drawing row's centre became its
/// fill-reference button, which owns the press.
Finder _railRowGrip(String id) =>
    find.named('timeline-layer-name-$id');

/// ⑨ (user, 2026-08-12): 「첫 드래그가 선택(1개/여러 개), 그 다음이 드래그」.
///
/// So every MOVE below selects its row first. The nudge goes SIDEWAYS: the
/// pan has to clear the touch slop to start at all (20px, most of a row),
/// while only the rail's own axis counts as travel — so a horizontal push
/// selects exactly the row it began on and nothing else.
Future<void> _selectRow(WidgetTester tester, Finder row) async {
  await tester.drag(row, const Offset(30, 0));
  await tester.pumpAndSettle();
}

/// A stack with an EMPTY folder on top — the case R5 #14 created and R5 #15
/// exists to reach: a folder with no members has no gap that means "inside
/// it", so a caret can never put anything there.
Project _emptyFolderProject() {
  return Project(
    id: const ProjectId('folder-drop-project'),
    name: 'Folder Drop',
    createdAt: DateTime.utc(2026, 8, 9),
    tracks: [
      Track(
        id: const TrackId('drag-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('drag-cut'),
            name: 'Drag Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              Layer(id: const LayerId('a'), name: 'A', frames: const []),
              Layer(id: const LayerId('b'), name: 'B', frames: const []),
              Layer(id: const LayerId('c'), name: 'C', frames: const []),
              createFolderLayer(id: const LayerId('f'), name: 'F'),
            ],
          ),
        ],
      ),
    ],
  );
}

/// F-50: a folder WITH a member, for the drop the user says went missing —
/// 「일반폴더를 레이어에 어태치장착시키는거」.
Project _folderWithMemberProject() {
  return Project(
    id: const ProjectId('folder-mount-project'),
    name: 'Folder Mount',
    createdAt: DateTime.utc(2026, 8, 29),
    tracks: [
      Track(
        id: const TrackId('drag-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('drag-cut'),
            name: 'Drag Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              Layer(id: const LayerId('a'), name: 'A', frames: const []),
              Layer(id: const LayerId('b'), name: 'B', frames: const []),
              Layer(id: const LayerId('c'), name: 'C', frames: const []),
              Layer(
                id: const LayerId('m'),
                name: 'M',
                frames: const [],
                folderId: const LayerId('f'),
              ),
              createFolderLayer(id: const LayerId('f'), name: 'F'),
            ],
          ),
        ],
      ),
    ],
  );
}

/// One cut holding [layers] (model order, bottom → top) under a camera.
Project _stackProject(List<Layer> layers) {
  return Project(
    id: const ProjectId('drag-project'),
    name: 'Drag Project',
    createdAt: DateTime.utc(2026, 10, 18),
    tracks: [
      Track(
        id: const TrackId('drag-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('drag-cut'),
            name: 'Drag Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              ...layers,
              Layer(
                id: const LayerId('cam'),
                name: 'Camera',
                kind: LayerKind.camera,
                frames: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// A folder of two over a loose row. Rail top-down: Camera, X, F, M2, M1, A.
Project _folderMembersProject() => _stackProject([
  Layer(id: const LayerId('a'), name: 'A', frames: const []),
  Layer(
    id: const LayerId('m1'),
    name: 'M1',
    frames: const [],
    folderId: const LayerId('f'),
  ),
  Layer(
    id: const LayerId('m2'),
    name: 'M2',
    frames: const [],
    folderId: const LayerId('f'),
  ),
  createFolderLayer(id: const LayerId('f'), name: 'F'),
  Layer(id: const LayerId('x'), name: 'X', frames: const []),
]);

/// The same folder with nothing loose above it. Rail top-down: Camera,
/// transitions, F, M2, M1, A.
Project _topFolderProject() => _stackProject([
  Layer(id: const LayerId('a'), name: 'A', frames: const []),
  Layer(
    id: const LayerId('m1'),
    name: 'M1',
    frames: const [],
    folderId: const LayerId('f'),
  ),
  Layer(
    id: const LayerId('m2'),
    name: 'M2',
    frames: const [],
    folderId: const LayerId('f'),
  ),
  createFolderLayer(id: const LayerId('f'), name: 'F'),
]);

/// The conte with a row riding it on each side, two loose rows above.
/// Rail top-down: Camera, B, A, Conte+1, Conte, Conte-1.
Project _conteGroupProject() => _stackProject([
  Layer(
    id: const LayerId('under'),
    name: 'Conte-1',
    kind: LayerKind.storyboard,
    frames: const [],
    attachedToLayerId: const LayerId('conte'),
    attachedPlacement: AttachedPlacement.below,
  ),
  Layer(
    id: const LayerId('conte'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    frames: const [],
  ),
  Layer(
    id: const LayerId('over'),
    name: 'Conte+1',
    kind: LayerKind.storyboard,
    frames: const [],
    attachedToLayerId: const LayerId('conte'),
  ),
  Layer(id: const LayerId('a'), name: 'A', frames: const []),
  Layer(id: const LayerId('b'), name: 'B', frames: const []),
]);

void main() {
  testWidgets('dragging a rail row up moves it up the stack', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    expect(_order(session), ['a', 'b', 'c']);

    // The rail renders the stack reversed, so the row for 'a' sits at the
    // BOTTOM. ④: the caret is the gap the POINTER is nearest, so one place
    // means putting the pointer ON the next boundary up — one and a half
    // rows from a grab in this row's middle. (It also has to clear the
    // middle band, which belongs to the on-row drop; landing exactly on the
    // boundary does both.)
    final row = _railRowGrip('a');
    await tester.ensureVisible(row);
    await _selectRow(tester, row);
    await tester.pumpAndSettle();
    await tester.drag(row, const Offset(0, -42));
    await tester.pumpAndSettle();

    expect(_order(session), ['b', 'a', 'c']);
  });

  testWidgets('the caret shows where it would land, and a release outside '
      'any legal slot leaves the stack alone', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    final row = _railRowGrip('a');
    await tester.ensureVisible(row);
    await _selectRow(tester, row);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 16));

    // ④: nothing yet — the press alone must not draw a caret over the row's
    // own gap, and a NUDGE that leaves the pointer inside its own row must
    // not either.
    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-before-b')),
      findsNothing,
    );
    await gesture.moveBy(const Offset(0, -12));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-before-b')),
      findsNothing,
      reason: 'the pointer has not reached the middle of the row above',
    );

    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-before-b')),
      findsOneWidget,
      reason: 'the caret sits on the boundary the row would land on',
    );

    // Back to where it started: no move, so no caret and no command.
    await gesture.moveBy(const Offset(0, 42));
    await tester.pump();
    expect(find.byType(EditorWorkspace), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_order(session), ['a', 'b', 'c']);
  });

  testWidgets('F-31①: the caret sits ON the row boundary, not inside a row '
      '— 유저 2026-08-28: 「가로선이 이상한 위치에 있다」', (tester) async {
    await _pump(tester);
    final row = _railRowGrip('a');
    await tester.ensureVisible(row);
    await _selectRow(tester, row);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -42));
    await tester.pump();

    final caret = find.byKey(
      const ValueKey<String>('timeline-row-caret-before-b'),
    );
    expect(caret, findsOneWidget);
    // The line the user sees is the BAR, not the badge beside it: measuring
    // the caret widget whole would pass on a bar drawn anywhere as long as
    // the label reached the edge (R‑lesson: 계측기를 먼저 의심하라).
    final bar = find.descendant(
      of: caret,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxHeight == 2,
      ),
    );
    expect(bar, findsOneWidget);
    final barRect = tester.getRect(bar);
    final rowRect = tester.getRect(_railRow('b'));
    expect(
      barRect.center.dy,
      moreOrLessEquals(rowRect.top, epsilon: 1.5),
      reason:
          'the bar must straddle the boundary; a bar inside the row would '
          'overlap the layer, which is what F-31① reported',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('dragging DOWN moves it down — a row sits between two gaps '
      'that are both where it already is', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    expect(_order(session), ['a', 'b', 'c']);

    // 'c' is the TOP row of the rail. ④ made the two directions the same
    // question — "which gap is the pointer nearest" — so this reads exactly
    // like the upward case, same distance, opposite sign.
    final row = _railRowGrip('c');
    await tester.ensureVisible(row);
    await _selectRow(tester, row);
    await tester.pumpAndSettle();
    await tester.drag(row, const Offset(0, 42));
    await tester.pumpAndSettle();

    expect(_order(session), ['a', 'c', 'b']);
  });

  testWidgets('dragging an fx HEADER re-orders that layer\'s chain', (
    tester,
  ) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    session.selectLayer(const LayerId('b'));
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.values.first);
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.values[1]);
    await tester.pumpAndSettle();

    List<EffectKind> chain() => [
      for (final effect
          in session.requireActiveCut.layers
              .firstWhere((layer) => layer.id == const LayerId('b'))
              .effects)
        effect.kind,
    ];
    final before = chain();
    expect(before.length, 2);

    // The add shows the row's lanes and each new header open (F-396); the
    // headers are shut again so one row's drag carries the first past the
    // second.
    final effects = session.requireActiveCut.layers
        .firstWhere((layer) => layer.id == const LayerId('b'))
        .effects;
    for (final effect in effects) {
      session.layerSwitches.setLayerLaneGroupExpanded(
        const LayerId('b'),
        effectGroupLaneId(effect.id),
        expanded: false,
      );
    }
    await tester.pumpAndSettle();

    final firstId = effects.first.id;
    final header = find.byKey(
      ValueKey<String>('timeline-lane-label-b-fx-group:${firstId.value}'),
    );
    // Taken by its label, as a layer row by its name ([_railRowGrip]): the
    // header wears the layer row's trailing skeleton, and its centre is the
    // group's Reset since the opacity column widened.
    final grip = find
        .descendant(of: header, matching: find.byType(Text))
        .first;
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();

    // 🚨CONTRACT CHANGED (T5, 유저 2026-08-13): 「모든 행은 자유롭게 규칙없이
    // 선택가능 … 셀과 같은문법으로 통일」. An fx header used to opt OUT of the
    // row selection entirely — its drag went straight to re-ordering — which
    // left it the one row kind with a grammar of its own. It follows the
    // cells' now: the FIRST drag selects and the second moves, exactly as a
    // layer row does (which is what `_selectRow` is doing for those above).
    await _selectRow(tester, grip);
    expect(
      chain(),
      before,
      reason: 'the first drag selected — nothing has moved yet',
    );
    expect(
      session.rowSelection.value,
      isNotEmpty,
      reason: 'T5: an fx header is a row like any other now. It used to answer '
          '「이 주체는 참여 안 함」, which is a KIND deciding whether a row may '
          'be named — the one thing ③ and ⑨ removed everywhere else',
    );

    await tester.drag(grip, const Offset(0, 28));
    await tester.pumpAndSettle();

    expect(
      chain(),
      before.reversed.toList(),
      reason: 'the first effect went past the second',
    );
  });

  testWidgets('the X-sheet drags its COLUMNS the same way, along its own '
      'axis', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    expect(_order(session), ['a', 'b', 'c']);

    // The sheet lists the stack RAW, so 'a' is the LEFTMOST column and
    // rightward is toward 'b'. ④: the landing is the boundary the pointer
    // is nearest, so from a grab in this column's middle it takes one and a
    // half columns to stand on the next one — the rail's rule transposed,
    // which is the whole point of the two surfaces sharing this drag.
    final header = find.named('xsheet-layer-row-a');
    // Grabbed by its name, like the rail's rows ([_railRowGrip]).
    final grip = find.named('xsheet-layer-name-a');
    await tester.ensureVisible(grip);
    await tester.pumpAndSettle();
    // ⑨: the sheet runs the other way, so its select nudge does too.
    await tester.drag(grip, const Offset(0, 30));
    await tester.pumpAndSettle();
    final width = tester.getSize(header).width;
    await tester.drag(grip, Offset(width * 1.5, 0));
    await tester.pumpAndSettle();

    expect(_order(session), ['b', 'a', 'c']);
  });

  testWidgets('dropping a row INSIDE an attach group mounts it, and the '
      'caret says so before the release', (tester) async {
    await _pump(tester, project: _groupProject());
    final session = _sessionOf(tester);
    expect(_layerOf(session, 'c').attachedToLayerId, isNull);

    // The rail runs top-down C, B+1, B, A — one row of downward travel puts
    // C's caret between B and B+1, which is the group's inside.
    final row = _railRowGrip('c');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await _selectRow(tester, row);
    // Across the rail at the name, along it at the ROW's middle: one row of
    // travel from there lands exactly on B+1's middle, and the name's own
    // middle sits half a pixel higher (the row's bottom hairline), which is
    // nearer the boundary C already stands on.
    final gesture = await tester.startGesture(
      Offset(tester.getCenter(row).dx, tester.getCenter(_railRow('c')).dy),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 28));
    await tester.pump();

    // Both rows are empty, so the two shapes agree: this will be SYNCED, and
    // the caret is where the promise is made.
    expect(
      find.text(
        AppText.strings.tlDropAttachSyncedTemplate.replaceAll('{name}', 'B'),
      ),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    final mounted = _layerOf(session, 'c');
    expect(mounted.attachedToLayerId, const LayerId('base'));
    expect(mounted.attachedPlacement, AttachedPlacement.above);
    expect(mounted.attachedMode, AttachedMode.synced);

    session.undo();
    await tester.pumpAndSettle();
    expect(_layerOf(session, 'c').attachedToLayerId, isNull);
  });

  testWidgets('R5 #15: dropping a row ON an EMPTY folder puts it inside — '
      'the landing a caret has no gap for', (tester) async {
    await _pump(tester, project: _emptyFolderProject());
    final session = _sessionOf(tester);
    expect(_layerOf(session, 'a').folderId, isNull);

    // The rail renders the stack reversed: F, C, B, A top-down. Three rows
    // of upward travel from A's centre lands the POINTER in the middle of
    // F's row — which is the on-row band, not the gaps either side of it.
    final row = _railRowGrip('a');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await _selectRow(tester, row);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -28 * 3));
    await tester.pump();

    // The row that would swallow it lights up — no caret, because a line
    // between two rows cannot mean "inside one of them".
    // The highlight belongs to the row doing the swallowing, so it is keyed
    // by the FOLDER — and no caret is drawn anywhere while it shows.
    expect(
      find.byKey(const ValueKey<String>('timeline-row-swallow-f')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'timeline-row-caret-',
            ),
      ),
      findsNothing,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(_layerOf(session, 'a').folderId, const LayerId('f'));

    session.undo();
    await tester.pumpAndSettle();
    expect(_layerOf(session, 'a').folderId, isNull);
  });

  testWidgets('R5 #15: dropping a row ON a drawing row makes it that row\'s '
      'FIRST rider — the other landing a gap cannot reach', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    expect(_layerOf(session, 'a').attachedToLayerId, isNull);

    // Rail top-down: Camera, C, B, A. A full row of upward travel lands the
    // pointer in the middle of B's row, and a row's middle is the
    // structural drop. B carries no riders, so there is no inside for a
    // caret to aim at — this is the only way to make the first one.
    final row = _railRowGrip('a');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await _selectRow(tester, row);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -28));
    await tester.pump();

    final swallow = find.byKey(
      const ValueKey<String>('timeline-row-swallow-b'),
    );
    expect(swallow, findsOneWidget);
    // What the drop does is said at the row's START, where a line says it,
    // centred across (F-436①, 유저 2026-10-21 — ↩️it stood at the far end).
    final box = tester.getRect(swallow);
    final badge = tester.getRect(
      find.descendant(of: swallow, matching: find.byType(Text)),
    );
    expect(
      badge.left - box.left,
      lessThan(box.right - badge.right),
      reason: 'the badge stands at the start the row runs from',
    );
    expect(badge.center.dy, moreOrLessEquals(box.center.dy, epsilon: 0.5));

    await gesture.up();
    await tester.pumpAndSettle();

    final mounted = _layerOf(session, 'a');
    expect(mounted.attachedToLayerId, const LayerId('b'));
    expect(
      mounted.attachedPlacement,
      AttachedPlacement.below,
      reason: '⑤: A came from UNDER B, so it rides under B — the side is a '
          'fact about the picture, and carrying a row up onto its new base '
          'used to flip it over that base',
    );

    session.undo();
    await tester.pumpAndSettle();
    expect(_layerOf(session, 'a').attachedToLayerId, isNull);
  });

  testWidgets('a row with fx of its own ASKS before a drop mounts it — and '
      'nothing is mounted until it is answered', (tester) async {
    // 유저 2026-08-29: 「기존 fx가 사라집니다. 실행하겠습니까?」 — an attach row
    // authors no fx, so mounting one that has them throws them away. The
    // drag's end asks through the confirm it is handed (ARCH, the eleventh
    // family), and holds the drop while the question is on screen.
    await _pump(tester);
    final session = _sessionOf(tester);
    session.laneVerbs.updateLayerTransformTrack(
      const LayerId('a'),
      TransformTrack(
        keyframes: {0: TransformPose(center: CanvasPoint(x: 3, y: 4))},
      ),
    );
    await tester.pumpAndSettle();

    final row = _railRowGrip('a');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await _selectRow(tester, row);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -28));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('attach-drops-fx-dialog')),
      findsOneWidget,
      reason: 'A carries a transform the mount would throw away',
    );
    // F-303: and it says WHICH rows, in the shared list under its sentence
    // — closed, since here the sentence is the point.
    expect(
      find.text('${AppText.strings.tlAttachDropsFxRows} (1)'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('app-notice-details-list')),
        findsNothing);
    expect(
      tester.takeException(),
      isNull,
      reason: 'a heading wider than its window wraps; it does not run off '
          'the edge (in this font it is wider)',
    );
    expect(
      _layerOf(session, 'a').attachedToLayerId,
      isNull,
      reason: 'the drop is held while the question is on screen',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('attach-drops-fx-confirm')),
    );
    await tester.pumpAndSettle();
    expect(_layerOf(session, 'a').attachedToLayerId, const LayerId('b'));
  });

  testWidgets('⑤ the mirror: a row carried DOWN onto a base rides ABOVE it', (
    tester,
  ) async {
    // The other half of the same law, and the half that used to be right by
    // accident — every drop mounted `above`, so only the upward case ever
    // looked wrong.
    await _pump(tester);
    final session = _sessionOf(tester);

    // Rail top-down: Camera, C, B, A. 'c' is above 'b' in the model, so
    // dragging its row DOWN onto B's is the descent.
    final row = _railRowGrip('c');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await _selectRow(tester, row);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 28));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('timeline-row-swallow-b')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();

    final mounted = _layerOf(session, 'c');
    expect(mounted.attachedToLayerId, const LayerId('b'));
    expect(mounted.attachedPlacement, AttachedPlacement.above);
  });

  /// P, held at its row's middle and carried to [row]'s — or [rowsPast]
  /// rows further down the rail: a half is the line under that row.
  Future<TestGesture> carryP(
    WidgetTester tester, {
    required String row,
    double rowsPast = 0,
  }) async {
    final grip = _railRowGrip('p');
    await tester.ensureVisible(grip);
    await tester.pumpAndSettle();
    await _selectRow(tester, grip);
    final from = Offset(
      tester.getCenter(grip).dx,
      tester.getCenter(_railRow('p')).dy,
    );
    final pitch = tester.getSize(_railRow('p')).height;
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(
      Offset(
        0,
        tester.getCenter(_railRow(row)).dy - from.dy + rowsPast * pitch,
      ),
    );
    await tester.pump();
    return gesture;
  }

  testWidgets('🚨F-312: a row dropped ON a group\'s last attach row becomes '
      'its last attach — 「어태치의 마지막」', (tester) async {
    await _pump(tester, project: _facingGroupsProject());
    final session = _sessionOf(tester);

    // P comes from ABOVE the group, over its base: the seat under B2-1 is
    // still the one it takes. ⛔Until F-312 this drop was refused (an
    // attach row carries no riders) and fell back to the nearest line.
    final gesture = await carryP(tester, row: 'b2down');
    expect(
      find.byKey(const ValueKey<String>('timeline-row-swallow-b2down')),
      findsOneWidget,
    );
    expect(
      find.text(
        AppText.strings.tlDropAttachSyncedTemplate.replaceAll('{name}', 'B2'),
      ),
      findsOneWidget,
      reason: 'the row says whose attach it will be before the release',
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_order(session), ['q', 'b1', 'b1up', 'p', 'b2down', 'b2']);
    final joined = _layerOf(session, 'p');
    expect(joined.attachedToLayerId, const LayerId('b2'));
    expect(joined.attachedPlacement, AttachedPlacement.below);

    session.undo();
    await tester.pumpAndSettle();
    expect(_order(session), ['q', 'b1', 'b1up', 'b2down', 'b2', 'p']);
    expect(_layerOf(session, 'p').attachedToLayerId, isNull);
  });

  testWidgets('🚨F-312: the LINE under that row is still 「사이」 — the same '
      'seat, nobody\'s attach', (tester) async {
    await _pump(tester, project: _facingGroupsProject());
    final session = _sessionOf(tester);

    final gesture = await carryP(tester, row: 'b2down', rowsPast: 0.5);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_order(session), ['q', 'b1', 'b1up', 'p', 'b2down', 'b2']);
    expect(_layerOf(session, 'p').attachedToLayerId, isNull);
  });

  testWidgets('🚨F-312: beside FOLDED groups the line is 「사이」 too — not '
      'the inside of a group nobody can see', (tester) async {
    await _pump(tester, project: _facingGroupsProject());
    final session = _sessionOf(tester);
    setRowFolds(session, const LayerId('b1'), collapsed: true);
    setRowFolds(session, const LayerId('b2'), collapsed: true);
    await tester.pumpAndSettle();
    expect(_railRow('b2down'), findsNothing, reason: '⛔전제: folded');
    expect(_railRow('b1up'), findsNothing, reason: '⛔전제: folded');

    // The line between the two bases. ↩️It dropped P between B2-1 and B2,
    // as B2's attach: 「접혀있을땐 사이에 두는게 안되고 어태치에 넣는거밖에
    // 안됨」.
    final gesture = await carryP(tester, row: 'b2', rowsPast: 0.5);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_order(session), ['q', 'b1', 'b1up', 'p', 'b2down', 'b2']);
    expect(_layerOf(session, 'p').attachedToLayerId, isNull);
  });

  /// [id], held at its name, its pointer put [fraction] of the way down
  /// [into]'s row — 0 its top edge, 1 its bottom. A fifth from an edge is a
  /// line's; the middle of a row is the row's own (R5 #15).
  Future<TestGesture> lift(WidgetTester tester, String id) async {
    final grip = _railRowGrip(id);
    await tester.ensureVisible(grip);
    await tester.pumpAndSettle();
    await _selectRow(tester, grip);
    final gesture = await tester.startGesture(
      Offset(tester.getCenter(grip).dx, tester.getCenter(_railRow(id)).dy),
    );
    await tester.pump(const Duration(milliseconds: 16));
    return gesture;
  }

  Future<void> pointInto(
    WidgetTester tester,
    TestGesture gesture,
    String into, {
    required double fraction,
    required double dx,
  }) async {
    final row = tester.getRect(_railRow(into));
    await gesture.moveTo(Offset(dx, row.top + row.height * fraction));
    await tester.pump();
  }

  Finder caretBefore(String id) =>
      find.byKey(ValueKey<String>('timeline-row-caret-before-$id'));

  final anyCaret = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'timeline-row-caret-',
        ),
  );

  testWidgets('🚨F-312 (10-08): the OUTERMOST attach row lets go where it '
      'stands — on its own edge, in the half past its group', (tester) async {
    // 유저: 「가장 바깥에 있는 어태치레이어는 그게 적용안됨. 적용되도록하고 다른
    // 곳에서도 법 다른거있으면 통일」. B2-1 is B2's outermost row below it,
    // B1+1 B1's above it, and the line they share is both groups' edge.
    await _pump(tester, project: _facingGroupsProject());
    final session = _sessionOf(tester);
    final dx = tester.getCenter(_railRowGrip('b2down')).dx;

    var gesture = await lift(tester, 'b2down');
    await pointInto(tester, gesture, 'b2down', fraction: 0.85, dx: dx);
    expect(anyCaret, findsNothing, reason: 'in its own row it goes nowhere');
    await pointInto(tester, gesture, 'b1up', fraction: 0.15, dx: dx);
    expect(caretBefore('b1up'), findsOneWidget, reason: 'its own edge');
    expect(find.text(AppText.strings.tlDropDetachAttach), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_order(session), ['q', 'b1', 'b1up', 'b2down', 'b2', 'p']);
    expect(_layerOf(session, 'b2down').attachedToLayerId, isNull);
    session.undo();
    await tester.pumpAndSettle();
    expect(_layerOf(session, 'b2down').attachedToLayerId, const LayerId('b2'));

    // And B1+1 from below, over the same line.
    gesture = await lift(tester, 'b1up');
    await pointInto(tester, gesture, 'b1up', fraction: 0.15, dx: dx);
    expect(anyCaret, findsNothing, reason: 'in its own row it goes nowhere');
    await pointInto(tester, gesture, 'b2down', fraction: 0.85, dx: dx);
    expect(caretBefore('b1up'), findsOneWidget, reason: 'its own edge');
    expect(find.text(AppText.strings.tlDropDetachAttach), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_order(session), ['q', 'b1', 'b1up', 'b2down', 'b2', 'p']);
    expect(_layerOf(session, 'b1up').attachedToLayerId, isNull);
  });

  // 🗣️F-436① (유저 2026-10-21): 「어태치 장착 텍스트가 블렌드쪽에 뜨는데,
  // 그게아니라 C에 어태치 라는 텍스트가 뜨는 위치처럼 왼쪽에 통일해서. 가로선
  // 텍스트 위치는 이 위치로 통일」.
  testWidgets('🚨F-436①: a row\'s word stands where a line\'s does — the '
      'same distance past the layer area\'s start', (tester) async {
    await _pump(tester, project: _facingGroupsProject());

    // A row's word: P carried onto B2-1 says whose attach it becomes.
    var gesture = await carryP(tester, row: 'b2down');
    final swallow = find.byKey(
      const ValueKey<String>('timeline-row-swallow-b2down'),
    );
    final rowWord =
        tester
            .getRect(find.descendant(of: swallow, matching: find.byType(Text)))
            .left -
        tester.getRect(swallow).left;
    await gesture.cancel();
    await tester.pumpAndSettle();

    // A line's word: B2-1 over its own edge lets go of its base.
    final dx = tester.getCenter(_railRowGrip('b2down')).dx;
    gesture = await lift(tester, 'b2down');
    await pointInto(tester, gesture, 'b1up', fraction: 0.15, dx: dx);
    final caret = caretBefore('b1up');
    expect(find.text(AppText.strings.tlDropDetachAttach), findsOneWidget);
    final bar = find.descendant(
      of: caret,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxHeight == 2,
      ),
    );
    final lineWord =
        tester
            .getRect(find.descendant(of: caret, matching: find.byType(Text)))
            .left -
        tester.getRect(bar).left;
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(rowWord, greaterThan(0), reason: '⛔전제: past the start');
    expect(rowWord, moreOrLessEquals(lineWord));
  });

  testWidgets('🚨F-312 (10-08): a FOLDER\'s bottom line splits the same way '
      '— in from inside, out from past it, and its last member goes out '
      'where it stands', (tester) async {
    await _pump(tester, project: _folderMembersProject());
    final session = _sessionOf(tester);
    final dx = tester.getCenter(_railRowGrip('m1')).dx;
    final out = find.text(AppText.strings.tlDropOutOfFolder);

    var gesture = await lift(tester, 'm1');
    await pointInto(tester, gesture, 'a', fraction: 0.15, dx: dx);
    expect(caretBefore('a'), findsOneWidget);
    expect(out, findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_order(session), ['a', 'm1', 'm2', 'x']);
    expect(_layerOf(session, 'm1').folderId, isNull);
    session.undo();
    await tester.pumpAndSettle();

    // M2 to the folder's bottom, with the pointer still in M1: it stays in.
    gesture = await lift(tester, 'm2');
    await pointInto(tester, gesture, 'm1', fraction: 0.85, dx: dx);
    expect(caretBefore('a'), findsOneWidget);
    expect(out, findsNothing, reason: 'still the folder\'s');
    // …and past M1 into A, the same line lets it out.
    await pointInto(tester, gesture, 'a', fraction: 0.15, dx: dx);
    expect(caretBefore('a'), findsOneWidget);
    expect(out, findsOneWidget);
    await pointInto(tester, gesture, 'm1', fraction: 0.85, dx: dx);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_order(session), ['a', 'm2', 'm1', 'x']);
    expect(_layerOf(session, 'm2').folderId, const LayerId('f'));
  });

  testWidgets('🚨F-423: a member of the TOP folder carried over the camera '
      'rows lands above its folder, out of it — as over a loose row there', (
    tester,
  ) async {
    // 유저 2026-10-20: 「선택한 파일을 폴더 위로 옮기는게 불가. 위 폴더밖에
    // 레이어가 존재해야만 이동되는거같은데」. The camera rows take no drop,
    // so the line they point at is the nearest one the drag may draw.
    await _pump(tester, project: _topFolderProject());
    final session = _sessionOf(tester);
    final dx = tester.getCenter(_railRowGrip('m1')).dx;

    final gesture = await lift(tester, 'm1');
    await pointInto(tester, gesture, 'cam', fraction: 0.8, dx: dx);
    expect(caretBefore('f'), findsOneWidget);
    expect(find.text(AppText.strings.tlDropOutOfFolder), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    final ids = [
      for (final layer in session.requireActiveCut.layers) layer.id.value,
    ];
    expect(ids.indexOf('m1'), greaterThan(ids.indexOf('f')));
    expect(_layerOf(session, 'm1').folderId, isNull);
  });

  testWidgets('🚨F-423②: what a drop draws on a row — the line\'s notice, '
      'the swallow\'s outline — starts clear of the section zone', (
    tester,
  ) async {
    // 유저 2026-10-20: 「ㅁㅁ 밖으로 안으로 등 가로선에 메시지도 액션섹션에
    // 잘려서 다 안보임. 가로선 안에 다 보이도록」.
    await _pump(tester, project: _topFolderProject());
    final dx = tester.getCenter(_railRowGrip('m1')).dx;
    final folder = tester.getRect(find.named('timeline-folder-row-f'));
    final zone = [
      for (final element in find.byType(SectionBandZone).evaluate())
        if (element.renderObject case final RenderBox box)
          box.localToGlobal(Offset.zero) & box.size,
    ].singleWhere(
      (band) => band.top <= folder.top && band.bottom >= folder.bottom,
    );

    var gesture = await lift(tester, 'm1');
    await pointInto(tester, gesture, 'cam', fraction: 0.8, dx: dx);
    final notice = find.ancestor(
      of: find.text(AppText.strings.tlDropOutOfFolder),
      matching: find.byType(DecoratedBox),
    );
    expect(notice, findsWidgets, reason: '⛔전제: the line says it');
    expect(tester.getRect(notice.first).left, greaterThanOrEqualTo(zone.right));
    await gesture.cancel();
    await tester.pumpAndSettle();

    gesture = await lift(tester, 'a');
    await pointInto(tester, gesture, 'm2', fraction: 0.5, dx: dx);
    final swallow = find.byKey(const ValueKey('timeline-row-swallow-m2'));
    expect(swallow, findsOneWidget, reason: '⛔전제: M2 takes it on');
    expect(tester.getRect(swallow).left, greaterThanOrEqualTo(zone.right));
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('F-423 on the sheet: a drawing column carried past its '
      'section\'s far end draws its line at that end', (tester) async {
    await _pump(tester, project: _topFolderProject());
    final session = _sessionOf(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-orientation-toggle-button')),
    );
    await tester.pumpAndSettle();
    final grip = find.named('xsheet-layer-name-a');
    await tester.ensureVisible(grip);
    await tester.pumpAndSettle();
    await tester.drag(grip, const Offset(0, 30));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(grip));
    await tester.pump(const Duration(milliseconds: 16));
    final cam = tester.getRect(find.named('xsheet-layer-row-cam'));
    await gesture.moveTo(
      Offset(cam.left + cam.width * 0.8, tester.getCenter(grip).dy),
    );
    await tester.pump();
    expect(
      [
        for (final element in anyCaret.evaluate())
          (element.widget.key! as ValueKey<String>).value,
      ],
      ['timeline-row-caret-after-f'],
    );
    await gesture.up();
    await tester.pumpAndSettle();
    final ids = [
      for (final layer in session.requireActiveCut.layers) layer.id.value,
    ];
    expect(ids.indexOf('a'), ids.indexOf('f') + 1);
  });

  testWidgets('the pointer over a row\'s LANES stands in that row — its own '
      'or a neighbour\'s', (tester) async {
    await _pump(tester, project: _folderMembersProject());
    final session = _sessionOf(tester);
    final rowHeight = tester.getSize(_railRow('m1')).height;
    session.layerSwitches.toggleLayerLanes(const LayerId('m1'));
    await tester.pumpAndSettle();
    final lanes =
        tester.getRect(_railRow('a')).top -
        tester.getRect(_railRow('m1')).bottom;
    expect(
      lanes,
      greaterThanOrEqualTo(rowHeight),
      reason: '⛔전제: M1 twirled open — a lane row at least',
    );
    final dx = tester.getCenter(_railRowGrip('m1')).dx;

    // Over its own last lane, by the line under them: it goes nowhere. Read
    // as no row at all, that half let it out of its folder.
    final gesture = await lift(tester, 'm1');
    await pointInto(tester, gesture, 'a', fraction: -0.1, dx: dx);
    expect(anyCaret, findsNothing);
    await pointInto(tester, gesture, 'a', fraction: 0.15, dx: dx);
    expect(caretBefore('a'), findsOneWidget);
    expect(find.text(AppText.strings.tlDropOutOfFolder), findsOneWidget);
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('the pointer over a NEIGHBOUR\'s lanes is past the group: the '
      'row carried there lets go', (tester) async {
    await _pump(tester, project: _facingGroupsProject());
    final session = _sessionOf(tester);
    final rowHeight = tester.getSize(_railRow('p')).height;
    session.layerSwitches.toggleLayerLanes(const LayerId('p'));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(_railRow('b2')).top -
          tester.getRect(_railRow('p')).bottom,
      greaterThanOrEqualTo(rowHeight),
      reason: '⛔전제: P twirled open — a lane row at least, or the pointer '
          'is in P\'s own row',
    );
    final dx = tester.getCenter(_railRowGrip('b2down')).dx;

    // B2-1 carried up past its base, to the line under P's lanes: P's.
    final gesture = await lift(tester, 'b2down');
    await pointInto(tester, gesture, 'b2', fraction: -0.1, dx: dx);
    expect(caretBefore('b2'), findsOneWidget);
    expect(find.text(AppText.strings.tlDropDetachAttach), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_order(session), ['q', 'b1', 'b1up', 'b2', 'b2down', 'p']);
    expect(_layerOf(session, 'b2down').attachedToLayerId, isNull);
  });

  testWidgets('the MIDDLE of a row that takes no drop is still that row: '
      'the folder\'s top member, carried onto the folder row, stays in', (
    tester,
  ) async {
    // Rail top-down: Camera, X, F, M2, M1, A. M2 is already at the top of
    // F's members, so the middle of F's row hands the drag back to the gap
    // above F — with the pointer still in the folder's rows, where a
    // member stays in, and a member cannot stand over its folder's row.
    // ↩️Handed no row there, the gap read the formula and let M2 out over
    // the row it never left.
    await _pump(tester, project: _folderMembersProject());
    final session = _sessionOf(tester);
    final dx = tester.getCenter(_railRowGrip('m2')).dx;

    final gesture = await lift(tester, 'm2');
    final folderRow = tester.getRect(find.named('timeline-folder-row-f'));
    await gesture.moveTo(Offset(dx, folderRow.center.dy));
    await tester.pump();
    expect(anyCaret, findsNothing);
    expect(find.text(AppText.strings.tlDropOutOfFolder), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_order(session), ['a', 'm1', 'm2', 'x']);
    expect(_layerOf(session, 'm2').folderId, const LayerId('f'));
  });

  testWidgets('🚨a row riding the conte, carried past its group, stands at '
      'the group\'s edge wherever past it the pointer is (결정 6)', (
    tester,
  ) async {
    // It is never let go (I-73-one-head-Q1), so the half past the edge has
    // only the edge's other meaning to give. ↩️Left to the walk, the line
    // fell a row INSIDE with the pointer by the edge and came back to the
    // edge further out (F-393's sweep, 10-18).
    await _pump(tester, project: _conteGroupProject());
    final session = _sessionOf(tester);
    final dx = tester.getCenter(_railRowGrip('under')).dx;

    final gesture = await lift(tester, 'under');
    for (final (row, fraction) in [
      ('over', 0.15),
      ('a', 0.85),
      ('a', 0.5),
      ('a', 0.15),
      ('b', 0.85),
      ('b', 0.5),
    ]) {
      await pointInto(tester, gesture, row, fraction: fraction, dx: dx);
      expect(
        [for (final caret in anyCaret.evaluate()) caret.widget.key],
        [const ValueKey<String>('timeline-row-caret-before-over')],
        reason: '$row at $fraction',
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final moved = session.requireActiveCut.layers;
    expect(
      [for (final layer in moved) layer.id.value],
      ['conte', 'over', 'under', 'a', 'b', 'cam'],
    );
    final under = _layerOf(session, 'under');
    expect(under.attachedToLayerId, const LayerId('conte'));
    expect(under.attachedPlacement, AttachedPlacement.above);
  });

  testWidgets('dragging an attach row clear of its group detaches it', (
    tester,
  ) async {
    await _pump(tester, project: _groupProject());
    final session = _sessionOf(tester);

    // Upward travel takes B+1 past C — clear of the group, and still inside
    // the drawing section (the camera row is the next boundary, and no
    // drawing row may cross it). Aimed at the BOUNDARY: a row's middle is
    // the structural drop now (R5 #15), and detaching is a move.
    final row = _railRowGrip('over');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await _selectRow(tester, row);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -42));
    await tester.pump();
    expect(find.text(AppText.strings.tlDropDetachAttach), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_order(session), ['a', 'base', 'c', 'over']);
    expect(_layerOf(session, 'over').attachedToLayerId, isNull);

    session.undo();
    await tester.pumpAndSettle();
    expect(_order(session), ['a', 'base', 'over', 'c']);
    expect(
      _layerOf(session, 'over').attachedToLayerId,
      const LayerId('base'),
      reason: 'one gesture, one undo — the move and the detach together',
    );
  });

  testWidgets('the drag is one undo', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    final row = _railRowGrip('a');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await _selectRow(tester, row);
    await tester.drag(row, const Offset(0, -42));
    await tester.pumpAndSettle();
    expect(_order(session), ['b', 'a', 'c']);

    session.undo();
    await tester.pumpAndSettle();
    expect(_order(session), ['a', 'b', 'c']);
  });

  testWidgets('F-31①: a caret carrying a NOTICE keeps the line on the '
      'boundary — the badge hangs off it, it does not move it', (
    tester,
  ) async {
    // 유저 2026-08-28: 「가로선이 이상한 위치에 있다는거야 … 레이어영역의
    // 중앙 위쪽? 에 그려져서 레이어랑 겹쳐」. The plain caret is right, so
    // this drives the case they were looking at: an ATTACH drop, whose
    // caret says what it will do.
    final drag = ValueNotifier<LayerRowDragState?>(
      const LayerRowDragState(
        subject: LayerRowSubject(LayerId('b')),
        caretSlot: 1,
        legal: true,
        joinLabel: '어태치 해제',
      ),
    );
    addTearDown(drag.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: LayerRowDragTarget(
                subject: const LayerRowSubject(LayerId('b')),
                slotBefore: 1,
                rowExtent: 28,
                axis: Axis.horizontal,
                hooks: TimelineRowDragHooks(
                  drag: drag,
                  onBegin: (_) {},
                  onUpdate: (_, _, {pointerInRow}) {},
                  onRowTarget: (_, _, _) {},
                  onEffectUpdate: (_, _, _) {},
                  onEnd: () {},
                  onCancel: () {},
                ),
                onCrossed: (_, _, _) {},
                child: const SizedBox(height: 28, key: ValueKey('the-row')),
              ),
            ),
          ),
        ),
      ),
    );

    final bar = find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxHeight == layerRowCaretThickness,
    );
    expect(bar, findsOneWidget);
    final rowTop = tester.getRect(find.byKey(const ValueKey('the-row'))).top;
    expect(
      tester.getRect(bar).center.dy,
      moreOrLessEquals(rowTop, epsilon: 1.5),
      reason:
          'the badge is taller than the 2px bar, so a Stack sized by the '
          'badge centres the bar inside the row instead of on its edge',
    );
    // …and the notice itself is still THERE and readable: hanging the badge
    // off the line must not be a way of hiding it.
    final badge = find.text('어태치 해제');
    expect(badge, findsOneWidget);
    final badgeRect = tester.getRect(badge);
    expect(badgeRect.height, greaterThan(layerRowCaretThickness));
    expect(
      badgeRect.center.dy,
      moreOrLessEquals(rowTop, epsilon: 1.5),
      reason: 'the badge straddles the line rather than sitting off it',
    );
  });

  testWidgets('F-50: a plain FOLDER dropped on a drawing row mounts it — '
      '유저 2026-08-28: 「일반폴더를 어태치 장착하는 기능이 사라졌어」', (
    tester,
  ) async {
    await _pump(tester, project: _folderWithMemberProject());
    final session = _sessionOf(tester);
    expect(_layerOf(session, 'm').attachedToLayerId, isNull);

    final row = find.named('timeline-folder-row-f');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    // ⑨'s select first. The folder row's LEFT edge is buttons, so the grab
    // goes through the middle of the row like the pointer would.
    final rect = tester.getRect(row);
    final grab = Offset(rect.left + rect.width * 0.3, rect.center.dy);
    await tester.dragFrom(grab, const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(session.rowSelection.value, isNotEmpty);

    // Rail top-down: F, M, C, B, A. Three rows down from F's centre puts
    // the pointer in the MIDDLE of B — the on-row band.
    final gesture = await tester.startGesture(grab);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 28 * 3));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('timeline-row-swallow-b')),
      findsOneWidget,
      reason: 'B is what would swallow the folder, so B is what lights up',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      _layerOf(session, 'm').attachedToLayerId,
      const LayerId('b'),
      reason: "the folder becomes B's organizer, so its member rides B",
    );
  });

  testWidgets('🆕F-139: an EMPTY folder dropped on a drawing row attaches '
      'too — 유저: 「아무것도 없으면 안되. 규칙 다른거 두지않도록」', (tester) async {
    // 유저 2026-09-18: 「폴더에 내용물이 있으면, 레이어가 들어가있으면
    // 드래그드롭으로 어태치 장착되는데 아무것도 없으면 안되」. The case above
    // is the WITH-members half; this is the half that was refused, and the
    // refusal was nobody's order (see `layer_drop_policy_test`).
    await _pump(tester, project: _emptyFolderProject());
    final session = _sessionOf(tester);
    expect(_layerOf(session, 'f').attachedToLayerId, isNull);

    final row = find.named('timeline-folder-row-f');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    // ⑨'s select first. The folder row's LEFT edge is buttons, so the grab
    // goes through the middle of the row like the pointer would.
    final rect = tester.getRect(row);
    final grab = Offset(rect.left + rect.width * 0.3, rect.center.dy);
    await tester.dragFrom(grab, const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(session.rowSelection.value, isNotEmpty);

    // Rail top-down: F, C, B, A. Two rows down from F's centre puts the
    // pointer in the MIDDLE of B — the on-row band.
    final gesture = await tester.startGesture(grab);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 28 * 2));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('timeline-row-swallow-b')),
      findsOneWidget,
      reason: 'B is what would swallow the folder, so B is what lights up',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      _layerOf(session, 'f').attachedToLayerId,
      const LayerId('b'),
      reason:
          'with no leaf to carry the relation the folder row carries it — '
          '`attachGroupBaseOf` reads a row\'s own field before deriving one',
    );
  });

  testWidgets('F-31① on the OTHER axis: the x-sheet\'s caret is a COLUMN '
      'boundary, and the badge must not push that either', (tester) async {
    // The same `_caret` draws both rails, so the badge that displaced the
    // horizontal line displaced this one sideways. One law, both surfaces —
    // the sheet had no test for its caret at all.
    final drag = ValueNotifier<LayerRowDragState?>(
      const LayerRowDragState(
        subject: LayerRowSubject(LayerId('b')),
        caretSlot: 1,
        legal: true,
        joinLabel: '어태치 해제',
      ),
    );
    addTearDown(drag.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 300,
              child: LayerRowDragTarget(
                subject: const LayerRowSubject(LayerId('b')),
                slotBefore: 1,
                rowExtent: 28,
                axis: Axis.vertical,
                hooks: TimelineRowDragHooks(
                  drag: drag,
                  onBegin: (_) {},
                  onUpdate: (_, _, {pointerInRow}) {},
                  onRowTarget: (_, _, _) {},
                  onEffectUpdate: (_, _, _) {},
                  onEnd: () {},
                  onCancel: () {},
                ),
                onCrossed: (_, _, _) {},
                child: const SizedBox(width: 28, key: ValueKey('the-column')),
              ),
            ),
          ),
        ),
      ),
    );

    final bar = find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxWidth == layerRowCaretThickness,
    );
    expect(bar, findsOneWidget);
    final columnLeft = tester
        .getRect(find.byKey(const ValueKey('the-column')))
        .left;
    expect(
      tester.getRect(bar).center.dx,
      moreOrLessEquals(columnLeft, epsilon: 1.5),
      reason: 'the bar straddles the column boundary, badge or no badge',
    );
    expect(find.text('어태치 해제'), findsOneWidget);
  });

  testWidgets('F-423② on the sheet: a column\'s swallow outline is the whole '
      'column — its band is a strip of its own, not a slot in it', (
    tester,
  ) async {
    final drag = ValueNotifier<LayerRowDragState?>(
      const LayerRowDragState(
        subject: LayerRowSubject(LayerId('a')),
        caretSlot: 0,
        legal: true,
        onRowTarget: LayerId('b'),
      ),
    );
    addTearDown(drag.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 300,
              child: LayerRowDragTarget(
                subject: const LayerRowSubject(LayerId('b')),
                slotBefore: 1,
                rowExtent: 28,
                axis: Axis.vertical,
                hooks: TimelineRowDragHooks(
                  drag: drag,
                  onBegin: (_) {},
                  onUpdate: (_, _, {pointerInRow}) {},
                  onRowTarget: (_, _, _) {},
                  onEffectUpdate: (_, _, _) {},
                  onEnd: () {},
                  onCancel: () {},
                ),
                onCrossed: (_, _, _) {},
                child: const SizedBox(width: 28, key: ValueKey('the-column')),
              ),
            ),
          ),
        ),
      ),
    );

    final swallow = find.byKey(const ValueKey('timeline-row-swallow-b'));
    expect(swallow, findsOneWidget, reason: '⛔전제');
    expect(
      tester.getRect(swallow).left,
      tester.getRect(find.byKey(const ValueKey('the-column'))).left,
    );
  });

  testWidgets('A5: the wrapper takes the ONE pin for the row it holds, and '
      'lets go only of its own', (tester) async {
    // The row window unmounts what has scrolled past, and an unmounted row
    // releases the grip mid-gesture (드래그 풀림). The wrapper is one of the
    // three surfaces that take the pin, and this is the half no source scan
    // can see: that a real drag reaches HeldRowPin at all.
    final pin = HeldRowPin();
    final drag = ValueNotifier<LayerRowDragState?>(null);
    addTearDown(drag.dispose);
    final layer = Layer(id: const LayerId('b'), name: 'B', frames: const []);
    final row = TimelineDisplayRow.layer(layer, layerIndex: 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: layerRowDragWrapper(
                row: row,
                dragRows: () => [row],
                rowExtent: 28,
                dragEdges: () => TimelineRowEdges.uniform(1, 28),
                axis: Axis.horizontal,
                hooks: TimelineRowDragHooks(
                  drag: drag,
                  onBegin: (_) {},
                  onUpdate: (_, _, {pointerInRow}) {},
                  onRowTarget: (_, _, _) {},
                  onEffectUpdate: (_, _, _) {},
                  onEnd: () {},
                  onCancel: () {},
                ),
                onRowSelectionSpan: null,
                pin: pin,
                child: const SizedBox(
                  width: 300,
                  height: 28,
                  key: ValueKey('pinned-row'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(LayerRowDragTarget), findsOneWidget);
    expect(pin.held, isNull, reason: 'nothing is held before the press');
    // A MOUSE: the row drag is a pen/mouse gesture unless the input policy
    // has been flipped to let touch edit ([AppInput.timelineEditPanDevices]).
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('pinned-row'))),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -42));
    await tester.pump();
    expect(
      pin.held,
      const LayerRowAddress(LayerId('b')),
      reason: 'the grip is taken for THIS row, by address',
    );

    // ⛔RELEASE ONLY IF STILL MINE: another surface letting go of another
    // row must not unpin the row this drag is holding.
    pin.release(const LayerRowAddress(LayerId('z')));
    expect(pin.held, const LayerRowAddress(LayerId('b')));

    await gesture.up();
    await tester.pump();
    expect(pin.held, isNull, reason: 'the drag let go of its own row');
  });
}
