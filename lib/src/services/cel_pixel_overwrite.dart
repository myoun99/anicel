import 'dart:typed_data';

import '../core/argb_channels.dart';
import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/bitmap_tile_rewrite.dart';
import '../models/tile_coord.dart';
import '../native/qa_native_engine.dart';
import 'cel_source_effect_pass.dart';

/// The four PIXEL VERBS the timeline's 색 편집 popover runs.
///
/// 🚨THE VERB IS ITS OWN FIELD, not the channel. It used to be:
/// `runPixelVerb(CelPixelChannel)`, where `.colour` meant 색 변환 and
/// `.alpha` meant 픽셀 삭제. That worked while there were two verbs and
/// broke the moment there were four — 색 삭제 and 픽셀 삭제 are both alpha
/// writes and differ only in WHICH pixels they take. One flag answering two
/// questions is the shape this project keeps finding bugs in.
enum CelPixelVerb {
  /// Replace RGB with the current colour, keep alpha.
  replaceColour(CelPixelChannel.colour),

  /// Empty the drawing: alpha to 0 everywhere the region covers.
  clearPixels(CelPixelChannel.alpha),

  /// Empty only the pixels that ARE the current colour.
  deleteColour(CelPixelChannel.alpha),

  /// Empty every pixel that is NOT the current colour.
  keepColour(CelPixelChannel.alpha);

  const CelPixelVerb(this.channel);

  final CelPixelChannel channel;

  /// Whether this verb picks its pixels by colour.
  bool get selectsByColour =>
      this == CelPixelVerb.deleteColour || this == CelPixelVerb.keepColour;

  /// The selector for [argb], or null for the verbs that take everything.
  ///
  /// ★THE SAME [CelColorKey] THE FX USES, on purpose. 유저 I-8 asked for one
  /// operation in two places — a button and an effect — and this is the
  /// single definition of "which pixels does that colour name", so the two
  /// cannot drift into two answers.
  ///
  /// ⛔TOLERANCE 0, and that is the button's whole design. 유저 2026-08-27
  /// (I-8-Q2): 「허용차 같은 고급설정은 fx의 색 제거 이펙트에서 하라하고
  /// 여기서는 간편하게만 하고싶음. 그러니 허용차 설정 없애고 색이 같을때만
  /// 삭제하면 필요없을거같은데」. A tolerance knob beside the button would be
  /// the same number in two places.
  CelColorKey? selectorFor(int argb) {
    if (!selectsByColour) {
      return null;
    }
    return CelColorKey(
      red: argbRed(argb),
      green: argbGreen(argb),
      blue: argbBlue(argb),
      tolerance: 0,
      amount: 1,
      keepsMatches: this == CelPixelVerb.keepColour,
    );
  }
}

/// The kernel behind the two PIXEL verbs — 색 변환 (replace the drawing's
/// colour, keeping its alpha) and 픽셀 비우기 (empty the drawing, keeping
/// its shape's bytes) — and the RECIPE that undoes either one.
///
/// The two verbs are one operation with the channel swapped:
///
/// | verb    | overwrites | preserves | undo needs       |
/// |---------|------------|-----------|------------------|
/// | 색 변환 | R,G,B      | A         | the original RGB |
/// | 비우기  | A          | R,G,B     | the original A   |
///
/// ⛔UNDO IS A RECIPE, NEVER A SURFACE SNAPSHOT. The obvious undo — keep
/// the pre-edit [BitmapSurface] the way `BrushStrokeHistoryCommand` does —
/// is TILE-granular: one changed pixel makes a whole 256x256x4 = 256 KB
/// tile a new object, so a recolour across a selection of cels retains
/// tens of megabytes and pushes the rest of the session's history off the
/// byte budget. A recipe is pixel-granular and, in the overwhelmingly
/// common case, THREE BYTES:
///
/// - the drawing under the region was one flat colour (every line art cel,
///   and ALWAYS true from the second recolour onward, since the first one
///   made it flat) -> [UniformCelPixelRestore], one value;
/// - it repeated in stretches, which is what a drawing does along a row
///   -> [RunLengthCelPixelRestore], one value per run;
/// - it was a handful of colours, interleaved -> [PalettedCelPixelRestore],
///   one index byte per touched pixel;
/// - it was noise -> [RawCelPixelRestore], the channels themselves.
///
/// ⚠️THESE ARE NOT TRIED IN ORDER — the smallest is kept. A fixed order was
/// a guess (that anything a palette can index is best said by indices), and
/// the guess is wrong wherever the values repeat, which is most drawings.
/// [_RestoreBuilder.build] measures all of them against one ruler.
///
/// Redo needs nothing at all: the forward pass is deterministic, so it
/// simply runs again.
enum CelPixelChannel {
  /// R, G and B are overwritten; alpha is left exactly as it was.
  colour,

