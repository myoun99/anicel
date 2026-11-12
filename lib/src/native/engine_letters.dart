import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart';

import '../core/lru.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/canvas_size.dart';
import '../models/cel_number_letters.dart';
import '../models/dirty_region.dart';
import '../models/pasteboard_bounds.dart' show PasteboardReach;
import '../models/tile_coord.dart';
import '../services/se_name_tag_plan.dart' show ResolvedSeNameTag;
import '../ui/text/canvas_letter_plate.dart' show letterPlateBytesKept;
import '../ui/text/canvas_letter_shapes.dart';
import '../ui/text/canvas_letter_style.dart' show canvasLetterWeight;
import '../ui/text/cel_number_paint.dart' show celNumberShapes;
import '../ui/text/se_name_tag_paint.dart' show seNameTagShapes;
import '../ui/text/text_measure.dart' show TextMeasure;
import '../ui/theme/app_theme.dart' show AppTypography;
import 'engine_faces.dart';

/// THE GPU ENGINE'S LETTERS (rust/src/kernels/letters): a cel number's
/// letters set by the engine itself, in the app's canvas letters' faces
/// ([AppTypography.canvasLetterFaces]), each cluster where the app's one
/// layout of them put it ([celNumberShapes]) — the plate a numbered row
/// lays on the engine (`planCompositeTree`) as the walk lays the app's
/// (`celNumberPlate`).
///
/// 🚨★★★THE PLATE IS CANVAS PIXELS ON THE ROW'S PAPER (the law of
/// cel-number-on-the-engine-letters, 유저 2026-11-07 「지금까지가 셀번호가
/// 벡터엿던게 버그야. 통일하지 않았던거니까」): the kernel is handed only where
/// the letters stand on the paper, and the plan lays the plate under the
/// row's placement, as it lays the row's picture.
///
/// The plate is a surface of tiles while the app's tiles are the pixels the
/// pool keeps (`TileHold.slotsOf`): the engine's raster read back, kept
/// here by the letters, laid by the plan as any row's tiles are.
class EngineLetters {
  EngineLetters._(this._composite, this._faces);

  /// The letters [composite] lays, in the app's faces ([EngineFaces]).
  static Future<EngineLetters> open(GpuComposite composite) async =>
      EngineLetters._(composite, await EngineFaces.bundled());

  final GpuComposite _composite;
  final GpuFaces _faces;

  /// The plates made, by what they show — bytes, as the walk's
  /// ([letterPlateBytesKept]).
  final Lru<_PlateKey, BitmapSurface> _plates = Lru(
    limit: () => letterPlateBytesKept,
    costOf: (plate) => plate.tiles.length * gpuTileBytes,
  );

  /// [letters]' plate on the paper of [row] — no tile where they cover no
  /// pixel —, made the first time it is asked for and kept.
  BitmapSurface celNumberPlate(CelNumberLetters letters, BitmapSurface row) =>
      _plates.resolve(
        (
          letters: letters,
          canvas: row.canvasSize,
          reach: row.pasteboardReach,
          fonts: TextMeasure.fontsNow,
        ),
        () => _plateOf(
          celNumberShapes(letters),
          canvas: row.canvasSize,
          reach: row.pasteboardReach,
        ),
      );

  /// [tag]'s plate in its own space on a canvas of [canvas] — its blocks'
  /// letters set as a cel number's are ([seNameTagShapes]), laid by its
  /// placement as a row's picture is (card the-flutter-fx-chain-is-a-
  /// second-chain, 🗣️-Q1 유저 2026-11-12 「가이드선이 이름표 위에 그려져도
  /// 된다 — 이름표를 엔진 그림 안으로」) —, made the first time it is asked
  /// for and kept. What it holds is its writing alone: where it is laid,
  /// how strong and through what are the row's.
  BitmapSurface seNameTagPlate(ResolvedSeNameTag tag, CanvasSize canvas) =>
      _plates.resolve(
        (
          letters: (tag.content, tag.line, tag.delivery, tag.widthBudget),
          canvas: canvas,
          reach: PasteboardReach.whole,
          fonts: TextMeasure.fontsNow,
        ),
        () => _plateOf(
          switch (seNameTagShapes(tag, canvasSize: canvas)) {
            null => null,
            final layers => (layers: layers, stand: _whereTheyStand),
          },
          canvas: canvas,
          reach: PasteboardReach.whole,
        ),
      );

