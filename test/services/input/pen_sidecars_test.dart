import 'dart:async';
import 'dart:ui' as ui show PointerChange, PointerData;

import 'package:flutter/gestures.dart'
    show
        Offset,
        PointerDeviceKind,
        PointerEvent,
        PointerHoverEvent,
        PointerMoveEvent,
        computeHitSlop;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_pen_points.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';
import 'package:anicel/src/services/input/pen_path.dart';
import 'package:anicel/src/services/input/pen_sidecars.dart';
import 'package:anicel/src/services/input/platform_pen_channel_service.dart';
import 'package:anicel/src/services/input/raw_pen_input_service.dart';
import 'package:anicel/src/services/input/wintab_pen_service.dart';

/// PEN-4: the macOS channel sidecar + the cross-platform facade.
void main() {
  tearDown(() {
    PenSidecars.debugReset();
    WintabPenService.instance.debugReset();
  });

  test('the channel service consumes samples and stands down when stale '
      'or malformed', () async {
    final controller = StreamController<dynamic>();
    addTearDown(controller.close);
    final service = PlatformPenChannelService(
      'qa_pen/test',
      'test',
      debugStream: controller.stream,
    );
    addTearDown(service.stop);

    expect(service.freshContactPressure(), isNull, reason: 'not started');
    service.start();
    expect(service.running, isTrue);

    controller.add({'pressure': 0.42, 'tiltX': 0.1, 'eraser': true});
    await Future<void>.delayed(Duration.zero);
    expect(service.latest.value?.pressure, 0.42);
    expect(service.latest.value?.eraser, isTrue);
    expect(service.freshContactPressure(), 0.42);

    // Malformed messages never disturb the last good sample.
    controller.add('garbage');
    controller.add(<String, Object>{'noPressure': 1});
    await Future<void>.delayed(Duration.zero);
    expect(service.latest.value?.pressure, 0.42);

    // Out-of-range pressure clamps.
    controller.add({'pressure': 3.2});
    await Future<void>.delayed(Duration.zero);
    expect(service.freshContactPressure(), 1.0);

    // Past the freshness window the override stands down.
    final stale = DateTime.now().add(
      PlatformPenChannelService.freshWindow + const Duration(milliseconds: 1),
    );
    expect(service.freshContactPressure(now: stale), isNull);

    service.stop();
    expect(service.latest.value, isNull);
  });

  test('the facade prefers Wintab, falls back to channel sidecars', () async {
    final controller = StreamController<dynamic>();
    addTearDown(controller.close);
    final channel = PlatformPenChannelService(
      'qa_pen/test',
      'test',
      debugStream: controller.stream,
    )..start();
    PenSidecars.channelServices.add(channel);

    expect(PenSidecars.freshReading(), isNull);

    controller.add({'pressure': 0.3});
    await Future<void>.delayed(Duration.zero);
    expect(PenSidecars.freshReading()?.pressure, 0.3);

    // A live Wintab stream outranks the channel sidecar.
    final wintab = WintabPenService.instance;
    // Freeze the freshness clock so the injected packet cannot age out of
    // the 150ms window while a busy suite runs between inject and read.
    WintabPenService.debugClockOverride = () => DateTime(2024);
    wintab.debugPollOverride = () => const [];
    wintab.start();
    wintab.debugInjectPacket(
      const QaTabletPacket(
        pressure: 0.9,
        timeMs: 1,
        buttons: 1,
      ),
    );
    expect(PenSidecars.freshReading()?.pressure, 0.9);

    wintab.debugReset();
    // A fresh channel sample for the fallback read: the channel's 150 ms
    // window runs on the real clock, and where the pen DLL is built beside
    // the engine `wintab.start()` loads it — under a loaded machine that
    // outlasted the window and the sample above had aged out (the lane's
    // native parity run, 2026-09-27).
    controller.add({'pressure': 0.3});
    await Future<void>.delayed(Duration.zero);
    expect(PenSidecars.freshReading()?.pressure, 0.3);
  });

  test('a reading says whether the pen was touching — the tip bit, or '
      'pressure above zero where there is no bit to read (H43)', () async {
    final wintab = WintabPenService.instance;
    WintabPenService.debugClockOverride = () => DateTime(2024);
    wintab.debugPollOverride = () => const [];
    wintab.start();
    QaTabletPacket packet({required double pressure, required int buttons}) =>
        QaTabletPacket(
          pressure: pressure,
          timeMs: 1,
          buttons: buttons,
        );

    wintab.debugInjectPacket(packet(pressure: 0, buttons: 0));
    expect(PenSidecars.freshReading()?.touching, isFalse, reason: 'hovering');
    wintab.debugInjectPacket(packet(pressure: 0, buttons: 1));
    expect(PenSidecars.freshReading()?.touching, isTrue, reason: 'tip down');
    wintab.debugInjectPacket(packet(pressure: 0.2, buttons: 0));
    expect(
      PenSidecars.freshReading()?.touching,
      isTrue,
      reason: 'a driver that leaves the tip bit clear',
    );
    // The barrel switch is not the tip.
    wintab.debugInjectPacket(packet(pressure: 0, buttons: 2));
    expect(PenSidecars.freshReading()?.touching, isFalse);
    wintab.debugReset();

    final controller = StreamController<dynamic>();
    addTearDown(controller.close);
    PenSidecars.channelServices.add(
      PlatformPenChannelService(
        'qa_pen/test',
        'test',
        debugStream: controller.stream,
      )..start(),
    );
    controller.add({'pressure': 0.0});
    await Future<void>.delayed(Duration.zero);
    expect(PenSidecars.freshReading()?.touching, isFalse);
    controller.add({'pressure': 0.4});
    await Future<void>.delayed(Duration.zero);
    expect(PenSidecars.freshReading()?.touching, isTrue);
  });

  test('the lean comes from HID first, then Wintab\'s orientation, and from '
      'nothing when neither has one (desktop-pen-tilt)', () {
    final hid = RawPenInputService.instance;
    addTearDown(hid.debugReset);
    RawPenInputService.debugClockOverride = () => DateTime(2024);
    QaPenRawState? report;
    hid.debugPollOverride = () => report;
    hid.start();
    final wintab = WintabPenService.instance;
    WintabPenService.debugClockOverride = () => DateTime(2024);
    wintab.debugPollOverride = () => const [];
    wintab.start();

    expect(PenSidecars.leanOf(_hover), isNull, reason: 'nothing speaks');

    // The top toward the user, half way up — while the pen only hovers.
    wintab.debugInjectPacket(
      const QaTabletPacket(
        pressure: 0,
        orientation: (bearing: 180, altitude: 0.5),
        timeMs: 1,
        buttons: 0,
      ),
    );
    expect(PenSidecars.leanOf(_hover), (azimuthDegrees: 90.0, altitude: 0.5));

    // HID outranks it: the top leans right, half way up.
    report = const QaPenRawState(flags: 0x01, sequence: 1, tilt: (x: 45, y: 0));
    expect(PenSidecars.leanOf(_hover)?.azimuthDegrees, closeTo(0, 1e-9));
    expect(PenSidecars.leanOf(_hover)?.altitude, closeTo(0.5, 1e-9));

    report = const QaPenRawState(flags: 0x01, sequence: 2);
    expect(
      PenSidecars.leanOf(_hover)?.azimuthDegrees,
      90.0,
      reason: 'a report with no tilt leaves the lean to Wintab',
    );

    wintab.debugInjectPacket(
      const QaTabletPacket(pressure: 0, timeMs: 2, buttons: 0),
    );
    expect(
      PenSidecars.leanOf(_hover),
      isNull,
      reason: 'a device with no orientation axes leans nowhere',
    );
  });

  test('the twist comes from HID first, then Wintab\'s, once round, and from '
      'nothing when neither has one (F-176-Q9)', () {
    final hid = RawPenInputService.instance;
    addTearDown(hid.debugReset);
    RawPenInputService.debugClockOverride = () => DateTime(2024);
    QaPenRawState? report;
    hid.debugPollOverride = () => report;
    hid.start();
    final wintab = WintabPenService.instance;
    WintabPenService.debugClockOverride = () => DateTime(2024);
    wintab.debugPollOverride = () => const [];
    wintab.start();

    expect(PenSidecars.twistOf(_hover), isNull, reason: 'nothing speaks');

    wintab.debugInjectPacket(
      const QaTabletPacket(
        pressure: 0,
        twistDegrees: 360,
        timeMs: 1,
        buttons: 0,
      ),
    );
    expect(PenSidecars.twistOf(_hover), 0, reason: 'a full turn is none');

    report = const QaPenRawState(flags: 0, sequence: 1, twistDegrees: 135);
    expect(PenSidecars.twistOf(_hover), 135, reason: 'HID outranks it');

    report = const QaPenRawState(flags: 0, sequence: 2);
    expect(
      PenSidecars.twistOf(_hover),
      0,
      reason: 'a report with no twist leaves it to Wintab',
    );

    wintab.debugInjectPacket(
      const QaTabletPacket(pressure: 0, timeMs: 2, buttons: 0),
    );
    expect(
      PenSidecars.twistOf(_hover),
      isNull,
      reason: 'a device with no twist axis is not a pen turned to 0°',
    );
  });

  test("🚨a point's own packet leans and turns it before the newest one — "
      'HID still first (pen-points-are-taken-off-the-ui-thread)', () {
    final hid = RawPenInputService.instance;
    addTearDown(hid.debugReset);
    RawPenInputService.debugClockOverride = () => DateTime(2024);
    QaPenRawState? report;
    hid.debugPollOverride = () => report;
    hid.start();
    final wintab = WintabPenService.instance;
    WintabPenService.debugClockOverride = () => DateTime(2024);
    wintab.debugPollOverride = () => const [];
    wintab.start();
    // The pen now: the top toward the user, half way up, turned 90°.
    wintab.debugInjectPacket(
      const QaTabletPacket(
        pressure: 0.5,
        orientation: (bearing: 180, altitude: 0.5),
        twistDegrees: 90,
        timeMs: 2,
        buttons: 1,
      ),
    );
    // As it was where the point was drawn: the top away, low, turned 300°.
    final drawn = _madeAt(const Offset(10, 20), (
      pressure: 0.4,
      lean: (bearing: 270, altitude: 0.25),
      twist: 300,
    ));

    expect(PenSidecars.leanOf(drawn), (azimuthDegrees: 180.0, altitude: 0.25));
    expect(PenSidecars.twistOf(drawn), 300);
    expect(
      PenSidecars.leanOf(_hover),
      (azimuthDegrees: 90.0, altitude: 0.5),
      reason: 'a point no packet was paired with leans as the pen does now',
    );
    expect(PenSidecars.twistOf(_hover), 90);

    report = const QaPenRawState(
      flags: 0x01,
      sequence: 1,
      tilt: (x: 45, y: 0),
      twistDegrees: 135,
    );
    expect(PenSidecars.leanOf(drawn)?.azimuthDegrees, closeTo(0, 1e-9));
    expect(PenSidecars.twistOf(drawn), 135, reason: 'HID outranks it');
  });

  /// 🗣️THE PEN LAW (tool-settings-panel-tidy, 유저 2026-10-10): 「우선 1번
  /// 제일 확실한방법 좋아. 앞으로의 펜 작동 기준으로 삼으면 좋을거같고」 —
  /// the driver says the pen is touching, so it is the pen, whatever the OS
  /// called it.
  test('🚨THE PEN LAW: a MOUSE while the driver says the pen is down is the '
      'pen — and nothing else moves it', () {
    const mouse = PointerDeviceKind.mouse;
    const stylus = PointerDeviceKind.stylus;
    expect(PenSidecars.kindOf(mouse), mouse, reason: 'no driver speaks');

    final wintab = WintabPenService.instance;
    WintabPenService.debugClockOverride = () => DateTime(2024);
    wintab.debugPollOverride = () => const [];
    wintab.start();
    wintab.debugInjectPacket(
      const QaTabletPacket(pressure: 0, timeMs: 1, buttons: 0),
    );
    expect(PenSidecars.penTouching(), isFalse);
    expect(PenSidecars.kindOf(mouse), mouse, reason: 'a hovering pen');

    wintab.debugInjectPacket(
      const QaTabletPacket(pressure: 0, timeMs: 2, buttons: 1),
    );
    expect(PenSidecars.kindOf(mouse), stylus, reason: 'the tip bit');
    wintab.debugInjectPacket(
      const QaTabletPacket(pressure: 0.3, timeMs: 3, buttons: 0),
    );
    expect(
      PenSidecars.kindOf(mouse),
      stylus,
      reason: 'a reading that touches, from a driver that leaves the bit '
          'clear',
    );
    for (final kind in const [
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
      PointerDeviceKind.trackpad,
    ]) {
      expect(PenSidecars.kindOf(kind), kind, reason: 'only a mouse is asked');
    }
    wintab.debugReset();

    // Raw Input's tip switch says the same, on its own.
    final hid = RawPenInputService.instance;
    addTearDown(hid.debugReset);
    RawPenInputService.debugClockOverride = () => DateTime(2024);
    QaPenRawState? report;
    hid.debugPollOverride = () => report;
    hid.start();
    report = const QaPenRawState(flags: 0x00, sequence: 1);
    expect(PenSidecars.kindOf(mouse), mouse, reason: 'in range, tip up');
    report = const QaPenRawState(flags: 0x01, sequence: 2);
    expect(PenSidecars.kindOf(mouse), stylus, reason: 'HID Tip Switch');
  });

  // 🗣️I-124: the two questions the law's home answers for everyone.
  test('the pen is either end, and a mouse whose pen is down wobbles as the '
      'pen does', () {
    expect(
      [
        for (final kind in PointerDeviceKind.values)
          if (PenSidecars.isPenKind(kind)) kind,
      ],
      [PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus],
    );

    const mouse = PointerDeviceKind.mouse;
    final mouseSlop = computeHitSlop(mouse, null);
    final penSlop = computeHitSlop(PointerDeviceKind.stylus, null);
    expect(penSlop, greaterThan(mouseSlop), reason: 'premise');
    expect(PenSidecars.hitSlopOf(mouse, null), mouseSlop);

    final wintab = WintabPenService.instance;
    WintabPenService.debugClockOverride = () => DateTime(2024);
    wintab.debugPollOverride = () => const [];
    wintab.start();
    wintab.debugInjectPacket(
      const QaTabletPacket(pressure: 0.3, timeMs: 1, buttons: 1),
    );
    expect(PenSidecars.hitSlopOf(mouse, null), penSlop, reason: 'tip down');
  });
}

/// An event no reader paired with any packet of the driver's.
const _hover = PointerHoverEvent();

/// The event a stroke reads at a point drawn [at], which the platform's
/// reader paired with the driver's packet that said [reading]
/// ([PenPath.eventsOf]).
PointerEvent _madeAt(Offset at, DriverReading reading) {
  QaPenPoints.debugTake = (_, _, _) => [
    (
      x: at.dx,
      y: at.dy,
      at: Duration.zero,
      pressure: null,
      tilt: null,
      orientation: null,
      driven: reading,
    ),
  ];
  addTearDown(() => QaPenPoints.debugTake = null);
  final move = PointerMoveEvent(position: at);
  PenPath.arrived(
    move,
    ui.PointerData(
      change: ui.PointerChange.move,
      physicalX: at.dx,
      physicalY: at.dy,
    ),
    1,
  );
  return PenPath.eventsOf(move).single;
}