  /// Alpha is overwritten; R, G and B are left exactly as they were.
  ///
  /// The colour bytes stay under a zeroed alpha on purpose. They are
  /// invisible either way, and leaving them alone means the undo recipe
  /// carries ONE channel instead of four.
  alpha;

  /// How many bytes of one pixel this channel names.
  ///
  /// 🚨★★★**A SWITCH, NOT `== colour ? … : …`, AND THAT IS THE WHOLE
  /// POINT.** Every one of this enum's questions used to be a ternary, so
  /// a THIRD channel would have compiled in silence and answered every one
  /// of them as if it were [alpha] — one byte wide, at offset 3, taking
  /// every masked pixel. Nothing would have gone red; the pass would just
  /// have written the wrong byte. An exhaustive switch turns that into a
  /// compile error at each site, which is the only place it can be caught.
  ///
  /// ⚠️[CelPixelVerb] was already written this way (`switch (verb)` in
  /// `CelPixelOverwriteCommand.forVerb`) — this enum was the one that had
  /// not caught up.
  int get byteCount => switch (this) {
    CelPixelChannel.colour => 3,
    CelPixelChannel.alpha => 1,
  };

  /// The offset of channel byte [index] within a pixel's RGBA quad.
  int byteOffset(int index) => switch (this) {
    CelPixelChannel.colour => index,
    CelPixelChannel.alpha => 3,
  };

  /// Whether a pixel with NO ink still takes part — the reason is the one
  /// [celPixelParticipates] gives: an alpha write destroys the question
  /// "was there ink here", so undo could not tell an already-empty pixel
  /// from one this pass emptied.
  ///
  /// ⛔ONE ANSWER FOR TWO LANGUAGES (ABI 34). The C pass stages this as a
  /// flag rather than re-deriving it from the channel, so the rule lives
  /// here and only here — an exhaustive switch, like the two above, so a
  /// third channel has to state its answer.
  bool get takesEmptyPixels => switch (this) {
    CelPixelChannel.colour => false,
    CelPixelChannel.alpha => true,
  };
}

/// Whether a pixel takes part, given its CURRENT alpha and its mask
/// coverage.
///
/// 🚨The two channels answer differently, and the reason is whether undo
/// can ask the question again:
///
/// - [CelPixelChannel.colour] leaves alpha untouched, so "was there ink
///   here?" reads the same before and after. Fully transparent pixels are
///   therefore skipped — an invisible pixel needs no new colour, and
///   skipping it is what makes a line art recipe cover only the ink.
/// - [CelPixelChannel.alpha] destroys that very question. Undo would have
///   no way to tell a pixel that was already empty from one it emptied, so
///   every masked pixel takes part and the recipe records the zeroes too.
bool celPixelParticipates({
  required CelPixelChannel channel,
  required int alpha,
  required int maskValue,
  CelColorKey? selector,
  int red = 0,
  int green = 0,
  int blue = 0,
}) {
  if (maskValue == 0) {
    return false;
  }
  if (selector != null) {
    // 🚨A SELECTOR NARROWS THE ALPHA VERB, AND UNDO SURVIVES IT — which is
    // the only reason it is allowed to.
    //
    // The paragraph above says a plain alpha pass must take EVERY masked
    // pixel, because writing alpha destroys the question "was there ink
    // here" and undo could not tell an already-empty pixel from one this
    // pass emptied. A colour selector reads R, G and B — and an alpha write
    // leaves those exactly as they were — so the undo pass re-asks the same
    // question of the same bytes and gets the same answer. The recipe's
    // positional walk therefore lines up pixel for pixel.
    //
    // ⛔THE SELECTOR MUST NOT READ ALPHA — [CelColorKey.erases] takes none,
    // and that is enforced by its signature rather than by remembering.
    // Even an "already empty, skip it" shortcut would make the undo walk
    // shorter than the forward one, and a positional recipe would then land
    // on the wrong pixels. A test caught exactly that.
    return selector.erases(red, green, blue);
  }
  // ⚠️The rule is [CelPixelChannel.takesEmptyPixels] — an exhaustive switch
  // on the enum, so a new channel must STATE its participation rule rather
  // than inheriting alpha's by falling off the end of a boolean. It lives
  // there rather than here because the C pass stages the same answer.
  return channel.takesEmptyPixels || alpha > 0;
}

/// What one cel needs in order to be put back exactly as it was.
///
/// Every variant restores the SAME pixels the forward pass touched, in the
/// same walk order, so the region and the channel are all the addressing
/// information any of them needs — no per-pixel coordinates are stored.
sealed class CelPixelRestore {
  const CelPixelRestore();

  /// Bytes this recipe holds, for the history manager's byte budget.
  int get estimatedRetainedBytes;

