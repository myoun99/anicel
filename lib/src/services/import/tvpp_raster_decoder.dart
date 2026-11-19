import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../models/canvas_size.dart';
import '../../models/import/tvpp_parse.dart';
import 'tile_cutter.dart' show RowSink, TileCutter;

/// Reads one .tvpp image slot as rows of straight (un-premultiplied) RGBA.
///
/// The pixel side of the format, verified pixel-perfect against
/// TVPaint's own PNG export of the same clip (376/376 images, spec in
/// memory `tvpp-format-notes`):
///
///  * Storage pixels are **premultiplied BGRA**, and the premultiply
///    rounds UP: `p = (v·a + 254) ~/ 255`. Grayscale ink hides a channel
///    swap, so any change here must be re-verified on a COLOUR layer.
///  * Rows are PackBits: byte `c >= 0x80` runs the next 4-byte pixel
///    `257 - c` times, `c < 0x80` copies `c + 1` literal pixels. A run
///    never crosses a row boundary.
///  * `DBOD` records are the whole canvas, row by row.
///  * `SRAW` type-64 records are a thumbnail as wide and as tall as the
///    head's u32s at 16 and 20 say, a table of `(totalTiles, X)` pairs,
///    then 64×64 tiles in row-major order (edge tiles truncated). Two tile
///    encodings exist, selected by X:
///      X > 0: tile 0 is X bytes of bare rows; after that each tile is a
///        12-byte copy marker — `(0, 0, srcTile)` of this picture,
///        `(0, 1, srcTile)` of the picture before ([TvppPicturesInOrder])
///        — or `u32 size` + rows.
///      X == 0: every tile is a 12-byte record `(a, anchor, c)`; `c == 0`
///        is empty, `c > 0` starts a chain — the c bytes belong to the
///        NEXT tile, then `u32 size` continues tile-by-tile until a zero.
///  * v11 and later wrap records in a zlib chain (64KB blocks); v10 stores them
///    raw. [TvppPicturesInOrder] reads both, by [TvppSlot.compressed].
class TvppRasterDecodeException implements Exception {
  const TvppRasterDecodeException(this.message);

  final String message;

  @override
  String toString() => 'TvppRasterDecodeException: $message';
}

/// A tile shows the picture before's (`(0, 1, s)`), and the picture was
/// read by a reader that read no picture before it: it reads only after the
/// one before it ([TvppPicturesInOrder]).
class TvppNeedsThePictureBefore extends TvppRasterDecodeException {
  const TvppNeedsThePictureBefore()
    : super('A tile shows the picture before, which was not read.');
}

/// A layer's pictures read in the order its file holds them, each over the
/// one before: a tile of a picture may be `(0, 1, s)` — 「the picture
/// before's tile s」 — and only a reader that read that picture can show it.
///
/// 🗣️F-621 ② (유저 2026-11-19, the user's file): two layers wrote each
/// picture as the tiles it changed and pointed the rest at the picture
/// before, and every picture of theirs but the first failed to read — 515.
/// 🔬It is the picture BEFORE's tile, not the layer's first's: filled from
/// it, a pointed tile meets the tiles around it with a mean difference of
/// 0.0–1.1 a channel; from the first, 1.5–2.9; left empty, 190–608 (six
/// records of that file). ↩️The decoder knew `(0, 0, s)` alone from its
/// first version (96d111583) and read the third shape's words as a size.
///
/// 🚨WHAT A PICTURE IS MADE OF, NEVER ITS PIXELS ([TvppTileSources]): the
/// bytes its tiles are read from, at most a record's worth, where its
/// pixels would be a canvas (F-608 ③).
class TvppPicturesInOrder {
  /// A reader that goes on from a picture another one read — [before], what
  /// that picture is made of ([last]) — or that starts a layer.
  TvppPicturesInOrder({TvppTileSources? before}) : _last = (() => before);

  TvppTileSources? Function() _last;

  /// What the picture read last is made of — the picture before the next
  /// one, for a reader that goes on from it — worked out as it is asked.
  /// Null where nothing was read.
  TvppTileSources? get last => _last();

  /// [slot]'s picture, over the one read before it, as rows of straight
  /// RGBA handed to [row] from the top — the rows a [TileCutter] cuts, as
  /// every picture a file holds is cut. A row with no ink is not handed on,
  /// which a cut reads as clear; a hold slot hands on none, and the picture
  /// before stays the one before. A row's bytes are the next one's once
  /// [row] returns.
  ///
  /// Read by a reader that read no picture before it, a picture with a tile
  /// that shows the picture before's throws [TvppNeedsThePictureBefore].
  ///
  /// [recordBytes] need hold no more than the slot's own record: a window of
  /// it, sent to a worker, is the same input by a different name.
  ///
  /// 🚨NEVER THE WHOLE CANVAS AT ONCE (card F-608 ③). ↩️Till 2026-11-16 a
  /// cel was decoded whole — its words, then its straight bytes: two
  /// canvases, 136 MB each at the user's 7751 × 4396 — and sliced into
  /// tiles by a cut of its own beside the [TileCutter]. Eight workers held
  /// over 2 GB at once, and the open showed no percent till all eight were
  /// done. A tiled record is read a band of its 64-pixel tiles at a time
  /// now, a whole-canvas one a row at a time.
  void read({
    required Uint8List recordBytes,
    required TvppSlot slot,
    required CanvasSize size,
    required RowSink row,
  }) {
    final rgba = Uint8List(size.width * 4);
    _walk(recordBytes, slot, size, (y, words, from) {
      if (_straightRow(words, from, rgba)) {
        row(y, rgba);
      }
    });
  }

