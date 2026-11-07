// The engine's Rust library carries the pen (rust/src/lib.rs), and its
// names are found in that code asset — no library opened, no path named.
@DefaultAsset(gpuEngineAsset)
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'gpu_engine_asset.dart';

/// One driver-side pen sample from the Wintab queue (PEN-2).
class QaTabletPacket {
  const QaTabletPacket({
    required this.pressure,
    this.orientation,
    this.twistDegrees,
    required this.timeMs,
    required this.buttons,
  });

  /// Normalized 0..1 against the DEVICE's pressure axis.
  final double pressure;

  /// How the pen leans, in Wintab's own words: its top's compass
  /// `bearing` in degrees (0 toward the top of the tablet, clockwise) and
  /// its `altitude` as a fraction of a right angle (1 upright; negative
  /// with the eraser end down) — or null when the device declares no
  /// orientation axes.
  ///
  /// ⛔ONE FIELD, NOT A PAIR AND A FLAG. The pair once said 「0° azimuth,
  /// lying flat」 for a pen with no tilt sensor at all, and a separate
  /// validity bit beside it would be a second way to be absent.
  /// ↩️Its doc used to call the azimuth 「along +x, driver convention」;
  /// Wintab's zero is the top of the tablet. `PenLean` converts it.
  final ({double bearing, double altitude})? orientation;

  /// How far the pen is turned about its own barrel, in degrees 0..360
  /// clockwise (Wintab's `orTwist`) — null when the device declares no
  /// twist axis (F-176-Q9).
  final double? twistDegrees;

  /// Driver timestamp in milliseconds (driver clock).
  final double timeMs;

  final int buttons;
}

/// One decoded HID digitizer report from the Raw Input observer.
///
/// These are the usages the pen hardware DECLARES (page 0x0D): nothing
/// here is inferred from pressure or from a vendor cursor index, which is
/// the whole reason this path exists beside Wintab.
class QaPenRawState {
  const QaPenRawState({
    required this.flags,
    required this.sequence,
    this.tilt,
    this.twistDegrees,
  });

  final int flags;

  /// Monotonic report counter — tells "no new report" apart from "a new
  /// report that repeats the previous flags".
  final int sequence;

  /// HID X Tilt (0x3D) and Y Tilt (0x3E) in degrees, as the descriptor
  /// declares them — the Pointer Events plane tilts, +x to the right and +y
  /// toward the user — or null when the report carries no tilt: a pen
  /// without the sensor.
  final ({double x, double y})? tilt;

  /// HID Twist (0x41): how far the pen is turned about its own barrel, in
  /// degrees 0..360 clockwise — or null when the report carries none: a
  /// device that declares no twist.
  final double? twistDegrees;

  /// HID Tip Switch (0x42): the writing end is touching.
  bool get tip => flags & 0x01 != 0;

  /// HID Barrel Switch (0x44): the side button.
  bool get barrel => flags & 0x02 != 0;

  /// HID Eraser (0x45): the tail end is touching.
  bool get eraser => flags & 0x04 != 0;

  /// HID Invert (0x3C): the pen is turned tail-down, contact or not —
  /// this is the one that reports while merely HOVERING.
  bool get inverted => flags & 0x08 != 0;

  /// HID Secondary Barrel Switch (0x5A): the upper side button.
  bool get secondaryBarrel => flags & 0x10 != 0;
}

@Native<Int32 Function()>(symbol: 'qat_abi_version')
external int _abiVersion();

@Native<Int32 Function()>(symbol: 'qat_available')
external int _available();

@Native<Int32 Function(Pointer<Uint16>, Int32)>(symbol: 'qat_device_name')
external int _deviceName(Pointer<Uint16> out, int cap);

@Native<Int32 Function()>(symbol: 'qat_open')
external int _open();

@Native<Int32 Function(Pointer<Float>, Int32)>(symbol: 'qat_poll')
external int _poll(Pointer<Float> out, int cap);

@Native<Void Function()>(symbol: 'qat_close')
external void _close();

@Native<Int32 Function()>(symbol: 'qpr_abi_version')
external int _rawAbiVersion();

@Native<Int32 Function()>(symbol: 'qpr_start')
external int _rawStart();

@Native<Void Function()>(symbol: 'qpr_stop')
external void _rawStop();

@Native<Int32 Function(Pointer<Float>, Int32)>(symbol: 'qpr_poll')
external int _rawPoll(Pointer<Float> out, int cap);