  /// How many pixels the pass touched — the length of the walk this recipe
  /// replays.
  ///
  /// ⚠️It was never asked before ABI 34, because every reader walked the
  /// recipe in lockstep with the pass and `readInto` never needed the end.
  /// The native undo expands the recipe to one entry per touched pixel
  /// BEFORE the pass runs, so it has to know how many there are — and a
  /// uniform recipe, which is one value, could not say.
  int get touchedPixelCount;

  /// Writes the original channel bytes of the [index]-th touched pixel
  /// into [into] (which is [CelPixelChannel.byteCount] long).
  void readInto(Uint8List into, int index);

  /// Every touched pixel's original bytes, end to end in walk order —
  /// [touchedPixelCount] entries of [byteCount].
  ///
  /// The native undo reads its recipe from inside C, which cannot call
  /// [readInto], so the recipe is laid flat once before the pass runs.
  /// ⛔Written in terms of [readInto] rather than once per shape: each shape
  /// already says "the i-th value" in one place, and a bulk form beside it
  /// would be a second answer to the same question.
  Uint8List expand(int byteCount) {
    final flat = Uint8List(touchedPixelCount * byteCount);
    final one = Uint8List(byteCount);
    for (var index = 0; index < touchedPixelCount; index += 1) {
      readInto(one, index);
      final at = index * byteCount;
      for (var byte = 0; byte < byteCount; byte += 1) {
        flat[at + byte] = one[byte];
      }
    }
    return flat;
  }

  /// How the C pass reads this recipe: [bytes], the entry for touched pixel
  /// `i` at `i * step`.
  ///
  /// Laid flat ([expand]) unless a shape can say it more cheaply — and the
  /// cheap answers are the COMMON ones: a uniform recipe is its one value
  /// stepped 0, a raw one is the buffer it already is, and runs are laid out
  /// a run at a time.
  ({Uint8List bytes, int step}) streamFor(int byteCount) =>
      (bytes: expand(byteCount), step: byteCount);
}

/// Copies [count] bytes from [from] at [base] into the front of [into] —
/// what every [CelPixelRestore.readInto] does, written once.
///
/// ⛔**NOT `into.setRange(…)`, AND THE REASON IS MEASURED.** A recipe is
/// read ONCE PER TOUCHED PIXEL — 2.2 million times on a 1920x1080 undo —
/// and `setRange`'s fixed per-call cost dwarfs the one to three bytes it
/// moves.
///
/// 🧪`cel_pixel_pass_benchmark_test.dart`, whole-picture undo on 128px
/// tiles. ⚠️THE UNIT IS A RATIO, NOT MILLISECONDS: this machine runs other
/// lanes' gates, and the same code measured 23 and 39 ns/px an hour apart.
/// The FORWARD pass never calls this function, so `undo / forward` inside
/// ONE run is the load-free instrument. Median of 3-4 runs per arm:
///
/// | recipe read            | `setRange` | this loop |
/// |------------------------|-----------:|----------:|
/// | alpha, 1 byte          |      1.152 | **0.856** |
/// | colour, 3 bytes        |      0.934 | **0.866** |
/// | raw, 3 bytes at offset |      0.437 | **0.313** |
///
/// The arms do not overlap on any of the three.
///
/// 🚨The tell was the ASYMMETRY, not any absolute number: the alpha undo
/// cost MORE than its own forward pass — same walk, same write,
/// `_RestoreBuilder.add` instead of this — while moving a third of the
/// bytes a colour pass moves. A cost that does not shrink with the byte
/// count is a per-CALL cost.
void copyRestoreBytes(Uint8List into, Uint8List from, int base, int count) {
  for (var byte = 0; byte < count; byte += 1) {
    into[byte] = from[base + byte];
  }
}

/// Writes [count] copies of [value] end to end into [into] from [at],
/// doubling the copied span each step — a run costs log(count) copies, not
/// [count]. (The per-call cost [copyRestoreBytes] avoids is paid here once
/// per doubling, over spans that grow to the whole run.)
void _fillRepeated(Uint8List into, int at, Uint8List value, int count) {
  final span = count * value.length;
  if (span == 0) {
    return;
  }
  into.setRange(at, at + value.length, value);
  var filled = value.length;
  while (filled < span) {
    final chunk = filled <= span - filled ? filled : span - filled;
    into.setRange(at + filled, at + filled + chunk, into, at);
    filled += chunk;
  }
}

/// [count] copies of [value], end to end.
Uint8List _repeatedRun(Uint8List value, int count) {
  final out = Uint8List(count * value.length);
  _fillRepeated(out, 0, value, count);
  return out;
}

/// Every touched pixel held the SAME value — so the value alone is the
/// whole recipe.
///
/// This is the case that matters. Line art is flat black; a recolour makes
/// the region flat by definition, so every recolour after the first one
/// lands here no matter what the drawing started as.
final class UniformCelPixelRestore extends CelPixelRestore {
  const UniformCelPixelRestore(this.value, {required this.touchedPixelCount});

