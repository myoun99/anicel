import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/cel_surface_as_shown.dart';
import 'package:anicel/src/services/cel_text_laying.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:flutter_test/flutter_test.dart';

/// R9-rest (the text tool, 유저 2026-10-06: 「셀의 그림이랑 정확히 동일」): a
/// text is part of the picture for everything that READS a cel, not only for
/// what draws it — the eyedropper picks a letter's colour, a fill stops at a
/// letter, a colour key names a letter's colour, and the shared plan hands
/// every paint route tiles that already hold the letters.
///
/// Each reader is asked through its own door, with a cel whose DRAWING says
/// one thing and whose text says another, so a reader that took the tiles
/// of a surface still carrying texts answers with the drawing and fails.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const tileSize = 4;

  /// An 8×8 picture's tiles from canvas pixels.
  Map<TileCoord, BitmapTile> tilesOf(Map<(int, int), List<int>> pixels) {
    final buffers = <TileCoord, Uint8List>{};
    for (final entry in pixels.entries) {
      final (x, y) = entry.key;
      final buffer = buffers.putIfAbsent(
        TileCoord(x: x ~/ tileSize, y: y ~/ tileSize),
        () => Uint8List(BitmapTile.bytesFor(tileSize)),
      );
      buffer.setAll(
        ((y % tileSize) * tileSize + (x % tileSize)) * 4,
        entry.value,
      );
    }
    return {
      for (final entry in buffers.entries)
        entry.key: BitmapTile(size: tileSize, pixels: entry.value),
    };
  }

  /// A cel that DRAWS [drawn] and carries one text baked to [letters].
  BitmapSurface cel({
    Map<(int, int), List<int>> drawn = const {},
    Map<(int, int), List<int>> letters = const {},
  }) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: tilesOf(drawn),
    texts: [
      CelText(
        id: 1,
        content: CelTextContent(
          spans: const [CelTextSpan(text: 'a', style: TextLetterStyle())],
          anchor: CanvasPoint(x: 0, y: 0),
        ),
        plate: tilesOf(letters),
      ),
    ],
  );

  final layer = Layer(
    id: const LayerId('ink'),
    name: 'Ink',
    frames: [Frame(id: const FrameId('f'), duration: 1, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('f'), length: 1)},
  );
  final cut = Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: [layer],
    duration: 24,
    canvasSize: canvasSize,
  );

  /// A closed box outline (2,2)..(5,5) — interior = (3..4, 3..4).
  Map<(int, int), List<int>> boxOutline(List<int> rgba) => {
    for (var x = 2; x <= 5; x += 1) ...{(x, 2): rgba, (x, 5): rgba},
    for (var y = 3; y <= 4; y += 1) ...{(2, y): rgba, (5, y): rgba},
  };

  const blue = [0, 0, 255, 255];
  const red = [255, 0, 0, 255];

  group('the eyedropper', () {
    test('picks a letter\'s colour where a letter covers the drawing', () {
      final picked = sampleCompositeColor(
        cut: cut,
        frameIndex: 0,
        surfaceResolver: (_, _) => cel(
          drawn: {(3, 3): blue, (6, 6): blue},
          letters: {(3, 3): red},
        ),
        point: CanvasPoint(x: 3, y: 3),
      );

      expect(picked, 0xFFFF0000);
    });

    test('picks a letter standing on bare paper', () {
      final picked = sampleCompositeColor(
        cut: cut,
        frameIndex: 0,
        surfaceResolver: (_, _) => cel(letters: {(6, 1): red}),
        point: CanvasPoint(x: 6, y: 1),
      );

      expect(picked, 0xFFFF0000);
    });

    test('still picks the drawing where no letter stands', () {
      final picked = sampleCompositeColor(
        cut: cut,
        frameIndex: 0,
        surfaceResolver: (_, _) => cel(
          drawn: {(3, 3): blue, (6, 6): blue},
          letters: {(3, 3): red},
        ),
        point: CanvasPoint(x: 6, y: 6),
      );

      expect(picked, 0xFF0000FF);
    });
  });

  group('the fill', () {
    test('🚨stops at letters as it stops at a drawn line: a box written as '
        'text encloses its inside', () {
      final dab = buildFillDab(
        cut: cut,
        frameIndex: 0,
        surfaceResolver: (_, _) => cel(letters: boxOutline([0, 0, 0, 255])),
        point: CanvasPoint(x: 3, y: 3),
        color: 0xFF3366CC,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      )!;

      expect(dab.size, 2, reason: 'the inside of the box, and no more');
      expect(dab.center, CanvasPoint(x: 4, y: 4));
    });

    test('fixture: with no letters the same tap floods the whole page', () {
      final dab = buildFillDab(
        cut: cut,
        frameIndex: 0,
        surfaceResolver: (_, _) => cel(),
        point: CanvasPoint(x: 3, y: 3),
        color: 0xFF3366CC,
        options: const FloodFillOptions(expandPx: 0, antiAlias: false),
      )!;

      expect(dab.size, 8);
    });
  });

  group('the shared plan — playback, export and the camera', () {
    List<int>? planPixel(BitmapSurface resolved, int x, int y) {
      final planned = planCutFrameComposite(
        cut: cut,
        frameIndex: 0,
        surfaceResolver: (_, _) => resolved,
      ).single.surface;
      final rgba = surfacePixelRgba(planned, x, y);
      return rgba == null
          ? null
          : [rgba >> 24 & 0xFF, rgba >> 16 & 0xFF, rgba >> 8 & 0xFF, rgba & 0xFF];
    }

    test('hands every route tiles that already hold the letters, and no '
        'texts left to lay', () {
      final resolved = cel(drawn: {(3, 3): blue}, letters: {(3, 3): red});

      expect(planPixel(resolved, 3, 3), red);
      expect(
        planCutFrameComposite(
          cut: cut,
          frameIndex: 0,
          surfaceResolver: (_, _) => resolved,
        ).single.surface.texts,
        isEmpty,
      );
    });

    test('the tree plan, which the paint routes walk, does too', () {
      final resolved = cel(drawn: {(3, 3): blue}, letters: {(3, 3): red});

      final leaf =
          planCutFrameCompositeTree(
                cut: cut,
                frameIndex: 0,
                surfaceResolver: (_, _) => resolved,
              ).single
              as CompositeLeaf<CutFrameCompositeLayer>;

      expect(surfacePixelRgba(leaf.payload.surface, 3, 3), 0xFF0000FF);
      expect(leaf.payload.surface.texts, isEmpty);
    });
  });

  group('the seam', () {
    ResolvedLayerEffect eraseColor(List<int> rgb) => ResolvedLayerEffect(
      kind: EffectKind.deleteColor,
      values: [rgb[0].toDouble(), rgb[1].toDouble(), rgb[2].toDouble(), 0, 100],
    );

    test('lays the texts and then keys: a colour key names a letter\'s '
        'colour as it names a drawn line\'s', () {
      final source = cel(
        drawn: {(1, 1): red, (3, 3): blue},
        letters: {(3, 3): red, (6, 6): red},
      );

      final shown = celSurfaceAsShown(source, [eraseColor(red)]);

      // Every red is gone — the drawn one, the letter over the drawing and
      // the letter over bare paper.
      expect(surfacePixelRgba(shown, 1, 1)! & 0xFF, 0);
      expect(surfacePixelRgba(shown, 3, 3)! & 0xFF, 0);
      expect(surfacePixelRgba(shown, 6, 6)! & 0xFF, 0);
    });

    test('a key for the DRAWING\'s colour does not take a letter that '
        'covers it — the letter is what shows there', () {
      final source = cel(
        drawn: {(3, 3): blue, (5, 5): blue},
        letters: {(3, 3): red},
      );

      final shown = celSurfaceAsShown(source, [eraseColor(blue)]);

      expect(surfacePixelRgba(shown, 3, 3), 0xFF0000FF, reason: 'the letter');
      expect(surfacePixelRgba(shown, 5, 5)! & 0xFF, 0, reason: 'the drawing');
    });

    test('with no chain it is the laying alone', () {
      final source = cel(drawn: {(3, 3): blue}, letters: {(3, 3): red});

      expect(
        identical(
          celSurfaceAsShown(source, const []),
          celSurfaceWithTextsLaid(source),
        ),
        isTrue,
      );
    });

    test('a cel with no text and no chain is not touched', () {
      final bare = BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: tilesOf({(3, 3): blue}),
      );

      expect(identical(celSurfaceAsShown(bare, const []), bare), isTrue);
    });
  });
}