/// The engine's pen on Windows (native/pen): what the tablet DRIVER says of
/// the pen (Wintab — `qat_*`) and what its HID report says (Raw Input —
/// `qpr_*`). Null on every other platform, and where the engine's pen
/// speaks another ABI than these read.
///
/// ↩️Until the connection round (connection-round-checklist H, 2026-11-08)
/// it was a DLL of its own beside the engine, qa_tablet.dll, and the Raw
/// Input half was looked up apart and allowed to be missing or older, for
/// an older DLL beside a newer app. One library ships with the app now, so
/// neither half can be.
class QaTabletBridge {
  QaTabletBridge._();

  /// v2 (F-176-Q9): a packet's record carries the twist.
  static const int abiVersion = 2;

  /// The Raw Input observer's own ABI: v2 (desktop-pen-tilt) hands over the
  /// report's tilt as well, v3 (F-176-Q9) its twist.
  static const int rawAbiVersion = 3;

  static bool _instantiated = false;
  static QaTabletBridge? _instance;

  static QaTabletBridge? get instanceOrNull {
    if (!_instantiated) {
      _instantiated = true;
      _instance =
          Platform.isWindows &&
              _abiVersion() == abiVersion &&
              _rawAbiVersion() == rawAbiVersion
          ? QaTabletBridge._()
          : null;
    }
    return _instance;
  }

  static const int _pollCapacity = 64;
  static const int _recordFloats = 8;
  final Pointer<Float> _pollBuffer = malloc<Float>(
    _pollCapacity * _recordFloats,
  );

  /// A report's floats: flags and counter, then the tilt and whether the
  /// report carried one, then the twist and whether.
  static const int _rawFloats = 7;
  final Pointer<Float> _rawBuffer = malloc<Float>(_rawFloats);

  /// Whether wintab32 loads AND an installed driver answers.
  bool get available => _available() != 0;

  /// The driver's device name ('' when unavailable).
  String deviceName() {
    final buffer = malloc<Uint16>(64);
    try {
      final length = _deviceName(buffer, 64);
      return length <= 0
          ? ''
          : String.fromCharCodes(buffer.asTypedList(length));
    } finally {
      malloc.free(buffer);
    }
  }

  /// Opens the observe-only polling context (idempotent). False = no
  /// driver / no app window yet.
  bool open() => _open() != 0;

  /// Drains queued driver packets (empty list when idle/closed).
  List<QaTabletPacket> poll() {
    final count = _poll(_pollBuffer, _pollCapacity);
    if (count <= 0) {
      return const [];
    }
    final floats = _pollBuffer.asTypedList(count * _recordFloats);
    return List<QaTabletPacket>.generate(
      count,
      (i) => packetFrom(floats, i * _recordFloats),
    );
  }

  /// The packet `qat_poll` wrote at [base] of [floats]: pressure, bearing,
  /// altitude, time, buttons, whether the device is oriented at all, and
  /// its twist and whether it declares one.
  @visibleForTesting
  static QaTabletPacket packetFrom(Float32List floats, int base) =>
      QaTabletPacket(
        pressure: floats[base],
        orientation: floats[base + 5] != 0
            ? (bearing: floats[base + 1], altitude: floats[base + 2])
            : null,
        twistDegrees: floats[base + 7] != 0 ? floats[base + 6] : null,
        timeMs: floats[base + 3],
        buttons: floats[base + 4].toInt(),
      );

  void close() => _close();

  /// Starts the HID observer thread (idempotent). False = no digitizer
  /// answered the registration.
  bool startRawInput() => _rawStart() != 0;

  void stopRawInput() => _rawStop();

  /// The newest decoded HID report; null when the observer is not live.
  QaPenRawState? pollRawInput() {
    if (_rawPoll(_rawBuffer, _rawFloats) == 0) {
      return null;
    }
    return rawStateFrom(_rawBuffer.asTypedList(_rawFloats));
  }

  /// The report `qpr_poll` wrote as [floats]: flags, counter and, where the
  /// report carried them, its tilt and its twist.
  @visibleForTesting
  static QaPenRawState rawStateFrom(Float32List floats) => QaPenRawState(
    flags: floats[0].toInt(),
    sequence: floats[1].toInt(),
    tilt: floats[4] != 0 ? (x: floats[2], y: floats[3]) : null,
    twistDegrees: floats[6] != 0 ? floats[5] : null,
  );
}
