import 'dart:typed_data';

import '../brush_tip_coverage.dart';
import '../import/clip_offscreen.dart';

/// A tip as coverage, one byte a pixel — what [brushTipMaskFromCoverage]
/// takes.
typedef SutTipCoverage = ({Uint8List coverage, int width, int height});

/// The tip a Clip Studio material holds, as Clip Studio stores it — or null
/// where this reader cannot say, and the material's preview stands in.
///
/// 🗣️유저 2026-10-31, board imported-water-blend-lays-almost-nothing Q4
/// 「진짜 팁을 읽는다」. 📏A material's own `thumbnail.png` is capped at 300
/// on its long side and carries a pixel of margin below that — every one of
/// the sixteen materials measured — and that is what came in as the tip: a
/// 2168 × 1770 tip reached the app through 300 × 245.
///
/// ## Format (memory `csp-clip-format-notes` §8)
///
/// A material is a TAR holding `data/*.layer`. A `.layer` is a C2F file,
/// chunks of `u32 LE length · "dATA" · body · 4 bytes` from offset 20: a
/// body opening `01 00` is enciphered, ten bytes of head and the rest
/// ciphertext, and one opening `00 00` is plain. Together they are a SQLite
/// database of the `.clip` schema, ciphered up to its first few pages.
///
/// ⛔THE CIPHERTEXT IS NOT TOUCHED (Q4's option as the user chose it: 「암호화된
/// 앞부분은 건드리지 않는다」). The database's own header and schema lie in it,
/// so it cannot be opened as a database: the pages after it are walked by
/// hand, and an `Offscreen` row is known by its blobs ([_offscreensOf]).
SutTipCoverage? sutMaterialTipCoverage(Uint8List material) {
  try {
    return _largestOf(_layersOf(material).map(_tipOf));
  } on Object {
    // The bytes of a format nobody documents: whatever they do past what was
    // measured, the preview is still there and the import still says so.
    return null;
  }
}

/// The `.layer` files of the TAR [material].
Iterable<Uint8List> _layersOf(Uint8List material) sync* {
  const block = 512;
  var at = 0;
  while (at + block <= material.length && material[at] != 0) {
    if (String.fromCharCodes(material, at + 257, at + 262) != 'ustar') {
      return;
    }
    final name = String.fromCharCodes(
      material,
      at,
      material.indexOf(0, at),
    );
    final size = int.parse(
      String.fromCharCodes(material, at + 124, at + 135).trim(),
      radix: 8,
    );
    final body = at + block;
    if (name.startsWith('data/') && name.endsWith('.layer')) {
      yield Uint8List.sublistView(material, body, body + size);
    }
    at = body + (size + block - 1) ~/ block * block;
  }
}

/// The largest picture in [layer] that holds anything.
SutTipCoverage? _tipOf(Uint8List layer) {
  final tail = _plainTailOf(layer);
  if (tail == null) {
    return null;
  }
  for (final pageSize in _pageSizes) {
    final pages = _Pages(tail.bytes, skipped: tail.skipped, size: pageSize);
    if (!pages.fit) {
      continue;
    }
    final tip = _largestOf(
      _offscreensOf(pages).map(
        (offscreen) => _coverageOf(
          parseClipOffscreenAttribute(offscreen.attribute),
          clipBlocksOf(offscreen.blocks),
        ),
      ),
    );
    if (tip != null) {
      return tip;
    }
  }
  return null;
}

/// The largest of [tips] by area, the earliest of equals.
SutTipCoverage? _largestOf(Iterable<SutTipCoverage?> tips) {
  SutTipCoverage? largest;
  for (final tip in tips.nonNulls) {
    if (largest == null ||
        tip.width * tip.height > largest.width * largest.height) {
      largest = tip;
    }
  }
  return largest;
}

/// 📏Fourteen of the sixteen measured layers are 1024 and two 4096. The size
/// is written in the ciphered header, so each is tried, and a wrong one
/// finds nothing.
const _pageSizes = [1024, 4096, 512, 2048, 8192, 16384, 32768];

/// [layer]'s plain chunk, and how many bytes of the database lie ciphered
/// ahead of it — null for any other shape of file than the measured one:
/// ciphered chunks, then one plain.
({Uint8List bytes, int skipped})? _plainTailOf(Uint8List layer) {
  const magic = [0x89, 0x43, 0x32, 0x46];
  for (var i = 0; i < magic.length; i += 1) {
    if (layer[i] != magic[i]) {
      return null;
    }
  }
  const cipherHead = 10;
  const plainHead = 2;
  final view = ByteData.sublistView(layer);
  var skipped = 0;
  Uint8List? plain;
  var at = 20;
  while (at + 8 <= layer.length) {
    final length = view.getUint32(at, Endian.little);
    if (String.fromCharCodes(layer, at + 4, at + 8) != 'dATA') {
      break;
    }
    final body = at + 8;
    if (plain != null) {
      return null;
    }
    if (layer[body] == 1) {
      skipped += length - cipherHead;
    } else {
      plain = Uint8List.sublistView(layer, body + plainHead, body + length);
    }
    at = body + length + 4;
  }
  return plain == null ? null : (bytes: plain, skipped: skipped);
}

/// The plain end of a SQLite database, by page number: [skipped] bytes of
/// it are not here.
final class _Pages {
  _Pages(this._bytes, {required int skipped, required this.size})
    : _skipped = skipped;

