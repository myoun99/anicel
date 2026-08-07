import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

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

EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

List<String> _order(EditorSessionManager session) => [
  for (final layer in session.requireActiveCut.layers)
    if (layer.kind == LayerKind.animation) layer.id.value,
];

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
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
