import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
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
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/panel_finders.dart';

/// 🚨★★★F-233 (유저 2026-09-29): 「언두 빠르게하면서 다시 빠르게 스트로크하면서
/// 하다보면 … 언두된 스트로크가 다시 1프레임 보였다가 사라지는상황」.
///
/// An undo takes the cel back inside its own key or pen event; the canvas
/// learns it at the next build. A pen that lands in between began its
/// stroke on the cel as the LAST FRAME had it — the undone stroke still on
/// it — and every tile the new stroke touched was pre-blended over that,
/// so the undone stroke came back inside them until the pen lifted. The
/// commit and the undo already read the cel as it stands; the pen now asks
/// the same question.
void main() {
  const frameId = FrameId('pc-frame');
  const layerId = LayerId('pc-layer');
  const key = BrushFrameKey(
    projectId: ProjectId('pc-project'),
    trackId: TrackId('pc-track'),
    cutId: CutId('pc-cut'),
    layerId: layerId,
    frameId: frameId,
  );

  Project oneFrameProject() => Project(
    id: const ProjectId('pc-project'),
    name: 'Press Cel',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('pc-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('pc-cut'),
            name: 'Press Cel Cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: layerId,
                name: 'Press Cel Layer',
                frames: [
                  Frame(id: frameId, name: 'A', duration: 1, strokes: const []),
                ],
                timeline: {
                  0: const TimelineExposure.drawing(frameId, length: 1),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  BitmapSurface celNow(WidgetTester tester) {
    final coordinator = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session
        .pixelEditing
        .coordinator;
    expect(coordinator, isNotNull, reason: '⛔fixture: the canvas built one');
    return coordinator!.currentSurfaceOf(key);
  }

  Future<void> stroke(WidgetTester tester) async {
    final pen = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await pen.moveBy(const Offset(24, 12));
    await tester.pump();
    await pen.up();
    await pumpFrames(tester);
  }

  testWidgets('🚨F-233: a pen that lands right after an undo, before the '
      'canvas has built again, draws on the cel the undo left', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: oneFrameProject())),
    );
    await tester.pumpAndSettle();
    await stroke(tester);
    final withTheStroke = celNow(tester);

    // Ctrl+Z, and the pen down straight after it — no frame in between.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    final undone = celNow(tester);
    expect(
      identical(undone, withTheStroke),
      isFalse,
      reason: '⛔premise: the undo took the stroke back',
    );
    final pen = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );

    final view = tester.widget<InteractiveBrushEditCanvasView>(
      find.byKey(const ValueKey<String>('brush-canvas-view')),
    );
    final overlay = view.overlayModel;
    expect(overlay, isNotNull, reason: '⛔fixture: the merged canvas');
    expect(
      identical(overlay!.preBlendBase, undone),
      isTrue,
      reason: 'the new stroke blends over the cel as the undo left it — '
          'not the one the last frame showed, with the undone stroke on it',
    );

    await pen.moveBy(const Offset(12, 24));
    await tester.pump();
    await pen.up();
    await pumpFrames(tester);
  });

  testWidgets('a pen that lands in the same frame the last one lifted draws '
      'over that stroke, not under it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: oneFrameProject())),
    );
    await tester.pumpAndSettle();

    // Stroke A, lifted, and B down at once: A has landed, the canvas has
    // not built since.
    final a = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await a.moveBy(const Offset(24, 12));
    await tester.pump();
    await a.up();
    final withA = celNow(tester);
    final b = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );

    final view = tester.widget<InteractiveBrushEditCanvasView>(
      find.byKey(const ValueKey<String>('brush-canvas-view')),
    );
    expect(
      identical(view.overlayModel!.preBlendBase, withA),
      isTrue,
      reason: 'B blends over A — A must not vanish under B until B lifts',
    );

    await b.moveBy(const Offset(12, 24));
    await tester.pump();
    await b.up();
    await pumpFrames(tester);
  });
}