  /// [slot]'s picture gone over as [read] goes over it — refused where
  /// [read] would refuse it — with no row of it made: what it is made of
  /// alone, for the picture after it ([last]).
  ///
  /// ⚡THE STEP A LAYER'S PICTURES TAKE IN ORDER (bake card
  /// tvpp-bake-waits-on-the-isolate-that-hands-out-records, 2026-11-19):
  /// the picture after needs this picture's makeup, not its pixels, so
  /// only this walks one after another and the pixels are read beside it.
  /// A run's PackBits are counted, not written ([_PackBits.take] with no
  /// words), so a record that would not read is refused here as well.
  void walk({
    required Uint8List recordBytes,
    required TvppSlot slot,
    required CanvasSize size,
  }) => _walk(recordBytes, slot, size, null);

  void _walk(
    Uint8List recordBytes,
    TvppSlot slot,
    CanvasSize size,
    _WordRows? rows,
  ) {
    if (slot.kind == TvppSlotKind.hold) {
      return;
    }
    _last = _recordRows(_recordOf(recordBytes, slot), size, last, rows);
  }
}

/// What a picture is made of, tile by tile: the PackBits rows each of the
/// 64-pixel tiles of its grid is read from — its own, another tile's of
/// it, or a tile's of the picture before — and how much of them the tile
/// shows. The picture before for the one after it ([TvppPicturesInOrder]).
///
/// Every root's rows once, copied out of the records they lie in: a
/// picture's sources hold no record, and none of the pictures before it.
class TvppTileSources {
  TvppTileSources._(this._roots, this._kept);

  final List<_Root?> _roots;
  final List<_Kept> _kept;
}

/// What a picture read is made of ([TvppTileSources]) — worked out only
/// where the picture after it asks ([TvppPicturesInOrder.last]).
typedef _MadeOf = TvppTileSources Function();

/// Where a tile's rows are read from: [bytes] from [start], [length] of
/// them, as many rows of [width] pixels as [height] says — the root tile's
/// own size, which the tile that shows it may not share.
typedef _Root = ({
  Uint8List bytes,
  int start,
  int length,
  int width,
  int height,
});

/// How much of its root a tile shows: no more than the smaller of the two
/// in each direction — the canvas cuts the grid's last column and row
/// short, and a copy keeps what both cover, from the top-left.
typedef _Kept = ({int width, int height});

/// The record [slot] holds, its magic first.
Uint8List _recordOf(Uint8List recordBytes, TvppSlot slot) {
  if (slot.compressed) {
    return _reassembleZchk(recordBytes, slot.chunkOffset, slot.chunkLength);
  }
  // v10 stores the record body as a bare chunk payload — its magic and
  // length live in the CHUNK header the parser already consumed.
  // Re-synthesize them so both wrappers hand the decoder the same
  // record shape (offsets in the tiled reader count from the magic).
  final body = Uint8List.sublistView(
    recordBytes,
    slot.chunkOffset,
    slot.chunkOffset + slot.chunkLength,
  );
  final record = Uint8List(8 + body.length);
  record.setAll(0, (slot.v10WholeCanvas ? 'DBOD' : 'SRAW').codeUnits);
  ByteData.sublistView(record, 4, 8).setUint32(0, body.length);
  record.setAll(8, body);
  return record;
}

// ---------------------------------------------------------------------------
// v12 ZCHK reassembly
// ---------------------------------------------------------------------------

