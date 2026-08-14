import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/canvas/display_tile_buffer.dart';

/// 🚨★★★ (v) 2단계 마무리의 계약 — **획 스텝은 자기가 건드린 타일만 낸다.**
///
/// The single buffer before this rasterised the whole visible rect every
/// paint: a two-pixel dab and a full-canvas fill cost the same. What this
/// counts is the only thing that can honestly report the saving — how many
/// times the content body actually runs.
///
/// ⚠️계측기를 먼저 의심하라. The counter here IS the paint callback, so a
/// saving it reports cannot be one that did not happen.
void main() {
  late DisplayTileBuffer buffer;
  late int paints;

  Canvas scratch() => Canvas(ui.PictureRecorder());

  void paintOnce({Rect bounds = const Rect.fromLTWH(0, 0, 256, 128)}) {
    buffer.draw(
      scratch(),
      bounds: bounds,
      quality: ui.FilterQuality.low,
      paintContent: (into) {
        paints += 1;
        into.drawRect(const Rect.fromLTWH(0, 0, 512, 512), Paint());
      },
    );
  }

  setUp(() {
    buffer = DisplayTileBuffer(tileSize: 128, padding: 2);
    paints = 0;
    buffer.keepFor('key-a');
  });

  tearDown(() => buffer.dispose());

  test('the first paint rasterises one tile per covered cell', () {
    paintOnce();

    expect(paints, 2, reason: '256x128 over a 128 grid is two tiles');
    expect(buffer.tileCount, 2);
  });

  test('a second paint with nothing dirty rasterises nothing', () {
    paintOnce();
    paintOnce();
    paintOnce();

    expect(
      paints,
      2,
      reason: 'three paints, two rasters — the fixed per-frame cost of the '
          'untiled buffer is what this removes',
    );
  });

  test('a stroke pays for the tiles it touched and no others', () {
    paintOnce();
    buffer.invalidateRegion(const Rect.fromLTWH(4, 4, 8, 8));

    expect(buffer.tileCount, 1, reason: 'the second tile survived');

    paintOnce();
    expect(
      paints,
      3,
      reason: 'one more raster, not two — that is the whole feature',
    );
  });

  test('a change just OUTSIDE a tile still dirties it, because its margin '
      'is showing that content', () {
    paintOnce();
    // One pixel to the left of tile 1, inside the 2px margin it carries.
    buffer.invalidateRegion(const Rect.fromLTWH(127, 4, 1, 1));

    expect(
      buffer.tileCount,
      0,
      reason: 'both tiles: tile 0 owns those pixels and tile 1 has them in '
          'its padding, which is exactly what a filtered tap will read',
    );
  });

  test('a new key drops everything, like the bake', () {
    paintOnce();
    buffer.keepFor('key-b');

    expect(buffer.tileCount, 0);
    paintOnce();
    expect(paints, 4);
  });

  test('an empty region dirties nothing', () {
    paintOnce();
    buffer.invalidateRegion(Rect.zero);

    expect(buffer.tileCount, 2);
  });

  test('tiles are drawn from an INSET source, so the margin is never shown', ()
      async {
    // The padding exists to be SAMPLED, not displayed. Painting a content
    // body whose colour changes across a tile boundary and reading the
    // result back is what catches a src rect that forgot the inset: the
    // neighbour's pixels would appear inside this tile.
    final tiled = DisplayTileBuffer(tileSize: 4, padding: 1);
    addTearDown(tiled.dispose);
    tiled.keepFor('k');

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 8, 4));
    tiled.draw(
      canvas,
      bounds: const Rect.fromLTWH(0, 0, 8, 4),
      quality: ui.FilterQuality.none,
      paintContent: (into) {
        into.drawRect(
          const Rect.fromLTWH(0, 0, 4, 4),
          Paint()..color = const Color(0xFFFF0000),
        );
        into.drawRect(
          const Rect.fromLTWH(4, 0, 4, 4),
          Paint()..color = const Color(0xFF0000FF),
        );
      },
    );
    final image = await recorder.endRecording().toImage(8, 4);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final pixels = bytes.buffer.asUint8List();

    int redAt(int x) => pixels[(x * 4)];
    int blueAt(int x) => pixels[(x * 4) + 2];

    expect(redAt(3), 255, reason: 'last pixel of the left tile is still red');
    expect(blueAt(3), 0);
    expect(blueAt(4), 255, reason: 'first pixel of the right tile is blue');
    expect(redAt(4), 0, reason: 'and it is not the margin bleeding across');
  });
}
