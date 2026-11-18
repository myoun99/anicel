import '../helpers/a_cut_as_surfaces.dart';
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
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/surface_rgba_in_place.dart';

/// R9-rest (the text tool, 유저 2026-10-06: 「셀의 그림이랑 정확히 동일」): a
/// text is part of the picture for everything that READS a cel, not only for
/// what draws it — the eyedropper picks a letter's colour, a fill stops at a
/// letter, a colour key names a letter's colour, and the shared plan hands
/// every paint route tiles that already hold the letters.
///
/// The key's is the plan's: the engine keys the tiles the row hands it
/// (`the_engine_keys_a_row_as_each_pixel_is_keyed_test`), and those hold
/// the letters. ↩️It was asked of a seam of its own, `celSurfaceAsShown`,
/// which laid the texts and then keyed them on the CPU before a plugin at
/// a chain's head, until that plugin was a step of the chain
/// (float-warp-resamples-in-the-c-engine (2), 2026-11-11).
///
/// Each reader is asked through its own door, with a cel whose DRAWING says
/// one thing and whose text says another, so a reader that took the tiles
/// of a surface still carrying texts answers with the drawing and fails.
/// (The fill's door is a canvas's, on the engine:
/// `test/ui/canvas/the_fill_reads_its_source_test.dart`.)
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const tileSize = defaultCelTileSize;

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

  group('the shared plan — playback, export and the camera', () {
    // ↩️A flat plan beside it asked the same; only tests called it
    // (the-flat-composite-plan-has-no-caller-but-tests, 10-25).
    test('the tree plan the paint routes walk hands every route tiles that '
        'already hold the letters, and no texts left to lay', () {
      final resolved = cel(drawn: {(3, 3): blue}, letters: {(3, 3): red});

      final leaf =
          planCutFrameCompositeTree(
                cut: cut,
                frameIndex: 0,
                reading: (surfaces: (_, _) => resolved, plugins: null),
              ).single
              as CompositeLeaf<CutFrameCompositeLayer>;

      expect(surfaceRgbaInPlace(leaf.payload.surface, 3, 3), 0xFF0000FF);
      expect(leaf.payload.surface.texts, isEmpty);
    });
  });
}
