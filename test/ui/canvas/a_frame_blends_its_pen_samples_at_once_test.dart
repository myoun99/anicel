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

/// 🚨A pen's samples blend once a frame, all that came since the last
/// together (F-600, 유저 11-17 「펜은 어느정도 빠른데 마우스는 심하게
/// 느림」): a blend a sample was a GPU submission a sample, and a mouse
/// hands five times a pen's. On the frame that follows them still — F-512,
/// 유저 10-30 「선이 커서 뒤로 처진다」: the picture is made at that frame's
/// paint, after the blend.
void main() {
  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  for (final kind in const [
    PointerDeviceKind.stylus,
    PointerDeviceKind.mouse,
  ]) {
    for (final steadied in const [false, true]) {
      testWidgets('🚨the samples blend at the next frame, together '
          '(${kind.name}, '
          '${steadied ? 'a steadied line' : 'a line as the pen went'})', (
        tester,
      ) async {
        final overlay = ActiveStrokeOverlayModel(tileSize: 128);
        addTearDown(overlay.dispose);
        final cel = BitmapSurface(
          canvasSize: const CanvasSize(width: 200, height: 40),
          tileSize: 128,
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
            kind: kind,
            buttons: kPrimaryButton,
            position: canvasGlobalOffset(tester, local),
            timeStamp: time,
            pressure: 1,
            pressureMin: 0,
            pressureMax: 1,
          );
        }

        tester.binding.handlePointerEvent(
          PointerAddedEvent(
            kind: kind,
            position: canvasGlobalOffset(tester, const Offset(10, 20)),
          ),
        );
        tester.binding.handlePointerEvent(
          PointerDownEvent(
            pointer: 1,
            kind: kind,
            buttons: kPrimaryButton,
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
        tester.binding.handlePointerEvent(move(const Offset(80, 20)));
        tester.binding.handlePointerEvent(move(const Offset(120, 20)));
        expect(
          overlay.dabs.length,
          before,
          reason: 'nothing blended a sample at a time',
        );
        await tester.pump();
        expect(
          overlay.dabs.length,
          greaterThan(before),
          reason: 'on the stroke at the frame that follows them',
        );

        tester.binding.handlePointerEvent(
          PointerUpEvent(
            pointer: 1,
            kind: kind,
            position: canvasGlobalOffset(tester, const Offset(120, 20)),
            timeStamp: time + const Duration(milliseconds: 8),
          ),
        );
        await tester.pump();
        await tester.pump();
      });
    }
  }
}
