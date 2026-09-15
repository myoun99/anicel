import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/effective_device_pixel_ratio.dart';

/// 🚨THE MODIFIER-PINCH SNAPS TO THE PERCENT THE READOUT SHOWS (audit
/// 2026-09-15).
///
/// The zoom snap list is written in DISPLAY percent — device pixels per
/// artwork pixel, the unit the readout, a typed zoom and the ± buttons all
/// speak (`CanvasZoomScale`, 유저 확정 2026-08-21). The pinch's constraint
/// snapped the RENDER zoom against it, so at any effective ratio but 1 a
/// constrained pinch landed on the list times the ratio.
void main() {
  tearDown(() {
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  testWidgets('at an effective ratio of 1.5, a modifier pinch lands on a '
      'percent the list names', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
      // The engine drives touch only off a non-draw one-finger slot (the
      // corpus baseline pins draw) — PEN-14's harness does the same.
      touchDragOneFinger: CanvasTouchDragAction.flip,
      // A list on which the render snap and the display snap disagree.
      zoomSnapPercents: const [100, 150, 250],
    );
    final viewports = <CanvasViewport>[];
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(tester.view),
        child: EffectiveDevicePixelRatioScope(
          uiScale: 1.5,
          child: MaterialApp(
            home: Scaffold(
              body: CanvasViewportGestureLayer(
                viewport: CanvasViewport(),
                onViewportChanged: viewports.add,
                onInvokeAction: (_) {},
                onBrushSizeDragStart: () {},
                onBrushSizeDragUpdate: (_, {required snap}) {},
                onBrushSizeDragEnd: () {},
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

    // Two fingers pinch OUT to render 2× — display 300% at this ratio.
    final first = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.touch,
      pointer: 41,
    );
    final second = await tester.startGesture(
      const Offset(300, 200),
      kind: PointerDeviceKind.touch,
      pointer: 42,
    );
    await first.moveBy(const Offset(-50, 0));
    await second.moveBy(const Offset(50, 0));
    await tester.pump();
    expect(
      viewports.last.zoom,
      closeTo(2.0, 0.01),
      reason: 'control: the pinch reached render 2×, before any constraint',
    );

    // The MODIFIER lands and the constraint takes over.
    final modifier = await tester.startGesture(
      const Offset(250, 300),
      kind: PointerDeviceKind.touch,
      pointer: 43,
    );
    await tester.pump();
    await second.moveBy(const Offset(2, 0));
    await tester.pump();

    final displayPercent = viewports.last.zoom * 1.5 * 100;
    expect(
      displayPercent,
      closeTo(250, 1e-6),
      reason: 'about 300% on the readout snaps to the 250 the list names, in '
          'the unit the readout shows — it read '
          '${displayPercent.toStringAsFixed(1)}%',
    );

    await first.up();
    await second.up();
    await modifier.up();
    await tester.pump();
  });
}
