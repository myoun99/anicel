import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;

/// How full the battery is, and whether the device is ON POWER — plugged
/// in, charging or already full: the bolt every OS draws over its battery.
typedef BatteryReading = ({int percent, bool charging});

/// 🗣️I-103 ① (유저 2026-10-15): 「디바이스의 배터리 상단띠 어딘가에
/// 표시하고싶음」 — and I-103-Q1 (2026-10-16): at the top strip's right end,
/// an icon and the percent, on a device that has a battery; a desktop
/// without one has no place for it at all, and a device's answer never
/// changes while the app runs.
///
/// So whether there IS a battery is asked once, before the first frame
/// ([watch]) — a place the strip made for it later would be UI that pops
/// into existence.
///
/// One question on every platform ([read]): Android, iOS and the Mac answer
/// it in their runners, over [channel]; Windows and Linux are asked
/// straight, as the screen reader flag is.
abstract final class DeviceBattery {
  /// The runners' channel and its one method, spelled again in
  /// `MainActivity.kt`, `AppDelegate.swift` and `MainFlutterWindow.swift`;
  /// `the_battery_is_asked_one_way_test.dart` reads all four.
  static const channel = MethodChannel('anicel/battery');
  static const readMethod = 'read';

  /// The battery the strip shows — null on a device without one, and in a
  /// run that never watched it (a test).
  static ValueListenable<BatteryReading>? get shown => _watch?.shown;
  static BatteryWatch? _watch;

  /// How long the launch waits for the first answer. A runner always
  /// answers — a missing handler answers at once — so this only bounds a
  /// broken one, which would otherwise hold the first frame for good.
  static const Duration _patience = Duration(seconds: 2);

  /// Asks once and, on a device with a battery, keeps [shown] up to date
  /// for the rest of the run. Once, from `main()`, before the first frame.
  static Future<void> watch() async {
    final first = await read().timeout(_patience, onTimeout: () => null);
    if (first != null) {
      _watch = BatteryWatch(first, read: read)..start();
    }
  }

  /// The battery now; null where there is none, or it cannot be asked.
  static Future<BatteryReading?> read() async {
    try {
      if (Platform.isWindows) {
        return _windowsReading();
      }
      if (Platform.isLinux) {
        return linuxReadingIn(Directory('/sys/class/power_supply'));
      }
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        return readingOf(await channel.invokeMethod<Object?>(readMethod));
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// A runner's answer as a reading: `{percent, charging}`, or nothing.
  static BatteryReading? readingOf(Object? answer) => switch (answer) {
    {'percent': final int percent, 'charging': final bool charging}
        when percent >= 0 && percent <= 100 =>
      (percent: percent, charging: charging),
    _ => null,
  };

  /// What the kernel's power supplies say under [supplies]
  /// (`/sys/class/power_supply`): the system battery's capacity, and
  /// whether it is charging or any mains supply is online.
  ///
  /// ⚠️A mouse or a headset reports a battery here too, scoped `Device`;
  /// the one the strip means is the system's. And a battery's own `Full`
  /// is not power: some report it off the mains at 100%, where the mains
  /// supply already says whether it is plugged in.
  ///
  /// ⚠️And a capacity can say more than full — the kernel divides what the
  /// battery holds by what it last held full, and a worn one overshoots —
  /// so it reads full: a reading refused there would cost a full battery
  /// its gauge for the run, and the strip keeps that place for the device
  /// (I-103-Q1). The Mac's runner caps its own the same way.
  static BatteryReading? linuxReadingIn(Directory supplies) {
    final named = supplies.listSync().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    int? percent;
    var charging = false;
    for (final supply in named) {
      String? field(String name) {
        try {
          return File('${supply.path}/$name').readAsStringSync().trim();
        } on FileSystemException {
          return null;
        }
      }

      switch (field('type')) {
        case 'Battery'
            when percent == null &&
                field('scope') != 'Device' &&
                field('present') != '0':
          percent = int.tryParse(field('capacity') ?? '');
          charging = charging || field('status') == 'Charging';
        case 'Mains' when field('online') == '1':
          charging = true;
      }
    }
    return switch (percent) {
      final int percent when percent >= 0 => (
        percent: math.min(percent, 100),
        charging: charging,
      ),
      _ => null,
    };
  }

  /// `GetSystemPowerStatus` (kernel32), asked straight: its
  /// `SYSTEM_POWER_STATUS` is twelve bytes, of which the first three are
  /// the AC line, the battery flag and the percent.
  static BatteryReading? _windowsReading() {
    final status = calloc<Uint8>(12);
    try {
      if (_getSystemPowerStatus(status) == 0) {
        return null;
      }
      final flag = status[1];
      final percent = status[2];
      if (flag == _noSystemBattery || flag == _unknown || percent > 100) {
        return null;
      }
      return (percent: percent, charging: status[0] == _acOnline);
    } finally {
      calloc.free(status);
    }
  }

  /// Looked up once — the watch asks every few seconds.
  static final _getSystemPowerStatus = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        Int32 Function(Pointer<Uint8>),
        int Function(Pointer<Uint8>)
      >('GetSystemPowerStatus');

  /// `SYSTEM_POWER_STATUS` values (winbase.h).
  static const int _acOnline = 1;
  static const int _noSystemBattery = 128;
  static const int _unknown = 255;
}

/// Keeps [shown] up to date: asks [read] every [every] while the app is on
/// screen, and once more the moment it is back.
///
/// Asked rather than told: the same question on every platform is one
/// door, where five OS notifications would be five. The charge moves by a
/// percent in minutes; [every] is set by the bolt, which a user plugging
/// in looks for at once.
class BatteryWatch {
  BatteryWatch(
    BatteryReading first, {
    required this.read,
    this.every = const Duration(seconds: 5),
  }) : _shown = ValueNotifier(first);

  final Future<BatteryReading?> Function() read;
  final Duration every;

  ValueListenable<BatteryReading> get shown => _shown;
  final ValueNotifier<BatteryReading> _shown;

  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  /// From now on, for as long as the app runs (or until [stop]).
  void start() {
    _lifecycle ??= AppLifecycleListener(
      onShow: () {
        unawaited(_ask());
        _keepAsking();
      },
      onHide: () => _timer?.cancel(),
    );
    _keepAsking();
  }

  /// Stops asking — for a test; the app never lets go.
  void stop() {
    _timer?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  void _keepAsking() {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(_ask()));
  }

  /// A reading that does not come keeps the last one: the place stays,
  /// and so does what it said.
  Future<void> _ask() async {
    final now = await read();
    if (now != null) {
      _shown.value = now;
    }
  }
}