  final Uint8List _bytes;
  final int _skipped;
  final int size;

  bool get fit => (_skipped + _bytes.length) % size == 0;

  int get last => (_skipped + _bytes.length) ~/ size;

  /// Page [number], counted from 1 as SQLite does — null for one in the part
  /// that is not here.
  Uint8List? operator [](int number) {
    final at = (number - 1) * size - _skipped;
    if (at < 0 || at + size > _bytes.length) {
      return null;
    }
    return Uint8List.sublistView(_bytes, at, at + size);
  }
}

/// Every `Offscreen` row on [pages]: a table leaf cell whose record holds an
/// `Attribute` blob, known by its opening u32 16, with the `BlockData` blob
/// right behind it. A row running through a page that is not here is
/// skipped.
Iterable<({Uint8List attribute, Uint8List blocks})> _offscreensOf(
  _Pages pages,
) sync* {
  const tableLeaf = 0x0D;
  const headerSize = 8;
  for (var number = 1; number <= pages.last; number += 1) {
    final page = pages[number];
    if (page == null || page[0] != tableLeaf) {
      continue;
    }
    final view = ByteData.sublistView(page);
    final cells = view.getUint16(3);
    if (headerSize + cells * 2 > page.length) {
      continue;
    }
    for (var cell = 0; cell < cells; cell += 1) {
      final at = view.getUint16(headerSize + cell * 2);
      final List<Uint8List?> blobs;
      try {
        blobs = _blobsOf(_payloadOf(page, at, pages));
      } on RangeError {
        // 📏A page of another size than the one tried: a slice of a 4096
        // page can open with the leaf's byte and hold no cells at all.
        continue;
      }
      for (var i = 0; i + 1 < blobs.length; i += 1) {
        final attribute = blobs[i];
        final blocks = blobs[i + 1];
        if (attribute != null &&
            blocks != null &&
            attribute.length >= 4 &&
            ByteData.sublistView(attribute).getUint32(0) == 16) {
          yield (attribute: attribute, blocks: blocks);
        }
      }
    }
  }
}

/// The value at [at] of the varint SQLite writes, and its length.
(int, int) _varint(Uint8List bytes, int at) {
  var value = 0;
  for (var i = 0; i < 8; i += 1) {
    final byte = bytes[at + i];
    value = (value << 7) | (byte & 0x7F);
    if (byte & 0x80 == 0) {
      return (value, i + 1);
    }
  }
  return ((value << 8) | bytes[at + 8], 9);
}

/// The record of the table leaf cell at [cell] of [page], gathered from its
/// overflow pages — empty where one of them is not here.
Uint8List _payloadOf(Uint8List page, int cell, _Pages pages) {
  final (length, lengthSize) = _varint(page, cell);
  final (_, rowIdSize) = _varint(page, cell + lengthSize);
  final start = cell + lengthSize + rowIdSize;
  final usable = pages.size;
  final inPageMost = usable - 35;
  if (length <= inPageMost) {
    return Uint8List.sublistView(page, start, start + length);
  }
  final inPageLeast = (usable - 12) * 32 ~/ 255 - 23;
  final carried = inPageLeast + (length - inPageLeast) % (usable - 4);
  final inPage = carried <= inPageMost ? carried : inPageLeast;
  final out = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(page, start, start + inPage));
  var next = ByteData.sublistView(page).getUint32(start + inPage);
  var left = length - inPage;
  while (next != 0 && left > 0) {
    final overflow = pages[next];
    if (overflow == null) {
      return Uint8List(0);
    }
    final take = left < usable - 4 ? left : usable - 4;
    out.add(Uint8List.sublistView(overflow, 4, 4 + take));
    left -= take;
    next = ByteData.sublistView(overflow).getUint32(0);
  }
  return out.takeBytes();
}

/// [record]'s columns: each blob, null for a column of any other type.
List<Uint8List?> _blobsOf(Uint8List record) {
  if (record.isEmpty) {
    return const [];
  }
  final (headerEnd, headerSize) = _varint(record, 0);
  final blobs = <Uint8List?>[];
  var at = headerSize;
  var data = headerEnd;
  while (at < headerEnd) {
    final (type, size) = _varint(record, at);
    at += size;
    final length = switch (type) {
      >= 1 && <= 4 => type,
      5 => 6,
      6 || 7 => 8,
      >= 12 => (type - 12) ~/ 2,
      _ => 0,
    };
    final isBlob = type >= 12 && type.isEven;
    blobs.add(
      isBlob ? Uint8List.sublistView(record, data, data + length) : null,
    );
    data += length;
  }
  return blobs;
}

/// [shape]'s picture as a tip, or null for one that holds nothing or comes
/// in a channel bundle no measured tip does.
SutTipCoverage? _coverageOf(
  ClipOffscreenShape shape,
  Map<int, Uint8List?> blocks,
) {
  final Uint8List? coverage;
  if (shape.isSingleChannel) {
    coverage = clipMaskPlane(shape, blocks);
  } else {
    final rgba = shape.isGray
        ? clipGrayRgba(shape, blocks)
        : clipColourRgba(shape, blocks);
    coverage = rgba == null ? null : brushTipCoverageOfRgba(rgba);
  }
  if (coverage == null || coverage.every((value) => value == 0)) {
    return null;
  }
  return (coverage: coverage, width: shape.width, height: shape.height);
}
