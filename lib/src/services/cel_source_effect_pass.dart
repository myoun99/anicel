/// The CPU half of the effect chain: the kinds that are computed over a
/// cel's OWN tile bytes before anything is drawn ([EffectKind.runsOnSourcePixels]).
///
/// 🚨WHY THERE IS A CPU HALF AT ALL. Every other kind folds into a
/// `ui.ColorFilter.matrix` or a `ui.ImageFilter`, which is linear-plus-clamp
/// and therefore cannot express "is this pixel within N of that color". The
/// two ways to express it were a fragment shader or this; 유저 2026-08-27
/// chose this, and named the follow-up rule with it: *「거기가 아프면
/// 셰이더가 답이 아니고 cpu에서 더 개선하는 방향을 찾아야지」*.
///
/// ★IT RUNS IN THE SHARED VISIT, which is the whole reason it is in
/// `services/`. `planCutFrameComposite`/`planCutFrameCompositeTree` resolve
/// every route's surfaces — editing stack, playback cache, camera, export —
/// so a key applied here is applied to all four by construction rather than
/// by four call sites remembering to ([[derived-cel-projection-pattern]]:
/// "공유 방문에 태우면 4서피스가 공짜로 일치한다").
///
/// ⛔THE RESULT IS NEVER STORED. It is a composite-time filter like the
/// others — the truth is the parameters, and [_derived] is a cache keyed on
/// the immutable source surface's identity. Baking it would make it a
/// projection instead, which is a different pattern with different rules.
library;

import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/layer_effect.dart';
import '../models/tile_coord.dart';

/// One color key sampled at one frame — the parameters as the pixel loop
/// wants them (bytes, not the spec's doubles).
///
/// ★SHARED WITH THE DESTRUCTIVE VERB. 유저 I-8 asked for the same operation
/// twice: as an fx, and as a button beside 색 변환. This class is the single
/// definition of "which pixels does that color name", so the two can never
/// drift into two answers for one question.
class CelColorKey {
  CelColorKey({
    required this.red,
    required this.green,
    required this.blue,
    required this.tolerance,
    required this.amount,
    required this.keepsMatches,
  });

  /// Reads one resolved chain entry. Returns null for a kind that is not a
  /// color key — callers filter with [EffectKind.runsOnSourcePixels] and
  /// this is the backstop, not a second gate.
  static CelColorKey? fromResolved(ResolvedLayerEffect effect) {
    if (!effect.kind.runsOnSourcePixels) {
      return null;
    }
    return CelColorKey(
      red: _byte(effect.parameter('keyRed')),
      green: _byte(effect.parameter('keyGreen')),
      blue: _byte(effect.parameter('keyBlue')),
      tolerance: _byte(effect.parameter('tolerance')),
      amount: (effect.parameter('amount') / 100).clamp(0.0, 1.0),
      keepsMatches: effect.kind == EffectKind.keepColor,
    );
  }

  final int red;
  final int green;
  final int blue;

  /// The largest per-channel difference a pixel may have and still count as
  /// the key color.
  ///
  /// ⛔CHEBYSHEV, NOT EUCLIDEAN — the largest single-channel gap, not the
  /// distance through color space. It is the metric a tolerance slider is
  /// read as everywhere else (a paint bucket's tolerance), it needs no
  /// square root in the inner loop, and it answers a question an artist can
  /// predict from the numbers in front of them.
  final int tolerance;

  /// 0…1. See [colorKeyParameterSpecs]' Amount note: a color key has no
  /// value that is an identity, so this is what makes a freshly added
  /// effect do nothing.
  final double amount;

  /// True for [EffectKind.keepColor] — the same comparison, opposite
  /// answer.
  final bool keepsMatches;

  bool get isNoOp => amount <= 0;

  bool matches(int red, int green, int blue) {
    final dr = red > this.red ? red - this.red : this.red - red;
    if (dr > tolerance) {
      return false;
    }
    final dg = green > this.green ? green - this.green : this.green - green;
    if (dg > tolerance) {
      return false;
    }
    final db = blue > this.blue ? blue - this.blue : this.blue - blue;
    return db <= tolerance;
  }

