import 'package:flutter/gestures.dart'
    show kPrimaryButton, kPrimaryStylusButton, kSecondaryStylusButton;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/qa_tablet_bridge.dart';
import 'package:anicel/src/services/input/pen_sidecars.dart';
import 'package:anicel/src/services/input/raw_pen_input_service.dart';
import 'package:anicel/src/services/input/wintab_pen_service.dart';

/// Path E: the Raw Input HID observer — the pen's DECLARED switches.
void main() {
  tearDown(() {
    RawPenInputService.instance.debugReset();
    WintabPenService.instance.debugReset();
    PenSidecars.debugReset();
  });

  test(
    'declared HID switches become Flutter buttons and a tail flag',
    () async {
      final service = RawPenInputService.instance;
      RawPenInputService.debugClockOverride = () => DateTime(2024);
      QaPenRawState? next;
      service.debugPollOverride = () => next;
      service.start();

      expect(service.freshButtons(), isNull, reason: 'nothing reported yet');
      expect(service.freshInverted(), isNull);

      // Barrel switch down with nothing touching: a BUTTON, which is
      // precisely what Windows Ink turns into a phantom drawing contact.
      next = const QaPenRawState(flags: 0x02, sequence: 1);
      await Future<void>.delayed(RawPenInputService.pollInterval * 3);
      expect(service.freshButtons(), kPrimaryStylusButton);
      expect(service.freshInverted(), isFalse);

      // The tail merely HOVERING — Invert with no contact. This is the
      // report the flip-scoped tail mapping engages on.
      next = const QaPenRawState(flags: 0x08, sequence: 2);
      await Future<void>.delayed(RawPenInputService.pollInterval * 3);
      expect(service.freshButtons(), 0, reason: 'hovering is not a contact');
      expect(service.freshInverted(), isTrue);

      // The tail TOUCHING: a primary (drawing) contact that is still the
      // tail — it draws, it just draws as the eraser.
      next = const QaPenRawState(flags: 0x04 | 0x08, sequence: 3);
      await Future<void>.delayed(RawPenInputService.pollInterval * 3);
      expect(service.freshButtons(), kPrimaryButton);
      expect(service.freshInverted(), isTrue);

      // Upper side switch.
      next = const QaPenRawState(flags: 0x10, sequence: 4);
      await Future<void>.delayed(RawPenInputService.pollInterval * 3);
      expect(service.freshButtons(), kSecondaryStylusButton);

      // Past the freshness window nothing speaks for the pen any more.
      final stale = DateTime(
        2024,
      ).add(RawPenInputService.freshWindow + const Duration(milliseconds: 1));
      expect(service.freshButtons(now: stale), isNull);
      expect(service.freshInverted(now: stale), isNull);

      service.stop();
      expect(service.freshButtons(), isNull, reason: 'idle observer is silent');
    },
  );

  test('a repeated report does not refresh the window', () async {
    final service = RawPenInputService.instance;
    var clock = DateTime(2024);
    RawPenInputService.debugClockOverride = () => clock;
    // A pen resting in proximity repeats its last flags forever; that is
    // not news, and treating it as news would keep a stale barrel state
    // alive indefinitely.
    service.debugPollOverride = () =>
        const QaPenRawState(flags: 0x02, sequence: 7);
    service.start();
    await Future<void>.delayed(RawPenInputService.pollInterval * 3);
    expect(service.freshButtons(), kPrimaryStylusButton);

    clock = DateTime(
      2024,
    ).add(RawPenInputService.freshWindow + const Duration(milliseconds: 1));
    await Future<void>.delayed(RawPenInputService.pollInterval * 3);
    expect(
      service.freshButtons(),
      isNull,
      reason: 'the counter never moved, so the report aged out',
    );

    service.stop();
  });

  test('the facade prefers the HID observer over Wintab', () async {
    final raw = RawPenInputService.instance;
    final wintab = WintabPenService.instance;
    RawPenInputService.debugClockOverride = () => DateTime(2024);
    WintabPenService.debugClockOverride = () => DateTime(2024);

    // Wintab says the LOWER barrel; HID says the UPPER one. HID wins:
    // it names the switch, where Wintab's word is positional.
    wintab.debugPollOverride = () => const [];
    wintab.start();
    wintab.debugInjectPacket(
      const QaTabletPacket(
        pressure: 0,
        tiltAzimuthDegrees: 0,
        altitude: 1,
        timeMs: 1,
        buttons: 0x02,
      ),
    );
    expect(PenSidecars.freshButtons(), kPrimaryStylusButton);

    raw.debugPollOverride = () => const QaPenRawState(flags: 0x10, sequence: 1);
    raw.start();
    await Future<void>.delayed(RawPenInputService.pollInterval * 3);
    expect(PenSidecars.freshButtons(), kSecondaryStylusButton);

    // And the tail flag only ever comes from HID.
    expect(PenSidecars.freshInverted(), isFalse);
    raw.debugInjectState(const QaPenRawState(flags: 0x08, sequence: 2));
    expect(PenSidecars.freshInverted(), isTrue);

    raw.stop();
    wintab.stop();
  });
}