/// A ZCHK payload is `'SRAW' u32 total-8 | 'czmp' u32 | u32 blocks`, then
/// block after block `u32 100 | u32 raw | u32 packed | zlib × packed`:
/// every block says how long its stream is, so each is inflated from
/// exactly its own bytes, straight into its place in the record.
///
/// 🚨WALKED BY THE BLOCKS' OWN HEADS (card F-608 ③). ↩️Till 2026-11-17
/// the head was read as the whole payload's, and the next stream was
/// FOUND — a scan for a zlib header from inside the stream before, each
/// candidate inflated with the whole rest of the payload as its input.
/// On the user's 7751 × 4396 file that was 48 s for its 754 records
/// (10.9 s for one) against 1.5 s walked, the same bytes for all 754 —
/// two-thirds of every cel's decode.
Uint8List _reassembleZchk(Uint8List bytes, int offset, int length) {
  if (length < 32) {
    throw const TvppRasterDecodeException('The ZCHK payload is too short.');
  }
  final payload = ByteData.sublistView(bytes, offset, offset + length);
  final expected = payload.getUint32(4) + 8;
  final record = Uint8List(expected);
  var filled = 0;
  var at = 20;
  while (filled < expected && at + 12 <= length) {
    final stream = at + 12;
    final end = stream + payload.getUint32(at + 8);
    if (end > length) {
      break;
    }
    final block = _inflated(bytes, offset + stream, offset + end);
    final taken = math.min(block.length, expected - filled);
    record.setRange(filled, filled + taken, block);
    filled += taken;
    at = end;
  }
  if (filled < expected) {
    throw TvppRasterDecodeException(
      'ZCHK reassembly failed: $filled/$expected bytes.',
    );
  }
  return record;
}

/// The zlib stream between [from] and [to] inflated — nothing, when it
/// is not one, which the record's count then reports.
List<int> _inflated(Uint8List bytes, int from, int to) {
  try {
    return ZLibDecoder().convert(Uint8List.sublistView(bytes, from, to));
  } on FormatException {
    return const [];
  }
}

// ---------------------------------------------------------------------------
// PackBits + tile assembly (premultiplied BGRA words, one per pixel)
// ---------------------------------------------------------------------------

class _PackBits {
  _PackBits(this.data, this.at, {this.skips = false});

  final Uint8List data;
  int at;

  /// Whether `0x80` passes pixels over ([_takeSkip]) — a DEEP animation
  /// frame's (`DBAN`) dialect — rather than running one 129 times. ⛔Off for
  /// a .tvpp record: no run there is 129 long (the longest is 124), and
  /// nothing here may change how a measured record reads.
  final bool skips;

  /// Decodes exactly [count] pixels into [out] (32-bit words) through
  /// [place] — or just consumes them when [out] is null.
  void take(int count, Uint32List? out, int Function(int nth)? place) {
    var got = 0;
    while (got < count) {
      if (at >= data.length) {
        throw const TvppRasterDecodeException('The record ended with rows still to read.');
      }
      final c = data[at];
      if (skips && c == 0x80) {
        got += _takeSkip(out, place, got, count);
      } else if (c >= 0x80) {
        final run = 257 - c;
        if (at + 5 > data.length) {
          throw const TvppRasterDecodeException('A run record is truncated.');
        }
        if (out != null) {
          final v = _wordAt(at + 1);
          var changed = false;
          for (var k = 0; k < run && got + k < count; k++) {
            final i = place!(got + k);
            if (i >= 0) {
              changed |= out[i] != v;
              out[i] = v;
            }
          }
          _refuseStale(changed);
        }
        got += run;
        at += 5;
      } else {
        final literal = c + 1;
        if (at + 1 + literal * 4 > data.length) {
          throw const TvppRasterDecodeException('A literal record is truncated.');
        }
        if (out != null) {
          var changed = false;
          for (var k = 0; k < literal && got + k < count; k++) {
            final i = place!(got + k);
            if (i >= 0) {
              final v = _wordAt(at + 1 + k * 4);
              changed |= out[i] != v;
              out[i] = v;
            }
          }
          _refuseStale(changed, endsRow: got + 1 == count);
        }
        got += literal;
        at += 1 + literal * 4;
      }
    }
    if (got != count) {
      throw const TvppRasterDecodeException('A run crossed a row boundary.');
    }
  }

  /// The pixel whose four bytes start at [q], as one big-endian word.
  int _wordAt(int q) =>
      (data[q] << 24) | (data[q + 1] << 16) | (data[q + 2] << 8) | data[q + 3];

