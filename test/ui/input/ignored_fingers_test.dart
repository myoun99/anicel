import 'dart:ui' as ui show PointerChange, PointerData, PointerDataPacket;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/input/ignored_fingers.dart';

import '../../helpers/scaled_test_binding.dart';

/// 🗣️I-124 (유저 2026-10-22): 「모든 터치입력 무시하는 옵션」 — what the
/// switch keeps out, and where; see [IgnoredFingers].
void main() {
  final binding = ScaledTestBinding.ensureInitialized();

  const finger = PointerDeviceKind.touch;

  group('the law', () {
    late IgnoredFingers fingers;
    setUp(() => fingers = IgnoredFingers());

    List<bool> admit(List<PointerEvent> events, {required bool ignoring}) => [
      for (final event in events) fingers.admit(event, ignoring: ignoring),
    ];

    List<PointerEvent> aContact(int pointer, {PointerDeviceKind? kind}) => [
      PointerDownEvent(pointer: pointer, kind: kind ?? finger),
      PointerMoveEvent(pointer: pointer, kind: kind ?? finger),
      PointerUpEvent(pointer: pointer, kind: kind ?? finger),
    ];

    test('ignored, a finger\'s press, move and lift all stay out', () {
      expect(admit(aContact(1), ignoring: true), [false, false, false]);
    });

    test('heard, every finger comes in', () {
      expect(admit(aContact(1), ignoring: false), [true, true, true]);
    });

    test('a pen and a mouse are no finger', () {
      for (final (pointer, kind) in const [
        (2, PointerDeviceKind.stylus),
        (3, PointerDeviceKind.mouse),
      ]) {
        expect(
          admit(aContact(pointer, kind: kind), ignoring: true),
          [true, true, true],
          reason: kind.name,
        );
      }
    });

    test('a contact already on the glass when the switch goes on comes in to '
        'its end — a lift kept out would leave it pressed for good', () {
      expect(
        fingers.admit(
          const PointerDownEvent(pointer: 4, kind: finger),
          ignoring: false,
        ),
        isTrue,
      );
      expect(
        admit(const [
          PointerMoveEvent(pointer: 4, kind: finger),
          PointerCancelEvent(pointer: 4, kind: finger),
        ], ignoring: true),
        [true, true],
      );
      expect(
        fingers.admit(
          const PointerDownEvent(pointer: 5, kind: finger),
          ignoring: true,
        ),
        isFalse,
        reason: 'the next contact is pressed while the switch is on',
      );
    });

    test('a contact pressed while ignored stays out through its own lift, '
        'even if the switch comes off first', () {
      expect(
        fingers.admit(
          const PointerDownEvent(pointer: 6, kind: finger),
          ignoring: true,
        ),
        isFalse,
      );
      expect(
        admit(const [
          PointerMoveEvent(pointer: 6, kind: finger),
          PointerUpEvent(pointer: 6, kind: finger),
        ], ignoring: false),
        [false, false],
      );
      expect(
        admit(aContact(7), ignoring: false),
        [true, true, true],
        reason: 'the next contact is pressed after the switch came off',
      );
    });

    test('a finger the door never saw press follows the switch', () {
      const stray = PointerHoverEvent(pointer: 8, kind: finger);
      expect(fingers.admit(stray, ignoring: true), isFalse);
      expect(fingers.admit(stray, ignoring: false), isTrue);
    });

    test('a finger\'s arrival and removal always come in — they are no '
        'contact', () {
      expect(
        admit(const [
          PointerAddedEvent(kind: finger),
          PointerRemovedEvent(kind: finger),
        ], ignoring: true),
        [true, true],
      );
    });
  });

  group('where it stands — the binding, where the platform\'s events come '
      'in', () {
    tearDown(
      () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
    );

    ui.PointerData at(
      WidgetTester tester,
      ui.PointerChange change,
      PointerDeviceKind kind, {
      int pointer = 0,
    }) => ui.PointerData(
      viewId: tester.view.viewId,
      change: change,
      kind: kind,
      device: kind == finger ? 1 : 0,
      pointerIdentifier: pointer,
      physicalX: 300,
      physicalY: 300,
    );

    testWidgets(
      'switched on, no finger reaches the tree — a mouse beside it does; '
      'switched off, the next finger does',
      (tester) async {
        final heard = <String>[];
        void hear(String phase, PointerEvent event) =>
            heard.add('${event.kind.name} $phase');
        await tester.pumpWidget(
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerHover: (event) => hear('hover', event),
            onPointerDown: (event) => hear('down', event),
            onPointerUp: (event) => hear('up', event),
            child: const SizedBox.expand(),
          ),
        );
        void send(List<ui.PointerData> data) =>
            binding.pumpPointerPacket(ui.PointerDataPacket(data: data));
        List<ui.PointerData> aTap(int pointer) => [
          at(tester, ui.PointerChange.add, finger, pointer: pointer),
          at(tester, ui.PointerChange.down, finger, pointer: pointer),
          at(tester, ui.PointerChange.up, finger, pointer: pointer),
          at(tester, ui.PointerChange.remove, finger, pointer: pointer),
        ];

        AppInput.settings.value = AppInputSettings.testCorpusBaseline
            .copyWith(touchIgnored: true);
        send([
          ...aTap(1),
          at(tester, ui.PointerChange.add, PointerDeviceKind.mouse),
          at(tester, ui.PointerChange.hover, PointerDeviceKind.mouse),
          at(tester, ui.PointerChange.remove, PointerDeviceKind.mouse),
        ]);
        expect(heard, ['mouse hover']);

        AppInput.settings.value = AppInputSettings.testCorpusBaseline;
        send(aTap(2));
        expect(heard, ['mouse hover', 'touch down', 'touch up']);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
      }),
    );
  });
}
