import 'dart:typed_data';

import '../../models/layer_blend_mode.dart';
import '../media/still_file_writing.dart' show StillPixels;
import 'psd_blend_modes.dart';

/// The longest side a Photoshop document (version 1) can name — past it a
/// file must be the large-document format, which this writer does not
/// write.
const int psdMaxSide = 30000;

/// Builds a Photoshop document — the layered picture the export window's
/// PSD format writes (I-117: 「psd 내보내기 내용물」), bottom row first, as
/// the file stores them.
///
/// The document reader's mirror (`psd_reader.dart`): the records, the
/// group brackets and the packed planes it reads are what this writes, in
/// the same order — so a file written here reads back through it whole.
///
/// ⚠️ONE ROW'S PIXELS AT A TIME. A layered frame is tens of pictures the
/// size of the canvas — held together, a 4K cut of thirty rows is a
/// gigabyte. So a row comes in packed ([packPsdLayer]) and only its packed
/// planes are kept: its picture can go once it is packed — where it was
/// read, so only the planes travel.
class PsdBuilder {
  PsdBuilder({required this.width, required this.height}) {
    if (width < 1 || height < 1 || width > psdMaxSide || height > psdMaxSide) {
      throw ArgumentError(
        'A Photoshop document is 1 to $psdMaxSide pixels a side, '
        'not ${width}x$height.',
      );
    }
  }

  final int width;
  final int height;

  final List<_Record> _records = [];
  final List<_Group> _open = [];

  /// [pixels] — a picture at the document's size, packed ([packPsdLayer])
  /// — as the row over everything added before it.
  void addLayer({
    required String name,
    required PsdLayerPixels pixels,
    double opacity = 1,
    bool visible = true,
    LayerBlendMode blendMode = LayerBlendMode.normal,
    bool clipped = false,
  }) {
    if (pixels.width != width || pixels.height != height) {
      throw ArgumentError(
        'A layer is at the document\'s ${width}x$height, '
        'not ${pixels.width}x${pixels.height}.',
      );
    }
    _records.add(
      _Record(
        name: name,
        bounds: pixels._bounds,
        opacity: opacity,
        flags: visible ? 0 : _hidden,
        blendKey: psdBlendKeyOf(blendMode),
        channels: pixels._channels,
        clipped: clipped,
      ),
    );
  }

  /// A folder: the rows added until its [closeGroup] are its members.
  /// [blendMode] [LayerBlendMode.passThrough] is Photoshop's 「통과」, as it
  /// is the app's folder default.
  void openGroup({
    required String name,
    double opacity = 1,
    bool visible = true,
    LayerBlendMode blendMode = LayerBlendMode.passThrough,
    bool collapsed = false,
    bool clipped = false,
  }) {
    final group = _Group(
      name: name,
      opacity: opacity,
      visible: visible,
      blendMode: blendMode,
      collapsed: collapsed,
      clipped: clipped,
    );
    _open.add(group);
    // The hidden record Photoshop opens a group's members with — below
    // them, as the file is bottom-first.
    _records.add(
      _Record(
        name: '</Layer group>',
        bounds: null,
        opacity: 1,
        flags: _sectionFlags,
        blendKey: psdBlendKeyOf(LayerBlendMode.normal),
        channels: _emptyChannels,
        section: _boundingSection,
      ),
    );
  }

  /// Closes the folder [openGroup] opened last: its own row, over its
  /// members.
  void closeGroup() {
    if (_open.isEmpty) {
      throw StateError('No folder is open.');
    }
    final group = _open.removeLast();
    _records.add(
      _Record(
        name: group.name,
        bounds: null,
        opacity: group.opacity,
        flags: _sectionFlags | (group.visible ? 0 : _hidden),
        blendKey: psdBlendKeyOf(group.blendMode),
        channels: _emptyChannels,
        section: group.collapsed ? _closedFolder : _openFolder,
        clipped: group.clipped,
      ),
    );
  }

