import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
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
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';

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
    find.byKey(ValueKey<String>('timeline-layer-row-$id'));

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
    final row = _railRow('a');
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
    final row = _railRow('a');
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
    final row = _railRow('a');
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
    final row = _railRow('c');
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
    session.addEffectToActiveLayer(EffectKind.values.first);
    session.addEffectToActiveLayer(EffectKind.values[1]);
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

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-lane-toggle-b')),
    );
    await tester.pumpAndSettle();

    final firstId = session.requireActiveCut.layers
        .firstWhere((layer) => layer.id == const LayerId('b'))
        .effects
        .first
        .id;
    final header = find.byKey(
      ValueKey<String>('timeline-lane-label-b-fx-group:${firstId.value}'),
    );
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();

    // 🚨CONTRACT CHANGED (T5, 유저 2026-08-13): 「모든 행은 자유롭게 규칙없이
    // 선택가능 … 셀과 같은문법으로 통일」. An fx header used to opt OUT of the
    // row selection entirely — its drag went straight to re-ordering — which
    // left it the one row kind with a grammar of its own. It follows the
    // cells' now: the FIRST drag selects and the second moves, exactly as a
    // layer row does (which is what `_selectRow` is doing for those above).
    await _selectRow(tester, header);
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

    await tester.drag(header, const Offset(0, 28));
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
    final header = find.byKey(const ValueKey<String>('xsheet-layer-row-a'));
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    // ⑨: the sheet runs the other way, so its select nudge does too.
    await tester.drag(header, const Offset(0, 30));
    await tester.pumpAndSettle();
    final width = tester.getSize(header).width;
    await tester.drag(header, Offset(width * 1.5, 0));
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
    final row = _railRow('c');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await _selectRow(tester, row);
    final gesture = await tester.startGesture(tester.getCenter(row));
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
    final row = _railRow('a');
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
    final row = _railRow('a');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await _selectRow(tester, row);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -28));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('timeline-row-swallow-b')),
      findsOneWidget,
    );

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
    final row = _railRow('c');
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

  testWidgets('dragging an attach row clear of its group detaches it', (
    tester,
  ) async {
    await _pump(tester, project: _groupProject());
    final session = _sessionOf(tester);

    // Upward travel takes B+1 past C — clear of the group, and still inside
    // the drawing section (the camera row is the next boundary, and no
    // drawing row may cross it). Aimed at the BOUNDARY: a row's middle is
    // the structural drop now (R5 #15), and detaching is a move.
    final row = _railRow('over');
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
    final row = _railRow('a');
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

    final row = find.byKey(const ValueKey<String>('timeline-folder-row-f'));
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
}
