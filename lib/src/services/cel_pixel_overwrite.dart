import 'dart:typed_data';

import '../models/bitmap_surface.dart';
import '../models/bitmap_tile.dart';
import '../models/tile_coord.dart';

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
/// - it was a handful of colours -> [PalettedCelPixelRestore], one index
///   byte per touched pixel;
/// - it was a photograph -> [RawCelPixelRestore], the channels themselves.
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
  int get byteCount => this == CelPixelChannel.colour ? 3 : 1;

  /// The offset of channel byte [index] within a pixel's RGBA quad.
  int byteOffset(int index) => this == CelPixelChannel.colour ? index : 3;
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
}) {
  if (maskValue == 0) {
    return false;
  }
  return channel == CelPixelChannel.alpha || alpha > 0;
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

  /// Writes the original channel bytes of the [index]-th touched pixel
  /// into [into] (which is [CelPixelChannel.byteCount] long).
  void readInto(Uint8List into, int index);
}

/// Every touched pixel held the SAME value — so the value alone is the
/// whole recipe.
///
/// This is the case that matters. Line art is flat black; a recolour makes
/// the region flat by definition, so every recolour after the first one
/// lands here no matter what the drawing started as.
final class UniformCelPixelRestore extends CelPixelRestore {
  const UniformCelPixelRestore(this.value);

  /// The channel bytes, in channel order (3 for colour, 1 for alpha).
  final Uint8List value;

  @override
  int get estimatedRetainedBytes => value.length;

  @override
  void readInto(Uint8List into, int index) {
    into.setRange(0, value.length, value);
  }
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
  void readInto(Uint8List into, int index) {
    final base = indices[index] * into.length;
    into.setRange(0, into.length, palette, base);
  }
}

/// More distinct values than a palette can index — the channels are kept
/// as they were, one pixel after another in walk order.
final class RawCelPixelRestore extends CelPixelRestore {
  const RawCelPixelRestore(this.values);

  /// Channel bytes for every touched pixel, in walk order.
  final Uint8List values;

  @override
  int get estimatedRetainedBytes => values.length;

  @override
  void readInto(Uint8List into, int index) {
    into.setRange(0, into.length, values, index * into.length);
  }
}

/// The largest palette [PalettedCelPixelRestore] may build. Beyond this an
/// index byte costs as much as the value it stands for.
const int _maxPaletteEntries = 256;

/// Collects the original values of the pixels a pass touches and decides,
/// at the end, which recipe shape says them most cheaply.
///
/// The three shapes are not guesses about the drawing — they are measured
/// while the forward pass walks the pixels it has to walk anyway, so
/// choosing between them costs one map lookup per pixel and no second
/// pass.
class _RestoreBuilder {
  _RestoreBuilder(this.byteCount);

  final int byteCount;

  final BytesBuilder _raw = BytesBuilder(copy: false);
  final List<int> _indices = <int>[];
  final Map<int, int> _paletteIndexByKey = <int, int>{};
  final BytesBuilder _palette = BytesBuilder(copy: false);

  /// Cleared once the palette overflows — the indices built so far are
  /// dropped and [_raw], which was being filled all along, becomes the
  /// answer.
  bool _paletteOpen = true;
  int _count = 0;

  void add(Uint8List channelBytes) {
    _raw.add(Uint8List.fromList(channelBytes));
    _count += 1;
    if (!_paletteOpen) {
      return;
    }
    var key = 0;
    for (var byte = 0; byte < byteCount; byte += 1) {
      key = (key << 8) | channelBytes[byte];
    }
    final existing = _paletteIndexByKey[key];
    if (existing != null) {
      _indices.add(existing);
      return;
    }
    if (_paletteIndexByKey.length == _maxPaletteEntries) {
      _paletteOpen = false;
      _indices.clear();
      _paletteIndexByKey.clear();
      return;
    }
    final index = _paletteIndexByKey.length;
    _paletteIndexByKey[key] = index;
    _palette.add(Uint8List.fromList(channelBytes));
    _indices.add(index);
  }

  /// Null when the pass touched nothing.
  CelPixelRestore? build() {
    if (_count == 0) {
      return null;
    }
    if (_paletteOpen && _paletteIndexByKey.length == 1) {
      return UniformCelPixelRestore(_palette.toBytes());
    }
    if (_paletteOpen) {
      return PalettedCelPixelRestore(
        palette: _palette.toBytes(),
        indices: Uint8List.fromList(_indices),
      );
    }
    return RawCelPixelRestore(_raw.toBytes());
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
  final byteCount = channel.byteCount;
  final builder = value == null ? null : _RestoreBuilder(byteCount);
  final original = Uint8List(byteCount);
  final incoming = Uint8List(byteCount);
  if (value != null) {
    incoming.setAll(0, value);
  }

  final rebuilt = <TileCoord, BitmapTile>{};
  final pixelCount = surface.tileSize * surface.tileSize;
  var index = 0;

  walk((coord, mask) {
    // Absent tile: nothing has ever been drawn here, so 색 변환 has no
    // colour to replace and 비우기 has nothing to empty. It stays absent
    // rather than materializing 256 KB of zeroes.
    final tile = surface.tileAt(coord);
    if (tile == null) {
      return;
    }
    // Reads come from the tile's own bytes and writes go to the copy, so
    // "the original value" stays available even after the pixel beside it
    // has been overwritten. The copy is made LAZILY, at the first pixel
    // that actually changes: a tile the walk crosses but never writes keeps
    // its ORIGINAL object and, the tile map being immutable, is then shared
    // with the old surface — the single biggest reason a whole-canvas pass
    // over line art costs almost nothing.
    final written = tile.readPixels<Uint8List?>((_, view) {
      Uint8List? out;
      for (var pixel = 0; pixel < pixelCount; pixel += 1) {
        final maskValue = mask == null ? 255 : mask[pixel];
        final offset = pixel * 4;
        if (!celPixelParticipates(
          channel: channel,
          alpha: view[offset + 3],
          maskValue: maskValue,
        )) {
          continue;
        }
        for (var byte = 0; byte < byteCount; byte += 1) {
          original[byte] = view[offset + channel.byteOffset(byte)];
        }
        builder?.add(original);
        if (restore != null) {
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
    if (written != null) {
      rebuilt[coord] = BitmapTile(
        coord: coord,
        size: surface.tileSize,
        pixels: written,
      );
    }
  });

  if (rebuilt.isEmpty) {
    return (surface: surface, restore: null);
  }
  return (surface: surface.putTiles(rebuilt.values), restore: builder?.build());
}

/// `older + (incoming - older) * coverage / 255`, in the integer mul-div-255
/// idiom the lift's soft mask already uses.
int _blend(int older, int incoming, int coverage) {
  final scaled = incoming * coverage + older * (255 - coverage) + 128;
  return (scaled + (scaled >> 8)) >> 8;
}