  /// The document: every row added, over [composite] — the merged picture
  /// a reader that does not composite shows (a thumbnail, a flattened
  /// open), RGB or RGBA at the document's size.
  Uint8List build({required StillPixels composite}) {
    if (_open.isNotEmpty) {
      throw StateError('${_open.length} folder(s) left open.');
    }
    if (composite.width != width ||
        composite.height != height ||
        (composite.channels != 3 && composite.channels != 4)) {
      throw ArgumentError(
        'The composite is RGB or RGBA at the document\'s ${width}x$height.',
      );
    }
    final out = _BigEndian()
      ..ascii('8BPS')
      ..u16(1)
      ..zeros(6)
      ..u16(composite.channels)
      ..u32(height)
      ..u32(width)
      ..u16(8)
      ..u16(_rgbMode)
      // No palette, and no image resources.
      ..u32(0)
      ..u32(0);
    final layerInfo = _layerInfo(mergedAlpha: composite.channels == 4);
    out
      ..u32(4 + layerInfo.length + 4)
      ..u32(layerInfo.length)
      ..bytes(layerInfo)
      // No global layer mask.
      ..u32(0);
    _writeComposite(out, composite);
    return out.take();
  }

  /// The layer info section: the count, every record, then every record's
  /// planes in the same order — padded to an even length.
  Uint8List _layerInfo({required bool mergedAlpha}) {
    if (_records.isEmpty) {
      return Uint8List(0);
    }
    // A negative count says the composite's fourth channel is its alpha.
    final out = _BigEndian()
      ..i16(mergedAlpha ? -_records.length : _records.length);
    for (final record in _records) {
      record.writeTo(out);
    }
    for (final record in _records) {
      for (final (_, data) in record.channels) {
        out.bytes(data);
      }
    }
    if (out.length.isOdd) {
      out.u8(0);
    }
    return out.take();
  }

  /// The merged picture, PackBits: every row length of every channel up
  /// front, then the rows — channel by channel, in RGB(A) order.
  void _writeComposite(_BigEndian out, StillPixels composite) {
    final planes = [
      for (var channel = 0; channel < composite.channels; channel += 1)
        _packPlane(
          composite,
          (left: 0, top: 0, right: width, bottom: height),
          channel,
        ),
    ];
    out.u16(_packBits);
    for (final plane in planes) {
      plane.rowLengths.forEach(out.u16);
    }
    for (final plane in planes) {
      out.bytes(plane.rows);
    }
  }
}

/// A layer's planes, each with its channel id: alpha (-1) first, then red,
/// green, blue — and where its byte sits in an RGBA pixel.
const _layerChannels = [(-1, 3), (0, 0), (1, 1), (2, 2)];

/// The planes of a row that holds no pixels: each just says it is raw, and
/// is empty.
final _emptyChannels = [
  for (final (id, _) in _layerChannels) (id, Uint8List.fromList([0, 0])),
];

const int _rgbMode = 3;
const int _packBits = 1;

/// Record flag: the row is hidden.
const int _hidden = 0x02;

/// Record flags a folder's two rows carry: their pixel data says nothing
/// about how they look (bit 4), and that bit is meant (bit 3).
const int _sectionFlags = 0x18;

/// `lsct` types: a folder shown open, one shown closed, and the hidden
/// record that brackets its members.
const int _openFolder = 1;
const int _closedFolder = 2;
const int _boundingSection = 3;

class _Group {
  _Group({
    required this.name,
    required this.opacity,
    required this.visible,
    required this.blendMode,
    required this.collapsed,
    required this.clipped,
  });

  final String name;
  final double opacity;
  final bool visible;
  final LayerBlendMode blendMode;
  final bool collapsed;
  final bool clipped;
}

typedef _Bounds = ({int left, int top, int right, int bottom});

/// One row of the layer section, its planes already packed.
class _Record {
  _Record({
    required this.name,
    required this.bounds,
    required this.opacity,
    required this.flags,
    required this.blendKey,
    required this.channels,
    this.section,
    this.clipped = false,
  });

  final String name;

  /// Where the row's pixels stand — null for a row with none.
  final _Bounds? bounds;
  final double opacity;
  final int flags;
  final String blendKey;

