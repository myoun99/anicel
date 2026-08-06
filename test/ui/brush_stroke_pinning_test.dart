import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/panel_finders.dart';

/// R13-4: flipping frames WHILE a stroke is in progress used to throw
/// "setState during build" (the mid-stroke red screen) and could land the
/// stroke on the wrong cel. The stroke now PINS to its original cel — the
/// canvas retargets the moment the pen lifts, and the commit goes to the
/// frame the stroke started on.
void main() {
  const frameA = FrameId('pin-frame-a');
  const frameB = FrameId('pin-frame-b');
  const layerId = LayerId('pin-layer');

  Project twoFrameProject() {
    return Project(
      id: const ProjectId('pin-project'),
      name: 'Pin Project',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('pin-track'),
          name: 'Video Track',
          cuts: [
            Cut(
              id: const CutId('pin-cut'),
              name: 'Pin Cut',
              duration: defaultCutDuration,
              canvasSize: defaultCutCanvasSize,
              layers: [
                Layer(
                  id: layerId,
                  name: 'Pin Layer',
                  frames: [
                    Frame(
                      id: frameA,
                      name: 'A',
                      duration: 1,
                      strokes: const [],
                    ),
                    Frame(
                      id: frameB,
                      name: 'B',
                      duration: 1,
                      strokes: const [],
                    ),
                  ],
                  timeline: {
                    0: TimelineExposure.drawing(frameA, length: 1),
                    1: TimelineExposure.drawing(frameB, length: 1),
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  BrushFrameKey keyFor(FrameId frameId) => BrushFrameKey(
    projectId: const ProjectId('pin-project'),
    trackId: const TrackId('pin-track'),
    cutId: const CutId('pin-cut'),
    layerId: layerId,
    frameId: frameId,
  );

  // PANEL-SCOPED (R26 #31): the timesheet docks open by default and its
  // ink planes are interactive views too — this test means the DRAWING
  // canvas's.
  InteractiveBrushEditCanvasView viewOf(WidgetTester tester) =>
      tester.widget<InteractiveBrushEditCanvasView>(mainCanvasView());

  testWidgets('a selection interaction blocks seeks until it ends (R15-⑤)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: twoFrameProject())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;

    session.beginSelectionInteraction();
    session.selectFrameIndex(1);
    expect(session.currentFrameIndex, 0, reason: 'seek refused mid-drag');
    session.scrubFrameIndex(1);
    expect(session.editingFrameCursor.value, 0, reason: 'scrub refused too');

    session.endSelectionInteraction();
    session.selectFrameIndex(1);
    expect(session.currentFrameIndex, 1);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('a committed seek during a stroke is REFUSED '
      'and the stroke commits to its ORIGINAL cel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: twoFrameProject())),
    );
    await tester.pumpAndSettle();

    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    final session = workspace.session;
    expect(viewOf(tester).frameId, frameA);

    // The canvas is the floor: its centre is under the timeline. Aim at
    // the middle of what the artist can SEE.
    final center = visibleCanvasPoint(tester);
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();

    // Mid-stroke frame flip: R15-⑤ REFUSES the seek outright — the
    // playhead itself must not move under a live stroke.
    session.selectFrameIndex(1);
    await tester.pump();
    expect(
      session.currentFrameIndex,
      0,
      reason: 'seeks are blocked while the pen is down',
    );
    expect(
      viewOf(tester).frameId,
      frameA,
      reason: 'a live stroke pins the canvas to its cel',
    );

    await gesture.moveBy(const Offset(24, 12));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // Pen-up: the commit landed on the ORIGINAL cel; a seek AFTER the
    // stroke works normally again.
    expect(viewOf(tester).frameId, frameA);
    session.selectFrameIndex(1);
    await tester.pumpAndSettle();
    expect(viewOf(tester).frameId, frameB);
    expect(
      session.brushFrameStore.celHasRenderableContent(keyFor(frameA)),
      isTrue,
      reason: 'the stroke belongs to the frame it STARTED on',
    );
    expect(
      session.brushFrameStore.celHasRenderableContent(keyFor(frameB)),
      isFalse,
      reason: 'nothing may leak onto the frame the seek landed on',
    );

    // Drain the prerender scheduler's debounced warming.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('a direct host retarget during a stroke never throws — the '
      'stroke tears down silently outside the build phase', (tester) async {
    // The host-level path (no session pinning in front of it): the view's
    // didUpdateWidget reset used to fire the stroke-end callback into an
    // ancestor setState DURING the build — the red screen.
    final keys = [keyFor(frameA), keyFor(frameB)];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainCanvasBrushHost(
            activeFrameKey: keys.first,
            availableFrameKeys: keys,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(viewOf(tester).frameId, frameA);

    // The canvas is the floor: its centre is under the timeline. Aim at
    // the middle of what the artist can SEE.
    final center = visibleCanvasPoint(tester);
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.moveBy(const Offset(20, 10));
    await tester.pump();

    // Retarget WITH the pen down: must not throw, stroke resets in place.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainCanvasBrushHost(
            activeFrameKey: keys.last,
            availableFrameKeys: keys,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(viewOf(tester).frameId, frameB);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
