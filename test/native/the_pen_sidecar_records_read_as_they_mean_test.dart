import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';

/// desktop-pen-tilt: the engine's pen ([_pen]) hands its readings over as
/// floats. This is the Dart half of that contract — the half a host with no
/// tablet can run; the Rust half keeps its layout beside its own `qat_poll`
/// and `qpr_poll`.
///
/// ↩️Until the connection round (connection-round-checklist H, 2026-11-08)
/// the pen was a DLL of its own, qa_tablet.dll, which these opened beside
/// the C engine.
void main() {
  final windowsOnly = Platform.isWindows ? false : 'the pen is Windows-only';

  test('🚨the engine\'s pen speaks the ABI this Dart reads — both halves — '
      'on Windows, and nowhere else', () {
    expect(
      QaTabletBridge.instanceOrNull,
      Platform.isWindows ? isNotNull : isNull,
      reason: 'qat_abi_version ${QaTabletBridge.abiVersion} and '
          'qpr_abi_version ${QaTabletBridge.rawAbiVersion}, as $_pen says '
          'them',
    );
  });

  test('the Raw Input reader listens where a pen reports: the Pen '
      'collection and the Digitizer one both (F-176-Q8 — a Cintiq sends '
      'every report through the Digitizer one alone)', () {
    final pen = QaTabletBridge.instanceOrNull!;
    expect(pen.startRawInput(), isTrue);
    addTearDown(pen.stopRawInput);

    final registered = DynamicLibrary.open('user32.dll')
        .lookupFunction<
          Uint32 Function(Pointer<Uint16>, Pointer<Uint32>, Uint32),
          int Function(Pointer<Uint16>, Pointer<Uint32>, int)
        >('GetRegisteredRawInputDevices');
    // RAWINPUTDEVICE in a 64-bit process: page, usage, flags, window.
    const bytes = 16;
    const room = 8;
    final count = calloc<Uint32>()..value = room;
    final devices = calloc<Uint16>(bytes ~/ 2 * room);
    addTearDown(() {
      calloc.free(devices);
      calloc.free(count);
    });
    final read = registered(devices, count, bytes);
    expect(read, inInclusiveRange(1, room));
    final collections = {
      for (var i = 0; i < read; i += 1)
        (page: devices[i * bytes ~/ 2], usage: devices[i * bytes ~/ 2 + 1]),
    };
    expect(
      collections,
      containsAll([(page: 0x0D, usage: 0x02), (page: 0x0D, usage: 0x01)]),
    );
  }, skip: windowsOnly);

  test('a Wintab record says how the pen leans only when the device is '
      'oriented, and how it is turned only when it declares a twist', () {
    final oriented = QaTabletBridge.packetFrom(
      Float32List.fromList([0.25, 135, 0.5, 1000, 1, 1, 0, 0]),
      0,
    );
    expect(oriented.pressure, 0.25);
    expect(oriented.orientation, (bearing: 135.0, altitude: 0.5));
    expect(oriented.timeMs, 1000);
    expect(oriented.buttons, 1);
    expect(
      oriented.twistDegrees,
      isNull,
      reason: 'a device with no twist axis: not a pen turned to 0°',
    );

    expect(
      QaTabletBridge.packetFrom(
        Float32List.fromList([0.25, 0, 0, 1000, 1, 0, 0, 0]),
        0,
      ).orientation,
      isNull,
      reason: 'a device with no orientation axes: not a pen lying flat',
    );

    // Records follow one another eight floats apart.
    final second = QaTabletBridge.packetFrom(
      Float32List.fromList([
        ...[0, 0, 0, 0, 0, 0, 0, 0],
        ...[0.75, 10, 1, 2, 0, 1, 270, 1],
      ]),
      8,
    );
    expect(second.pressure, 0.75);
    expect(second.orientation, (bearing: 10.0, altitude: 1.0));
    expect(second.twistDegrees, 270);
  });

  test('a Raw Input record says the tilt and the twist only when the '
      'report carried them', () {
    final posed = Float32List.fromList([1, 7, 12.5, -30, 1, 135, 1]);
    final state = QaTabletBridge.rawStateFrom(posed);
    expect(state.flags, 1);
    expect(state.sequence, 7);
    expect(state.tilt, (x: 12.5, y: -30.0));
    expect(state.twistDegrees, 135);

    final bare = QaTabletBridge.rawStateFrom(
      Float32List.fromList([1, 8, 0, 0, 0, 0, 0]),
    );
    expect(
      bare.tilt,
      isNull,
      reason: 'a report with no tilt is not an upright pen',
    );
    expect(
      bare.twistDegrees,
      isNull,
      reason: 'a report with no twist is not a pen turned to 0°',
    );
  });
}

/// The pen these read — named as a path, so a lane that changed only the
/// engine's pen runs this file (`affected_tests` picks a test by the paths
/// it writes out, 보드/인프라 2026-11-08 05:35).
const _pen = 'packages/gpu_engine/rust/native/pen';
