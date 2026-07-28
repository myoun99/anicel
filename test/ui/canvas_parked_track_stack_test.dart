import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/camera/camera_frame_overlay.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The multitrack display path's canvas mount (parked state): a gap
/// parking swaps the canvas content to the track stack — a parked frame
/// ON a cut shows that cut's camera-framed composite instead of the old
/// unconditional void, while a frame no track covers keeps the void.
void main() {
  const stackKey = ValueKey<String>('canvas-track-stack-view');
  const framesKey = ValueKey<String>('canvas-track-stack-frames');
  const voidKey = ValueKey<String>('canvas-track-stack-void');

  /// Two default-track cuts with a 4-frame gap before the second.
  (EditorSessionManager, CutId, int) gappedSession() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createCut();
    final track = s.repository.requireProject().tracks.first;
    final first = track.cuts[0].id;
    final second = track.cuts[1].id;
    s.repository.updateCutLeadingGap(cutId: second, leadingGapFrames: 4);
    return (s, first, track.cuts[0].duration);
  }

  /// Drains the prerender scheduler's debounced warming (the established
  /// EditorCanvasArea test epilogue — its Future.delayed timers cannot be
  /// cancelled by dispose).
  Future<void> drainWarming(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  Future<void> pumpArea(
    WidgetTester tester,
    EditorSessionManager session, {
    bool cameraViewEnabled = false,
  }) async {
    final brushTool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
    final cameraView = ValueNotifier<bool>(cameraViewEnabled);
    final cameraDim = ValueNotifier<double>(0.5);
    addTearDown(brushTool.dispose);
    addTearDown(cameraView.dispose);
    addTearDown(cameraDim.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorCanvasArea(
            session: session,
            brushToolState: brushTool,
            cameraViewEnabled: cameraView,
            cameraDimOpacity: cameraDim,
          ),
        ),
      ),
    );
  }

  testWidgets('a parking ON a covered frame shows the track stack (the '
      'SE-row press contract, feedback #7): camera-framed composite, not '
      'the void', (tester) async {
    final (s, first, _) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    await pumpArea(tester, s);
    expect(find.byKey(stackKey), findsNothing, reason: 'cut active = editing');

    s.parkGlobalFrame(1); // ON cut 1 — the SE-row press parks in place.
    await tester.pump();

    expect(s.activeCutId, isNull);
    expect(find.byKey(stackKey), findsOneWidget);
    expect(
      find.byKey(framesKey),
      findsOneWidget,
      reason: 'the covered frame paints a projection, not the void',
    );
    expect(tester.takeException(), isNull);
    await drainWarming(tester);
  });

  testWidgets('a parking in a REAL gap keeps the void (no track covers '
      'the frame)', (tester) async {
    final (s, first, aEnd) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    await pumpArea(tester, s);

    s.selectGlobalFrame(aEnd + 1); // the gap between the cuts
    await tester.pump();

    expect(s.activeCutId, isNull);
    expect(find.byKey(stackKey), findsOneWidget);
    expect(find.byKey(voidKey), findsOneWidget);
    expect(find.byKey(framesKey), findsNothing);
    await drainWarming(tester);
  });

  testWidgets('camera view enabled + gap parking builds without the '
      'authoring overlay (regression: cameraPoseAtCurrentFrame used to '
      'throw requireActiveCut through the overlay build)', (tester) async {
    final (s, first, _) = gappedSession();
    addTearDown(s.dispose);
    s.selectCut(first);
    await pumpArea(tester, s, cameraViewEnabled: true);
    expect(find.byType(CameraFrameOverlay), findsOneWidget);

    s.parkGlobalFrame(1);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byType(CameraFrameOverlay),
      findsNothing,
      reason: 'no active cut = nothing to author; the stack frames itself',
    );
    expect(find.byKey(stackKey), findsOneWidget);

    // Selecting the cut again restores the authoring overlay.
    s.selectCut(first);
    await tester.pump();
    expect(find.byType(CameraFrameOverlay), findsOneWidget);
    expect(find.byKey(stackKey), findsNothing);
    await drainWarming(tester);
  });
}
