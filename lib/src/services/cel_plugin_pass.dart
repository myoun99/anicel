/// A PLUGIN'S EFFECT OVER A CEL'S OWN PIXELS — the CPU half's second step,
/// after the colour keys (`celSurfaceWithSourceEffects`).
///
/// 🗣️I-132-Q32 (유저 2026-10-30): 「b 로 첫 판, 이어서 a」 — b: a plugin
/// runs at the head of a cel row's chain, with nothing before it but colour
/// keys, at the place the keys run, so every route that shows a cel shows
/// it through the plugin by the one seam (`celSurfaceAsShown`). Its cost,
/// named with the answer: 「무거운 플러그인은 그 행이 바뀔 때마다 캔버스가
/// 그만큼 멈춘다(같은 프레임 · 같은 값은 보관해서 한 번만 돈다)」.
///
/// ⛔A WHOLE PICTURE, NEVER A TILE. A plugin may move a pixel anywhere in
/// its reach — or read the whole picture for one pixel — so it is handed
/// the cel in one piece and gives back one; nothing here asks it of a tile.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/rgba_premultiply.dart';
import '../core/signed_memo.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/canvas_size.dart';
import '../models/dirty_region.dart';
import '../models/fx_plugin_description.dart';
import '../models/fx_plugin_run.dart';
import '../models/layer_effect.dart';
import '../models/layer_id.dart';
import '../models/placed_tile.dart';
import '../models/tile_coord.dart';
import 'brush_stroke_blend.dart' show bitmapSurfaceRegionPixels;
import 'cel_text_laying.dart';

/// [surface] — a cel's picture, its texts laid and its keys applied —
/// through [effect], a plugin's effect with its run ([ResolvedLayerEffect.run]);
/// [surface] itself where it has none, or where the plugin fails.
///
/// ⛔Called by the source pass alone (`celSurfaceWithSourceEffects`), for
/// that pass's reason: a route that ran the plugin itself would be a route
/// that could run it otherwise (`a_cel_is_shown_through_one_seam_test`).
BitmapSurface celSurfaceThroughPlugin(
  BitmapSurface surface,
  ResolvedLayerEffect effect,
) {
  final run = effect.run;
  if (run == null) {
    return surface;
  }
  // ONE entry per surface, as the keys keep theirs: a value dragged makes a
  // new sample each step, and only the one being looked at is wanted.
  return _ran.resolve(
    surface,
    effect,
    () => _rendered(surface, effect, run) ?? surface,
  );
}

/// The rows [effect]'s layer parameters name that its run holds, each once,
/// in the order the parameters name them — the order of `frame->layers`.
List<LayerId> fxPluginRowsOf(ResolvedLayerEffect effect, FxPluginRun run) => [
  ...{
    for (final row in effect.layers.values)
      if (row != null && run.rows.containsKey(row)) row,
  },
];

/// [effect]'s values as a frame hands them (anicel_fx_value: four doubles a
/// parameter, in its parameters' order) — a point where [paper] puts it, a
/// layer the place of its row in [rows], or -1 where it names none.
Float64List fxPluginValuesOf(
  ResolvedLayerEffect effect, {
  required CanvasSize paper,
  required List<LayerId> rows,
}) {
  final specs = effect.specs;
  final values = Float64List(specs.length * 4);
  for (final (index, spec) in specs.indexed) {
    final at = index * 4;
    final value = effect.parameter(spec.id);
    switch (spec.unit) {
      case EffectParameterUnit.color:
        values.setAll(at, FxPluginDescription.channelsOf(value.toInt()));
      case EffectParameterUnit.point:
        final point = effectPointOnPaper(effect.points[spec.id], paper);
        values
          ..[at] = point.x
          ..[at + 1] = point.y;
      case EffectParameterUnit.flag:
        values[at] = effectFlagIsOn(value) ? 1 : 0;
      case EffectParameterUnit.layer:
        final row = effect.layers[spec.id];
        values[at] = row == null ? -1 : rows.indexOf(row).toDouble();
      case EffectParameterUnit.number ||
          EffectParameterUnit.degrees ||
          EffectParameterUnit.pixels ||
          EffectParameterUnit.choice:
        values[at] = value;
    }
  }
  return values;
}

