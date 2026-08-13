import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Photoshop documents, BUILT — the fixtures the PSD tests run on.
///
/// A binary fixture would be easier to produce and impossible to reason
/// about: when a fixture-driven parse test fails you cannot tell whether
/// the parser or the fixture is wrong, and you cannot write the case you
/// actually want (a disabled mask, a 16-bit channel, a `.psb` length
/// field) without Photoshop in the room. Building the bytes means every
/// case is one readable call.


class PsdTestMask {
  PsdTestMask({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.samples,
    this.defaultColor = 0,
    this.disabled = false,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;
  final Uint8List samples;
  final int defaultColor;
  final bool disabled;

  int get width => right - left;
  int get height => bottom - top;
}

class PsdTestLayer {
  PsdTestLayer({
    required this.name,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.planes,
    this.unicodeName,
    this.opacity = 255,
    this.hidden = false,
    this.clipping = false,
    this.blend = 'norm',
    this.sectionType,
    this.adjustment,
    this.alpha,
    this.mask,
    this.compression = 0,
  });

  final String name;
  final String? unicodeName;
  final int left;
  final int top;
  final int right;
  final int bottom;

  /// 8-bit samples per colour channel, row-major over the layer's bounds.
  final List<Uint8List> planes;
  final Uint8List? alpha;
  final int opacity;
  final bool hidden;
  final bool clipping;
  final String blend;
  final int? sectionType;
  final String? adjustment;
  final PsdTestMask? mask;
  final int compression;

  int get width => right - left;
  int get height => bottom - top;
}

List<Uint8List> psdSolidPlanes(int width, int height, List<int> rgb) {
  final count = width * height;
  return [
    for (final value in rgb) Uint8List.fromList(List<int>.filled(count, value)),
  ];
}

class _Bytes {
  final BytesBuilder _builder = BytesBuilder();

  int get length => _builder.length;
  Uint8List get bytes => _builder.toBytes();

  void u8(int value) => _builder.addByte(value & 0xFF);

  void u16(int value) {
    u8(value >> 8);
    u8(value);
  }

  void u32(int value) {
    u8(value >> 24);
    u8(value >> 16);
    u8(value >> 8);
    u8(value);
  }

  void u64(int value) {
    u32(value >> 32);
    u32(value);
  }

  void text(String value) => _builder.add(ascii.encode(value));

  void raw(List<int> value) => _builder.add(value);

  /// A length-prefixed block, the shape most of this format is made of.
  void block(void Function(_Bytes) build, {bool long = false}) {
    final inner = _Bytes();
    build(inner);
    if (long) {
      u64(inner.length);
    } else {
      u32(inner.length);
    }
    raw(inner.bytes);
  }
}

/// One channel's bytes at [depth], with the compression tag in front.
Uint8List _channelBytes(
  Uint8List samples, {
  required int width,
  required int height,
  required int depth,
  required int compression,
  required bool psb,
}) {
  final out = _Bytes()..u16(compression);
  final expanded = depth == 16
      ? (Uint8List(samples.length * 2)
        ..setAll(0, [
          for (final sample in samples) ...[sample, sample],
        ]))
      : samples;
  final bytesPerRow = depth == 16 ? width * 2 : width;
  switch (compression) {
    case 0:
      out.raw(expanded);
    case 1:
      final rows = <Uint8List>[
        for (var y = 0; y < height; y += 1)
          _packBits(
            Uint8List.sublistView(expanded, y * bytesPerRow, (y + 1) * bytesPerRow),
          ),
      ];
      for (final row in rows) {
        if (psb) {
          out.u32(row.length);
        } else {
          out.u16(row.length);
        }
      }
      for (final row in rows) {
        out.raw(row);
      }
    case 2:
      out.raw(ZLibEncoder().convert(expanded));
    default:
      throw ArgumentError('unsupported test compression $compression');
  }
  return out.bytes;
}

/// PackBits, literal runs only — valid output, and the shortest builder that
/// exercises the decoder's literal path.
Uint8List _packBits(Uint8List row) {
  final out = _Bytes();
  var at = 0;
  while (at < row.length) {
    final take = row.length - at > 128 ? 128 : row.length - at;
    out.u8(take - 1);
    out.raw(Uint8List.sublistView(row, at, at + take));
    at += take;
  }
  return out.bytes;
}

Uint8List buildPsd({
  required int width,
  required int height,
  int channels = 3,
  int depth = 8,
  int mode = 3,
  bool psb = false,
  bool mergedAlpha = false,
  bool rleComposite = false,
  List<PsdTestLayer> layers = const [],
  List<Uint8List>? compositePlanes,
}) {
  final file = _Bytes()
    ..text('8BPS')
    ..u16(psb ? 2 : 1)
    ..raw(Uint8List(6))
    ..u16(channels)
    ..u32(height)
    ..u32(width)
    ..u16(depth)
    ..u16(mode)
    ..u32(0) // Colour mode data.
    ..u32(0); // Image resources.

  // Layer and mask information.
  file.block(long: psb, (layerMask) {
    if (layers.isEmpty) {
      return;
    }
    layerMask.block(long: psb, (layerInfo) {
      layerInfo.u16(
        mergedAlpha ? (0x10000 - layers.length) : layers.length,
      );
      for (final layer in layers) {
        _writeLayerRecord(layerInfo, layer, depth: depth, psb: psb);
      }
      for (final layer in layers) {
        layerInfo.raw(_layerChannelBytes(layer, depth: depth, psb: psb));
      }
    });
    layerMask.u32(0); // Global layer mask info.
  });

  if (compositePlanes != null) {
    file.u16(rleComposite ? 1 : 0);
    if (rleComposite) {
      final rows = <Uint8List>[];
      final bytesPerRow = depth == 16 ? width * 2 : width;
      for (final plane in compositePlanes) {
        final expanded = depth == 16
            ? (Uint8List(plane.length * 2)
              ..setAll(0, [
                for (final sample in plane) ...[sample, sample],
              ]))
            : plane;
        for (var y = 0; y < height; y += 1) {
          rows.add(
            _packBits(
              Uint8List.sublistView(
                expanded,
                y * bytesPerRow,
                (y + 1) * bytesPerRow,
              ),
            ),
          );
        }
      }
      for (final row in rows) {
        if (psb) {
          file.u32(row.length);
        } else {
          file.u16(row.length);
        }
      }
      for (final row in rows) {
        file.raw(row);
      }
    } else {
      for (final plane in compositePlanes) {
        if (depth == 16) {
          for (final sample in plane) {
            file.u8(sample);
            file.u8(sample);
          }
        } else {
          file.raw(plane);
        }
      }
    }
  }
  return file.bytes;
}

void _writeLayerRecord(
  _Bytes out,
  PsdTestLayer layer, {
  required int depth,
  required bool psb,
}) {
  out
    ..u32(layer.top)
    ..u32(layer.left)
    ..u32(layer.bottom)
    ..u32(layer.right);
  final channelIds = <int>[
    if (layer.alpha != null) -1,
    for (var i = 0; i < layer.planes.length; i += 1) i,
    if (layer.mask != null) -2,
  ];
  out.u16(channelIds.length);
  for (final id in channelIds) {
    out.u16(id < 0 ? 0x10000 + id : id);
    final bytes = _channelForId(layer, id, depth: depth, psb: psb);
    if (psb) {
      out.u64(bytes.length);
    } else {
      out.u32(bytes.length);
    }
  }
  out
    ..text('8BIM')
    ..text(layer.blend)
    ..u8(layer.opacity)
    ..u8(layer.clipping ? 1 : 0)
    ..u8(layer.hidden ? 0x02 : 0x00)
    ..u8(0);
  out.block((extra) {
    final mask = layer.mask;
    if (mask == null) {
      extra.u32(0);
    } else {
      extra.block((maskBlock) {
        maskBlock
          ..u32(mask.top)
          ..u32(mask.left)
          ..u32(mask.bottom)
          ..u32(mask.right)
          ..u8(mask.defaultColor)
          ..u8(mask.disabled ? 0x02 : 0x00)
          ..u16(0); // Padding to the 20-byte shape Photoshop writes.
      });
    }
    extra.u32(0); // Blending ranges.
    // Pascal name, padded so the field is a multiple of four.
    final nameBytes = ascii.encode(layer.name);
    extra.u8(nameBytes.length);
    extra.raw(nameBytes);
    final padding = (4 - ((nameBytes.length + 1) % 4)) % 4;
    extra.raw(Uint8List(padding));
    final unicodeName = layer.unicodeName;
    if (unicodeName != null) {
      extra
        ..text('8BIM')
        ..text('luni');
      extra.block((block) {
        block.u32(unicodeName.length + 1);
        for (final unit in unicodeName.codeUnits) {
          block.u16(unit);
        }
        block.u16(0);
      });
    }
    final section = layer.sectionType;
    if (section != null) {
      extra
        ..text('8BIM')
        ..text('lsct');
      extra.block((block) => block.u32(section));
    }
    final adjustment = layer.adjustment;
    if (adjustment != null) {
      extra
        ..text('8BIM')
        ..text(adjustment);
      extra.block((block) => block.u32(0));
    }
  });
}

Uint8List _channelForId(
  PsdTestLayer layer,
  int id, {
  required int depth,
  required bool psb,
}) {
  if (id == -1) {
    return _channelBytes(
      layer.alpha!,
      width: layer.width,
      height: layer.height,
      depth: depth,
      compression: layer.compression,
      psb: psb,
    );
  }
  if (id == -2) {
    final mask = layer.mask!;
    return _channelBytes(
      mask.samples,
      width: mask.width,
      height: mask.height,
      depth: depth,
      compression: layer.compression,
      psb: psb,
    );
  }
  return _channelBytes(
    layer.planes[id],
    width: layer.width,
    height: layer.height,
    depth: depth,
    compression: layer.compression,
    psb: psb,
  );
}

Uint8List _layerChannelBytes(
  PsdTestLayer layer, {
  required int depth,
  required bool psb,
}) {
  final out = _Bytes();
  if (layer.alpha != null) {
    out.raw(_channelForId(layer, -1, depth: depth, psb: psb));
  }
  for (var i = 0; i < layer.planes.length; i += 1) {
    out.raw(_channelForId(layer, i, depth: depth, psb: psb));
  }
  if (layer.mask != null) {
    out.raw(_channelForId(layer, -2, depth: depth, psb: psb));
  }
  return out.bytes;
}