  /// A `DBAN`'s `0x80`: the count byte after it passes that many pixels
  /// from the [got]th of the row's [count] — kept as the frame before had
  /// them where the count is positive, all made the pixel above the first
  /// of them where it is negative — and answers how many.
  ///
  /// 🚨A POSITIVE COUNT KEEPS; A NEGATIVE ONE FILLS ITS PIXELS WITH THE ONE
  /// ABOVE THEIR FIRST — the row above as this frame has it, and one pixel
  /// of it for the whole span, not the span's own length of it (card I-86).
  /// A count byte below `0x80` passes `n`, one from it up `256 - n`, which
  /// ends every row of all 29 tips of the user's BRUSH.tvpx at its width.
  /// 🔬Held to TVPaint's own stamps (2026-11-15): the user stamped the HB
  /// pencil's fifteen frames with no paper (I-86-Q8 「팁 그림 종이질감 빼고 팁
  /// 찍어서 출력한거임. 정확하게 팁 들여줬으면해서」), and laid over them at an
  /// eighth of a pixel every frame read so stands as near as the first —
  /// which no skip touches — does: 7.0–10.4 of ink off in all against its
  /// 8.2, the worst pixel 0.10–0.19 against its 0.12. Each span solved by
  /// itself against the picture is 0 or 255 whole — 255 where the pixel
  /// above its first is, whatever stands above its others. And of the
  /// 78,457 writes of their 150-frame 89×91 tip none changes nothing, nor
  /// is any run one a skip would have filled.
  /// ↩️It cleared (2026-11-14, by the pencil's ink staying about its first
  /// frame's): seven of the fourteen frames then stood a pixel's 0.45–0.93
  /// off, and that 89×91 tip made 185 writes that changed nothing. Copying
  /// the row above pixel for pixel leaves five frames 0.27–0.60 off.
  /// ⛔A frame's first row has no pixel above it. None of the user's tips
  /// skips so there, so what TVPaint would mean by it is not known, and it
  /// is refused, not guessed.
  int _takeSkip(
    Uint32List? out,
    int Function(int nth)? place,
    int got,
    int count,
  ) {
    if (at + 2 > data.length) {
      throw const TvppRasterDecodeException('A skip record is truncated.');
    }
    final n = data[at + 1];
    at += 2;
    if (n < 0x80) {
      return n;
    }
    final passed = 256 - n;
    if (out != null) {
      // The rows are read whole and in order ([_readRows]), each [count]
      // wide: the pixel above is that many back.
      final first = place!(got);
      if (first < count) {
        throw const TvppRasterDecodeException(
          'A skip that fills from the row above stands in the first row.',
        );
      }
      final above = out[first - count];
      for (var k = 0; k < passed && got + k < count; k++) {
        out[first + k] = above;
      }
    }
    return passed;
  }

  /// Refuses a frame one of whose writes changed nothing, where [skips] —
  /// an encoder that keeps with a skip writes only what differs — but the
  /// one pixel that ends a row, written by itself ([endsRow]).
  ///
  /// 🚨IT IS HOW A READING OTHER THAN TVPAINT'S SHOWS (card I-86): a tip
  /// read wrong would not be the tip («팁은 … 진짜 하나도 안틀리도록», 유저
  /// 2026-11-14). 🔬Of the 125,225 writes of the seven animated tips in the
  /// user's BRUSH.tvpx (2026-11-15), read as [_takeSkip] reads them, 25
  /// change nothing, and every one is a lone literal of its row's last
  /// pixel: TVPaint writes that pixel by itself where what came before it
  /// stopped one short, changed or not (`K124 K18 N124 K124 L1`, a row of
  /// 391).
  /// ↩️It refused those too, and with the skip read as clearing nine of the
  /// user's 29 custom brushes stayed out for it.
  void _refuseStale(bool changed, {bool endsRow = false}) {
    if (skips && !changed && !endsRow) {
      throw const TvppRasterDecodeException(
        'A frame wrote over pixels what they already held.',
      );
    }
  }
}

/// Where a record's rows go: row [y] of the picture, premultiplied BGRA
/// words, the picture's width of them from [from] in [words] — which hold
/// the next row once this returns.
typedef _WordRows = void Function(int y, Uint32List words, int from);

/// [record]'s rows, handed to [rows] from the top — but rows of tiles it
/// left empty, which hold no ink — read over [before], what the picture
/// before is made of — none made where [rows] is null. Answers what the
/// record's picture is made of, for the picture after it to ask.
///
/// 🔬Not only a tiled picture is a picture before: both layers of the
/// user's file that read in order open on a whole-canvas record (`DBOD`),
/// and the next picture's tiles point into it (F-621 ②, 2026-11-19).
_MadeOf _recordRows(
  Uint8List record,
  CanvasSize size,
  TvppTileSources? before,
  _WordRows? rows,
) {
  if (record.length < 8) {
    throw const TvppRasterDecodeException('The record is too short.');
  }
  final magic = String.fromCharCodes(record, 0, 4);
  if (magic == 'SRAW' &&
      record.length >= 12 &&
      ByteData.sublistView(record).getUint32(8) == 5) {
    // Type 5 (28 bytes, zero payload): a BLANK instance — 12.0.6 writes
    // these where 12.1 writes a contentless type-64 (288's A_KAKI runs
    // blank cels on 2s this way). An instance boundary with no pixels.
    return () => _blankSources(size);
  }
  if (magic == 'DBOD') {
    _wholeCanvasRows(record, size.width, size.height, rows);
    return () => _wholeCanvasSources(record, size);
  }
  if (magic == 'SRAW') {
    return _tiledRows(record, size, before, rows).sources;
  }
  throw TvppRasterDecodeException('Unknown raster magic «$magic».');
}