  /// The alpha [alpha] becomes. RGB is never touched — the same division
  /// [CelPixelChannel.alpha] draws, and the reason the destructive verb's
  /// undo recipe survives a color selector: an RGB comparison still picks
  /// exactly the same pixels after the pass has run.
  ///
  /// ⛔ONE PASS. The Amount mix is folded into this arithmetic rather than
  /// drawn as a second layer over the first, because a two-pass mix
  /// accumulates alpha ([[derived-cel-projection-pattern]] rule 6).
  int alphaFor(int red, int green, int blue, int alpha) {
    if (alpha == 0) {
      return 0;
    }
    if (matches(red, green, blue) == keepsMatches) {
      return alpha;
    }
    if (amount >= 1) {
      return 0;
    }
    return (alpha * (1 - amount)).round();
  }

  /// The value identity a cache key needs. ⛔Values, not a hash: a hash
  /// collision here does not read stale, it MERGES two different pictures
  /// ([[derived-cel-projection-pattern]]: "누락 = 충돌").
  List<double> get signature => [
    red.toDouble(),
    green.toDouble(),
    blue.toDouble(),
    tolerance.toDouble(),
    amount,
    keepsMatches ? 1 : 0,
  ];

  static int _byte(double value) => value.round().clamp(0, 255);
}

/// [effects] split into the CPU half and the paint half, each keeping its
/// own relative order.
///
/// 🚨THE CPU HALF ALWAYS RUNS FIRST, and that is why [normalizedEffectChain]
/// exists: the chain a layer can HOLD is already ordered this way, so this
/// split cannot reorder anything the artist can see. If it ever could, the
/// lane list and the pixels would disagree about what the chain means.
({List<ResolvedLayerEffect> source, List<ResolvedLayerEffect> paint})
splitSourceEffects(List<ResolvedLayerEffect> effects) {
  if (effects.isEmpty) {
    return (source: const [], paint: const []);
  }
  List<ResolvedLayerEffect>? source;
  List<ResolvedLayerEffect>? paint;
  for (final effect in effects) {
    if (effect.kind.runsOnSourcePixels) {
      (source ??= []).add(effect);
    } else {
      (paint ??= []).add(effect);
    }
  }
  if (source == null) {
    return (source: const [], paint: effects);
  }
  return (source: source, paint: paint ?? const []);
}

/// The values every color key in [effects] was resolved to — what a cache
/// over keyed pixels has to carry in its validity check.
///
/// ★A CACHE KEYED ON THE CEL'S REVISION IS NOT ENOUGH. A revision moves
/// when the DRAWING changes; dragging Tolerance changes no drawing, so a
/// cache that does not hold these values serves the pixels of the old
/// tolerance for ever. Empty for a chain with no keys, which is the common
/// case and compares in one length check.
List<double> celSourceEffectSignature(List<ResolvedLayerEffect> effects) {
  if (effects.isEmpty) {
    return const [];
  }
  List<double>? signature;
  for (final effect in effects) {
    final key = CelColorKey.fromResolved(effect);
    if (key != null && !key.isNoOp) {
      (signature ??= []).addAll(key.signature);
    }
  }
  return signature ?? const [];
}

/// Whether two [celSourceEffectSignature] results say the same thing.
bool sameCelSourceEffectSignature(List<double> a, List<double> b) =>
    _sameSignature(a, b);

/// The alpha ONE pixel keeps after every color key in [effects].
///
/// ★The one-pixel door into the same kernel the tile pass walks. The
/// eyedropper reads a single byte quad and must see the row's FINISHED
/// pixels (유저 2026-08-27: *「레이어의 완성본 픽셀을 스포이드 찍도록 하고싶어.
/// 그러니 fx가 싫으면 fx끄고 스포이드 찍도록」*) — routing it through
/// [CelColorKey.alphaFor] rather than a second implementation is what keeps
/// "is this pixel keyed out" from having two answers.
int celSourceEffectAlphaFor(
  List<ResolvedLayerEffect> effects, {
  required int red,
  required int green,
  required int blue,
  required int alpha,
}) {
  if (effects.isEmpty || alpha == 0) {
    return alpha;
  }
  var next = alpha;
  for (final effect in effects) {
    final key = CelColorKey.fromResolved(effect);
    if (key == null || key.isNoOp) {
      continue;
    }
    next = key.alphaFor(red, green, blue, next);
    if (next == 0) {
      return 0;
    }
  }
  return next;
}

