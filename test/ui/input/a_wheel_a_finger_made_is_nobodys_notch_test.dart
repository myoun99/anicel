import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// 🚨★★★A WHEEL THAT A FINGER MADE IS NOBODY'S NOTCH.
///
/// 유저 실기 2026-09-17 (보조 손가락 핀치 줌 스냅, 터치): 「작동은 함. 근데
/// 100다음 200인데 **110**에 간다거나. 200다음 300인데 200에서 **220**에 가고
/// 300간다거나. **1프레임정도 그렇게 튀는 순간이있음**」.
///
/// 110 and 220 are the snapped stop times 1.1 — exactly one notch of the
/// wheel zoom (`_zoomByWheel`). Windows promotes a touch PINCH to a legacy
/// `mouse scroll` at the centroid and Flutter delivers it (the capture in
/// `CanvasTouchContacts`, 2026-08-23: 「mouse scroll #0 ← the pinch, promoted
/// to a WHEEL」). The touch engine was holding the view on a stop; the echo
/// zoomed the LIVE view by a notch through a road that knows nothing of the
/// constraint; the engine's next update put it back. One frame of a zoom
/// nobody asked for — 「보이는 중 ≠ 결과」, from an input nobody made.
///
/// A free pinch takes the same blip; it only reads as a number on the pill
/// when the stops are far apart.
void main() {
  setUp(CanvasTouchContacts.reset);
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  /// The app's ONE always-mounted pointer observer around a canvas gesture
  /// layer — the production arrangement, so the finger census is fed the
  /// way it really is.
  Future<List<CanvasViewport>> pumpCanvas(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    AppInput.settings.value = AppInputSettings.testCorpusBaseline.copyWith(
      // The engine drives touch only off a non-draw one-finger slot.
      touchDragOneFinger: CanvasTouchDragAction.flip,
      zoomSnapPercents: const [100, 200, 300],
    );
    final emitted = <CanvasViewport>[];
    var viewport = CanvasViewport();
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: InputInspectorHost(
              child: CanvasViewportGestureLayer(
                viewport: viewport,
                onViewportChanged: (next) {
                  emitted.add(next);
                  setState(() => viewport = next);
                },
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
    await tester.pumpAndSettle();
    return emitted;
  }

  /// One notch UP (zoom in) from a mouse at [position] — what Windows sends
  /// for a pinch-out, and what a hand on a wheel sends.
  Future<void> wheelIn(WidgetTester tester, Offset position) async {
    final mouse = TestPointer(77, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(position));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
    await tester.pump();
  }

  testWidgets('🚨mid-pinch, held on a stop by the modifier finger: the echo '
      'of the pinch does not zoom the view a notch past it', (tester) async {
    final emitted = await pumpCanvas(tester);

    // Two fingers pinch out to about 2×, then the MODIFIER lands: the zoom
    // is held on the nearest stop of [100, 200, 300].
    final first = await tester.startGesture(
      const Offset(300, 300),
      kind: PointerDeviceKind.touch,
      pointer: 41,
    );
    final second = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.touch,
      pointer: 42,
    );
    await first.moveBy(const Offset(-50, 0));
    await second.moveBy(const Offset(50, 0));
    await tester.pump();
    final modifier = await tester.startGesture(
      const Offset(350, 420),
      kind: PointerDeviceKind.touch,
      pointer: 43,
    );
    await tester.pump();
    await second.moveBy(const Offset(2, 0));
    await tester.pump();
    expect(
      emitted.last.zoom,
      closeTo(2.0, 1e-9),
      reason: 'fixture: the modifier holds the pinch on the 200% stop',
    );
    final before = emitted.length;

    // Windows' echo of the pinch, at the centroid.
    await wheelIn(tester, const Offset(350, 300));

    expect(
      emitted.skip(before).map((view) => (view.zoom * 100).round()).toList(),
      isEmpty,
      reason: 'the wheel zoom is one notch (×1.1) of the LIVE view — 220% '
          'on screen for the frame before the engine puts the stop back. '
          'While a finger is on the glass a wheel is the promotion\'s echo, '
          'not a hand on a mouse',
    );

    await first.up();
    await second.up();
    await modifier.up();
    await tester.pump();
  });

  testWidgets('a FREE pinch takes no notch from its own echo either', (
    tester,
  ) async {
    final emitted = await pumpCanvas(tester);
    final first = await tester.startGesture(
      const Offset(300, 300),
      kind: PointerDeviceKind.touch,
      pointer: 41,
    );
    final second = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.touch,
      pointer: 42,
    );
    await first.moveBy(const Offset(-25, 0));
    await second.moveBy(const Offset(25, 0));
    await tester.pump();
    final pinched = emitted.last.zoom;
    expect(pinched, closeTo(1.5, 1e-9), reason: 'fixture: 100px → 150px');

    await wheelIn(tester, const Offset(350, 300));

    expect(emitted.last.zoom, pinched);
    await first.up();
    await second.up();
    await tester.pump();
  });

  testWidgets('⛔with no finger down the wheel is a hand on a mouse, and '
      'zooms its notch', (tester) async {
    final emitted = await pumpCanvas(tester);

    await wheelIn(tester, const Offset(350, 300));

    expect(emitted, hasLength(1));
    expect(
      emitted.single.zoom,
      closeTo(1.1, 1e-9),
      reason: 'the law refuses an echo, not the wheel',
    );
  });

  testWidgets('the law is the FUNNEL\'s, so a bar under the echo does not '
      'step either', (tester) async {
    // A finger anywhere in the app — the census is app-wide on purpose: a
    // pinch over one panel echoes wherever Windows parks the cursor.
    var value = 50.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputInspectorHost(
            child: Center(
              child: SizedBox(
                width: 200,
                child: StatefulBuilder(
                  builder: (context, setState) => FieldSlider(
                    value: value,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    onChanged: (next) => setState(() => value = next),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final bar = tester.getCenter(find.byType(FieldSlider));

    await wheelIn(tester, bar);
    final stepped = value;
    expect(stepped, isNot(50.0), reason: 'control: a wheel steps the bar');

    final finger = await tester.startGesture(
      const Offset(20, 20),
      kind: PointerDeviceKind.touch,
      pointer: 51,
    );
    await wheelIn(tester, bar);
    expect(value, stepped, reason: 'a finger is down: the wheel is its echo');

    await finger.up();
    await tester.pump();
    await wheelIn(tester, bar);
    expect(value, isNot(stepped), reason: 'the finger lifted: a wheel again');
  });
}