/// A `DBOD`'s rows, the whole canvas's, read one at a time — counted only,
/// where no [rows] are wanted.
void _wholeCanvasRows(
  Uint8List record,
  int width,
  int height,
  _WordRows? rows,
) {
  final pb = _PackBits(record, 8);
  final words = rows == null ? null : Uint32List(width);
  for (var y = 0; y < height; y++) {
    pb.take(width, words, _itself);
    if (words != null) {
      rows!(y, words, 0);
    }
  }
}

int _itself(int nth) => nth;

/// How many 64-pixel tiles of the grid [pixels] takes.
int _tilesAcross(int pixels) =>
    (pixels + _TileGrid.tile - 1) ~/ _TileGrid.tile;

/// A blank picture as the picture before: its grid, no tile showing any.
TvppTileSources _blankSources(CanvasSize size) {
  final total = _tilesAcross(size.width) * _tilesAcross(size.height);
  return TvppTileSources._(
    List.filled(total, null),
    List.filled(total, (width: 0, height: 0)),
  );
}

/// What a whole-canvas picture is made of ([TvppTileSources]), on the grid
/// a tiled one is cut into: its rows read again a band of the grid at a
/// time, each tile packed anew as a tiled record packs one
/// ([_PackedWords]), none for a tile without ink — so a tile of the picture
/// after shows it as it shows any other's, and it carries packed rows, not
/// the canvas.
TvppTileSources _wholeCanvasSources(Uint8List record, CanvasSize size) {
  const tile = _TileGrid.tile;
  final CanvasSize(:width, :height) = size;
  final pb = _PackBits(record, 8);
  final band = Uint32List(width * tile);
  final packed = _PackedWords(band, width);
  final places = <({int start, int length, int width, int height})?>[];
  for (var top = 0; top < height; top += tile) {
    final rows = math.min(tile, height - top);
    for (var y = 0; y < rows; y += 1) {
      final at = y * width;
      pb.take(width, band, (nth) => at + nth);
    }
    for (var left = 0; left < width; left += tile) {
      places.add(packed.tile(left, math.min(tile, width - left), rows));
    }
  }
  final bytes = packed.bytes;
  return TvppTileSources._(
    [
      for (final place in places)
        if (place == null)
          null
        else
          (
            bytes: bytes,
            start: place.start,
            length: place.length,
            width: place.width,
            height: place.height,
          ),
    ],
    [
      for (final place in places)
        (width: place?.width ?? 0, height: place?.height ?? 0),
    ],
  );
}

/// Tiles of a [band] of rows, [stride] words each, packed one after
/// another as a tiled record packs a tile: row by row, a run of equal
/// words as `257 - n` and the word (no longer than 128, so never `0x80`
/// — [_PackBits.skips]), anything else literal, `n - 1` and the words.
///
/// ⚖️THE SECOND PACKBITS ENCODER — PSD's `packBitsRow` packs bytes, this
/// packs four-byte pixels, which moves where a run pays: two equal words
/// cost five bytes as a run and nine as literals, where two equal bytes
/// cost the same either way. Not one code until a third wants it (rule of
/// three, `when-rules-conflict`).
class _PackedWords {
  _PackedWords(this.band, this.stride);

  final Uint32List band;
  final int stride;
  final _bytes = <int>[];

  /// A word's four bytes as a record stores them, big-endian.
  final _four = ByteData(4);
  late final _fourBytes = _four.buffer.asUint8List();

  /// Every tile packed so far, back to back.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// The tile [width] wide and [height] tall from column [left] of the
  /// band, packed — where it lies in [bytes] — or null where it has no ink.
  ({int start, int length, int width, int height})? tile(
    int left,
    int width,
    int height,
  ) {
    if (!_inked(left, width, height)) {
      return null;
    }
    final start = _bytes.length;
    for (var y = 0; y < height; y += 1) {
      _row(y * stride + left, y * stride + left + width);
    }
    return (
      start: start,
      length: _bytes.length - start,
      width: width,
      height: height,
    );
  }

  bool _inked(int left, int width, int height) {
    for (var y = 0; y < height; y += 1) {
      for (var x = left; x < left + width; x += 1) {
        if (band[y * stride + x] != 0) {
          return true;
        }
      }
    }
    return false;
  }

  void _row(int from, int end) {
    var at = from;
    while (at < end) {
      var run = 1;
      while (at + run < end && run < 128 && band[at + run] == band[at]) {
        run += 1;
      }
      if (run >= 2) {
        _bytes.add(257 - run);
        _word(band[at]);
        at += run;
        continue;
      }
      final start = at;
      at += 1;
      while (at < end &&
          at - start < 128 &&
          !(at + 1 < end && band[at] == band[at + 1])) {
        at += 1;
      }
      _bytes.add(at - start - 1);
      for (var k = start; k < at; k += 1) {
        _word(band[k]);
      }
    }
  }

  void _word(int word) {
    _four.setUint32(0, word);
    _bytes.addAll(_fourBytes);
  }
}

