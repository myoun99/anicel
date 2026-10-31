import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_correction.dart';
import 'package:anicel/src/models/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

import '../brush_canvas_test_helpers.dart';

/// 🚨A pen's sample is on the stroke as it comes, not at the next frame
/// (F-512, 유저 2026-10-30 「선이 커서 뒤로 처진다」): the step it makes goes in
/// from there, and waiting for a frame cost the line a frame on the glass.
void main() {
  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  for (final steadied in const [false, true]) {
    testWidgets('🚨the sample blends with no frame between '
        '(${steadied ? 'a steadied line' : 'a line as the pen went'})', (
      tester,
    ) async {
      final overlay = ActiveStrokeOverlayModel(tileSize: 16);
      addTearDown(overlay.dispose);
      final cel = BitmapSurface(
        canvasSize: const CanvasSize(width: 200, height: 40),
        tileSize: 16,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: InteractiveBrushEditCanvasView(
                celNow: () => cel,
                layerId: const LayerId('layer-a'),
                frameId: const FrameId('frame-a'),
                viewport: CanvasViewport(),
                inputSettings: () => BrushEditCanvasInputSettings(
                  size: 4,
                  correction: BrushCorrection(steadies: steadied),
                ),
                overlayModel: overlay,
                onSourceStrokeCommitted: (_) {},
              ),
            ),
          ),
        ),
      );

      var time = Duration.zero;
      PointerEvent move(Offset local) {
        time += const Duration(milliseconds: 8);
        return PointerMoveEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: canvasGlobalOffset(tester, local),
          timeStamp: time,
          pressure: 1,
          pressureMin: 0,
          pressureMax: 1,
        );
      }

      tester.binding.handlePointerEvent(
        PointerDownEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: canvasGlobalOffset(tester, const Offset(10, 20)),
          timeStamp: time,
          pressure: 1,
          pressureMin: 0,
          pressureMax: 1,
        ),
      );
      await tester.pump();
      tester.binding.handlePointerEvent(move(const Offset(40, 20)));
      await tester.pump();

      final before = overlay.dabs.length;
      tester.binding.handlePointerEvent(move(const Offset(120, 20)));
      expect(
        overlay.dabs.length,
        greaterThan(before),
        reason: 'on the stroke with no frame since the sample came',
      );

      tester.binding.handlePointerEvent(
        PointerUpEvent(
          pointer: 1,
          kind: PointerDeviceKind.stylus,
          position: canvasGlobalOffset(tester, const Offset(120, 20)),
          timeStamp: time + const Duration(milliseconds: 8),
        ),
      );
      await tester.pump();
      await tester.pump();
    });
  }
}
