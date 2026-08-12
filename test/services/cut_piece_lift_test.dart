import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/floor_math.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/cut_piece_lift.dart';

/// The CUT verb: it takes a copy and leaves the cel alone.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);

  /// A 4x4 opaque block at (2,2)..(5,5), every pixel distinguishable by
  /// its red channel so a mis-addressed gather shows up as wrong VALUES,
  /// not merely wrong counts.
  BitmapSurface paintedSurface({int left = 2, int top = 2}) {
    final rgba = Uint8List(4 * 4 * 4);
    for (var i = 0; i < 16; i += 1) {
      rgba[i * 4] = 10 + i * 10;
      rgba[i * 4 + 1] = 7;
      rgba[i * 4 + 2] = 90;
      rgba[i * 4 + 3] = 255;
    }
    return materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 8),
      sequence: BrushDabSequence([
        BrushDab(
          center: CanvasPoint(x: left + 2, y: top + 2),
          color: 0xFF000000,
          size: 4,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.square,
          pressure: 1,
          sequence: 0,
          stamp: BrushStampImage(id: 'base', width: 4, height: 4, rgba: rgba),
        ),
      ]),
    ).surface;
  }

  List<int> pixelAt(BitmapSurface surface, int x, int y) {
    final tileSize = surface.tileSize;
    final tile = surface.tiles[TileCoord(
      x: floorDiv(x, tileSize),
      y: floorDiv(y, tileSize),
    )];
    if (tile == null) {
      return const [0, 0, 0, 0];
    }
    final offset =
        (((y % tileSize + tileSize) % tileSize) * tileSize +
                ((x % tileSize + tileSize) % tileSize)) *
            4;
    return tile.pixels.sublist(offset, offset + 4);
  }

  Uint8List snapshot(BitmapSurface surface) {
    final bytes = Uint8List(canvasSize.width * canvasSize.height * 4);
    for (var y = 0; y < canvasSize.height; y += 1) {
      for (var x = 0; x < canvasSize.width; x += 1) {
        bytes.setRange(
          (y * canvasSize.width + x) * 4,
          (y * canvasSize.width + x) * 4 + 4,
          pixelAt(surface, x, y),
        );
      }
    }
    return bytes;
  }

  CanvasSelectionRegion rect({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    return CanvasSelectionRegion.shape(
      CanvasSelectionShape.rect(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      ),
    );
  }

  test('cutting leaves the source surface byte-identical', () {
    // The whole verb, in one assertion. 유저 확정: "잘라내기는 원본 남기는
    // 복사" — if this ever goes red, the cut has been wired into the
    // selection MOVE lift, which erases as it takes.
    final surface = paintedSurface();
    final before = snapshot(surface);
    final piece = buildCutPiece(
      region: rect(left: 1, top: 1, right: 7, bottom: 7),
      surface: surface,
      pieceId: 'cut-1',
    );
    expect(piece, isNotNull);
    expect(snapshot(surface), before);
  });

  test('the piece carries the pixels it covered, at their cel coordinates', () {
    final surface = paintedSurface();
    final piece = buildCutPiece(
      region: rect(left: 2, top: 2, right: 6, bottom: 6),
      surface: surface,
      pieceId: 'cut-1',
    )!;
    // Origin is where the piece came FROM, in cel space — this is what
    // "paste at the original position" anchors to, and it is deliberately
    // not screen space.
    expect(piece.originLeft, 2);
    expect(piece.originTop, 2);
    // Top-left of the block: red 10, alpha 255.
    final rgba = piece.image.rgba;
    expect(rgba[0], 10);
    expect(rgba[3], 255);
    expect(piece.image.width, greaterThanOrEqualTo(4));
    expect(piece.image.height, greaterThanOrEqualTo(4));
  });

  test('an empty stretch of cel yields no piece at all', () {
    // The slot survives frames, cuts and projects, so a stray drag over
    // blank cel must not be able to overwrite it with nothing.
    final surface = paintedSurface();
    final piece = buildCutPiece(
      region: rect(left: 10, top: 10, right: 14, bottom: 14),
      surface: surface,
      pieceId: 'cut-1',
    );
    expect(piece, isNull);
  });

  test('a fully off-pasteboard outline yields no piece', () {
    final surface = paintedSurface();
    final piece = buildCutPiece(
      // Far outside the 5x5 pasteboard footprint on the negative side.
      region: rect(left: -400, top: -400, right: -390, bottom: -390),
      surface: surface,
      pieceId: 'cut-1',
    );
    expect(piece, isNull);
  });

  test('the mask is hard-edged: every lifted pixel keeps its exact alpha', () {
    // 2치 보존. A soft edge would write mid-alpha into a two-value drawing
    // and break the fill pass downstream, and this app has no two-value
    // layer flag to switch such a thing off with.
    final surface = paintedSurface();
    final piece = buildCutPiece(
      region: rect(left: 1, top: 1, right: 7, bottom: 7),
      surface: surface,
      pieceId: 'cut-1',
    )!;
    final rgba = piece.image.rgba;
    for (var index = 0; index < rgba.length; index += 4) {
      final alpha = rgba[index + 3];
      expect(
        alpha == 0 || alpha == 255,
        isTrue,
        reason: 'partial alpha $alpha at byte $index',
      );
    }
  });

  test('a lasso outline takes only what it encloses', () {
    final surface = paintedSurface();
    // A triangle over the block's top-left corner.
    final piece = buildCutPiece(
      region: CanvasSelectionRegion.shape(
        CanvasSelectionShape([
          CanvasPoint(x: 2, y: 2),
          CanvasPoint(x: 6, y: 2),
          CanvasPoint(x: 2, y: 6),
        ]),
      ),
      surface: surface,
      pieceId: 'cut-1',
    )!;
    final rgba = piece.image.rgba;
    var opaque = 0;
    for (var index = 0; index < rgba.length; index += 4) {
      if (rgba[index + 3] != 0) {
        opaque += 1;
      }
    }
    // Strictly fewer than the 16 pixels the whole block would give, and
    // more than nothing — the outline actually clipped.
    expect(opaque, greaterThan(0));
    expect(opaque, lessThan(16));
  });

  test('artwork past the canvas edge is cuttable', () {
    // The clip is the pasteboard, not the canvas: an animator draws limbs
    // off-frame every day, and those pixels are real artwork.
    final surface = paintedSurface(left: -6, top: 2);
    final piece = buildCutPiece(
      region: rect(left: -7, top: 1, right: -1, bottom: 7),
      surface: surface,
      pieceId: 'cut-1',
    );
    expect(piece, isNotNull);
    expect(piece!.originLeft, lessThan(0));
  });

  test('cutting twice hands back independent pieces', () {
    // Each cut replaces the held piece, so the second must not be a view
    // onto the first's buffer.
    final surface = paintedSurface();
    final first = buildCutPiece(
      region: rect(left: 1, top: 1, right: 7, bottom: 7),
      surface: surface,
      pieceId: 'cut-1',
    )!;
    final second = buildCutPiece(
      region: rect(left: 1, top: 1, right: 7, bottom: 7),
      surface: surface,
      pieceId: 'cut-2',
    )!;
    expect(identical(first.image.rgba, second.image.rgba), isFalse);
    expect(first.image.rgba, second.image.rgba);
  });
}
