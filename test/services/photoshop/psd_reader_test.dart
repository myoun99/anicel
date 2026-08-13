import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/photoshop/psd_pixels.dart';
import 'package:anicel/src/services/photoshop/psd_reader.dart';

/// The document reader, exercised against documents this file BUILDS.
///
/// A binary fixture would have been easier to produce and impossible to
/// reason about: when a fixture-driven parse test fails you cannot tell
/// whether the parser or the fixture is wrong, and you cannot write the case
/// you actually want (a disabled mask, a 16-bit channel, a `.psb` length
/// field) without Photoshop in the room. Building the bytes here means every
/// case is one readable call, and the builder itself is checked by the
/// straightforward cases passing.
void main() {
  group('signature', () {
    test('recognises a document and refuses anything else', () {
      expect(looksLikePsdBytes(_document(width: 1, height: 1)), isTrue);
      expect(
        looksLikePsdBytes(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])),
        isFalse,
      );
      expect(looksLikePsdBytes(Uint8List(2)), isFalse);
    });

    test('a PNG handed to the reader is refused, not misread', () {
      expect(
        () => readPsdDocument(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0])),
        throwsFormatException,
      );
    });
  });

  group('composite', () {
    test('raw RGB arrives as opaque RGBA', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 2,
          compositePlanes: [
            Uint8List.fromList([10, 20, 30, 40]),
            Uint8List.fromList([50, 60, 70, 80]),
            Uint8List.fromList([90, 100, 110, 120]),
          ],
        ),
      );
      expect(document.width, 2);
      expect(document.height, 2);
      expect(document.colorMode, PsdColorMode.rgb);
      expect(document.composite, isNotNull);
      expect(document.composite!.sublist(0, 8), [
        10, 50, 90, 255, //
        20, 60, 100, 255,
      ]);
    });

    test('RLE and raw produce the same picture', () {
      final planes = [
        Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        Uint8List.fromList([7, 8, 9, 10, 11, 12]),
        Uint8List.fromList([13, 14, 15, 16, 17, 18]),
      ];
      final raw = readPsdDocument(
        _document(width: 3, height: 2, compositePlanes: planes),
      );
      final rle = readPsdDocument(
        _document(
          width: 3,
          height: 2,
          compositePlanes: planes,
          rleComposite: true,
        ),
      );
      expect(rle.composite, raw.composite);
    });

    test('a fourth channel is transparency only when the file says so', () {
      final planes = [
        Uint8List.fromList([255, 255]),
        Uint8List.fromList([255, 255]),
        Uint8List.fromList([255, 255]),
        Uint8List.fromList([0, 128]),
      ];
      // No layer section: the spot-channel reading, so the picture is opaque.
      final opaque = readPsdDocument(
        _document(
          width: 2,
          height: 1,
          channels: 4,
          compositePlanes: planes,
        ),
      );
      expect(opaque.composite![3], 255);
      expect(opaque.composite![7], 255);

      // A NEGATIVE layer count is Photoshop saying the first extra channel
      // IS the merged transparency. The count lives in the layer section,
      // so a document making that claim has one.
      final transparent = readPsdDocument(
        _document(
          width: 2,
          height: 1,
          channels: 4,
          compositePlanes: planes,
          mergedAlpha: true,
          layers: [
            _TestLayer(
              name: 'only',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: _solid(2, 1, [255, 255, 255]),
              alpha: Uint8List.fromList([0, 128]),
            ),
          ],
        ),
      );
      expect(transparent.composite![3], 0);
      expect(transparent.composite![7], 128);
    });

    test('16-bit steps down to 8 and says so', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 1,
          depth: 16,
          compositePlanes: [
            Uint8List.fromList([0, 255]),
            Uint8List.fromList([64, 128]),
            Uint8List.fromList([32, 16]),
          ],
        ),
      );
      expect(document.composite!.sublist(0, 8), [
        0, 64, 32, 255, //
        255, 128, 16, 255,
      ]);
      expect(document.warnings, contains('16-bit document stepped down to 8-bit.'));
    });

    test('grayscale fills all three channels', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 1,
          channels: 1,
          mode: PsdColorMode.grayscale.code,
          compositePlanes: [
            Uint8List.fromList([12, 200]),
          ],
        ),
      );
      expect(document.composite, [12, 12, 12, 255, 200, 200, 200, 255]);
    });

    test('CMYK converts and warns rather than refusing', () {
      // Photoshop stores CMYK inverted: 255 is no ink. Pure cyan is then
      // c=0, m=y=k=255.
      final document = readPsdDocument(
        _document(
          width: 1,
          height: 1,
          channels: 4,
          mode: PsdColorMode.cmyk.code,
          compositePlanes: [
            Uint8List.fromList([0]),
            Uint8List.fromList([255]),
            Uint8List.fromList([255]),
            Uint8List.fromList([255]),
          ],
        ),
      );
      expect(document.composite!.sublist(0, 4), [0, 255, 255, 255]);
      expect(
        document.warnings.any((warning) => warning.startsWith('CMYK')),
        isTrue,
      );
    });

    test('the composite can be skipped when only the structure is wanted', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 2,
          compositePlanes: [
            Uint8List(4),
            Uint8List(4),
            Uint8List(4),
          ],
        ),
        withComposite: false,
      );
      expect(document.composite, isNull);
      expect(document.width, 2);
    });
  });

  group('layers', () {
    test('bounds, name, opacity, visibility and blend come through', () {
      final document = readPsdDocument(
        _document(
          width: 4,
          height: 4,
          layers: [
            _TestLayer(
              name: 'BG',
              left: 1,
              top: 2,
              right: 3,
              bottom: 4,
              opacity: 128,
              hidden: true,
              blend: 'mul ',
              planes: _solid(2, 2, [10, 20, 30]),
            ),
          ],
        ),
      );
      expect(document.layers, hasLength(1));
      final layer = document.layers.single;
      expect(layer.name, 'BG');
      expect(layer.left, 1);
      expect(layer.top, 2);
      expect(layer.width, 2);
      expect(layer.height, 2);
      expect(layer.opacity, 128);
      expect(layer.visible, isFalse);
      expect(layer.blendKey, 'mul ');
      expect(layer.hasPixels, isTrue);
      expect(layer.pixels!.sublist(0, 4), [10, 20, 30, 255]);
    });

    test('the unicode name wins over the truncated Pascal one', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 2,
          layers: [
            _TestLayer(
              name: 'ascii-only',
              unicodeName: '原画A',
              left: 0,
              top: 0,
              right: 2,
              bottom: 2,
              planes: _solid(2, 2, [1, 2, 3]),
            ),
          ],
        ),
      );
      expect(document.layers.single.name, '原画A');
    });

    test('alpha rides in on channel -1', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 1,
          layers: [
            _TestLayer(
              name: 'a',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: _solid(2, 1, [200, 200, 200]),
              alpha: Uint8List.fromList([255, 0]),
            ),
          ],
        ),
      );
      final pixels = document.layers.single.pixels!;
      expect(pixels[3], 255);
      expect(pixels[7], 0);
    });

    test('a group is a folder row above the members it brackets', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 2,
          layers: [
            _TestLayer(
              name: '</Layer group>',
              left: 0,
              top: 0,
              right: 0,
              bottom: 0,
              sectionType: 3,
              planes: const [],
            ),
            _TestLayer(
              name: 'inside',
              left: 0,
              top: 0,
              right: 2,
              bottom: 2,
              planes: _solid(2, 2, [9, 9, 9]),
            ),
            _TestLayer(
              name: 'BOOK',
              left: 0,
              top: 0,
              right: 0,
              bottom: 0,
              sectionType: 1,
              blend: 'pass',
              planes: const [],
            ),
          ],
        ),
      );
      expect(
        document.layers.map((layer) => layer.role).toList(),
        [PsdLayerRole.groupClose, PsdLayerRole.raster, PsdLayerRole.groupOpen],
      );
      expect(document.layers.last.name, 'BOOK');
      expect(document.layers.last.isPassThrough, isTrue);
      expect(document.layers.last.hasPixels, isFalse);
    });

    test('an adjustment layer is named rather than mistaken for a picture', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 2,
          layers: [
            _TestLayer(
              name: 'Curves 1',
              left: 0,
              top: 0,
              right: 0,
              bottom: 0,
              adjustment: 'curv',
              planes: const [],
            ),
          ],
        ),
      );
      expect(document.layers.single.adjustmentKey, 'curv');
      expect(document.layers.single.hasPixels, isFalse);
    });

    test('clipping is carried even though nothing maps it yet', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 2,
          layers: [
            _TestLayer(
              name: 'colour',
              left: 0,
              top: 0,
              right: 2,
              bottom: 2,
              clipping: true,
              planes: _solid(2, 2, [1, 1, 1]),
            ),
          ],
        ),
      );
      expect(document.layers.single.clipping, isTrue);
    });

    test('zip-compressed channels read the same as raw ones', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 2,
          layers: [
            _TestLayer(
              name: 'zipped',
              left: 0,
              top: 0,
              right: 2,
              bottom: 2,
              compression: 2,
              planes: [
                Uint8List.fromList([1, 2, 3, 4]),
                Uint8List.fromList([5, 6, 7, 8]),
                Uint8List.fromList([9, 10, 11, 12]),
              ],
            ),
          ],
        ),
      );
      expect(document.layers.single.pixels!.sublist(0, 8), [
        1, 5, 9, 255, //
        2, 6, 10, 255,
      ]);
    });

    test('layers can be skipped when only the picture is wanted', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 2,
          layers: [
            _TestLayer(
              name: 'a',
              left: 0,
              top: 0,
              right: 2,
              bottom: 2,
              planes: _solid(2, 2, [1, 2, 3]),
            ),
          ],
          compositePlanes: [Uint8List(4), Uint8List(4), Uint8List(4)],
        ),
        withLayers: false,
      );
      expect(document.layers, isEmpty);
      expect(document.composite, isNotNull);
    });
  });

  group('layer masks', () {
    test('a mask multiplies into alpha', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 1,
          layers: [
            _TestLayer(
              name: 'masked',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: _solid(2, 1, [255, 255, 255]),
              mask: _TestMask(
                left: 0,
                top: 0,
                right: 2,
                bottom: 1,
                samples: Uint8List.fromList([255, 0]),
              ),
            ),
          ],
        ),
      );
      final pixels = document.layers.single.pixels!;
      expect(pixels[3], 255);
      expect(pixels[7], 0);
    });

    test('a DISABLED mask is left alone', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 1,
          layers: [
            _TestLayer(
              name: 'masked',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: _solid(2, 1, [255, 255, 255]),
              mask: _TestMask(
                left: 0,
                top: 0,
                right: 2,
                bottom: 1,
                samples: Uint8List.fromList([255, 0]),
                disabled: true,
              ),
            ),
          ],
        ),
      );
      expect(document.layers.single.pixels![7], 255);
    });

    test('outside the mask rectangle the default colour rules', () {
      // The mask covers only the left pixel; its default is black, so the
      // right pixel is hidden even though no mask sample describes it.
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 1,
          layers: [
            _TestLayer(
              name: 'masked',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: _solid(2, 1, [255, 255, 255]),
              mask: _TestMask(
                left: 0,
                top: 0,
                right: 1,
                bottom: 1,
                samples: Uint8List.fromList([255]),
                defaultColor: 0,
              ),
            ),
          ],
        ),
      );
      final pixels = document.layers.single.pixels!;
      expect(pixels[3], 255);
      expect(pixels[7], 0);
    });
  });

  group('psb', () {
    test('the large format reads through the same path', () {
      final document = readPsdDocument(
        _document(
          width: 2,
          height: 1,
          psb: true,
          layers: [
            _TestLayer(
              name: 'big',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: _solid(2, 1, [7, 8, 9]),
            ),
          ],
          compositePlanes: [
            Uint8List.fromList([7, 7]),
            Uint8List.fromList([8, 8]),
            Uint8List.fromList([9, 9]),
          ],
        ),
      );
      expect(document.isPsb, isTrue);
      expect(document.layers.single.name, 'big');
      expect(document.layers.single.pixels!.sublist(0, 4), [7, 8, 9, 255]);
      expect(document.composite!.sublist(0, 4), [7, 8, 9, 255]);
    });
  });
}

// --- The document builder ------------------------------------------------

class _TestMask {
  _TestMask({
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

class _TestLayer {
  _TestLayer({
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
  final _TestMask? mask;
  final int compression;

  int get width => right - left;
  int get height => bottom - top;
}

List<Uint8List> _solid(int width, int height, List<int> rgb) {
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

Uint8List _document({
  required int width,
  required int height,
  int channels = 3,
  int depth = 8,
  int mode = 3,
  bool psb = false,
  bool mergedAlpha = false,
  bool rleComposite = false,
  List<_TestLayer> layers = const [],
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
  _TestLayer layer, {
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
  _TestLayer layer,
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
  _TestLayer layer, {
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