BitmapSurface? _rendered(
  BitmapSurface surface,
  ResolvedLayerEffect effect,
  FxPluginRun run,
) {
  final rows = fxPluginRowsOf(effect, run);
  final values = fxPluginValuesOf(
    effect,
    paper: surface.canvasSize,
    rows: rows,
  );
  final reach = run.runner.reach(values, run.moment);
  if (reach == null) {
    return null;
  }
  final input = _inflated(_contentOf(surface), _bounded(reach, surface));
  FxPluginPicture pictureOf(BitmapSurface? picture) => (
    pixels: picture == null
        ? Uint8List(input.width * input.height * 4)
        : _premultiplied(
            bitmapSurfaceRegionPixels(celSurfaceWithTextsLaid(picture), input),
          ),
    width: input.width,
    height: input.height,
    left: input.left,
    top: input.top,
  );
  final output = run.runner.render(
    input: pictureOf(surface),
    values: values,
    layers: [for (final row in rows) pictureOf(run.rows[row])],
    moment: run.moment,
  );
  if (output == null) {
    return null;
  }
  final straight = straightRgbaFor(output);
  zeroFullyClearPixels(straight);
  return _surfaceOf(surface, straight, input);
}

/// The paper, and every tile of [surface] that holds ink — what a plugin is
/// handed, as AE hands an effect a comp-sized solid: an empty cel still
/// gives it the paper to draw on.
DirtyRegion _contentOf(BitmapSurface surface) {
  var content = DirtyRegion(
    left: 0,
    top: 0,
    rightExclusive: surface.canvasSize.width,
    bottomExclusive: surface.canvasSize.height,
  );
  final size = surface.tileSize;
  for (final MapEntry(key: coord, value: tile) in surface.tiles.entries) {
    if (tile.hasInk) {
      content = content.union(
        DirtyRegion(
          left: coord.x * size,
          top: coord.y * size,
          rightExclusive: (coord.x + 1) * size,
          bottomExclusive: (coord.y + 1) * size,
        ),
      );
    }
  }
  return content;
}

/// [reach], no farther than the picture is across: past its storable rect
/// every pixel is clear and nothing drawn there is kept, so a reach beyond
/// that reads and draws nothing more — and a plugin that names a wild one
/// is not handed a picture past what the device can hold.
int _bounded(int reach, BitmapSurface surface) {
  final storable = surface.storableRect;
  return math.min(
    reach,
    math.max(storable.width, storable.height).ceil(),
  );
}

DirtyRegion _inflated(DirtyRegion region, int by) => DirtyRegion(
  left: region.left - by,
  top: region.top - by,
  rightExclusive: region.rightExclusive + by,
  bottomExclusive: region.bottomExclusive + by,
);

/// [straight] — the plugin's picture over [input] — as [surface]'s tiles:
/// every tile of [input] the picture keeps ([BitmapSurface.containsTileCoord]),
/// the clear ones dropped. Nothing outside [input] held ink
/// ([_contentOf]), so the picture is the whole cel.
BitmapSurface _surfaceOf(
  BitmapSurface surface,
  Uint8List straight,
  DirtyRegion input,
) {
  final size = surface.tileSize;
  final tiles = <PlacedTile>[];
  final (:firstX, :lastX, :firstY, :lastY) = input.tileRange(tileSize: size);
  for (var y = firstY; y <= lastY; y += 1) {
    for (var x = firstX; x <= lastX; x += 1) {
      final coord = TileCoord(x: x, y: y);
      if (!surface.containsTileCoord(coord)) {
        continue;
      }
      final within = input.intersection(
        DirtyRegion(
          left: x * size,
          top: y * size,
          rightExclusive: (x + 1) * size,
          bottomExclusive: (y + 1) * size,
        ),
      )!;
      final pixels = Uint8List(size * size * 4);
      final rowBytes = within.width * 4;
      for (var row = within.top; row < within.bottomExclusive; row += 1) {
        final to = ((row - y * size) * size + within.left - x * size) * 4;
        pixels.setRange(
          to,
          to + rowBytes,
          straight,
          ((row - input.top) * input.width + within.left - input.left) * 4,
        );
      }
      tiles.add((coord: coord, tile: BitmapTile(size: size, pixels: pixels)));
    }
  }
  return BitmapSurface(
    canvasSize: surface.canvasSize,
    pasteboardReach: surface.pasteboardReach,
    tileSize: size,
    texts: surface.texts,
    photos: surface.photos,
    laidBounds: surface.laidBounds,
  ).putMaterializedTiles(tiles);
}

Uint8List _premultiplied(Uint8List straight) {
  premultiplyRgbaInPlace(straight);
  return straight;
}

/// The picture a plugin made of each surface, by the sample it was made
/// with — its values and its run, rows and moment and all
/// ([ResolvedLayerEffect.==]).
final SignedMemo<ResolvedLayerEffect, BitmapSurface> _ran = SignedMemo(
  'celPluginSurfaces',
);
