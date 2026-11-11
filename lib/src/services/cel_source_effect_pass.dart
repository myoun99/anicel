/// A cel row's colour keys: the kinds computed over a cel's OWN bytes
/// ([EffectKind.runsOnSourcePixels]) — the one definition the fx and the
/// destructive verb share ([CelColorKey]), the tables the engine keys by
/// ([keyRgbaTablesOf]), and the leading run a float or a text over the row
/// asks after ([celSourceKeys]).
///
/// 🚨WHY THERE WAS A CPU HALF AT ALL. Every other kind folds into a
/// `ui.ColorFilter.matrix` or a `ui.ImageFilter`, which is linear-plus-clamp
/// and therefore cannot express "is this pixel within N of that color". The
/// two ways to express it were a fragment shader or this; 유저 2026-08-27
/// chose this, and named the follow-up rule with it: *「거기가 아프면
/// 셰이더가 답이 아니고 cpu에서 더 개선하는 방향을 찾아야지」*. The
/// engine's key run is neither: it walks these very tables over a row's
/// stored bytes, the same answer to the byte. ↩️Every route's cels were
/// keyed here until the engine keyed a row (float-warp-resamples-in-the-c-
/// engine (1), 2026-11-11), and a plugin's input after them until (2).
///
/// ⛔A KEY'S RESULT IS NEVER STORED. It is a composite-time filter like the
/// others — the truth is the parameters, and the engine keys a row's
/// stored bytes each time it lays it. Baking it would make it a projection
/// instead, which is a different pattern with different rules.
library;

import 'dart:typed_data';

import 'package:collection/collection.dart' show ListExtensions;

import '../models/layer_effect.dart';

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
  /// engine's alpha table ([_keyTables]).
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

/// The LEADING run of colour keys in [effects] — the keys that still see
/// the cel's own bytes: what a float or a text over the row asks after,
/// whether the landing it shows is keyed. The chain is the paint's, keys
/// and all: the engine keys a row's stored bytes with what a hand holds
/// over them (`KeyRun`, a row's `keys`), and a plugin anywhere in it runs
/// over the picture the chain made before it (`PluginEffect`).
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
/// now, so the run follows the order instead of the order following the
/// run.
///
/// ↩️A PLUGIN RIGHT AFTER THEM RAN HERE, ON THE CPU, over the keyed cel
/// (I-132-Q32 b, 유저 2026-10-30: 「b 로 첫 판」 — 「셀 행에서 fx 줄 맨 앞(앞에
/// 색상 키만 있어도 됨)일 때 돈다 — 색상 키의 CPU 길과 같은 자리」), and the
/// chain was split there. 「이어서 a」 is float-warp-resamples-in-the-c-
/// engine (2) (관제 2026-11-11): a plugin at the head runs where one
/// anywhere else does (🗣️I-132-Q34 a 「어디에 걸어도 돌고, 결과가 올 때까지
/// 그 프레임의 직전 완성 그림에 머문다」) — one plugin, one road. ↩️Keys alone
/// were the CPU's until (1): a stroke on a keyed row read its tiles back,
/// keyed them and sent them up again, and the pool held a keyed copy beside
/// each tile.
List<ResolvedLayerEffect> celSourceKeys(List<ResolvedLayerEffect> effects) {
  var leading = 0;
  while (leading < effects.length &&
      effects[leading].kind.runsOnSourcePixels) {
    leading += 1;
  }
  return leading == effects.length ? effects : effects.sublist(0, leading);
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

/// Up to [keyRgbaKeysAtOnce] colour keys as the engine's key run reads them
/// (`kernels/effects/key.wgsl`) — a table lookup a channel where the keys
/// asked a question a key: bit k of `red[r]`, `green[g]` and `blue[b]` says
/// key k is within its tolerance of a pixel in that channel, bit k of
/// `restores` that key k gives back what its run erased of what it names
/// instead of erasing it, and `alphaMaps[k * 256 + a]` is what key k leaves
/// of an alpha `a` it erases ([keyRgbaTablesOf] makes them).
typedef KeyRgbaTables = ({
  Uint32List red,
  Uint32List green,
  Uint32List blue,
  int restores,
  Uint8List alphaMaps,
});

/// The keys one set of [KeyRgbaTables] holds: a bit each in a 32-bit word.
const int keyRgbaKeysAtOnce = 32;

/// [keys] as the tables a run of them is walked by, [keyRgbaKeysAtOnce]
/// keys a set in the chain's order — each set over what the one before it
/// left, a restore in any giving back to the run's input: the engine's key
/// run (composite_tree_plan.dart) and the destructive verb's selector
/// (`cel_pixel_overwrite.dart`).
List<KeyRgbaTables> keyRgbaTablesOf(List<CelColorKey> keys) => [
  for (final set in keys.slices(keyRgbaKeysAtOnce)) _keyTables(set),
];

/// Up to [keyRgbaKeysAtOnce] colour keys as the engine reads them
/// ([KeyRgbaTables]).
///
/// ⛔MADE FROM THE KEYS' OWN ANSWERS, never a second spelling of them: a
/// channel's bit is [CelColorKey.matches] asked with the other two channels
/// at the key's own values, and an alpha's is [CelColorKey._erased] — so the
/// engine's run cannot drift from the definition the destructive verb and
/// the shader are held to.
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