/// One frame of a DEEP animation — a TVPaint brush tip's `.dip` — as
/// premultiplied BGRA words: a `DBOD` [body] read as a whole canvas, or a
/// `DBAN` [body] read over [before], the frame it follows, whose pixels its
/// positive skips keep and its negative ones fill from the row above
/// ([_PackBits.skips]).
///
/// The rows are a .tvpp `DBOD`'s, the same walker's — `DBAN` adds the skip.
Uint32List decodeDeepFrameWords(
  Uint8List body, {
  required int width,
  required int height,
  Uint32List? before,
}) => _readRows(
  _PackBits(body, 0, skips: before != null),
  before == null ? Uint32List(width * height) : Uint32List.fromList(before),
  width,
);

/// [img]'s rows, [width] pixels each, read from [pb] in order.
Uint32List _readRows(_PackBits pb, Uint32List img, int width) {
  for (var row = 0; row < img.length; row += width) {
    pb.take(width, img, (nth) => row + nth);
  }
  return img;
}

/// One tiled raster being read: the 64×64 grid the picture is cut into,
/// the PackBits cursor walking the record, and the grid's row of tiles
/// under way — its [band] — handed on to [rowsOut] as the walk leaves it;
/// no band at all where there is no [rowsOut], only what the picture is
/// made of ([TvppPicturesInOrder.walk]).
///
/// ⛔The record's shape is measured, not documented — see
/// `tvpp-format-notes.md`. Nothing here may change what bytes are read
/// or in what order.
///
/// 🚨NO TILE IS HELD PAST ITS BAND (card F-608 ③): the walk meets the
/// tiles in order, a row of the grid after another, so the band is all of
/// the picture there is at once. A tile that copies one of a band already
/// handed on — or one of the picture before — reads that one's bytes again
/// ([_readAgain]).
class _TileGrid {
  _TileGrid(
    this.record, {
    required this.width,
    required this.height,
    required this.rowsOut,
    required this.before,
  }) : cols = (width + tile - 1) ~/ tile,
       rows = (height + tile - 1) ~/ tile,
       band = Uint32List(rowsOut == null ? 0 : width * tile),
       pb = _PackBits(record, 24);

  static const tile = 64;

  final Uint8List record;
  final int width;
  final int height;
  final _WordRows? rowsOut;
  final int cols;
  final int rows;
  final _PackBits pb;

  /// What the picture before is made of — null where it was not read.
  final TvppTileSources? before;

  /// The grid's row of tiles under way: its [tile] rows of pixels, [width]
  /// words each, zero where no tile was written.
  final Uint32List band;
  int _bandRow = 0;

  /// The tiles written into [band] — to clear once it is handed on.
  final List<int> _written = [];

  int get total => cols * rows;

  /// Where tile t's rows are read from — its own where it was read — or
  /// null where it shows none: never written, or a copy of one that showed
  /// none.
  late final List<_Root?> _roots = List.filled(total, null);

  /// How much of its root tile t shows ([_Kept]).
  late final List<_Kept> _kept = List.filled(total, (width: 0, height: 0));

  /// A root's pixels read again ([_readAgain]), rows of its own width, and
  /// which root they are.
  final Uint32List _again = Uint32List(tile * tile);
  _Root? _againOf;

  /// The thumbnail's pixels, as many as the head says it is wide and tall
  /// — 96 × 54 in every tiled record of the user's 7751 × 4396 file (240 of
  /// them, 2026-11-17). ↩️Till 2026-11-16 it was 96 × 67 for every canvas,
  /// and past the first picture a 16:9 file read noise (card F-608 ②).
  int get thumbnailPixels => _uint32At(16) * _uint32At(20);

  int _uint32At(int offset) =>
      ByteData.sublistView(record, offset, offset + 4).getUint32(0);

  int _tileWidth(int column) =>
      column == cols - 1 ? width - column * tile : tile;

  int _tileHeight(int row) => row == rows - 1 ? height - row * tile : tile;

  /// Reads the (totalTiles, X) table and answers X.
  ///
  /// The pair COUNT varies per file, so the table is read while the first
  /// word still says how many tiles this picture has; X is the last one
  /// read, and it decides which of the two tile layouts follows.
  int readTileTable() {
    var x = -1;
    while (pb.at + 8 <= record.length && _uint32At(pb.at) == total) {
      x = _uint32At(pb.at + 4);
      pb.at += 8;
    }
    if (x < 0) {
      throw const TvppRasterDecodeException('The tile table is missing.');
    }
    return x;
  }

