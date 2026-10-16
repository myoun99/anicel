import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/device_battery.dart';

/// 🗣️I-103-Q1 (유저 2026-10-16): the device's battery at the top strip's
/// end — what each OS says, read as one reading, and kept up to date while
/// the app is on screen.
void main() {
  group("a runner's answer", () {
    test('reads as its percent and whether the device is on power', () {
      expect(
        DeviceBattery.readingOf({'percent': 87, 'charging': true}),
        (percent: 87, charging: true),
      );
      expect(
        DeviceBattery.readingOf({'percent': 0, 'charging': false}),
        (percent: 0, charging: false),
      );
      expect(
        DeviceBattery.readingOf({'percent': 100, 'charging': false}),
        (percent: 100, charging: false),
      );
    });

    test('is no reading where there is no battery, or what came is not '
        'one', () {
      for (final answer in <Object?>[
        null,
        {'percent': 101, 'charging': false},
        {'percent': -1, 'charging': false},
        {'percent': 50},
        {'charging': true},
        {'percent': '50', 'charging': false},
        {'percent': 50, 'charging': 'yes'},
      ]) {
        expect(DeviceBattery.readingOf(answer), isNull, reason: '$answer');
      }
    });
  });

  group("Linux's power supplies", () {
    late Directory supplies;
    setUp(() => supplies = Directory.systemTemp.createTempSync('supplies'));
    tearDown(() => supplies.deleteSync(recursive: true));

    void supply(String name, Map<String, String> fields) {
      final folder = Directory('${supplies.path}/$name')..createSync();
      for (final MapEntry(:key, :value) in fields.entries) {
        File('${folder.path}/$key').writeAsStringSync('$value\n');
      }
    }

    test("read as the system battery's capacity, on power while the mains "
        'supply is online', () {
      supply('AC', {'type': 'Mains', 'online': '0'});
      supply('BAT0', {
        'type': 'Battery',
        'present': '1',
        'capacity': '54',
        'status': 'Discharging',
      });
      expect(
        DeviceBattery.linuxReadingIn(supplies),
        (percent: 54, charging: false),
      );
      File('${supplies.path}/AC/online').writeAsStringSync('1\n');
      expect(
        DeviceBattery.linuxReadingIn(supplies),
        (percent: 54, charging: true),
      );
    });

    test('a battery that is charging is on power with no mains listed', () {
      supply('BAT0', {
        'type': 'Battery',
        'capacity': '20',
        'status': 'Charging',
      });
      expect(
        DeviceBattery.linuxReadingIn(supplies),
        (percent: 20, charging: true),
      );
    });

    test('a battery that says it is full is not on power by that', () {
      supply('AC', {'type': 'Mains', 'online': '0'});
      supply('BAT0', {'type': 'Battery', 'capacity': '100', 'status': 'Full'});
      expect(
        DeviceBattery.linuxReadingIn(supplies),
        (percent: 100, charging: false),
      );
    });

    test("a mouse's battery is not the device's", () {
      supply('hidpp_battery_0', {
        'type': 'Battery',
        'scope': 'Device',
        'capacity': '80',
        'status': 'Discharging',
      });
      expect(DeviceBattery.linuxReadingIn(supplies), isNull);
      supply('BAT1', {
        'type': 'Battery',
        'capacity': '33',
        'status': 'Discharging',
      });
      expect(
        DeviceBattery.linuxReadingIn(supplies),
        (percent: 33, charging: false),
      );
    });

    test('no battery listed, or none present, is no battery', () {
      supply('AC', {'type': 'Mains', 'online': '1'});
      expect(DeviceBattery.linuxReadingIn(supplies), isNull);
      supply('BAT0', {'type': 'Battery', 'present': '0', 'capacity': '0'});
      expect(DeviceBattery.linuxReadingIn(supplies), isNull);
    });
  });

  group('the watch', () {
    testWidgets('asks every few seconds and shows what it hears — and a '
        'reading that does not come keeps the last', (tester) async {
      final answers = <BatteryReading?>[
        (percent: 80, charging: false),
        null,
        (percent: 79, charging: true),
      ];
      var asked = 0;
      final watch = BatteryWatch(
        (percent: 81, charging: false),
        read: () async => answers[asked++],
        every: const Duration(seconds: 5),
      );
      watch.start();
      expect(watch.shown.value, (percent: 81, charging: false));

      await tester.pump(const Duration(seconds: 4));
      expect(asked, 0, reason: 'not before its time');
      await tester.pump(const Duration(seconds: 1));
      expect(asked, 1);
      expect(watch.shown.value, (percent: 80, charging: false));
      await tester.pump(const Duration(seconds: 5));
      expect(asked, 2);
      expect(
        watch.shown.value,
        (percent: 80, charging: false),
        reason: 'nothing came — the last reading stays',
      );
      await tester.pump(const Duration(seconds: 5));
      expect(watch.shown.value, (percent: 79, charging: true));
      // In the body: the binding counts pending timers before a tear-down
      // runs.
      watch.stop();
    });

    testWidgets('asks nothing while the app is hidden, and asks at once '
        'when it shows again', (tester) async {
      var asked = 0;
      final watch = BatteryWatch(
        (percent: 50, charging: false),
        read: () async => (percent: 50 - ++asked, charging: false),
        every: const Duration(seconds: 5),
      );
      watch.start();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 30));
      expect(asked, 0, reason: 'hidden — nothing asked');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(asked, 1, reason: 'asked the moment it shows');
      expect(watch.shown.value, (percent: 49, charging: false));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 5));
      expect(asked, 2, reason: 'and every few seconds again');
      expect(watch.shown.value, (percent: 48, charging: false));
      // In the body: the binding counts pending timers before a tear-down
      // runs.
      watch.stop();
    });
  });
}
