import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/native_engine_path.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';

/// The writer's two cheap fills are the rounded-rect fill, byte for byte:
/// [TimelineGridTileOpWriter.boxFill] is `rrectFill` with no corner, and
/// [TimelineGridTileOpWriter.runFill] is `rrectFill` of the whole run, drawn
/// as two corner pieces and a box between.
///
/// ⚡They exist to be cheaper (the field's square root at every pixel of a
/// block's paper was what the tiles paid most for), so what has to hold is
/// that NOTHING else changed — randomized fractional geometry, every corner
/// mask, off-tile boxes, on the Dart reference and on the native engine.
void main() {
  final dllPath = nativeEngineLibraryPathOrNull();

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
    QaNativeEngine.debugForceDartFallback = false;
  });

  int randomRgba(Random random) =>
      random.nextInt(256) |
      (random.nextInt(256) << 8) |
      (random.nextInt(256) << 16) |
      ((random.nextInt(8) == 0 ? 255 : 1 + random.nextInt(255)) << 24);

  ({int width, int height}) tileOf(Random random) =>
      (width: 8 + random.nextInt(120), height: 4 + random.nextInt(60));

  Uint8List reference(
    ({int width, int height}) tile,
    int background,
    TimelineGridTileOpWriter writer,
  ) {
    final pixels = Uint8List(tile.width * tile.height * 4);
    expect(
      timelineGridRasterTileReference(
        pixels: pixels,
        tileWidth: tile.width,
        tileHeight: tile.height,
        backgroundRgba: background,
        ops: writer.build(),
      ),
      0,
    );
    return pixels;
  }

  Uint8List? native(
    ({int width, int height}) tile,
    int background,
    TimelineGridTileOpWriter writer,
  ) {
    final engine = QaNativeEngine.instance;
    if (engine == null) {
      return null;
    }
    final pixels = Uint8List(tile.width * tile.height * 4);
    expect(
      engine.gridRasterTileBytes(
        pixels: pixels,
        tileWidth: tile.width,
        tileHeight: tile.height,
        backgroundRgba: background,
        ops: writer.build(),
      ),
      0,
    );
    return pixels;
  }

  void expectSamePicture(
    ({int width, int height}) tile,
    int background,
    TimelineGridTileOpWriter field,
    TimelineGridTileOpWriter split,
    String reason,
  ) {
    expect(
      reference(tile, background, split),
      equals(reference(tile, background, field)),
      reason: 'reference: $reason',
    );
    final nativeSplit = native(tile, background, split);
    if (nativeSplit != null) {
      expect(
        nativeSplit,
        equals(native(tile, background, field)),
        reason: 'native: $reason',
      );
    }
  }

  test('a box is the field with no corner, byte for byte — fractional, '
      'hairline and off-tile boxes', () {
    final random = Random(20260924);
    for (var round = 0; round < 400; round += 1) {
      final tile = tileOf(random);
      // Hairlines (a line is a box too) and boxes that hang off every edge.
      final thin = random.nextInt(3) == 0;
      final x = random.nextDouble() * (tile.width + 20) - 10;
      final y = random.nextDouble() * (tile.height + 20) - 10;
      final width = thin
          ? 0.25 + random.nextDouble() * 1.5
          : random.nextDouble() * 60;
      final height = random.nextDouble() * 50;
      final rgba = randomRgba(random);
      final background = random.nextBool() ? 0 : randomRgba(random);
      expectSamePicture(
        tile,
        background,
        TimelineGridTileOpWriter()..rrectFill(x, y, width, height, 0, 0, rgba),
        TimelineGridTileOpWriter()..boxFill(x, y, width, height, rgba),
        'round $round: ($x, $y) $width x $height',
      );
    }
  });

  test('a run is the whole rounded rect, byte for byte — either axis, every '
      'corner mask, any length', () {
    final random = Random(20260925);
    var split = 0;
    for (var round = 0; round < 600; round += 1) {
      final tile = tileOf(random);
      final alongX = random.nextBool();
      final along = alongX ? tile.width : tile.height;
      final across = alongX ? tile.height : tile.width;
      // A run from a fraction of a pixel to past the tile; the cross extent
      // from a sliver to the whole tile.
      final start = random.nextDouble() * (along + 10) - 5;
      final length = random.nextDouble() * (along + 10);
      final crossStart = random.nextDouble() * 4 - 1;
      final crossLength = 1 + random.nextDouble() * across;
      final radius = random.nextInt(6) == 0 ? 0.0 : random.nextDouble() * 9;
      final mask = random.nextInt(16);
      final x = alongX ? start : crossStart;
      final y = alongX ? crossStart : start;
      final width = alongX ? length : crossLength;
      final height = alongX ? crossLength : length;
      final rgba = randomRgba(random);
      final background = random.nextBool() ? 0 : randomRgba(random);
      final runWriter = TimelineGridTileOpWriter()
        ..runFill(x, y, width, height, radius, mask, rgba, alongX: alongX);
      // Count the rounds that did not hand the whole run to the field — a
      // test of the split that never splits would pass on anything.
      final ops = runWriter.build();
      if (!(ops.length == 8 && ops[0] == TimelineGridTileOp.rrectFill)) {
        split += 1;
      }
      expectSamePicture(
        tile,
        background,
        TimelineGridTileOpWriter()
          ..rrectFill(x, y, width, height, radius, mask, rgba),
        runWriter,
        'round $round: alongX $alongX ($x, $y) $width x $height '
            'r $radius mask $mask',
      );
    }
    expect(split, greaterThan(300), reason: 'most rounds must split');
  });

  test('a block\'s paper, the way a row lays it: long runs at a hidpi ratio '
      'split into two corner pieces and a box', () {
    const dpr = 1.5;
    final writer = TimelineGridTileOpWriter()
      ..runFill(
        3 * dpr,
        0,
        200 * dpr,
        27 * dpr,
        6 * dpr,
        TimelineGridTileOp.cornerTopLeft |
            TimelineGridTileOp.cornerBottomLeft |
            TimelineGridTileOp.cornerTopRight |
            TimelineGridTileOp.cornerBottomRight,
        0xFFF7FDFF,
        alongX: true,
      );
    final ops = writer.build();
    var fields = 0;
    var cursor = 0;
    while (cursor < ops.length) {
      switch (ops[cursor]) {
        case TimelineGridTileOp.rrectFill:
          fields += 1;
          cursor += 8;
        default:
          cursor += 6;
      }
    }
    expect(fields, 2, reason: 'the field is asked at the two ends only');
    expectSamePicture(
      (width: 320, height: 42),
      0,
      TimelineGridTileOpWriter()
        ..rrectFill(
          3 * dpr,
          0,
          200 * dpr,
          27 * dpr,
          6 * dpr,
          TimelineGridTileOp.cornerTopLeft |
              TimelineGridTileOp.cornerBottomLeft |
              TimelineGridTileOp.cornerTopRight |
              TimelineGridTileOp.cornerBottomRight,
          0xFFF7FDFF,
        ),
      writer,
      'a 200px block at 1.5x',
    );
  });
}
