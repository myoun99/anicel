import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';
import 'package:anicel/src/services/input/pen_sidecars.dart';
import 'package:anicel/src/services/input/platform_pen_channel_service.dart';
import 'package:anicel/src/services/input/wintab_pen_service.dart';

/// PEN-4: the macOS/Linux channel sidecars + the cross-platform facade.
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

    expect(PenSidecars.freshContactPressure(), isNull);

    controller.add({'pressure': 0.3});
    await Future<void>.delayed(Duration.zero);
    expect(PenSidecars.freshContactPressure(), 0.3);

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
        tiltAzimuthDegrees: 0,
        altitude: 1,
        timeMs: 1,
        buttons: 1,
      ),
    );
    expect(PenSidecars.freshContactPressure(), 0.9);

    wintab.debugReset();
    expect(PenSidecars.freshContactPressure(), 0.3);
  });
}