  /// The channel bytes, in channel order (3 for colour, 1 for alpha).
  final Uint8List value;

  /// ⚠️STORED, because a uniform recipe is ONE value and says nothing about
  /// how many pixels it stands for — see [CelPixelRestore.touchedPixelCount].
  @override
  final int touchedPixelCount;

  @override
  int get estimatedRetainedBytes => value.length;

  @override
  void readInto(Uint8List into, int index) {
    copyRestoreBytes(into, value, 0, value.length);
  }

  /// One value, stepped 0: the recipe that matters most is never laid out.
  @override
  ({Uint8List bytes, int step}) streamFor(int byteCount) =>
      (bytes: value, step: 0);
}

/// The region held few enough distinct values to name each by an index.
///
/// Cel painting is a palette medium — a drawing carries line, shadow and
/// highlight colours, not a continuum — so anything that is not flat
/// almost always lands here, at one byte per touched pixel instead of
/// three.
final class PalettedCelPixelRestore extends CelPixelRestore {
  const PalettedCelPixelRestore({required this.palette, required this.indices});

  /// Distinct values, packed end to end in channel order.
  final Uint8List palette;

  /// One palette index per touched pixel, in walk order.
  final Uint8List indices;

  @override
  int get estimatedRetainedBytes => palette.length + indices.length;

  @override
  int get touchedPixelCount => indices.length;

  @override
  void readInto(Uint8List into, int index) {
    final base = indices[index] * into.length;
    copyRestoreBytes(into, palette, base, into.length);
  }
}

/// The values REPEAT along the walk — so the recipe names each run once.
///
/// 🚨THE TIER THE OTHER THREE COULD NOT REACH, and the drawings that need
/// it are the ordinary ones. A palette index is one byte PER PIXEL however
/// few colours there are, and [RawCelPixelRestore] is the whole channel
/// per pixel — so a pass over a shaded cel with a couple of hundred
/// colours in it paid megabytes to say the same value over and over. A
/// drawing is not noise: line, fill and paper arrive in long stretches
/// along a row, which is exactly what a run says cheaply.
///
/// ⚠️It does not replace the palette. Runs lose to indices the moment the
/// values INTERLEAVE — a dither or a photograph makes every run one pixel
/// long, and then a run costs more than the value it stands for. That is
/// why [_RestoreBuilder] measures all of them and keeps the smallest
/// rather than trying them in a fixed order.
final class RunLengthCelPixelRestore extends CelPixelRestore {
  RunLengthCelPixelRestore({required this.values, required this.lengths})
    : assert(
        lengths.isNotEmpty,
        'a run-length recipe with no runs restores nothing.',
      );

  /// One value per run, packed end to end in channel order.
  final Uint8List values;

  /// How many touched pixels each run covers, in walk order.
  final Uint32List lengths;

  @override
  int get estimatedRetainedBytes => values.length + lengths.lengthInBytes;

  @override
  late final int touchedPixelCount = lengths.fold<int>(
    0,
    (sum, run) => sum + run,
  );

  /// Where the cursor stands: [_run] is the run holding pixel [_runStart].
  ///
  /// ⚠️A CURSOR, because every caller walks forward. [overwriteCelPixels]
  /// reads index 0, 1, 2 … in one pass, so the cursor advances one step per
  /// pixel and the whole read is linear. A caller that jumps BACKWARD (a
  /// second undo pass starting over) resets and re-walks — correct at any
  /// order, fast at the only order anyone uses.
  int _run = 0;
  int _runStart = 0;

  @override
  void readInto(Uint8List into, int index) {
    if (index < _runStart) {
      _run = 0;
      _runStart = 0;
    }
    while (_runStart + lengths[_run] <= index) {
      _runStart += lengths[_run];
      _run += 1;
    }
    copyRestoreBytes(into, values, _run * into.length, into.length);
  }

  /// A run at a time rather than a pixel at a time — [readInto]'s cursor
  /// walk, in bulk. ⚠️Real drawings land HERE (runs beat a palette wherever
  /// values repeat along a row), so laying this one out per pixel would leave
  /// their undo paying the Dart loop the C pass exists to remove.
  @override
  ({Uint8List bytes, int step}) streamFor(int byteCount) {
    final flat = Uint8List(touchedPixelCount * byteCount);
    var at = 0;
    for (var run = 0; run < lengths.length; run += 1) {
      final from = run * byteCount;
      _fillRepeated(
        flat,
        at,
        Uint8List.sublistView(values, from, from + byteCount),
        lengths[run],
      );
      at += lengths[run] * byteCount;
    }
    return (bytes: flat, step: byteCount);
  }
}

