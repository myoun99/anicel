// The first crossing compiles the stamp landing's kernels: 40 s on a
// machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuSampling;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/native/engine_stamp_pictures.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/canvas_selection.dart' show carryStampDab;
import 'package:anicel/src/services/layer_pose_matrix.dart';
import 'package:anicel/src/services/resample/resample_kernel.dart'
    show ResampleMode;
import 'package:anicel/src/services/selection_placement.dart';

import '../helpers/placement_reading.dart';

/// 🚨A STAMP'S CROSSING OF A ROW'S PLACEMENT IS THE ENGINE'S
/// (gpu-canonical-store ⑪, 2026-11-11).
///
/// A float carried over a posed row shows as its landing at every step of
/// the hand (유저 2026-09-17: 「보이는 중이랑 결과랑 절대로 다르면 안 되」), so
/// the crossing back into the row is made at every step. 🔬Made here, a
/// 26.7 MB stamp was 55–68 ms of resample and 32–44 ms of handing its bytes
/// up again, a step (main PC) — 220–250 ms a frame on the Surface Pro 11,
/// where master, showing the float itself, took 142–146.
///
/// WHERE a stamp crosses to is `a_stamp_crosses_a_placement_test.dart`'s.
/// These pin whose work the crossing is: the stamp's picture goes up once,
/// each crossing is made of it there, and what it made lands without a byte
/// of it coming here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 320, height: 256);

  const red = [255, 0, 0, 255];
  const green = [0, 255, 0, 255];
  const blue = [0, 0, 255, 255];
  const white = [255, 255, 255, 255];
  const own = [red, green, blue, white];

  /// Four opaque colours, a quarter each:
  ///   R G
  ///   B W
  BrushStampImage quarters(int side) => BrushStampImage(
    id: 'quarters',
    width: side,
    height: side,
    rgba: Uint8List.fromList([
      for (var y = 0; y < side; y += 1)
        for (var x = 0; x < side; x += 1)
          ...own[(y < side ~/ 2 ? 0 : 2) + (x < side ~/ 2 ? 0 : 1)],
    ]),
  );

  BrushDab dabOf(BrushStampImage stamp, {required double x, double y = 100}) =>
      BrushDab(
        center: CanvasPoint(x: x, y: y),
        color: 0xFFFFFFFF,
        size: stamp.width.toDouble(),
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.square,
        pressure: 1,
        sequence: 0,
        stamp: stamp,
      );

  /// A row scaled and turned off the quarter about the canvas's middle: no
  /// crossing of it is a move, or a turn a table makes.
  final posed = placedBy(
    TransformPose(
      center: CanvasPoint(x: canvas.width / 2, y: canvas.height / 2),
      scaleX: 1.1,
      scaleY: 1.1,
      rotationDegrees: 8,
    ),
    canvas,
  );

  List<List<int>> pixelsOf(BrushStampImage stamp) => [
    for (var i = 0; i < stamp.width * stamp.height; i += 1)
      stamp.rgba.sublist(i * 4, i * 4 + 4),
  ];

  /// Every tile [dabs] leave on an empty cel, by where it stands.
  Map<TileCoord, List<int>> landed(List<BrushDab> dabs) {
    final surface = materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvas),
      sequence: BrushDabSequence(dabs),
    ).surface;
    return {
      for (final MapEntry(key: coord, value: tile) in surface.tiles.entries)
        coord: tile.pixels,
    };
  }

  test('a stamp carried into a posed row from place after place goes up '
      'once, and no crossing is resampled here or read back', () {
    final stamp = quarters(24);
    final handedUp = EngineStampPictures.debugHandedUp;
    final readBack = EngineStampPictures.debugReadBack;

    final crossed = [
      for (final x in const [90.0, 96.0, 103.5, 140.0])
        stampInArtwork(dabOf(stamp, x: x), posed),
    ];

    expect(
      {for (final dab in crossed) dab.center},
      hasLength(4),
      reason: '⛔CONTROL: four places, each crossed to a place of its own',
    );
    expect(EngineStampPictures.debugHandedUp - handedUp, 1);
    expect(EngineStampPictures.debugReadBack - readBack, 0);
  });

  test('what it crossed as lands with no byte of it handed up or read back '
      '— as a stamp of those bytes lands', () {
    final crossed = stampInArtwork(dabOf(quarters(24), x: 96), posed);
    final handedUp = EngineStampPictures.debugHandedUp;
    final readBack = EngineStampPictures.debugReadBack;

    final byItsPicture = landed([crossed]);

    expect(EngineStampPictures.debugHandedUp - handedUp, 0);
    expect(EngineStampPictures.debugReadBack - readBack, 0);
    final made = crossed.stamp!;
    final ofItsBytes = BrushStampImage(
      id: 'of-its-bytes',
      width: made.width,
      height: made.height,
      rgba: made.rgba,
    );
    expect(
      EngineStampPictures.debugReadBack - readBack,
      1,
      reason: 'its bytes are read from the engine where they are asked for',
    );
    expect(
      pixelsOf(made).where((pixel) => pixel[3] == 255),
      isNotEmpty,
      reason: '⛔CONTROL: the picture, not an empty box',
    );
    expect(byItsPicture, isNotEmpty);
    expect(byItsPicture, landed([crossed.copyWith(stamp: ofItsBytes)]));
  });

  test('it crosses in the mode asked: PICK carries the stamp\'s own colours '
      'and no other, BLEND mixes them where two meet', () {
    final dab = dabOf(quarters(8), x: 96);
    final back = canvasToArtwork(posed)!;
    bool itsOwn(List<int> pixel) =>
        pixel[3] == 0 || own.any((colour) => _same(colour, pixel));

    final picked = carryStampDab(
      dab,
      to: back,
      from: posed,
      mode: ResampleMode.pick,
    );
    final blended = carryStampDab(dab, to: back, from: posed);

    expect(pixelsOf(picked.stamp!).where((pixel) => pixel[3] > 0), isNotEmpty);
    expect(pixelsOf(picked.stamp!).every(itsOwn), isTrue);
    expect(pixelsOf(blended.stamp!).every(itsOwn), isFalse);
  });

  test('a map of other than nine numbers is refused before the engine '
      'reads nine of it', () {
    expect(
      () => EngineStampPictures.carried(
        quarters(8),
        id: 'short',
        inverse: const [1, 0, 0, 0, 1, 0],
        radiusFloor: 1,
        sampling: GpuSampling.blend,
        width: 8,
        height: 8,
      ),
      throwsArgumentError,
    );
  });
}

bool _same(List<int> a, List<int> b) =>
    a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3];
