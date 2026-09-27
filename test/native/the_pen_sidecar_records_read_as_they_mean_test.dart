import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

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