/// [surface] with every color key in [effects] applied, or [surface] itself
/// when there is nothing to do.
///
/// Repeated calls with the same surface and the same values answer from the
/// cache, so a playhead crossing twenty exposures of one cel pays once and
/// scrubbing pays nothing.
BitmapSurface celSurfaceWithSourceEffects(
  BitmapSurface surface,
  List<ResolvedLayerEffect> effects,
) {
  if (effects.isEmpty) {
    return surface;
  }
  final keys = <CelColorKey>[];
  for (final effect in effects) {
    final key = CelColorKey.fromResolved(effect);
    if (key != null && !key.isNoOp) {
      keys.add(key);
    }
  }
  if (keys.isEmpty) {
    return surface;
  }
  final signature = [for (final key in keys) ...key.signature];
  final cached = _derived[surface];
  if (cached != null && _sameSignature(cached.signature, signature)) {
    return cached.surface;
  }
  final result = _applyKeys(surface, keys);
  // ONE entry per surface, deliberately. Dragging Tolerance makes a new
  // signature every frame, and holding them all would retain a derived copy
  // of the cel per slider step; the value being dragged is the only one
  // anyone is looking at.
  _derived[surface] = _DerivedSurface(signature, result);
  return result;
}

BitmapSurface _applyKeys(BitmapSurface surface, List<CelColorKey> keys) {
  final rebuilt = <TileCoord, BitmapTile>{};
  for (final entry in surface.tiles.entries) {
    final keyed = _keyedTile(entry.value, keys, surface.tileSize);
    if (!identical(keyed, entry.value)) {
      rebuilt[entry.key] = keyed;
    }
  }
  if (rebuilt.isEmpty) {
    return surface;
  }
  return surface.putTiles(rebuilt.values);
}

/// 🚨THE CACHE IS PER TILE, NOT PER SURFACE, and that is what makes the CPU
/// pass usable while you are DRAWING on a keyed row.
///
/// A surface-grained cache would be right for scrubbing and wrong for a
/// stroke: every dab commits a new [BitmapSurface], so a per-surface key
/// would miss on every dab and re-key the whole cel each time. Tiles are
/// immutable and structurally shared, so a dab makes exactly ONE new tile
/// object — cache here and the stroke re-keys one tile while the rest of
/// the cel answers from memory. Same reasoning, same [Expando] shape, as
/// `BitmapTileImageCache`.
BitmapTile _keyedTile(BitmapTile tile, List<CelColorKey> keys, int tileSize) {
  final signature = [for (final key in keys) ...key.signature];
  final cached = _keyedTiles[tile];
  if (cached != null && _sameSignature(cached.signature, signature)) {
    return cached.tile;
  }
  // Reads come from the tile's own bytes, writes go to a copy made LAZILY
  // at the first pixel that actually moves — a tile the key does not touch
  // keeps its ORIGINAL object, which is what lets the surface share it and
  // the tile image cache keep the image already decoded for it.
  final pixelCount = tileSize * tileSize;
  final written = tile.readPixels<Uint8List?>((_, view) {
    Uint8List? out;
    for (var pixel = 0; pixel < pixelCount; pixel += 1) {
      final offset = pixel * 4;
      final alpha = view[offset + 3];
      if (alpha == 0) {
        continue;
      }
      final red = view[offset];
      final green = view[offset + 1];
      final blue = view[offset + 2];
      var next = alpha;
      for (final key in keys) {
        next = key.alphaFor(red, green, blue, next);
        if (next == 0) {
          break;
        }
      }
      if (next == alpha) {
        continue;
      }
      out ??= Uint8List.fromList(view);
      out[offset + 3] = next;
    }
    return out;
  });
  final keyed = written == null
      ? tile
      : BitmapTile(coord: tile.coord, size: tileSize, pixels: written);
  _keyedTiles[tile] = _KeyedTile(signature, keyed);
  return keyed;
}

class _KeyedTile {
  const _KeyedTile(this.signature, this.tile);

  final List<double> signature;
  final BitmapTile tile;
}

/// One keyed tile per source tile — the newest values win, for the reason
/// [_derived] states about a slider being dragged.
final Expando<_KeyedTile> _keyedTiles = Expando<_KeyedTile>(
  'celSourceEffectTiles',
);

class _DerivedSurface {
  const _DerivedSurface(this.signature, this.surface);

  final List<double> signature;
  final BitmapSurface surface;
}

/// Derived render data keyed on the SOURCE surface's identity. Surfaces are
/// immutable, so identity is a stable key and an edited cel is a different
/// object that misses and recomputes — the same contract
/// `BitmapTileImageCache` runs on. The [Expando] releases an entry when the
/// source surface itself goes.
final Expando<_DerivedSurface> _derived = Expando<_DerivedSurface>(
  'celSourceEffectSurfaces',
);

bool _sameSignature(List<double> a, List<double> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