  /// (channel id, the plane as the file stores it) — its compression tag,
  /// then its data.
  final List<(int, Uint8List)> channels;

  /// The `lsct` type of a folder's row, null for a picture.
  final int? section;

  /// Clipped to the row below it (I-92) — Photoshop's clipping byte, 1 for
  /// a row that is not a base.
  final bool clipped;

  void writeTo(_BigEndian out) {
    final at = bounds;
    out
      ..i32(at?.top ?? 0)
      ..i32(at?.left ?? 0)
      ..i32(at?.bottom ?? 0)
      ..i32(at?.right ?? 0)
      ..u16(channels.length);
    for (final (id, data) in channels) {
      out
        ..i16(id)
        ..u32(data.length);
    }
    out
      ..ascii('8BIM')
      ..ascii(blendKey)
      ..u8((opacity.clamp(0.0, 1.0) * 255).round())
      ..u8(clipped ? 1 : 0)
      ..u8(flags)
      ..u8(0);
    final extra = _extraData();
    out
      ..u32(extra.length)
      ..bytes(extra);
  }

  /// No mask and no blending ranges, the name twice — the Pascal one old
  /// readers take, the unicode one (`luni`) everything since reads — and,
  /// for a folder's row, its `lsct`.
  Uint8List _extraData() {
    final out = _BigEndian()
      ..u32(0)
      ..u32(0)
      ..pascal(name);
    final units = name.codeUnits;
    out
      ..ascii('8BIM')
      ..ascii('luni')
      ..u32(4 + units.length * 2)
      ..u32(units.length);
    units.forEach(out.u16);
    final type = section;
    if (type != null) {
      out
        ..ascii('8BIM')
        ..ascii('lsct')
        ..u32(12)
        ..u32(type)
        ..ascii('8BIM')
        ..ascii(blendKey);
    }
    return out.take();
  }
}

/// A row's picture as a document keeps it ([packPsdLayer]): the box it
/// draws in, and its four planes there, packed — small where the row draws
/// little.
final class PsdLayerPixels {
  PsdLayerPixels._({
    required this.width,
    required this.height,
    required _Bounds? bounds,
    required List<(int, Uint8List)> channels,
  }) : _bounds = bounds,
       _channels = channels;

  /// The size of the picture it was packed from — the document's, or
  /// [PsdBuilder.addLayer] refuses it.
  final int width;
  final int height;

  final _Bounds? _bounds;
  final List<(int, Uint8List)> _channels;
}

/// [picture] — RGBA, its colour not premultiplied — packed as a document
/// keeps a row: only the box it draws in, plane by plane.
///
/// Apart from [PsdBuilder] so it runs where the picture was read: an
/// isolate packs it, and only the planes come back.
PsdLayerPixels packPsdLayer(StillPixels picture) {
  if (picture.channels != 4) {
    throw ArgumentError(
      'A layer is RGBA, not ${picture.channels} channels a pixel.',
    );
  }
  final bounds = _drawnBounds(picture);
  return PsdLayerPixels._(
    width: picture.width,
    height: picture.height,
    bounds: bounds,
    channels: bounds == null
        ? _emptyChannels
        : [
            for (final (id, offset) in _layerChannels)
              (id, _packedChannel(picture, bounds, offset)),
          ],
  );
}

/// Where [picture] holds anything — its alpha above zero — or null when it
/// holds nothing.
_Bounds? _drawnBounds(StillPixels picture) {
  final pixels = picture.pixels;
  var left = picture.width;
  var top = picture.height;
  var right = 0;
  var bottom = 0;
  for (var y = 0; y < picture.height; y += 1) {
    final row = y * picture.width * 4;
    for (var x = 0; x < picture.width; x += 1) {
      if (pixels[row + x * 4 + 3] != 0) {
        left = x < left ? x : left;
        right = x >= right ? x + 1 : right;
        top = y < top ? y : top;
        bottom = y + 1;
      }
    }
  }
  if (right == 0) {
    return null;
  }
  return (left: left, top: top, right: right, bottom: bottom);
}