/// More distinct values than a palette can index — the channels are kept
/// as they were, one pixel after another in walk order.
final class RawCelPixelRestore extends CelPixelRestore {
  const RawCelPixelRestore(this.values, {required this.touchedPixelCount});

  /// Channel bytes for every touched pixel, in walk order.
  final Uint8List values;

  /// ⚠️STORED: [values] is `touchedPixelCount * byteCount` long, and this
  /// recipe never learns the byte count — [readInto] is handed it.
  @override
  final int touchedPixelCount;

  @override
  int get estimatedRetainedBytes => values.length;

  @override
  void readInto(Uint8List into, int index) {
    copyRestoreBytes(into, values, index * into.length, into.length);
  }

  @override
  ({Uint8List bytes, int step}) streamFor(int byteCount) =>
      (bytes: values, step: byteCount);
}

/// The largest palette [PalettedCelPixelRestore] may build. Beyond this an
/// index byte costs as much as the value it stands for.
const int _maxPaletteEntries = 256;

/// What one run's LENGTH costs, beside its value.
///
/// ⚠️Four, and it has to be four: a run is counted across the whole walk,
/// not within a tile, so a flat cel is one run of several million. A
/// 16-bit length would have to split those, which is a rule that buys
/// nothing — the split runs would each carry their value again.
const int _runLengthBytes = 4;

/// Collects the original values of the pixels a pass touches and decides,
/// at the end, which recipe shape says them most cheaply.
///
/// The four shapes are not guesses about the drawing — they are measured
/// while the forward pass walks the pixels it has to walk anyway, so
/// choosing between them costs one map lookup per pixel and no second
/// pass.
class _RestoreBuilder {
  _RestoreBuilder(this.byteCount);

  final int byteCount;

  /// 🚨THE UNIFORM PASS COSTS ONE COMPARISON PER PIXEL, and it is the case
  /// that actually happens.
  ///
  /// 유저 2026-08-27: 「타일 바뀌는게 실시간으로 보이는데 … 그냥 그렇게
  /// 가볍게하면 되는거아닌가?」. 🧪Measured on 1920×1080 flat line art:
  /// **371ms**, of which the pixel writing was **51ms** — 86% went into
  /// remembering. And what it remembered was `UniformCelPixelRestore`, THREE
  /// BYTES. The old code paid `Uint8List.fromList` per pixel unconditionally
  /// — 2.6 million allocations to discover that every value was the same one.
  ///
  /// So the builder stays optimistic: hold the first value, count, compare.
  /// The palette and raw structures are not even allocated until a SECOND
  /// distinct value turns up, and then the pixels skipped so far are filled
  /// in as copies of the first — the same bytes the old path would have
  /// built, arrived at without paying for them in the case that never needs
  /// them.
  ///
  /// 🚨★★★**AND THE PARAGRAPH ABOVE WAS ONLY HALF TRUE UNTIL 2026-09-09.**
  /// It reads as if the per-pixel allocation was gone. It was gone from the
  /// UNIFORM path only — every structure below was a `BytesBuilder(copy:
  /// false)`, which keeps the reference it is handed, so each of them had to
  /// be fed a fresh `Uint8List.fromList` per pixel. The forward pass reuses
  /// ONE scratch buffer, so that copy was not tidiness, it was required.
  ///
  /// And a second distinct value is not the rare case — it is the anti-
  /// aliased edge of any line the user drew. 🧪Measured, recolouring
  /// anti-aliased line art at 1920×1080 (2.1 Mpx): **280ms before, 118ms
  /// after**, with a byte-identical recipe (114,247 B both ways). The
  /// builders copy now, so the scratch buffer is handed over directly.
  ///
  /// ⛔**DO NOT PUT `copy: false` BACK.** With it, every entry aliases the
  /// one scratch buffer and the recipe records the LAST value repeated —
  /// three tests in `cel_pixel_overwrite_test` go red, which is how this
  /// comment came to be written rather than guessed at.
  Uint8List? _first;
  bool _uniform = true;

  BytesBuilder? _raw;
  late List<int> _indices;
  late Map<int, int> _paletteIndexByKey;
  late BytesBuilder _palette;

  /// Cleared once the palette overflows — the indices built so far are
  /// dropped and [_raw], which was being filled all along, becomes the
  /// answer.
  bool _paletteOpen = true;
  int _count = 0;

  /// The runs, filled from the moment a second distinct value arrives.
  /// ⚠️Never cleared: unlike the palette these cannot overflow — a run per
  /// pixel is simply a bad answer, and [build] then picks a better one.
  final BytesBuilder _runValues = BytesBuilder();
  final List<int> _runLengths = [];
  int _lastRunKey = -1;

