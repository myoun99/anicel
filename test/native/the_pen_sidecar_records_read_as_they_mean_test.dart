import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_tablet_bridge.dart';

import '../helpers/native_engine_path.dart';

/// desktop-pen-tilt: the pen DLL (`qa_tablet_win.c`, `qa_penraw_win.c`)
/// hands its readings over as floats. This is the Dart half of that
/// contract — the half a host with no tablet can run; the C half keeps its
/// layout beside its own `qat_poll` and `qpr_poll`.
void main() {
  // The pen DLL lives beside the engine; it is Windows-only.
  final engine = Platform.isWindows ? nativeEngineLibraryPathOrNull() : null;
  final dllSkip = !Platform.isWindows
      ? 'the pen DLL is Windows-only'
      : engine == null
      ? nativeEngineMissingSkipReason
      : false;

  test('🚨the pen DLL built from this C speaks the Raw Input ABI this Dart '
      'reads — v2, the one that hands over the tilt', () {
    final dll = '${File(engine!).parent.path}${Platform.pathSeparator}'
        'qa_tablet.dll';
    final rawAbi = DynamicLibrary.open(dll)
        .lookupFunction<Int32 Function(), int Function()>('qpr_abi_version')();
    expect(rawAbi, QaTabletBridge.rawAbiVersion);

    QaTabletBridge.debugLibraryPathOverride = dll;
    QaTabletBridge.debugResetInstance();
    addTearDown(() {
      QaTabletBridge.debugLibraryPathOverride = null;
      QaTabletBridge.debugResetInstance();
    });
    expect(QaTabletBridge.instanceOrNull?.rawInputSupported, isTrue);
  }, skip: dllSkip);

  test('the Raw Input reader listens where a pen reports: the Pen '
      'collection and the Digitizer one both (F-176-Q8 — a Cintiq sends '
      'every report through the Digitizer one alone)', () {
    final pen = DynamicLibrary.open(
      '${File(engine!).parent.path}${Platform.pathSeparator}qa_tablet.dll',
    );
    final start = pen.lookupFunction<Int32 Function(), int Function()>(
      'qpr_start',
    );
    final stop = pen.lookupFunction<Void Function(), void Function()>(
      'qpr_stop',
    );
    expect(start(), 1);
    addTearDown(stop);

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
  }, skip: dllSkip);

  test('a Wintab record says how the pen leans only when the device is '
      'oriented', () {
    final oriented = QaTabletBridge.packetFrom(
      Float32List.fromList([0.25, 135, 0.5, 1000, 1, 1]),
      0,
    );
    expect(oriented.pressure, 0.25);
    expect(oriented.orientation, (bearing: 135.0, altitude: 0.5));
    expect(oriented.timeMs, 1000);
    expect(oriented.buttons, 1);

    expect(
      QaTabletBridge.packetFrom(
        Float32List.fromList([0.25, 0, 0, 1000, 1, 0]),
        0,
      ).orientation,
      isNull,
      reason: 'a device with no orientation axes: not a pen lying flat',
    );

    // Records follow one another six floats apart.
    final second = QaTabletBridge.packetFrom(
      Float32List.fromList([0, 0, 0, 0, 0, 0, 0.75, 10, 1, 2, 0, 1]),
      6,
    );
    expect(second.pressure, 0.75);
    expect(second.orientation, (bearing: 10.0, altitude: 1.0));
  });

  test('a Raw Input record says the tilt only from a v2 observer, and only '
      'when the report carried one', () {
    final tilted = Float32List.fromList([1, 7, 12.5, -30, 1]);
    final state = QaTabletBridge.rawStateFrom(tilted, tilts: true);
    expect(state.flags, 1);
    expect(state.sequence, 7);
    expect(state.tilt, (x: 12.5, y: -30.0));

    expect(
      QaTabletBridge.rawStateFrom(tilted, tilts: false).tilt,
      isNull,
      reason: 'a v1 observer never wrote one',
    );
    expect(
      QaTabletBridge.rawStateFrom(
        Float32List.fromList([1, 8, 0, 0, 0]),
        tilts: true,
      ).tilt,
      isNull,
      reason: 'a report with no tilt is not an upright pen',
    );
  });
}
