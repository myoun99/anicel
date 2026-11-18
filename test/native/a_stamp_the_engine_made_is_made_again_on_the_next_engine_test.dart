// Each engine compiles the stamp landing's kernels where it first makes a
// stamp: 40 s apiece on a machine this busy, and each test here has two.
@Timeout(Duration(minutes: 5))
library;

import 'dart:typed_data';

import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/native/engine_stamp_pictures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuSampling;

import '../helpers/the_apps_engine_let_go.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
/// 유지한다」 — 「잃는 것은 그리던 획 정도다」. A stamp the engine made — a
/// float carried over a posed row, or warped — has no bytes here till
/// something asks for them, and every one is made of a stamp whose bytes
/// are here: so it is made again on the next engine as it was made
/// (`EngineStampPictures`), and nothing of it is lost with a device.
/// ↩️It read from the picture of the engine let go, which refused.
///
/// On the app's own engine, which each test loses: the one after it finds
/// the next.
void main() {
  /// Sixteen pixels, each its own colour.
  BrushStampImage sixteen() => BrushStampImage(
    id: 'sixteen',
    width: 4,
    height: 4,
    rgba: Uint8List.fromList([
      for (var at = 0; at < 16; at += 1) ...[at * 16, 255 - at * 16, at, 255],
    ]),
  );

  /// [stamp] a pixel to the right, each pixel the one nearest; [through]
  /// is the nine it is carried by.
  BrushStampImage shifted(BrushStampImage stamp, {List<double>? through}) =>
      EngineStampPictures.carried(
        stamp,
        id: 'shifted',
        inverse: through ?? <double>[1, 0, -1, 0, 1, 0, 0, 0, 1],
        radiusFloor: 1,
        sampling: GpuSampling.pick,
        width: 4,
        height: 4,
      );

  /// [stamp] a pixel to the right through a mesh of one cell, each pixel
  /// the one nearest; its corners rest at [rest] and were dragged [to].
  BrushStampImage meshed(
    BrushStampImage stamp, {
    List<double>? rest,
    List<double>? to,
  }) =>
      EngineStampPictures.meshed(
        stamp,
        id: 'meshed',
        at: (0, 0),
        columns: 1,
        rows: 1,
        source: rest ?? <double>[0, 0, 4, 0, 0, 4, 4, 4],
        destination: to ?? <double>[1, 0, 5, 0, 1, 4, 5, 4],
        radiusFloor: 1,
        sampling: GpuSampling.pick,
        window: (0, 0, 6, 4),
      );

  test('a stamp the engine made is made again on the next engine as it was '
      'made — of the stamp it was made of, handed up once more, and by the '
      'numbers it was made by, whatever is written to them since', () {
    final stamp = sixteen();
    final asItWas = shifted(stamp).rgba;
    expect(asItWas.toSet().length, greaterThan(8), reason: '⛔premise');
    final through = <double>[1, 0, -1, 0, 1, 0, 0, 0, 1];
    final made = shifted(stamp, through: through);
    final first = EngineStampPictures.of(made);
    final handedUp = EngineStampPictures.debugHandedUp;
    final readBack = EngineStampPictures.debugReadBack;
    through[2] = 2;

    theAppsEngineLostAndLetGo();

    expect(identical(EngineStampPictures.of(made), first), isFalse);
    expect(EngineStampPictures.debugReadBack, readBack, reason: 'not read');
    expect(made.rgba, asItWas);
    expect(EngineStampPictures.debugHandedUp, handedUp + 1);
  });

  test('one made of a stamp the engine made is made again of that one made '
      'again — and only the one asked for is read', () {
    final stamp = sixteen();
    final asItWas = meshed(shifted(stamp)).rgba;
    expect(asItWas.toSet().length, greaterThan(8), reason: '⛔premise');
    final rest = <double>[0, 0, 4, 0, 0, 4, 4, 4];
    final to = <double>[1, 0, 5, 0, 1, 4, 5, 4];
    final made = meshed(shifted(stamp), rest: rest, to: to);
    final handedUp = EngineStampPictures.debugHandedUp;
    final readBack = EngineStampPictures.debugReadBack;
    rest[0] = 2;
    to[0] = 3;

    theAppsEngineLostAndLetGo();

    expect(made.rgba, asItWas);
    expect(EngineStampPictures.debugHandedUp, handedUp + 1);
    expect(EngineStampPictures.debugReadBack, readBack + 1);
  });
}