  /// Adds [length] touched pixels whose channel bytes are all the
  /// [byteCount] bytes of [from] at [at] — ONE pixel from the Dart pass, a
  /// whole RUN from the C one.
  ///
  /// 🚨Runs are why the C pass pays off. Fed one pixel at a time, this
  /// method cost as much as the pixel loop C took over; fed a run, a flat
  /// cel costs one call per tile.
  void addRun(Uint8List from, int at, int length) {
    _count += length;
    if (_uniform) {
      final first = _first;
      if (first == null) {
        _first = Uint8List.fromList(
          Uint8List.sublistView(from, at, at + byteCount),
        );
        return;
      }
      var same = true;
      for (var byte = 0; byte < byteCount; byte += 1) {
        if (first[byte] != from[at + byte]) {
          same = false;
          break;
        }
      }
      if (same) {
        return;
      }
      _uniform = false;
      _openStructures(first, _count - length);
    }
    _addRunToStructures(Uint8List.sublistView(from, at, at + byteCount), length);
  }

  /// A second distinct value arrived: build what the uniform run would have
  /// built, then carry on the slow way.
  void _openStructures(Uint8List first, int skipped) {
    final raw = BytesBuilder();
    final palette = BytesBuilder();
    // In bulk: the uniform stretch can be millions of pixels long, and one
    // `add` per pixel is the very cost the optimistic path exists to avoid.
    raw.add(_repeatedRun(first, skipped));
    palette.add(first);
    var key = 0;
    for (var byte = 0; byte < byteCount; byte += 1) {
      key = (key << 8) | first[byte];
    }
    _raw = raw;
    _indices = List<int>.filled(skipped, 0, growable: true);
    _palette = palette;
    _paletteIndexByKey = {key: 0};
    // The uniform stretch that just ended IS the first run, however long it
    // was — the optimistic path never had to remember it pixel by pixel.
    _runValues.add(first);
    _runLengths.add(skipped);
    _lastRunKey = key;
  }

  /// [length] more pixels on the current run, or the start of the next one.
  void _extendRun(int key, Uint8List value, int length) {
    if (key == _lastRunKey) {
      _runLengths[_runLengths.length - 1] += length;
      return;
    }
    _lastRunKey = key;
    _runValues.add(value);
    _runLengths.add(length);
  }

  void _addRunToStructures(Uint8List value, int length) {
    _raw!.add(length == 1 ? value : _repeatedRun(value, length));
    var key = 0;
    for (var byte = 0; byte < byteCount; byte += 1) {
      key = (key << 8) | value[byte];
    }
    // ⚠️BEFORE the palette's early return: runs are measured even after the
    // palette has overflowed, and that is the whole point — a drawing with
    // more than 256 colours is exactly the drawing the old ladder had to
    // answer with four bytes a pixel.
    _extendRun(key, value, length);
    if (!_paletteOpen) {
      return;
    }
    final byKey = _paletteIndexByKey;
    var index = byKey[key];
    if (index == null) {
      if (byKey.length == _maxPaletteEntries) {
        _paletteOpen = false;
        _indices.clear();
        byKey.clear();
        return;
      }
      index = byKey.length;
      byKey[key] = index;
      _palette.add(value);
    }
    if (length == 1) {
      _indices.add(index);
    } else {
      _indices.addAll(List<int>.filled(length, index));
    }
  }

  /// Null when the pass touched nothing.
  ///
  /// 🚨★★★**THE SMALLEST WINS — it is not a ladder any more.** It used to
  /// be an ordered fallback (uniform, else paletted, else raw), and that
  /// order encoded a guess: that anything a palette can index is best said
  /// by indices. The guess is wrong wherever the values REPEAT, which is
  /// most drawings — a palette index is one byte per pixel however few
  /// colours there are. Every shape is measured against the same ruler now
  /// ([CelPixelRestore.estimatedRetainedBytes]) and the cheapest is kept.
  ///
  /// ⚠️Measured from the BUILDERS' lengths, not by building all of them: a
  /// whole-cel pass's raw buffer is megabytes, and materializing it only to
  /// find it lost would be the expensive half of the work.
  CelPixelRestore? build() {
    if (_count == 0) {
      return null;
    }
    if (_uniform) {
      return UniformCelPixelRestore(_first!, touchedPixelCount: _count);
    }
    if (_paletteOpen && _paletteIndexByKey.length == 1) {
      return UniformCelPixelRestore(
        _palette.toBytes(),
        touchedPixelCount: _count,
      );
    }
    final runBytes = _runLengths.length * (byteCount + _runLengthBytes);
    final paletteBytes = _paletteOpen
        ? _palette.length + _indices.length
        : null;
    final rawBytes = _raw!.length;
    if (runBytes <= rawBytes && (paletteBytes == null || runBytes <= paletteBytes)) {
      return RunLengthCelPixelRestore(
        values: _runValues.toBytes(),
        lengths: Uint32List.fromList(_runLengths),
      );
    }
    if (paletteBytes != null && paletteBytes <= rawBytes) {
      return PalettedCelPixelRestore(
        palette: _palette.toBytes(),
        indices: Uint8List.fromList(_indices),
      );
    }
    return RawCelPixelRestore(_raw!.toBytes(), touchedPixelCount: _count);
  }
}

