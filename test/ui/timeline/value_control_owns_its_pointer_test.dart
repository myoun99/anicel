import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// T11: pressing a VALUE CONTROL in a rail row must not also start the row's
/// selection drag.
///
/// 🚨The device matters, and it is why three attempts at this came back
/// green. The row's pan measures the VECTOR LENGTH of the first move; the
/// slider measures only |dx|. Both thresholds are `computeHitSlop`, which is
/// 18px for stylus and touch but **1px for a mouse**. So with a pen the
/// slider comfortably wins every angle, and with a mouse a first move of
/// (0.5, 1.2) gives the row a length of 1.3 — past 1 — while the slider's
/// 0.5 has not moved at all.
///
/// A VERTICAL drag is the pure case: |dx| stays 0 forever, so the slider can
/// never cross its threshold and the row wins by walkover rather than by
/// racing. That is the user's 「세로 드래그 = 무조건 재현」.
///
/// ⛔Do not re-measure this with `PointerDeviceKind.stylus`. It is green
/// there and the bug is still in the app.
Project _project() {
  return Project(
    id: const ProjectId('slider-pointer-project'),
    name: 'Slider Pointer',
    createdAt: DateTime.utc(2026, 8, 14),
    tracks: [
      Track(
        id: const TrackId('slider-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('slider-cut'),
            name: 'Slider Cut',
            duration: 12,
            canvasSize: const CanvasSize(width: 1280, height: 720),
            camera: CutCamera.empty(),
            layers: [
              Layer(id: const LayerId('a'), name: 'A', frames: const []),
              Layer(id: const LayerId('b'), name: 'B', frames: const []),
              Layer(id: const LayerId('c'), name: 'C', frames: const []),
            ],
          ),
        ],
      ),
    ],
  );
}

EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

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

Finder _opacitySlider(String layerId) =>
    find.byKey(ValueKey<String>('timeline-layer-opacity-$layerId'));

void main() {
  testWidgets(
    'a MOUSE drag straight down the opacity slider does not select the row',
    (tester) async {
      await _pump(tester);
      final session = _sessionOf(tester);
      expect(
        session.rowSelection.value,
        isEmpty,
        reason: 'nothing selected before the gesture',
      );

      final slider = _opacitySlider('a');
      expect(slider, findsOneWidget, reason: 'the rail row has its slider');

      final gesture = await tester.startGesture(
        tester.getCenter(slider),
        kind: PointerDeviceKind.mouse,
      );
      // Straight down, in steps a real hand would produce. |dx| is 0 the
      // whole way: the slider's own threshold is unreachable, so nothing
      // but the row is left to accept this.
      for (var step = 0; step < 8; step += 1) {
        await gesture.moveBy(const Offset(0, 5));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        session.rowSelection.value,
        isEmpty,
        reason:
            'the press landed on a value control, so the row never owned '
            'this pointer',
      );
    },
  );

  testWidgets(
    'a MOUSE drag that starts DIAGONALLY on the slider does not select the row',
    (tester) async {
      await _pump(tester);
      final session = _sessionOf(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(_opacitySlider('a')),
        kind: PointerDeviceKind.mouse,
      );
      // The intermittent case: length √(0.5² + 1.2²) ≈ 1.3 clears the
      // mouse's 1px slop while |dx| = 0.5 does not, so the row's pan can
      // accept a move the slider is still calling stillness.
      await gesture.moveBy(const Offset(0.5, 1.2));
      await tester.pump();
      for (var step = 0; step < 6; step += 1) {
        await gesture.moveBy(const Offset(2, 4));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        session.rowSelection.value,
        isEmpty,
        reason: 'the first move being diagonal does not hand the row the '
            'pointer either',
      );
    },
  );

  testWidgets('the row still selects when the press misses the slider', (
    tester,
  ) async {
    await _pump(tester);
    final session = _sessionOf(tester);

    // The guard must be about WHERE the press landed, not about the rail
    // giving up its drag: a press on the row itself still selects. Without
    // this the fix could be "rows never select" and the two tests above
    // would still pass.
    await tester.drag(
      find.byKey(const ValueKey<String>('timeline-layer-row-a')),
      const Offset(30, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(
      session.rowSelection.value,
      isNotEmpty,
      reason: 'a press on the ROW is still a row selection',
    );
  });
}