  /// Decodes tile [t]'s pixels straight into [band], and checks that it
  /// consumed exactly the bytes the record said it would — a mismatch
  /// means the cursor has drifted and everything after it is noise.
  void readTile(int t, int declaredSize) {
    final tc = t % cols;
    final tw = _tileWidth(tc);
    final th = _tileHeight(t ~/ cols);
    final out = _bandFor(t);
    final from = pb.at;
    for (var y = 0; y < th; y++) {
      final at = y * width + tc * tile;
      pb.take(tw, out, (nth) => at + nth);
    }
    if (pb.at - from != declaredSize) {
      throw TvppRasterDecodeException(
        'Tile $t size mismatch: ${pb.at - from} ≠ $declaredSize.',
      );
    }
    _roots[t] = (
      bytes: record,
      start: from,
      length: declaredSize,
      width: tw,
      height: th,
    );
    _kept[t] = (width: tw, height: th);
  }

  /// Copies an already-decoded tile onto another — how the format says
  /// "this tile is the same as that one".
  void copyTile(int dst, int src) {
    // ⛔An EQUIVALENT guard, kept as the statement of what the caller
    // already promises: `readSizedTiles` tests `< total` before it calls,
    // the source word is unsigned so it cannot be negative, and copying a
    // tile onto itself writes back the bytes it read. Mutating it away
    // leaves the suite green, and that is the honest state (2026-09-05) —
    // it is here for the day a corrupt file reaches this line another way.
    if (dst == src || src < 0 || src >= total) {
      return;
    }
    // A source the walk has not written yet — later in it, or left empty —
    // shows nothing, and so does its copy.
    _show(dst, _roots[src], _kept[src]);
  }

  /// Shows the picture before's tile [src] on tile [dst] — how the format
  /// says 「this tile is the same as that one, the picture before」.
  void copyFromBefore(int dst, int src) {
    final before = this.before;
    if (before == null) {
      throw const TvppNeedsThePictureBefore();
    }
    if (src >= before._roots.length) {
      return;
    }
    _show(dst, before._roots[src], before._kept[src]);
  }

  /// Tile [dst] shows [root], as much of it as [kept] says and the tile
  /// covers — nothing where there is no root.
  void _show(int dst, _Root? root, _Kept kept) {
    if (root == null) {
      return;
    }
    final dc = dst % cols;
    final shown = (
      width: math.min(kept.width, _tileWidth(dc)),
      height: math.min(kept.height, _tileHeight(dst ~/ cols)),
    );
    _roots[dst] = root;
    _kept[dst] = shown;
    final out = _bandFor(dst);
    if (out == null) {
      return;
    }
    final pixels = _readAgain(root);
    for (var y = 0; y < shown.height; y++) {
      final at = y * width + dc * tile;
      out.setRange(at, at + shown.width, pixels, y * root.width);
    }
  }

  /// [band], moved on to tile [t]'s row of the grid, with [t] to be cleared
  /// in it once it is handed on — none where no rows are wanted ([rowsOut]).
  Uint32List? _bandFor(int t) {
    if (rowsOut == null) {
      return null;
    }
    _enterBandOf(t);
    _written.add(t);
    return band;
  }

  /// [root]'s pixels, read again from its bytes — rows of its own width, in
  /// a buffer the next root read again reuses.
  Uint32List _readAgain(_Root root) {
    if (_againOf == root) {
      return _again;
    }
    final again = _PackBits(root.bytes, root.start);
    for (var y = 0; y < root.height; y++) {
      final at = y * root.width;
      again.take(root.width, _again, (nth) => at + nth);
    }
    _againOf = root;
    return _again;
  }

  /// What this picture is made of ([TvppTileSources]): every root its tiles
  /// show, copied out once into bytes of its own — the picture before's
  /// with them, so the next picture holds neither record.
  TvppTileSources sources() {
    final copiedTo = <_Root, int>{};
    var length = 0;
    for (final root in _roots) {
      if (root != null && !copiedTo.containsKey(root)) {
        copiedTo[root] = length;
        length += root.length;
      }
    }
    final bytes = Uint8List(length);
    for (final MapEntry(key: root, value: at) in copiedTo.entries) {
      bytes.setRange(at, at + root.length, root.bytes, root.start);
    }
    return TvppTileSources._([
      for (final root in _roots)
        if (root == null)
          null
        else
          (
            bytes: bytes,
            start: copiedTo[root]!,
            length: root.length,
            width: root.width,
            height: root.height,
          ),
    ], List.of(_kept));
  }

  /// [band] moved on to tile [t]'s row of the grid — the rows before it
  /// handed on first.
  void _enterBandOf(int t) {
    final row = t ~/ cols;
    if (row != _bandRow) {
      handOn();
      _bandRow = row;
    }
  }

  /// [band]'s rows handed on, and the band cleared where it was written —
  /// a band no tile was written in hands on nothing — nor does a walk that
  /// wants no rows, which writes none ([_bandFor]).
  void handOn() {
    final rowsOut = this.rowsOut;
    if (rowsOut == null || _written.isEmpty) {
      return;
    }
    final bandHeight = _tileHeight(_bandRow);
    for (var y = 0; y < bandHeight; y++) {
      rowsOut(_bandRow * tile + y, band, y * width);
    }
    for (final t in _written) {
      final at = (t % cols) * tile;
      final tw = _tileWidth(t % cols);
      for (var y = 0; y < bandHeight; y++) {
        band.fillRange(y * width + at, y * width + at + tw, 0);
      }
    }
    _written.clear();
  }

