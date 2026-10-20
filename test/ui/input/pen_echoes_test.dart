import 'dart:io' show File;
import 'dart:ui' as ui show PointerChange, PointerData, PointerDataPacket;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/debug/input_inspector.dart';
import 'package:anicel/src/ui/input/pen_echoes.dart';

import '../../helpers/scaled_test_binding.dart';

/// 🗣️F-400 — what a pen in range keeps out, and where; see [PenEchoes].
/// 🗣️F-427 — and how it leaves where the window could not hear it go.
void main() {
  final binding = ScaledTestBinding.ensureInitialized();
  // The runner's own channel, read from it: the app is told on this.
  final windowHearsAgain = RegExp(
    r'kWindowHearsAgainChannel\[\] = "([^"]*)";',
  ).firstMatch(
    File('windows/runner/flutter_window.cpp').readAsStringSync(),
  )?.group(1);

  const pen = PointerDeviceKind.stylus;
  const mouse = PointerDeviceKind.mouse;
  const penDevice = 3;

  group('the law', () {
    late PenEchoes echoes;
    setUp(() => echoes = PenEchoes());

    bool admit(PointerEvent event) => echoes.admit(event);

    test('🚨the F-400 screenshot: while the pen drags a block and hovers off '
        'it, the mouse the OS echoes it as never comes in', () {
      expect(
        admit(const PointerAddedEvent(kind: pen, device: penDevice)),
        isTrue,
      );
      expect(
        admit(const PointerHoverEvent(kind: pen, device: penDevice)),
        isTrue,
      );
      expect(
        admit(
          const PointerDownEvent(pointer: 6188, kind: pen, device: penDevice),
        ),
        isTrue,
      );
      expect(
        admit(const PointerAddedEvent(kind: mouse)),
        isTrue,
        reason: 'the mouse tracker keeps the device by its arrival',
      );
      // Every echo with the pen's button is a press under a new pointer.
      expect(admit(const PointerDownEvent(pointer: 6193, kind: mouse)), isFalse);
      expect(
        admit(
          const PointerMoveEvent(pointer: 6188, kind: pen, device: penDevice),
        ),
        isTrue,
      );
      expect(admit(const PointerDownEvent(pointer: 6194, kind: mouse)), isFalse);
      expect(
        admit(
          const PointerUpEvent(pointer: 6188, kind: pen, device: penDevice),
        ),
        isTrue,
      );
      expect(
        admit(const PointerHoverEvent(kind: pen, device: penDevice)),
        isTrue,
      );
      expect(
        admit(const PointerHoverEvent(kind: mouse)),
        isFalse,
        reason: 'the mouse hover row among the pen\'s',
      );
    });

    test('an echo\'s press stays out through its own lift, even one that comes '
        'after the pen has left — and then the mouse is the mouse again', () {
      admit(const PointerAddedEvent(kind: pen, device: penDevice));
      expect(admit(const PointerDownEvent(pointer: 10, kind: mouse)), isFalse);
      expect(admit(const PointerMoveEvent(pointer: 10, kind: mouse)), isFalse);
      admit(const PointerRemovedEvent(kind: pen, device: penDevice));

      expect(admit(const PointerMoveEvent(pointer: 10, kind: mouse)), isFalse);
      expect(admit(const PointerCancelEvent(pointer: 10, kind: mouse)), isFalse);

      expect(admit(const PointerHoverEvent(kind: mouse)), isTrue);
      expect(admit(const PointerDownEvent(pointer: 11, kind: mouse)), isTrue);
      expect(admit(const PointerMoveEvent(pointer: 11, kind: mouse)), isTrue);
      expect(admit(const PointerUpEvent(pointer: 11, kind: mouse)), isTrue);
    });

    test('an echo\'s UP stays out as its cancel does', () {
      admit(const PointerAddedEvent(kind: pen, device: penDevice));
      admit(const PointerDownEvent(pointer: 12, kind: mouse));

      expect(admit(const PointerUpEvent(pointer: 12, kind: mouse)), isFalse);
    });

    test('a press the mouse began before any pen came is the mouse\'s to its '
        'end, and the next one is an echo', () {
      expect(admit(const PointerDownEvent(pointer: 1, kind: mouse)), isTrue);
      admit(const PointerAddedEvent(kind: pen, device: penDevice));
      admit(const PointerHoverEvent(kind: pen, device: penDevice));

      expect(admit(const PointerMoveEvent(pointer: 1, kind: mouse)), isTrue);
      expect(admit(const PointerUpEvent(pointer: 1, kind: mouse)), isTrue);
      expect(admit(const PointerDownEvent(pointer: 2, kind: mouse)), isFalse);
    });

    test('the mouse\'s arrival and removal always come in, and its wheel', () {
      admit(const PointerAddedEvent(kind: pen, device: penDevice));

      expect(admit(const PointerAddedEvent(kind: mouse)), isTrue);
      expect(
        admit(
          const PointerScrollEvent(kind: mouse, scrollDelta: Offset(0, 120)),
        ),
        isTrue,
      );
      expect(admit(const PointerRemovedEvent(kind: mouse)), isTrue);
    });

    test('the eraser end is the pen in range too', () {
      admit(
        const PointerAddedEvent(
          kind: PointerDeviceKind.invertedStylus,
          device: penDevice,
        ),
      );
      expect(admit(const PointerHoverEvent(kind: mouse)), isFalse);

      admit(
        const PointerRemovedEvent(
          kind: PointerDeviceKind.invertedStylus,
          device: penDevice,
        ),
      );
      expect(admit(const PointerHoverEvent(kind: mouse)), isTrue);
    });

    test('with two pens the mouse is back only when the last one leaves', () {
      admit(const PointerAddedEvent(kind: pen, device: 3));
      admit(const PointerAddedEvent(kind: pen, device: 4));
      admit(const PointerRemovedEvent(kind: pen, device: 3));
      expect(admit(const PointerHoverEvent(kind: mouse)), isFalse);

      admit(const PointerRemovedEvent(kind: pen, device: 4));
      expect(admit(const PointerHoverEvent(kind: mouse)), isTrue);
    });

    test('⛔a finger is no pen: it keeps no mouse out, and nothing keeps it '
        'out', () {
      const finger = PointerDeviceKind.touch;
      expect(
        admit(const PointerDownEvent(pointer: 30, kind: finger, device: 7)),
        isTrue,
      );
      expect(admit(const PointerHoverEvent(kind: mouse)), isTrue);
      expect(admit(const PointerDownEvent(pointer: 31, kind: mouse)), isTrue);

      admit(const PointerAddedEvent(kind: pen, device: penDevice));
      expect(
        admit(const PointerMoveEvent(pointer: 30, kind: finger, device: 7)),
        isTrue,
      );
    });

    test('without a pen nothing is kept out', () {
      expect(admit(const PointerHoverEvent(kind: mouse)), isTrue);
      expect(admit(const PointerDownEvent(pointer: 40, kind: mouse)), isTrue);
      expect(admit(const PointerMoveEvent(pointer: 40, kind: mouse)), isTrue);
      expect(admit(const PointerCancelEvent(pointer: 40, kind: mouse)), isTrue);
    });

    test('🚨F-427: the leave of every pen in range, made for a window that '
        'could not hear them go — and with them in, the mouse is back', () {
      admit(const PointerAddedEvent(kind: pen, device: penDevice));
      admit(
        const PointerHoverEvent(
          kind: pen,
          device: penDevice,
          position: Offset(5, 6),
        ),
      );
      admit(
        const PointerHoverEvent(
          kind: PointerDeviceKind.invertedStylus,
          device: 4,
          position: Offset(7, 8),
        ),
      );
      final leaves = echoes.leavesUnheard();
      expect(
        [
          for (final leave in leaves)
            (leave.kind, leave.device, leave.position),
        ],
        [
          (pen, penDevice, const Offset(5, 6)),
          (PointerDeviceKind.invertedStylus, 4, const Offset(7, 8)),
        ],
      );
      expect(
        admit(const PointerHoverEvent(kind: mouse)),
        isFalse,
        reason: 'made, not yet in',
      );

      expect(leaves.every(admit), isTrue);
      expect(admit(const PointerHoverEvent(kind: mouse)), isTrue);
      expect(echoes.leavesUnheard(), isEmpty);
    });
  });

  group('where it stands — the binding, where the platform\'s events come '
      'in', () {
    tearDown(InputInspector.reset);

    ui.PointerData at(
      WidgetTester tester,
      ui.PointerChange change,
      PointerDeviceKind kind, {
      int device = 0,
      int pointer = 0,
      int buttons = 0,
    }) => ui.PointerData(
      viewId: tester.view.viewId,
      change: change,
      kind: kind,
      device: device,
      pointerIdentifier: pointer,
      buttons: buttons,
      physicalX: 300,
      physicalY: 300,
    );

    // A pen in the air over the window, and the mouse the OS echoes it as:
    // a hover, then a press with the pen's button.
    List<ui.PointerData> aPenAndItsEcho(WidgetTester tester) => [
      at(tester, ui.PointerChange.add, pen, device: penDevice),
      at(tester, ui.PointerChange.hover, pen, device: penDevice),
      at(tester, ui.PointerChange.add, mouse),
      at(tester, ui.PointerChange.hover, mouse),
      at(
        tester,
        ui.PointerChange.down,
        mouse,
        pointer: 9,
        buttons: kPrimaryButton,
      ),
    ];

    // The echo's lift, the pen leaving, and the mouse moving after it.
    List<ui.PointerData> thePenLeaves(WidgetTester tester) => [
      at(tester, ui.PointerChange.up, mouse, pointer: 9),
      at(tester, ui.PointerChange.remove, pen, device: penDevice),
      at(tester, ui.PointerChange.hover, mouse),
      at(tester, ui.PointerChange.remove, mouse),
    ];

    Future<List<String>> listen(WidgetTester tester) async {
      final heard = <String>[];
      void hear(String phase, PointerEvent event) =>
          heard.add('${event.kind.name} $phase');
      await tester.pumpWidget(
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerHover: (event) => hear('hover', event),
          onPointerDown: (event) => hear('down', event),
          onPointerUp: (event) => hear('up', event),
          onPointerCancel: (event) => hear('cancel', event),
          child: const SizedBox.expand(),
        ),
      );
      return heard;
    }

    void send(List<ui.PointerData> data) =>
        binding.pumpPointerPacket(ui.PointerDataPacket(data: data));

    testWidgets(
      '🚨on Windows the echo stays out ahead of every listener, and the '
      'inspector counts what it kept out',
      (tester) async {
        final heard = await listen(tester);

        send(aPenAndItsEcho(tester));
        expect(heard, ['stylus hover']);
        expect(InputInspector.echoes, 2);

        send(thePenLeaves(tester));
        expect(
          heard,
          ['stylus hover', 'mouse hover'],
          reason: 'the echo\'s lift stays out; the mouse after the pen is in',
        );
        expect(InputInspector.echoes, 3);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      '🚨F-427: a window that hears again — the runner says so — lets every '
      'pen it held go, as the pen\'s own leave would: its hover ends and the '
      'mouse is heard again',
      (tester) async {
        final heard = <String>[];
        await tester.pumpWidget(
          MouseRegion(
            onExit: (event) => heard.add('${event.kind.name} exit'),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerHover: (event) => heard.add('${event.kind.name} hover'),
              child: const SizedBox.expand(),
            ),
          ),
        );
        send([
          at(tester, ui.PointerChange.add, pen, device: penDevice),
          at(tester, ui.PointerChange.hover, pen, device: penDevice),
          at(tester, ui.PointerChange.add, mouse),
          at(tester, ui.PointerChange.hover, mouse),
        ]);
        expect(heard, ['stylus hover']);

        await binding.defaultBinaryMessenger.handlePlatformMessage(
          windowHearsAgain!,
          null,
          (_) {},
        );
        send([at(tester, ui.PointerChange.hover, mouse)]);
        expect(heard, ['stylus hover', 'stylus exit', 'mouse hover']);
        send([at(tester, ui.PointerChange.remove, mouse)]);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'elsewhere nothing is kept out — no other OS has been seen to echo a '
      'pen',
      (tester) async {
        final heard = await listen(tester);

        send(aPenAndItsEcho(tester));
        send(thePenLeaves(tester));

        expect(heard, [
          'stylus hover',
          'mouse hover',
          'mouse down',
          'mouse up',
          'mouse hover',
        ]);
        expect(InputInspector.echoes, 0);
      },
      variant: TargetPlatformVariant.all(
        excluding: <TargetPlatform>{TargetPlatform.windows},
      ),
    );
  });
}
