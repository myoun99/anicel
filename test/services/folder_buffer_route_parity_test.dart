import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/tile_coord.dart';

/// R27 #29 — the PIXELS, not just the plan.
///
/// "그룹 한번합쳐서 한번블렌드" is a claim about what multiply does where two
/// members OVERLAP. This renders the group both ways and shows they differ,
/// then shows the buffered one matches the reference: composite the members
/// first, blend the result once.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  /// A surface whose left/right half (or all) is one opaque color.
  BitmapSurface slab(int argb, {required int fromX, required int toX}) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var y = 0; y < 8; y += 1) {
      for (var x = fromX; x < toX; x += 1) {
        final i = (y * 8 + x) * 4;
        pixels[i] = (argb >> 16) & 0xFF;
        pixels[i + 1] = (argb >> 8) & 0xFF;
        pixels[i + 2] = argb & 0xFF;
        pixels[i + 3] = 0xFF;
      }
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          coord: TileCoord(x: 0, y: 0),
          size: 8,
          pixels: pixels,
        ),
      },
    );
  }

  Future<ui.Image> imageOf(BitmapSurface surface) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final tile = surface.tiles.values.single;
    for (var y = 0; y < 8; y += 1) {
      for (var x = 0; x < 8; x += 1) {
        final i = (y * 8 + x) * 4;
        if (tile.pixels[i + 3] == 0) {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          Paint()
            ..color = Color.fromARGB(
              tile.pixels[i + 3],
              tile.pixels[i],
              tile.pixels[i + 1],
              tile.pixels[i + 2],
            ),
        );
      }
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(8, 8);
    } finally {
      picture.dispose();
    }
  }

  Future<List<int>> pixelAt(ui.Image image, int x, int y) async {
    final data = await image.toByteData();
    final i = (y * image.width + x) * 4;
    return [
      data!.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
      data.getUint8(i + 3),
    ];
  }

  /// Paints [backdrop], then the two members with the folder's multiply
  /// applied either PER MEMBER (the old fold) or ONCE to their composed
  /// buffer (R27 #29).
  Future<ui.Image> render({
    required ui.Image backdrop,
    required ui.Image memberA,
    required ui.Image memberB,
    required bool buffered,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(backdrop, Offset.zero, Paint());
    final bounds = const Rect.fromLTWH(0, 0, 8, 8);
    if (buffered) {
      canvas.saveLayer(
        bounds,
        Paint()..blendMode = LayerBlendMode.multiply.paintBlendMode,
      );
      canvas.drawImage(memberA, Offset.zero, Paint());
      canvas.drawImage(memberB, Offset.zero, Paint());
      canvas.restore();
    } else {
      final fold = Paint()
        ..blendMode = LayerBlendMode.multiply.paintBlendMode;
      canvas.drawImage(memberA, Offset.zero, fold);
      canvas.drawImage(memberB, Offset.zero, fold);
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(8, 8);
    } finally {
      picture.dispose();
    }
  }

  test('a MULTIPLY folder darkens overlapping members once, not twice', () async {
    // Backdrop mid-grey; both members mid-grey slabs that OVERLAP on x=2..5.
    final backdrop = await imageOf(slab(0x808080, fromX: 0, toX: 8));
    final memberA = await imageOf(slab(0x808080, fromX: 0, toX: 6));
    final memberB = await imageOf(slab(0x808080, fromX: 2, toX: 8));
    addTearDown(() {
      backdrop.dispose();
      memberA.dispose();
      memberB.dispose();
    });

    final folded = await render(
      backdrop: backdrop,
      memberA: memberA,
      memberB: memberB,
      buffered: false,
    );
    final buffered = await render(
      backdrop: backdrop,
      memberA: memberA,
      memberB: memberB,
      buffered: true,
    );
    addTearDown(() {
      folded.dispose();
      buffered.dispose();
    });

    // x=0 is member A alone: both routes agree (one multiply either way).
    expect(
      await pixelAt(folded, 0, 4),
      await pixelAt(buffered, 0, 4),
      reason: 'no overlap, no disagreement — this is why a non-overlapping '
          'group never showed the bug',
    );

    // x=3 is the OVERLAP. Folding multiplies twice (0.5·0.5·0.5 ≈ 0.125·255
    // ≈ 32); buffering composes the members first (B covers A, still 0.5)
    // and multiplies once (0.5·0.5 = 0.25·255 ≈ 64).
    final foldedOverlap = (await pixelAt(folded, 3, 4))[0];
    final bufferedOverlap = (await pixelAt(buffered, 3, 4))[0];
    expect(
      foldedOverlap,
      lessThan(bufferedOverlap),
      reason: 'the fold darkens where members cross — the reported bug',
    );
    expect(bufferedOverlap, closeTo(64, 2));
    expect(foldedOverlap, closeTo(32, 2));

    // And the buffered overlap equals the NON-overlapping result: one
    // multiply is one multiply, wherever the members happen to land.
    expect(
      bufferedOverlap,
      closeTo((await pixelAt(buffered, 0, 4))[0].toDouble(), 2),
      reason: 'a group blends once — overlap must not change the result',
    );
  });
}