/// The tiles one pass covers, each with the coverage over it.
///
/// A `null` mask means the whole tile is covered — the "범위는 전체" case,
/// which is the default gesture and would otherwise pay for a 64 KB buffer
/// of 255s per tile. Otherwise the mask is one byte per tile pixel, in the
/// tile's own row-major order.
///
/// ⛔TILE-GRANULAR ON PURPOSE, not pixel-granular. A whole-canvas pass over
/// a shipping cel visits ~4 million pixels; handing those over one callback
/// at a time spends more time on the calls than on the pixels. The walk
/// names tiles, the kernel loops inside them.
///
/// TILE-MAJOR, and the walk ORDER is a contract: a recipe stores values
/// positionally, so the undo pass must visit the same tiles in the same
/// sequence. Walking tiles (rather than destination rows) is also what keeps
/// the pass off the per-pixel [TileCoord] allocation and map lookup that
/// made whole-picture lifts quadratic — the lesson
/// `gatherMaskedSurfacePixels` records at length.
typedef CelPixelWalk =
    void Function(void Function(TileCoord coord, Uint8List? mask) visit);

/// Applies [channel] over [surface] wherever [walk] reaches, writing
/// [value] (blended by mask coverage) and returning the new surface
/// together with the recipe that undoes it.
///
/// [value] holds the channel's bytes: three for colour, one for alpha.
/// Passing a [restore] instead replays an earlier pass's original values —
/// that is the undo, and it runs through this very function so the two
/// directions cannot drift apart.
({BitmapSurface surface, CelPixelRestore? restore}) overwriteCelPixels({
  required BitmapSurface surface,
  required CelPixelChannel channel,
  required CelPixelWalk walk,
  Uint8List? value,
  CelPixelRestore? restore,
  CelColorKey? selector,
}) {
  assert(
    (value == null) != (restore == null),
    'overwriteCelPixels writes either a flat value (forward) or a recipe '
    '(undo) — never both, never neither.',
  );
  assert(
    value == null || value.length == channel.byteCount,
    'value must carry exactly the channel bytes.',
  );
  final builder = value == null ? null : _RestoreBuilder(channel.byteCount);
  final pass = (
    channel: channel,
    tileSize: surface.tileSize,
    value: value,
    restore: restore,
    selector: selector,
    builder: builder,
  );
  final engine = QaNativeEngine.instance;
  final rewrite = engine == null
      ? _dartTileRewrite(pass)
      : _nativeTileRewrite(engine, pass);

  final rebuilt = <TileCoord, BitmapTile>{};
  try {
    walk((coord, mask) {
      // Absent tile: nothing has ever been drawn here, so 색 변환 has no
      // colour to replace and 비우기 has nothing to empty. It stays absent
      // rather than materializing 256 KB of zeroes.
      final tile = surface.tileAt(coord);
      if (tile == null) {
        return;
      }
      final rewritten = rewrite(tile, mask);
      if (rewritten != null) {
        rebuilt[coord] = rewritten;
      }
    });
  } finally {
    engine?.finishCelPixelPass();
  }

  return (
    surface: surface.withRebuiltTiles(rebuilt),
    restore: rebuilt.isEmpty ? null : builder?.build(),
  );
}

/// One tile of the pass: the rewritten tile, or null when nothing in it
/// took part. Each implementation carries its own running walk index — the
/// only addressing a recipe has.
typedef _TileRewrite = BitmapTile? Function(BitmapTile tile, Uint8List? mask);

/// One pass, named once: everything both rewrites read.
typedef _Pass = ({
  CelPixelChannel channel,
  int tileSize,
  Uint8List? value,
  CelPixelRestore? restore,
  CelColorKey? selector,
  _RestoreBuilder? builder,
});

