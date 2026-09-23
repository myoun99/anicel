import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/canvas/canvas_viewport_gesture_layer.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';
import '../../helpers/dart_sources.dart';

/// H23 — **one wheel notch, one consumer.**
///
/// 유저 2026-08-23: 「휠 줌이 패널과 띠에서 동시 발동」.
///
/// 🚨The mechanism, measured rather than guessed: a `Listener`'s
/// `onPointerSignal` does NOT consume the event. Flutter offers a pointer
/// signal to EVERY listener in the hit path, and the one way to make it
/// exclusive is [PointerSignalResolver] — which nothing in this app was using.
/// So a notch over a control that sits inside the canvas's gesture layer moved
/// the control AND zoomed the view, from one turn of the wheel.
///
/// ⇒ The law is "register, do not handle": whoever is deepest under the
/// pointer wins, because that is who the pointer is pointing at.
void main() {
  Future<({double zoom, double slider})> wheelOverSlider(
    WidgetTester tester,
  ) async {
    var viewport = CanvasViewport();
    var slider = 0.5;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: CanvasViewportGestureLayer(
              viewport: viewport,
              onViewportChanged: (next) => setState(() => viewport = next),
              child: Center(
                child: SizedBox(
                  width: 200,
                  height: 24,
                  child: FieldSlider(
                    key: const ValueKey<String>('probe-slider'),
                    min: 0,
                    max: 1,
                    value: slider,
                    label: 'Probe',
                    onChanged: (next) => setState(() => slider = next),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final centre = tester.getCenter(
      find.byKey(const ValueKey<String>('probe-slider')),
    );
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(centre));
    await tester.sendEventToBinding(
      pointer.scroll(const Offset(0, -60)),
    );
    await tester.pumpAndSettle();

    return (zoom: viewport.zoom, slider: slider);
  }

  testWidgets('a notch over a control moves the control and NOT the view', (
    tester,
  ) async {
    final after = await wheelOverSlider(tester);

    expect(
      after.slider,
      isNot(0.5),
      reason: 'fixture premise: the notch reached the control under it',
    );
    expect(
      after.zoom,
      CanvasViewport().zoom,
      reason: 'one notch is one edit — the view is not also zoomed by the '
          'same turn of the wheel',
    );
  });

  testWidgets('and a notch over BARE canvas still zooms it', (tester) async {
    var viewport = CanvasViewport();

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: CanvasViewportGestureLayer(
              viewport: viewport,
              onViewportChanged: (next) => setState(() => viewport = next),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(const Offset(400, 300)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -60)));
    await tester.pumpAndSettle();

    expect(
      viewport.zoom,
      greaterThan(CanvasViewport().zoom),
      reason: 'the law is one consumer, not none — with nothing deeper to '
          'win the notch, the view takes it',
    );
  });

  /// ⚠️The behaviour above only holds while every wheel consumer REGISTERS.
  /// One that handles directly takes the notch before anything deeper is
  /// offered it, which is the bug with the resolver present — and a source
  /// scan is the only thing that sees a consumer no test happens to stack.
  test('every wheel consumer registers instead of handling', () {
    const observers = <String, String>{
      'lib/src/ui/debug/input_inspector.dart':
          'a debug READOUT — a reader that competed for the event would '
              'change what it is reading',
      'lib/src/ui/playback/playback_actuation_gate.dart':
          'T28-c: the first actuation of any kind stops playback, so it has '
              'to see every notch including one a deeper surface wins',
    };

    final offenders = <String>[];
    for (final entry in dartFilesUnder('lib/src/ui')) {
      final relative = entry.path.replaceAll('\\', '/');
      final key = relative.substring(relative.indexOf('lib/src/ui'));
      if (observers.containsKey(key)) {
        continue;
      }
      final text = entry.readAsStringSync();
      if (!text.contains('onPointerSignal')) {
        continue;
      }
      // Either arm of the law: compete for the notch, or defer to the list
      // this control might be sitting in and compete only outside one.
      if (!text.contains('handleWheelExclusively') &&
          !text.contains('handleWheelUnlessScrolling')) {
        offenders.add(key);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'use handleWheelExclusively, or add the file to the observer '
          'ledger above with a sentence saying why it must not compete',
    );
  });
}