  /// Layout A (X > 0): tile 0 is [firstTileSize] bytes long, and every
  /// tile after it is either a 12-byte reference — to an earlier tile
  /// (0, 0, source), or to the picture before's (0, 1, source) — or a
  /// 4-byte size followed by its pixels.
  void readSizedTiles(int firstTileSize) {
    readTile(0, firstTileSize);
    for (var t = 1; t < total; t++) {
      if (pb.at + 12 <= record.length) {
        final v = ByteData.sublistView(record, pb.at, pb.at + 12);
        final ofBefore = v.getUint32(4);
        final source = v.getUint32(8);
        if (v.getUint32(0) == 0 && ofBefore <= 1 && source < total) {
          if (ofBefore == 0) {
            copyTile(t, source);
          } else {
            copyFromBefore(t, source);
          }
          pb.at += 12;
          continue;
        }
      }
      if (pb.at + 4 > record.length) {
        throw const TvppRasterDecodeException('The tile size field is truncated.');
      }
      final size = _uint32At(pb.at);
      pb.at += 4;
      readTile(t, size);
    }
  }

  /// Layout B (X == 0): a 12-byte header whose last word is the next
  /// tile's size, then a RUN of tiles each followed by the next one's
  /// size. A zero size means the tile is empty and the run has not
  /// started yet.
  void readTileRuns() {
    var t = 0;
    while (t < total) {
      if (pb.at + 12 > record.length) {
        break; // the encoder truncates its trailing record — measured.
      }
      final size = _uint32At(pb.at + 8);
      pb.at += 12;
      if (size == 0) {
        t += 1;
        continue;
      }
      t = _readRunFrom(t + 1, size);
    }
  }

  /// One run of tiles, starting at [firstIndex] with a tile of
  /// [firstSize] bytes. Answers the index the outer walk resumes at.
  int _readRunFrom(int firstIndex, int firstSize) {
    var ti = firstIndex;
    var next = firstSize;
    while (next > 0 && ti < total && pb.at + next <= record.length) {
      readTile(ti, next);
      ti += 1;
      if (pb.at + 4 > record.length) {
        break;
      }
      next = _uint32At(pb.at);
      pb.at += 4;
    }
    return ti;
  }
}

/// ↩️The thumbnail was skipped as 96 × 67 till 2026-11-16 — the size of
/// every canvas measured (near 3:2), and wrong for any other: a 16:9
/// file's pictures after each layer's first keyframe all failed, the tile
/// table looked for 1,248 pixels late (card F-608 — 240 in one file).
_TileGrid _tiledRows(
  Uint8List record,
  CanvasSize size,
  TvppTileSources? before,
  _WordRows? rows,
) {
  final grid = _TileGrid(
    record,
    width: size.width,
    height: size.height,
    rowsOut: rows,
    before: before,
  );
  grid.pb.take(grid.thumbnailPixels, null, null);
  final x = grid.readTileTable();
  if (x > 0) {
    grid.readSizedTiles(x);
  } else {
    grid.readTileRuns();
  }
  grid.handOn();
  return grid;
}

// ---------------------------------------------------------------------------
// Premultiplied BGRA → straight RGBA
// ---------------------------------------------------------------------------

/// TVPaint's own PNG export computes `v = ⌊p·255 / a⌋` (the inverse of
/// its ceiling premultiply) — matching it exactly is what made the
/// 376-image comparison land on zero differences.
///
/// [words]' pixels from [from], as many as [rgba] holds, written into
/// [rgba] — or false, and [rgba] as it was, where none of them has ink.
bool _straightRow(Uint32List words, int from, Uint8List rgba) {
  final width = rgba.length ~/ 4;
  var x = 0;
  while (x < width && (words[from + x] & 0xff) == 0) {
    x += 1;
  }
  if (x == width) {
    return false;
  }
  for (var i = 0; i < width; i++) {
    final v = words[from + i];
    final a = v & 0xff;
    final o = i * 4;
    if (a == 0) {
      rgba[o] = 0;
      rgba[o + 1] = 0;
      rgba[o + 2] = 0;
      rgba[o + 3] = 0;
      continue;
    }
    rgba[o] = _straight((v >>> 8) & 0xff, a);
    rgba[o + 1] = _straight((v >>> 16) & 0xff, a);
    rgba[o + 2] = _straight((v >>> 24) & 0xff, a);
    rgba[o + 3] = a;
  }
  return true;
}

int _straight(int premultiplied, int alpha) {
  final s = (premultiplied * 255) ~/ alpha;
  return s > 255 ? 255 : s;
}
