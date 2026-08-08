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

void main() {
  testWidgets('dragging a rail row up moves it up the stack', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    expect(_order(session), ['a', 'b', 'c']);

    // The rail renders the stack reversed, so the row for 'a' sits at the
    // BOTTOM. One row height upward puts it past 'b'.
    final row = _railRow('a');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.drag(row, const Offset(0, -28));
    await tester.pumpAndSettle();

    expect(_order(session), ['b', 'a', 'c']);
  });

  testWidgets('the caret shows where it would land, and a release outside '
      'any legal slot leaves the stack alone', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    final row = _railRow('a');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -28));
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('timeline-row-caret-before-b')),
      findsOneWidget,
      reason: 'the caret sits on the boundary the row would land on',
    );

    // Back to where it started: no move, so no caret and no command.
    await gesture.moveBy(const Offset(0, 28));
    await tester.pump();
    expect(find.byType(EditorWorkspace), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_order(session), ['a', 'b', 'c']);
  });

  testWidgets('dragging DOWN moves it down — a row sits between two gaps '
      'that are both where it already is', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    expect(_order(session), ['a', 'b', 'c']);

    // 'c' is the TOP row of the rail; downward is toward 'b'.
    final row = _railRow('c');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.drag(row, const Offset(0, 28));
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
    // rightward is toward 'b'. One column width commits one step.
    final header = find.byKey(const ValueKey<String>('xsheet-layer-header-a'));
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    final width = tester.getSize(header).width;
    await tester.drag(header, Offset(width, 0));
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

  testWidgets('dragging an attach row clear of its group detaches it', (
    tester,
  ) async {
    await _pump(tester, project: _groupProject());
    final session = _sessionOf(tester);

    // One row of upward travel takes B+1 past C — clear of the group, and
    // still inside the drawing section (the camera row is the next boundary,
    // and no drawing row may cross it).
    final row = _railRow('over');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -28));
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
    await tester.drag(row, const Offset(0, -28));
    await tester.pumpAndSettle();
    expect(_order(session), ['b', 'a', 'c']);

    session.undo();
    await tester.pumpAndSettle();
    expect(_order(session), ['a', 'b', 'c']);
  });
}
