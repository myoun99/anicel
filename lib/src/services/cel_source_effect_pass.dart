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

import '../core/collection_equality.dart';
import '../core/signed_memo.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/bitmap_tile_rewrite.dart';
import '../models/layer_effect.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';
import 'cel_plugin_pass.dart';

/// What a [CelColorKey] does to the pixels its colour names.
///
/// 🚨THREE ANSWERS, NOT A FLAG. `keepsMatches` answered two questions: for
/// the BUTTON 색 유지 it erased every pixel the colour did NOT name, and the
/// fx Keep Color meant the same. I-132-Q2 (유저 2026-10-27: 「하나로 + AE
/// 뜻」) made the fx's keep AE's — it gives back what the keys before it
/// erased — and the button's stays what it was.
enum CelKeyOperation {
  /// Erases what the colour names: the fx's Key Colors, the button 색 삭제.
  eraseMatches,

  /// Erases what the colour does NOT name: the button 색 유지 alone.
  eraseOthers,

  /// Gives back, of what the colour names, what the keys before it in its
  /// run erased: the fx's Keep Colors.
  restoreMatches,
}

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
    required this.operation,
  }) : _keptFraction = _asFloat32(1 - _asFloat32(amount));

  /// `1 - amount`, ROUNDED TO 32-BIT FLOAT at every step.
  ///
  /// ⛔FLOAT32, DELIBERATELY, in a language whose doubles are 64-bit. This
  /// effect has two implementations by necessity: the BUTTON edits stored
  /// bytes, which only Dart can do, and the FX keys a composited buffer,
  /// which only a fragment shader can do (`shaders/colour_key.frag`). A
  /// specification one of them cannot follow is not a specification.
  ///
  /// 🧪MEASURED, not feared: computing the mix in doubles disagreed with the
  /// shader on **222 of 25856** (alpha, amount) pairs. Every one of them was
  /// a value that landed on an exact half — alpha 70 at amount 0.05 is
  /// exactly 66.5, which a double rounds up to 67 and a float32 has already
  /// fallen below. Neither answer is truer; having two of them is the
  /// problem.
  final double _keptFraction;

  static final Float32List _scratch = Float32List(1);

  /// ⚠️A STORE IS THE ROUNDING. Dart has no float32 arithmetic, so the only
  /// way to get one is to put a double into a `Float32List` and read it back.
  static double _asFloat32(double value) {
    _scratch[0] = value;
    return _scratch[0];
  }

  /// Reads one resolved chain entry. Returns null for a kind that is not a
  /// color key — callers filter with [EffectKind.runsOnSourcePixels] and
  /// this is the backstop, not a second gate.
  static CelColorKey? fromResolved(ResolvedLayerEffect effect) {
    if (!effect.kind.runsOnSourcePixels) {
      return null;
    }
    final key = effect.color('keyColor');
    return CelColorKey(
      red: (key >> 16) & 0xFF,
      green: (key >> 8) & 0xFF,
      blue: key & 0xFF,
      tolerance: _byte(effect.parameter('tolerance')),
      amount: (effect.parameter('amount') / 100).clamp(0.0, 1.0),
      operation: effect.parameter('keyOperation').round() == 0
          ? CelKeyOperation.eraseMatches
          : CelKeyOperation.restoreMatches,
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

  final CelKeyOperation operation;

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
  /// ⛔The full-strength case is NOT a branch. `_keptFraction` is 0 there and
  /// the arithmetic ([_erased]) lands on 0 by itself — a second path would be
  /// a second place for the shader to fail to match.
  ///
  /// [original] is the alpha the pixel had before its RUN of keys — the keys
  /// standing together in the chain. A restore gives back, by Amount, what
  /// the run took of it: `original - erased(original - alpha)`, the erase's
  /// own arithmetic over what is missing, so a restore with nothing taken
  /// before it changes nothing.
  int alphaFor(
    int red,
    int green,
    int blue,
    int alpha, {
    required int original,
  }) {
    if (operation == CelKeyOperation.restoreMatches) {
      return matches(red, green, blue)
          ? original - _erased(original - alpha)
          : alpha;
    }
    if (alpha == 0 || !erases(red, green, blue)) {
      return alpha;
    }
    return _erased(alpha);
  }

  /// What erasing leaves of [alpha] — [alphaFor]'s arithmetic, and the
  /// walk's alpha table ([_keyTables]).
  int _erased(int alpha) => (_asFloat32(alpha * _keptFraction) + 0.5).floor();

  /// Whether this key NAMES the pixel for erasure — PURELY a colour
  /// question, with no alpha in it.
  ///
  /// 🚨THE PURITY IS LOAD-BEARING, not tidiness. The destructive verb's undo
  /// replays the forward walk positionally, so the selector has to pick the
  /// same pixels the second time — and by then the forward pass has ZEROED
  /// their alpha. Reading alpha here (even as an "already empty, skip it"
  /// shortcut) makes the undo walk shorter than the forward one and the
  /// recipe lands on the wrong pixels. A test caught exactly that.
  bool erases(int red, int green, int blue) => switch (operation) {
    CelKeyOperation.eraseMatches => matches(red, green, blue),
    CelKeyOperation.eraseOthers => !matches(red, green, blue),
    CelKeyOperation.restoreMatches => false,
  };

  /// The value identity a cache key needs. ⛔Values, not a hash: a hash
  /// collision here does not read stale, it MERGES two different pictures
  /// ([[derived-cel-projection-pattern]]: "누락 = 충돌").
  List<double> get signature => [
    red.toDouble(),
    green.toDouble(),
    blue.toDouble(),
    tolerance.toDouble(),
    amount,
    operation.index.toDouble(),
  ];

  static int _byte(double value) => value.round().clamp(0, 255);
}

/// [effects] split at the point where the chain stops being about the cel's
/// own bytes: the LEADING run of source-pixel kinds, and everything from the
/// first painted effect onward.
///
/// 🚨THE LEADING RUN, NOT EVERY ONE OF THEM. 유저 2026-08-27: *「누가
/// 트랜스폼fx처럼 고정 fx가 아닌것에 순서를 고정하라했지? ae몰라? ae는 순서
/// 자유잖아. 자유롭게 해야지. 순서가 결과에 영향주는거고」* — so a colour key
/// UNDER a blur means "blur first, then key", and there is no cel byte left
/// to key by then. Only a key that still sees the cel's own bytes can be one
/// of these; the rest are shader passes over what the chain has painted so
/// far (see `resolveCompositeEffectPlan`).
///
/// ⛔The old rule pulled EVERY key to the front, and the chain a row could
/// hold was normalized to match so the lane list never lied. Order is free
/// now, so the split follows the order instead of the order following the
/// split.
///
/// 🗣️AND A PLUGIN RIGHT AFTER THEM, ONE (I-132-Q32 b, 유저 2026-10-30: 「b
/// 로 첫 판」): 「셀 행에서 fx 줄 맨 앞(앞에 색상 키만 있어도 됨)일 때 돈다 —
/// 색상 키의 CPU 길과 같은 자리」. A plugin anywhere else — under another
/// effect, a second one — runs as a step over what the chain made before
/// it (`PluginEffect`, 🗣️I-132-Q34 a 「어디에 걸어도 돌고」).
({List<ResolvedLayerEffect> source, List<ResolvedLayerEffect> paint})
splitSourceEffects(List<ResolvedLayerEffect> effects) {
  if (effects.isEmpty) {
    return (source: const [], paint: const []);
  }
  var leading = 0;
  while (leading < effects.length &&
      effects[leading].kind.runsOnSourcePixels) {
    leading += 1;
  }
  if (leading < effects.length &&
      effects[leading].kind == EffectKind.plugin) {
    leading += 1;
  }
  if (leading == 0) {
    return (source: const [], paint: effects);
  }
  if (leading == effects.length) {
    return (source: effects, paint: const []);
  }
  return (
    source: effects.sublist(0, leading),
    paint: effects.sublist(leading),
  );
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
    listEquals(a, b);

/// The plugin's effect a source run ([splitSourceEffects]) ends at, where
/// it runs ([ResolvedLayerEffect.run]) — null where none does.
///
/// ★WHAT A CACHE OVER A SHOWN CEL HOLDS BESIDE [celSourceEffectSignature]:
/// a plugin's picture moves with its values, its frame and the rows it
/// reads, none of which is a cel's revision. And the question a route that
/// shows a cel a TILE at a time asks: a plugin is run over the whole cel
/// ([celSurfaceThroughPlugin]), never a tile.
ResolvedLayerEffect? celSourcePlugin(List<ResolvedLayerEffect> effects) =>
    switch (effects.lastOrNull) {
      final effect? when effect.run != null => effect,
      _ => null,
    };

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
  final keyed = _keyed(surface, effects);
  return switch (celSourcePlugin(effects)) {
    final plugin? => celSurfaceThroughPlugin(keyed, plugin),
    null => keyed,
  };
}

/// [surface] with every colour key in [effects] applied.
BitmapSurface _keyed(BitmapSurface surface, List<ResolvedLayerEffect> effects) {
  final keys = _keysOf(effects);
  if (keys.isEmpty) {
    return surface;
  }
  // Once per call, not once per tile: the same values reach every tile in
  // the surface, and rebuilding this list per tile allocated a list per
  // tile per frame while a slider was moving.
  final signature = [for (final key in keys) ...key.signature];
  // ONE entry per surface, deliberately. Dragging Tolerance makes a new
  // signature every frame, and holding them all would retain a derived copy
  // of the cel per slider step; the value being dragged is the only one
  // anyone is looking at.
  return _derived.resolve(
    surface,
    signature,
    () => _applyKeys(surface, keys, signature),
  );
}

/// [straight] — straight rgba, a cel's bytes as its texts make them — with
/// every colour key in [effects] applied IN PLACE: the walk the tile pass
/// takes over each tile ([_keyedPixels]), over bytes that are no tile.
///
/// What a text a hand carries will land as is asked over a REGION of its
/// cel (`celTextLandingAsShown`, F-344-Q3), and the alpha a pixel keeps is
/// that pixel's own answer, so this makes the tile pass's bytes there.
/// ⛔Called by the seam alone, for [celSurfaceWithSourceEffects]'s reason
/// (`a_cel_is_shown_through_one_seam_test`).
void celSourceEffectsOverStraight(
  Uint8List straight,
  List<ResolvedLayerEffect> effects,
) {
  if (effects.isEmpty) {
    return;
  }
  assert(celSourcePlugin(effects) == null, _wholeCelOnly);
  final keys = _keysOf(effects);
  if (keys.isNotEmpty) {
    _keyedPixels(straight, keys, () => straight);
  }
}

/// [tile] — one of a cel's tiles as its texts make it — with every colour
/// key in [effects] applied: the very tile [celSurfaceWithSourceEffects]
/// makes of it in a surface (one memo, [_keyedTile]), or [tile] itself
/// when there is nothing to do.
///
/// ⛔Called by the seam alone, for [celSurfaceWithSourceEffects]'s reason
/// (`a_cel_is_shown_through_one_seam_test`).
BitmapTile celTileWithSourceEffects(
  BitmapTile tile,
  List<ResolvedLayerEffect> effects,
  int tileSize,
) {
  assert(celSourcePlugin(effects) == null, _wholeCelOnly);
  final keys = _keysOf(effects);
  return keys.isEmpty
      ? tile
      : _keyedTile(tile, keys, [
          for (final key in keys) ...key.signature,
        ], tileSize);
}

const String _wholeCelOnly =
    'A plugin runs over the whole cel (celSurfaceAsShown), never a tile.';

/// The colour keys [effects] applies, in its order — a kind that keys
/// nothing, and a key that does nothing, left out.
List<CelColorKey> _keysOf(List<ResolvedLayerEffect> effects) => [
  for (final effect in effects)
    if (CelColorKey.fromResolved(effect) case final key? when !key.isNoOp)
      key,
];

BitmapSurface _applyKeys(
  BitmapSurface surface,
  List<CelColorKey> keys,
  List<double> signature,
) {
  final rebuilt = <TileCoord, BitmapTile>{};
  for (final entry in surface.tiles.entries) {
    final keyed = _keyedTile(entry.value, keys, signature, surface.tileSize);
    if (!identical(keyed, entry.value)) {
      rebuilt[entry.key] = keyed;
    }
  }
  return surface.withRebuiltTiles(rebuilt);
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
BitmapTile _keyedTile(
  BitmapTile tile,
  List<CelColorKey> keys,
  List<double> signature,
  int tileSize,
) {
  return _keyedTiles.resolve(
    tile,
    signature,
    () =>
        rewriteTileLazily(
          tile,
          tileSize,
          (view) => _keyedPixels(view, keys, () => Uint8List.fromList(view)),
        ) ??
        tile,
  );
}

/// [keys] over the straight rgba [view]: every pixel's alpha what they
/// leave it, written to the bytes [into] answers — asked once, at the
/// first pixel that changes — and null when none does. THE walk, a tile's
/// ([_keyedTile]) and a region's ([celSourceEffectsOverStraight]) alike,
/// [keyRgbaKeysAtOnce] keys at a time in the chain's order.
Uint8List? _keyedPixels(
  Uint8List view,
  List<CelColorKey> keys,
  Uint8List Function() into,
) {
  Uint8List? out;
  for (var from = 0; from < keys.length; from += keyRgbaKeysAtOnce) {
    final tables = _keyTables(
      keys.sublist(from, math.min(from + keyRgbaKeysAtOnce, keys.length)),
    );
    final source = out;
    // A restore past the first thirty-two still gives back to [view]'s
    // alphas — the run's, whichever call it falls in.
    out = source == null
        ? _walk(view, view, tables, into)
        : _walk(source, view, tables, () => source) ?? source;
  }
  return out;
}

/// [tables] over [view] as [_keyedPixels] says — in C where the engine is
/// loaded (`qa_key_rgba`), and here, step for step the same, where it is
/// not (`the_keys_walk_the_same_in_c_test`).
///
/// 🔬IN C BECAUSE A STROKE PAYS IT EVERY FLUSH: a live stroke on a keyed row
/// shows each tile it changes through the keys, and asking each key of
/// each pixel took 1.1–3.4 ms over one 256 px tile of a keyed sheet here
/// (AOT, 10-16), and these tables walked in C take 0.13 ms, the copy into
/// the engine's buffer and all — the C pool pre-blends a whole 1800 px
/// brush's tiles in ~21 ms (`ActiveStrokeOverlayModel`).
///
/// [originals] is the run's input, whose alphas a restore gives back to
/// ([CelColorKey.alphaFor]) — [view] itself in the first call.
Uint8List? _walk(
  Uint8List view,
  Uint8List originals,
  KeyRgbaTables tables,
  Uint8List Function() into,
) {
  final engine = QaNativeEngine.instance;
  if (engine != null) {
    final keyed = engine.keyRgba(view, originals, tables);
    return keyed == null ? null : (into()..setAll(0, keyed));
  }
  final (:red, :green, :blue, :restores, alphaMaps: maps) = tables;
  Uint8List? out;
  final length = view.length;
  for (var offset = 0; offset < length; offset += 4) {
    final original = originals[offset + 3];
    if (original == 0) {
      continue;
    }
    final alpha = view[offset + 3];
    var naming =
        red[view[offset]] & green[view[offset + 1]] & blue[view[offset + 2]];
    var restoring = restores;
    var next = alpha;
    for (var map = 0; naming != 0; map += 256) {
      if (naming & 1 == 1) {
        next = restoring & 1 == 1
            ? original - maps[map + original - next]
            : maps[map + next];
      }
      naming >>= 1;
      restoring >>= 1;
    }
    if (next == alpha) {
      continue;
    }
    out ??= into();
    out[offset + 3] = next;
  }
  return out;
}

/// Up to [keyRgbaKeysAtOnce] colour keys as the walk reads them, here and
/// in C ([KeyRgbaTables]).
///
/// ⛔MADE FROM THE KEYS' OWN ANSWERS, never a second spelling of them: a
/// channel's bit is [CelColorKey.matches] asked with the other two channels
/// at the key's own values, and an alpha's is [CelColorKey._erased] — so the
/// walk, in either language, cannot drift from the definition the
/// destructive verb and the shader are held to.
///
/// ⛔No key here erases what its colour does not name: that is the button
/// 색 유지's alone ([CelKeyOperation.eraseOthers]), which edits bytes
/// through its own kernel and never walks a chain.
KeyRgbaTables _keyTables(List<CelColorKey> keys) {
  assert(keys.length <= keyRgbaKeysAtOnce);
  assert(keys.every((key) => key.operation != CelKeyOperation.eraseOthers));
  final red = Uint32List(256);
  final green = Uint32List(256);
  final blue = Uint32List(256);
  final alphaMaps = Uint8List(keys.length * 256);
  for (final (k, key) in keys.indexed) {
    final bit = 1 << k;
    for (var value = 0; value < 256; value += 1) {
      if (key.matches(value, key.green, key.blue)) {
        red[value] |= bit;
      }
      if (key.matches(key.red, value, key.blue)) {
        green[value] |= bit;
      }
      if (key.matches(key.red, key.green, value)) {
        blue[value] |= bit;
      }
      alphaMaps[k * 256 + value] = key._erased(value);
    }
  }
  return (
    red: red,
    green: green,
    blue: blue,
    restores: keys.indexed.fold(
      0,
      (bits, entry) => entry.$2.operation == CelKeyOperation.restoreMatches
          ? bits | 1 << entry.$1
          : bits,
    ),
    alphaMaps: alphaMaps,
  );
}

/// One keyed tile per source tile — the newest values win, for the reason
/// [_derived] states about a slider being dragged — by the values, as
/// [_derived] keeps its.
final SignedMemo<List<double>, BitmapTile> _keyedTiles = SignedMemo(
  'celSourceEffectTiles',
  same: sameCelSourceEffectSignature,
);

/// The keyed copy this pass made of [tile] and still holds, through whatever
/// keys it was last made with — [tile] itself where the keys changed
/// nothing, null where it was never keyed. A LOOKUP: it keys nothing.
///
/// A copy lives exactly as long as its source, so a picture made for the
/// copy is let go with the source's (undo-held-tile-pictures, stage 2).
BitmapTile? keyedCopyOf(BitmapTile tile) => _keyedTiles.keptOf(tile);

/// Derived render data keyed on the SOURCE surface's identity. Surfaces are
/// immutable, so identity is a stable key and an edited cel is a different
/// object that misses and recomputes — the same contract
/// `BitmapTileImageCache` runs on. The memo lets an entry go when the
/// source surface itself goes.
///
/// ⛔Kept by the VALUES the keys were made from, not a hash — see
/// [CelColorKey.signature].
final SignedMemo<List<double>, BitmapSurface> _derived = SignedMemo(
  'celSourceEffectSurfaces',
  same: sameCelSourceEffectSignature,
);