  BitmapSurface _plateOf(
    ({List<CanvasLetterShapes> layers, List<double> stand})? shapes, {
    required CanvasSize canvas,
    required PasteboardReach reach,
  }) {
    BitmapSurface on({
      Map<TileCoord, BitmapTile> tiles = const {},
      DirtyRegion? laid,
    }) => BitmapSurface(
      canvasSize: canvas,
      pasteboardReach: reach,
      tileSize: gpuTileSide,
      tiles: tiles,
      laidBounds: laid,
    );
    if (shapes == null) {
      return on();
    }
    final picture = GpuLetters();
    try {
      shapes.layers.forEach(picture._hand);
      final lettered = picture.set(_composite, _faces, shapes.stand);
      if (lettered == null) {
        return on();
      }
      try {
        final (:x0, :y0, :columns, :rows) = lettered.rect;
        final bytes = lettered.read();
        return on(
          tiles: {
            for (var down = 0; down < rows; down++)
              for (var across = 0; across < columns; across++)
                TileCoord(x: x0 + across, y: y0 + down): BitmapTile(
                  size: gpuTileSide,
                  pixels: Uint8List.sublistView(
                    bytes,
                    (down * columns + across) * gpuTileBytes,
                    (down * columns + across + 1) * gpuTileBytes,
                  ),
                ),
          },
          // A picture laid, kept whole wherever its letters stand — as the
          // walk's plate is, which no pasteboard cuts.
          laid: DirtyRegion(
            left: x0 * gpuTileSide,
            top: y0 * gpuTileSide,
            rightExclusive: (x0 + columns) * gpuTileSide,
            bottomExclusive: (y0 + rows) * gpuTileSide,
          ),
        );
      } finally {
        lettered.free();
      }
    } finally {
      picture.free();
    }
  }
}

typedef _PlateKey = ({
  Object letters,
  CanvasSize canvas,
  PasteboardReach reach,
  int fonts,
});

extension on GpuLetters {
  /// [layer] handed over as a pass of its own, every length in 64ths of a
  /// px of the layout.
  void _hand(CanvasLetterShapes layer) {
    pass(
      gpuColourOf(layer.argb),
      hard: layer.hard,
      outline: _inSixtyFourths(layer.outline),
    );
    for (final shape in layer.shapes) {
      switch (shape) {
        case CanvasLetterClusters(
          :final letters,
          :final size,
          :final clusters,
        ):
          if (letters.fontFamily case final family?) {
            throw UnsupportedError(
              'letters in a face the engine is not handed: $family',
            );
          }
          run(
            _whereTheyStand,
            size: _inSixtyFourths(size),
            weight: canvasLetterWeight(letters).value,
            italic: letters.italic,
            clusters: [
              for (final (:text, :left, :baseline) in clusters)
                (
                  text: text,
                  x: _inSixtyFourths(left),
                  y: _inSixtyFourths(baseline),
                ),
            ],
          );
        case CanvasLetterRect(:final rect):
          this.rect(_whereTheyStand, (
            _inSixtyFourths(rect.left),
            _inSixtyFourths(rect.top),
            _inSixtyFourths(rect.right),
            _inSixtyFourths(rect.bottom),
          ));
      }
    }
  }
}

/// A layer's shapes stand where its layout set them: no placement of their
/// own.
const _whereTheyStand = <double>[1, 0, 0, 1, 0, 0];

int _inSixtyFourths(double length) => (length * 64).round();
