import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/device_battery.dart';

import '../helpers/source_body.dart';

/// 🗣️I-103-Q1 (유저 2026-10-16): the battery at the top strip's end.
///
/// A CHANNEL HAS NO COMPILER (`one_channel_dialect_test`), so this is the
/// battery's type check: every runner that answers [DeviceBattery.channel]
/// answers its one method with its battery reading, in the one shape
/// [DeviceBattery.readingOf] reads — `percent`, and `charging`.
///
/// ⚠️A SOURCE PIN, because no machine this suite runs on is a tablet or a
/// Mac: it can say each runner answers; what the battery says is the
/// device's to show.
void main() {
  for (final (path, reading) in const [
    (
      'android/app/src/main/kotlin/com/myoun/anicel/MainActivity.kt',
      'private fun batteryReading(',
    ),
    ('ios/Runner/AppDelegate.swift', 'static func batteryReading('),
    ('macos/Runner/MainFlutterWindow.swift', 'static func batteryReading('),
  ]) {
    test('$path answers the battery, in its shape', () {
      final source = File(path).readAsStringSync();
      final channel = source.indexOf('"${DeviceBattery.channel.name}"');
      expect(channel, isNot(-1), reason: 'premise: the channel is there');
      final handler = sourceBodyOf(
        source.substring(channel),
        'setMethodCallHandler',
      );
      expect(handler, contains('"${DeviceBattery.readMethod}"'));
      expect(handler, contains('batteryReading()'));
      final body = sourceBodyOf(source, reading);
      expect(body, contains('"percent"'));
      expect(body, contains('"charging"'));
    });
  }
}