/// [picture]'s channel at [offset] over [bounds], as a layer's plane is
/// stored: its compression tag, the row lengths, the rows.
Uint8List _packedChannel(StillPixels picture, _Bounds bounds, int offset) {
  final plane = _packPlane(picture, bounds, offset);
  final out = _BigEndian()..u16(_packBits);
  plane.rowLengths.forEach(out.u16);
  return (out..bytes(plane.rows)).take();
}

/// One channel of [picture] — the byte at [offset] of every pixel — over
/// [box], PackBits row by row.
({List<int> rowLengths, Uint8List rows}) _packPlane(
  StillPixels picture,
  _Bounds box,
  int offset,
) {
  final stride = picture.channels;
  final row = Uint8List(box.right - box.left);
  final rowLengths = <int>[];
  final rows = BytesBuilder(copy: false);
  for (var y = box.top; y < box.bottom; y += 1) {
    final start = (y * picture.width + box.left) * stride + offset;
    for (var x = 0; x < row.length; x += 1) {
      row[x] = picture.pixels[start + x * stride];
    }
    final packed = packBitsRow(row);
    rowLengths.add(packed.length);
    rows.add(packed);
  }
  return (rowLengths: rowLengths, rows: rows.takeBytes());
}

/// [row] in PackBits — Apple's run-length code Photoshop packs a plane's
/// rows in, which `decodePackBitsRows` reads back: a header byte `n` below
/// 128 carries the `n + 1` bytes that follow as they are; above it, the one
/// byte that follows stands `257 - n` times.
///
/// Three equal bytes start a run: a run of two costs what two literal bytes
/// do, and breaking a literal stretch for it costs a header more.
///
/// ⚠️The TGA writer packs its rows by the same walk, with its own header
/// and a pixel for a unit (`_tgaRowPackets`) — two of one algorithm, which
/// a third would make one.
Uint8List packBitsRow(Uint8List row) {
  final out = BytesBuilder(copy: false);
  var at = 0;
  while (at < row.length) {
    final run = _runAt(row, at);
    if (run >= 3) {
      out
        ..addByte(257 - run)
        ..addByte(row[at]);
      at += run;
      continue;
    }
    final start = at;
    while (at < row.length && at - start < 128 && _runAt(row, at) < 3) {
      at += 1;
    }
    out
      ..addByte(at - start - 1)
      ..add(Uint8List.sublistView(row, start, at));
  }
  return out.takeBytes();
}

/// How many bytes from [at] equal the one there — 128 at most, a packet's
/// longest.
int _runAt(Uint8List row, int at) {
  var end = at + 1;
  while (end < row.length && end - at < 128 && row[end] == row[at]) {
    end += 1;
  }
  return end - at;
}

/// Bytes, most significant first, as every number in the file is stored.
class _BigEndian {
  final BytesBuilder _out = BytesBuilder(copy: false);

  int get length => _out.length;

  void u8(int value) => _out.addByte(value & 0xFF);

  void u16(int value) => _out
    ..addByte((value >> 8) & 0xFF)
    ..addByte(value & 0xFF);

  void i16(int value) => u16(value & 0xFFFF);

  void u32(int value) => _out
    ..addByte((value >> 24) & 0xFF)
    ..addByte((value >> 16) & 0xFF)
    ..addByte((value >> 8) & 0xFF)
    ..addByte(value & 0xFF);

  void i32(int value) => u32(value & 0xFFFFFFFF);

  void zeros(int count) => _out.add(Uint8List(count));

  void ascii(String text) => _out.add(text.codeUnits);

  void bytes(List<int> data) => _out.add(data);

  /// [text] as a Pascal string — a length byte, then the characters an old
  /// reader can take (anything past ASCII as `?`, 255 at most) — padded so
  /// the whole field is a multiple of four.
  void pascal(String text) {
    final units = [
      for (final unit in text.codeUnits.take(255))
        if (unit < 0x80) unit else 0x3F,
    ];
    _out
      ..addByte(units.length)
      ..add(units);
    final padding = (4 - (units.length + 1) % 4) % 4;
    zeros(padding);
  }

  Uint8List take() => _out.takeBytes();
}
