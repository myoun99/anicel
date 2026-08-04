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
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/canvas_selection.dart';

/// R14-④ lift builder: the erase+stamp pair cuts EXACTLY the selection's
/// pixels, a zero-move drop is byte-identical, and a translated stamp
/// lands the pixels at the destination.
void main() {
  const canvasSize = CanvasSize(width: 16, height: 16);

  BitmapSurface paintedSurface() {
    // A 4x4 opaque gradient block at (2,2)..(5,5).
    final rgba = Uint8List(4 * 4 * 4);
    for (var i = 0; i < 16; i += 1) {
      rgba[i * 4] = 40 + i * 10;
      rgba[i * 4 + 1] = 200 - i * 5;
      rgba[i * 4 + 2] = 90;
      rgba[i * 4 + 3] = 255;
    }
    return materializeBrushDabSequenceOnBitmapSurface(
      surface: BitmapSurface(canvasSize: canvasSize, tileSize: 8),
      sequence: BrushDabSequence([
        BrushDab(
          center: CanvasPoint(x: 4, y: 4),
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
    // floorDiv so pasteboard (negative) pixels resolve to their tile.
    final tile = surface.tiles[TileCoord(
      x: floorDiv(x, tileSize),
      y: floorDiv(y, tileSize),
    )];
    if (tile == null) {
      return const [0, 0, 0, 0];
    }
    final pixels = tile.pixels;
    final offset = ((y % tileSize) * tileSize + (x % tileSize)) * 4;
    return pixels.sublist(offset, offset + 4);
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

  test('the tile-major gather equals a per-pixel reference, swept across '
      'tile boundaries and the pasteboard', () {
    // The gather walks TILES and the pixels inside them, instead of
    // walking destination rows and asking which tile each pixel belongs
    // to. The existing tests here pin the lift's semantics but not its
    // TILING — a rewrite that dropped, doubled or misaddressed a tile's
    // share of a straddling bbox passes all of them. This is the oracle
    // for the axis the rewrite actually changed: a reference gather
    // written the naive way, right here, compared byte for byte.
    //
    // Cases are chosen to straddle: a bbox inside one tile, one crossing
    // a tile edge, one spanning several, one starting on an exact
    // boundary, one entirely in the negative (pasteboard) quadrant, and
    // one over a coordinate that has no tile at all.
    Uint8List referenceGather({
      required BitmapSurface surface,
      required Uint8List mask,
      required int left,
      required int top,
      required int width,
      required int height,
    }) {
      final out = Uint8List(width * height * 4);
      final tileSize = surface.tileSize;
      for (var row = 0; row < height; row += 1) {
        final y = top + row;
        for (var col = 0; col < width; col += 1) {
          final maskValue = mask[row * width + col];
          if (maskValue == 0) {
            continue;
          }
          final x = left + col;
          final tile = surface.tiles[TileCoord(
            x: floorDiv(x, tileSize),
            y: floorDiv(y, tileSize),
          )];
          if (tile == null) {
            continue;
          }
          final pixels = tile.pixels;
          final source = ((y % tileSize) * tileSize + (x % tileSize)) * 4;
          final alpha = pixels[source + 3];
          if (alpha == 0) {
            continue;
          }
          final target = (row * width + col) * 4;
          out[target] = pixels[source];
          out[target + 1] = pixels[source + 1];
          out[target + 2] = pixels[source + 2];
          if (maskValue == 255) {
            out[target + 3] = alpha;
          } else {
            final product = alpha * maskValue + 128;
            out[target + 3] = (product + (product >> 8)) >> 8;
          }
        }
      }
      return out;
    }

    // A cel with ink in several tiles including negative coordinates, so
    // the sweep below really does cross tile edges with content on both
    // sides of them.
    var surface = BitmapSurface(canvasSize: canvasSize, tileSize: 8);
    for (final centre in [
      CanvasPoint(x: 3, y: 3),
      CanvasPoint(x: 9, y: 5),
      CanvasPoint(x: 7.5, y: 8.5),
      CanvasPoint(x: -5, y: -3),
      CanvasPoint(x: -2, y: 6),
    ]) {
      surface = materializeBrushDabSequenceOnBitmapSurface(
        surface: surface,
        sequence: BrushDabSequence([
          BrushDab(
            center: centre,
            color: 0xC03377AA,
            size: 5,
            opacity: 0.8,
            flow: 0.9,
            hardness: 0.4,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: 0,
          ),
        ]),
      ).surface;
    }

    const cases = <({int left, int top, int width, int height})>[
      (left: 1, top: 1, width: 5, height: 5), // inside one tile
      (left: 5, top: 2, width: 7, height: 4), // crosses a vertical edge
      (left: 2, top: 5, width: 4, height: 7), // crosses a horizontal edge
      (left: 8, top: 8, width: 6, height: 6), // starts ON a boundary
      (left: 3, top: 3, width: 11, height: 11), // spans four tiles
      (left: -7, top: -5, width: 9, height: 9), // pasteboard, negative
      (left: -3, top: 2, width: 8, height: 8), // straddles x = 0
      (left: 12, top: 12, width: 4, height: 4), // over an empty coordinate
    ];

    for (final box in cases) {
      // Two masks per case: hard, and a soft one that exercises the
      // mul-div-255 branch at every pixel.
      for (final soft in const [false, true]) {
        final mask = Uint8List(box.width * box.height);
        for (var i = 0; i < mask.length; i += 1) {
          // A varying pattern, with genuine zeroes so the skip path runs.
          final v = (i * 37) % 256;
          mask[i] = v < 24 ? 0 : (soft ? v : 255);
        }
        final expected = referenceGather(
          surface: surface,
          mask: mask,
          left: box.left,
          top: box.top,
          width: box.width,
          height: box.height,
        );
        final actual = gatherMaskedSurfacePixels(
          surface: surface,
          mask: mask,
          left: box.left,
          top: box.top,
          width: box.width,
          height: box.height,
        );
        expect(
          actual.rgba,
          expected,
          reason:
              'tile-major gather differs from the reference at '
              '${box.left},${box.top} ${box.width}x${box.height} '
              '(soft: $soft)',
        );
        expect(
          actual.liftedAnything,
          expected.any((byte) => byte != 0),
          reason: 'liftedAnything disagrees at ${box.left},${box.top}',
        );
      }
    }
  });

  test('a zero-move lift-and-drop is byte-identical to the original', () {
    final surface = paintedSurface();
    final before = snapshot(surface);

    final lift = buildSelectionLiftDabs(
      region: CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 1, top: 1, right: 7, bottom: 7),
      ),
      surface: surface,
      liftId: 'roundtrip',
    )!;
    final after = materializeBrushDabSequenceOnBitmapSurface(
      surface: surface,
      sequence: BrushDabSequence([lift.eraseDab, lift.stampDab]),
    ).surface;

    expect(snapshot(after), before);
  });

  test('a PARTIAL selection lifts only the covered pixels — the boundary '
      'content splits between origin remnant and moved stamp', () {
    final surface = paintedSurface();

    // Select the LEFT half of the block: x in [2, 3].
    final lift = buildSelectionLiftDabs(
      region: CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 2, top: 2, right: 4, bottom: 6),
      ),
      surface: surface,
      liftId: 'partial',
    )!;

    // Drop the lifted pixels 8px to the right (stamp center +8).
    final movedStamp = lift.stampDab.copyWith(
      center: CanvasPoint(
        x: lift.stampDab.center.x + 8,
        y: lift.stampDab.center.y,
      ),
    );
    final after = materializeBrushDabSequenceOnBitmapSurface(
      surface: surface,
      sequence: BrushDabSequence([lift.eraseDab, movedStamp]),
    ).surface;

    // Origin: selected columns cut, unselected columns intact.
    expect(pixelAt(after, 2, 2), const [0, 0, 0, 0]);
    expect(pixelAt(after, 3, 4), const [0, 0, 0, 0]);
    expect(pixelAt(after, 4, 2), isNot(const [0, 0, 0, 0]));
    expect(pixelAt(after, 5, 5), isNot(const [0, 0, 0, 0]));
    // Destination: the exact source bytes landed +8 to the right.
    expect(pixelAt(after, 10, 2), pixelAt(surface, 2, 2));
    expect(pixelAt(after, 11, 4), pixelAt(surface, 3, 4));
  });

  test('a selection moved OFF the canvas keeps its pixels on the '
      'pasteboard, and moving it back restores them byte-exactly', () {
    final surface = paintedSurface();
    final before = snapshot(surface);

    // Lift the whole block and drop it 10px past the LEFT canvas edge:
    // block columns [2, 5] land at [-8, -5] — pure pasteboard space.
    final lift = buildSelectionLiftDabs(
      region: CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 1, top: 1, right: 7, bottom: 7),
      ),
      surface: surface,
      liftId: 'off-canvas',
    )!;
    final movedOff = materializeBrushDabSequenceOnBitmapSurface(
      surface: surface,
      sequence: BrushDabSequence([
        lift.eraseDab,
        lift.stampDab.copyWith(
          center: CanvasPoint(
            x: lift.stampDab.center.x - 10,
            y: lift.stampDab.center.y,
          ),
        ),
      ]),
    ).surface;

    // The origin is cut, the pixels live at negative coords.
    expect(pixelAt(movedOff, 2, 2), const [0, 0, 0, 0]);
    expect(pixelAt(movedOff, -8, 2), pixelAt(surface, 2, 2));
    expect(pixelAt(movedOff, -5, 5), pixelAt(surface, 5, 5));

    // Select the off-canvas block and move it back: byte-identical.
    final liftBack = buildSelectionLiftDabs(
      region: CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: -9, top: 1, right: -3, bottom: 7),
      ),
      surface: movedOff,
      liftId: 'back',
    )!;
    final restored = materializeBrushDabSequenceOnBitmapSurface(
      surface: movedOff,
      sequence: BrushDabSequence([
        liftBack.eraseDab,
        liftBack.stampDab.copyWith(
          center: CanvasPoint(
            x: liftBack.stampDab.center.x + 10,
            y: liftBack.stampDab.center.y,
          ),
        ),
      ]),
    ).surface;

    expect(snapshot(restored), before);
    // No pasteboard residue left behind.
    expect(pixelAt(restored, -8, 2), const [0, 0, 0, 0]);
  });

  test('a selection over empty canvas builds no lift', () {
    expect(
      buildSelectionLiftDabs(
        region: CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(
            left: 10,
            top: 10,
            right: 14,
            bottom: 14,
          ),
        ),
        surface: paintedSurface(),
        liftId: 'empty',
      ),
      isNull,
    );
  });

  // --- R26 (C2): selection mask options -----------------------------

  /// The erase stamp's alpha at canvas (x, y) — the mask oracle.
  int eraseAlphaAt(SelectionLiftDabs lift, int x, int y) {
    final stamp = lift.eraseDab.stamp!;
    final left = (lift.eraseDab.center.x - stamp.width / 2).round();
    final top = (lift.eraseDab.center.y - stamp.height / 2).round();
    final col = x - left;
    final row = y - top;
    if (col < 0 || row < 0 || col >= stamp.width || row >= stamp.height) {
      return 0;
    }
    return stamp.rgba[(row * stamp.width + col) * 4 + 3];
  }

  CanvasSelectionRegion rect2to5() => CanvasSelectionRegion.shape(
    CanvasSelectionShape.rect(left: 2, top: 2, right: 6, bottom: 6),
  );

  test('default options are BYTE-IDENTICAL to the classic hard lift', () {
    final surface = paintedSurface();
    final classic = buildSelectionLiftDabs(
      region: rect2to5(),
      surface: surface,
      liftId: 'a',
    )!;
    final withDefaults = buildSelectionLiftDabs(
      region: rect2to5(),
      surface: surface,
      liftId: 'a',
      options: SelectionMaskOptions.none,
    )!;
    expect(withDefaults.stampDab.stamp!.rgba, classic.stampDab.stamp!.rgba);
    expect(withDefaults.eraseDab.stamp!.rgba, classic.eraseDab.stamp!.rgba);
  });

  test('grow +2 selects 2px beyond the rect; shrink -1 releases the rim',
      () {
    final surface = paintedSurface();
    final grown = buildSelectionLiftDabs(
      region: rect2to5(),
      surface: surface,
      liftId: 'g',
      options: const SelectionMaskOptions(growPx: 2),
    )!;
    // (1, 3) and (0, 3) are 1px and 2px left of the rect: both grown in.
    expect(eraseAlphaAt(grown, 1, 3), 255);
    expect(eraseAlphaAt(grown, 0, 3), 255);
    // Diagonal corner 2 steps out in BOTH axes stays out (4-neighbor
    // growth is diamond-shaped, exactly like the fill expand).
    expect(eraseAlphaAt(grown, 0, 0), 0);

    final shrunk = buildSelectionLiftDabs(
      region: rect2to5(),
      surface: surface,
      liftId: 's',
      options: const SelectionMaskOptions(growPx: -1),
    )!;
    // The rect's rim (x==2) erodes away; the interior keeps.
    expect(eraseAlphaAt(shrunk, 2, 3), 0);
    expect(eraseAlphaAt(shrunk, 3, 3), 255);
  });

  test('feather ramps alpha inward: boundary < interior, center full',
      () {
    final surface = paintedSurface();
    final feathered = buildSelectionLiftDabs(
      region: rect2to5(),
      surface: surface,
      liftId: 'f',
      options: const SelectionMaskOptions(featherPx: 3),
    )!;
    final rim = eraseAlphaAt(feathered, 2, 4);
    final inner = eraseAlphaAt(feathered, 3, 4);
    expect(rim, greaterThan(0));
    expect(inner, greaterThan(rim));
    expect(eraseAlphaAt(feathered, 7, 4), 0, reason: 'outside stays out');
  });

  test('anti-alias softens only the boundary', () {
    final surface = paintedSurface();
    final softened = buildSelectionLiftDabs(
      region: rect2to5(),
      surface: surface,
      liftId: 'aa',
      options: const SelectionMaskOptions(antiAlias: true),
    )!;
    final rim = eraseAlphaAt(softened, 2, 4);
    expect(rim, greaterThan(0));
    expect(rim, lessThan(255));
    expect(eraseAlphaAt(softened, 4, 4), 255, reason: 'interior untouched');
  });
}