/// The pass in Dart: the reference `cel_pixel_pass_parity_test.dart`
/// compares the C pass against byte for byte, and what runs with no engine.
_TileRewrite _dartTileRewrite(_Pass pass) {
  final (:channel, :tileSize, :value, :restore, :selector, :builder) = pass;
  final byteCount = channel.byteCount;
  final original = Uint8List(byteCount);
  final incoming = Uint8List(byteCount);
  if (value != null) {
    incoming.setAll(0, value);
  }
  final pixelCount = tileSize * tileSize;
  var index = 0;
  return (tile, mask) => rewriteTileLazily(tile, tileSize, (view) {
    Uint8List? out;
    for (var pixel = 0; pixel < pixelCount; pixel += 1) {
      final maskValue = mask == null ? 255 : mask[pixel];
      final offset = pixel * 4;
      if (!celPixelParticipates(
        channel: channel,
        alpha: view[offset + 3],
        maskValue: maskValue,
        selector: selector,
        red: view[offset],
        green: view[offset + 1],
        blue: view[offset + 2],
      )) {
        continue;
      }
      for (var byte = 0; byte < byteCount; byte += 1) {
        original[byte] = view[offset + channel.byteOffset(byte)];
      }
      builder?.addRun(original, 0, 1);
      if (restore != null) {
        // ⛔A recipe shorter than its walk was built over some other
        // surface. The C pass has to refuse it — reading on there reads
        // whatever memory follows the stream — so this one refuses it too,
        // or the two passes would answer one malformed undo differently.
        if (index >= restore.touchedPixelCount) {
          throw StateError(
            'the recipe holds ${restore.touchedPixelCount} pixels and the '
            'walk it replays goes past them',
          );
        }
        restore.readInto(incoming, index);
      }
      index += 1;
      out ??= Uint8List.fromList(view);
      for (var byte = 0; byte < byteCount; byte += 1) {
        out[offset + channel.byteOffset(byte)] =
            // 🚨UNDO WRITES, IT DOES NOT BLEND. The recipe already holds
            // what the pixel was, so putting it back is a plain assignment
            // at every coverage. Running the recipe through the blend
            // instead only converges toward the original and never reaches
            // it — a feathered recolour of flat black came back as
            // [55, 61, 67] rather than [10, 20, 30], and a second undo
            // would have drifted again.
            restore != null || maskValue == 255
            ? incoming[byte]
            // Forward, partial coverage blends the VALUE, so a feathered
            // edge fades between the old colour and the new one while the
            // drawing's own alpha — its shape — is left alone.
            : _blend(original[byte], incoming[byte], maskValue);
      }
    }
    return out;
  });
}

/// The pass in C (ABI 34): `qa_cel_pixel_pass_tile`, one tile per call.
///
/// The participation law, the blend and the lazy copy run in the kernel;
/// the RECIPE stays here. C hands back each tile's originals as RUNS and
/// [_RestoreBuilder] — the one place a recipe's shape is chosen — takes them
/// a run at a time, so the compression is never written twice (the card's
/// fork ②: C speaks the bytes, Dart compresses). An undo hands C the recipe
/// the way [CelPixelRestore.streamFor] lays it out.
_TileRewrite _nativeTileRewrite(QaNativeEngine engine, _Pass pass) {
  final (:channel, :tileSize, :value, :restore, :selector, :builder) = pass;
  final byteCount = channel.byteCount;
  final base = channel.byteOffset(0);
  final stride = byteCount == 1 ? 0 : channel.byteOffset(1) - base;
  assert(() {
    for (var byte = 0; byte < byteCount; byte += 1) {
      if (channel.byteOffset(byte) != base + byte * stride) {
        return false;
      }
    }
    return true;
  }(), 'the C pass addresses channel byte i at base + i * stride');
  final stream = restore?.streamFor(byteCount);
  engine.stageCelPixelPass(
    CelPixelStage(
      byteCount: byteCount,
      byteOffsetBase: base,
      byteOffsetStride: stride,
      takesEmptyPixels: channel.takesEmptyPixels,
      tileSize: tileSize,
      isUndo: restore != null,
      incoming: value ?? stream!.bytes,
      incomingCount: restore?.touchedPixelCount ?? 1,
      incomingStep: stream?.step ?? 0,
      selector: selector == null
          ? null
          : (
              red: selector.red,
              green: selector.green,
              blue: selector.blue,
              tolerance: selector.tolerance,
              keepsMatches: selector.keepsMatches,
            ),
    ),
  );
  var index = 0;
  return (tile, mask) {
    final result = tile.readPixels(
      (pixels, _) => engine.celPixelPassTile(
        inPixels: pixels,
        mask: mask,
        startIndex: index,
        wantRuns: builder != null,
      ),
    );
    index += result.count;
    final values = result.runValues;
    final lengths = result.runLengths;
    if (builder != null && values != null && lengths != null) {
      for (var run = 0; run < lengths.length; run += 1) {
        builder.addRun(values, run * byteCount, lengths[run]);
      }
    }
    final pixels = result.pixels;
    return pixels == null
        ? null
        : BitmapTile.adoptNative(size: tileSize, pixels: pixels);
  };
}

/// `older + (incoming - older) * coverage / 255`, in the integer mul-div-255
/// idiom the lift's soft mask already uses.
int _blend(int older, int incoming, int coverage) {
  final scaled = incoming * coverage + older * (255 - coverage) + 128;
  return (scaled + (scaled >> 8)) >> 8;
}
