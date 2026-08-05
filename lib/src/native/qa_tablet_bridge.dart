import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// One driver-side pen sample from the Wintab queue (PEN-2).
class QaTabletPacket {
  const QaTabletPacket({
    required this.pressure,
    required this.tiltAzimuthDegrees,
    required this.altitude,
    required this.timeMs,
    required this.buttons,
  });

  /// Normalized 0..1 against the DEVICE's pressure axis.
  final double pressure;

  /// Pen azimuth in degrees (0 = along +x, driver convention).
  final double tiltAzimuthDegrees;

  /// Normalized 0..1 altitude (1 = vertical pen).
  final double altitude;

  /// Driver timestamp in milliseconds (driver clock).
  final double timeMs;

  final int buttons;
}

/// One decoded HID digitizer report from the Raw Input sidecar.
///
/// These are the usages the pen hardware DECLARES (page 0x0D): nothing
/// here is inferred from pressure or from a vendor cursor index, which is
/// the whole reason this path exists beside Wintab.
class QaPenRawState {
  const QaPenRawState({required this.flags, required this.sequence});

  final int flags;

  /// Monotonic report counter — tells "no new report" apart from "a new
  /// report that repeats the previous flags".
  final int sequence;

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

/// FFI wrapper for the Wintab sidecar DLL (qa_tablet.dll) — the
/// qa_engine loader idiom: dynamic open, env override (QA_TABLET_PATH),
/// absence or ABI mismatch = null instance = the feature silently absent.
/// Windows-only by construction (the DLL only builds there).
class QaTabletBridge {
  QaTabletBridge._(
    this._available,
    this._deviceName,
    this._open,
    this._poll,
    this._close,
    this._rawStart,
    this._rawStop,
    this._rawPoll,
  );

  static const int abiVersion = 1;

  /// The Raw Input observer's own ABI — looked up separately and allowed
  /// to be absent, so an older qa_tablet.dll still gives us Wintab.
  static const int rawAbiVersion = 1;

  /// Test hook: an explicit DLL path (bypasses the platform gate).
  static String? debugLibraryPathOverride;

  static bool _instantiated = false;
  static QaTabletBridge? _instance;

  static QaTabletBridge? get instanceOrNull {
    if (!_instantiated) {
      _instantiated = true;
      _instance = _tryCreate();
    }
    return _instance;
  }

  /// Test hook: forget the cached instance (with [debugLibraryPathOverride]
  /// this lets a test point at a purpose-built DLL and back).
  static void debugResetInstance() {
    _instantiated = false;
    _instance = null;
  }

  final int Function() _available;
  final int Function(Pointer<Uint16>, int) _deviceName;
  final int Function() _open;
  final int Function(Pointer<Float>, int) _poll;
  final void Function() _close;
  final int Function()? _rawStart;
  final void Function()? _rawStop;
  final int Function(Pointer<Float>, int)? _rawPoll;

  static const int _pollCapacity = 64;
  static const int _recordFloats = 6;
  final Pointer<Float> _pollBuffer = malloc<Float>(
    _pollCapacity * _recordFloats,
  );

  static const int _rawFloats = 2;
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
    return List<QaTabletPacket>.generate(count, (i) {
      final base = i * _recordFloats;
      return QaTabletPacket(
        pressure: floats[base],
        tiltAzimuthDegrees: floats[base + 1],
        altitude: floats[base + 2],
        timeMs: floats[base + 3],
        buttons: floats[base + 4].toInt(),
      );
    });
  }

  void close() => _close();

  /// Whether this DLL carries the Raw Input observer at all.
  bool get rawInputSupported => _rawStart != null;

  /// Starts the HID observer thread (idempotent). False = unsupported,
  /// or no digitizer answered the registration.
  bool startRawInput() => (_rawStart?.call() ?? 0) != 0;

  void stopRawInput() => _rawStop?.call();

  /// The newest decoded HID report; null when the observer is not live.
  QaPenRawState? pollRawInput() {
    final poll = _rawPoll;
    if (poll == null || poll(_rawBuffer, _rawFloats) == 0) {
      return null;
    }
    final floats = _rawBuffer.asTypedList(_rawFloats);
    return QaPenRawState(flags: floats[0].toInt(), sequence: floats[1].toInt());
  }

  static QaTabletBridge? _tryCreate() {
    final overridePath =
        debugLibraryPathOverride ?? Platform.environment['QA_TABLET_PATH'];
    if (overridePath == null && !Platform.isWindows) {
      return null;
    }
    DynamicLibrary? lib;
    for (final candidate in [
      if (overridePath != null && overridePath.isNotEmpty) overridePath,
      if (Platform.isWindows) 'qa_tablet.dll',
    ]) {
      try {
        lib = DynamicLibrary.open(candidate);
        break;
      } on Object {
        continue;
      }
    }
    if (lib == null) {
      return null;
    }
    try {
      final abi = lib.lookupFunction<Int32 Function(), int Function()>(
        'qat_abi_version',
      )();
      if (abi != abiVersion) {
        return null;
      }
      // The Raw Input observer is looked up SEPARATELY and is allowed to
      // be missing: it shipped later than the Wintab half, and an older
      // DLL beside a newer app should lose the observer, not the tablet.
      int Function()? rawStart;
      void Function()? rawStop;
      int Function(Pointer<Float>, int)? rawPoll;
      try {
        final rawAbi = lib.lookupFunction<Int32 Function(), int Function()>(
          'qpr_abi_version',
        )();
        if (rawAbi == rawAbiVersion) {
          rawStart = lib.lookupFunction<Int32 Function(), int Function()>(
            'qpr_start',
          );
          rawStop = lib.lookupFunction<Void Function(), void Function()>(
            'qpr_stop',
          );
          rawPoll = lib
              .lookupFunction<
                Int32 Function(Pointer<Float>, Int32),
                int Function(Pointer<Float>, int)
              >('qpr_poll');
        }
      } on Object {
        rawStart = null;
        rawStop = null;
        rawPoll = null;
      }
      return QaTabletBridge._(
        lib.lookupFunction<Int32 Function(), int Function()>('qat_available'),
        lib.lookupFunction<
          Int32 Function(Pointer<Uint16>, Int32),
          int Function(Pointer<Uint16>, int)
        >('qat_device_name'),
        lib.lookupFunction<Int32 Function(), int Function()>('qat_open'),
        lib.lookupFunction<
          Int32 Function(Pointer<Float>, Int32),
          int Function(Pointer<Float>, int)
        >('qat_poll'),
        lib.lookupFunction<Void Function(), void Function()>('qat_close'),
        rawStart,
        rawStop,
        rawPoll,
      );
    } on Object {
      return null;
    }
  }
}
