import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_bitmap_materialization_history_state.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/brush_edit_session_state.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_surface_state.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

/// 🗣️F-196 (유저 2026-09-27): 「이 상황 이후 발생함. 타임라인이 잠금상태?
/// 룰러쪽 드래그 안먹는데 위아래 이동은 먹힘」.
///
/// The commit ran inside pen-up and the stroke's END came after it, so a
/// commit that threw skipped the end: the host never heard 「the pen is
/// up」 and went on refusing every seek, and this view kept the drawing
/// pointer and refused every new press. The end does not wait on the
/// commit any more.
void main() {
  testWidgets('a commit that throws still ends the stroke, and the next '
      'press draws', (tester) async {
    final strokeLive = <bool>[];
    var commits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: InteractiveBrushEditCanvasView(
              sessionState: BrushEditSessionState(
                canvasState: CanvasSurfaceState(
                  currentSurface: BitmapSurface(
                    canvasSize: const CanvasSize(width: 64, height: 64),
                    tileSize: 16,
                  ),
                ),
                materializationHistoryState:
                    BrushBitmapMaterializationHistoryState(),
              ),
              layerId: const LayerId('layer-a'),
              frameId: const FrameId('frame-a'),
              inputSettings: () => BrushEditCanvasInputSettings.defaults,
              onActiveStrokeChanged: strokeLive.add,
              onSourceStrokeCommitted: (_) {
                commits += 1;
                throw StateError('the commit was refused');
              },
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(
      find.byType(InteractiveBrushEditCanvasView),
    );

    Future<void> stroke() async {
      final gesture = await tester.startGesture(
        origin + const Offset(8, 8),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump();
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    await stroke();
    expect(commits, 1, reason: 'LIVENESS — the stroke reached its commit');
    expect(tester.takeException(), isStateError, reason: 'and it threw');
    expect(
      strokeLive,
      [true, false],
      reason: 'the stroke ended anyway — the host hears the pen go up',
    );

    await stroke();
    expect(tester.takeException(), isStateError);
    expect(
      commits,
      2,
      reason: 'the view let go of the pointer, so the next press drew',
    );
    expect(strokeLive, [true, false, true, false]);
  });
}
