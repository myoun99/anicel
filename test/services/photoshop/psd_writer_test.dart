import 'dart:typed_data';

import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/services/media/still_file_writing.dart'
    show StillPixels;
import 'package:anicel/src/services/photoshop/photoshop_byte_reader.dart';
import 'package:anicel/src/services/photoshop/psd_reader.dart';
import 'package:anicel/src/services/photoshop/psd_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The Photoshop documents the export window writes (I-117), read back by
/// the app's own reader — the import's, which every file written here must
/// pass whole — and by one that is not ours (the `image` package's).
void main() {
  const width = 8;
  const height = 6;

  /// A transparent RGBA picture at the document's size with [paint] laid
  /// on: each (x, y) → its RGBA.
  StillPixels picture(Map<(int, int), List<int>> paint) {
    final pixels = Uint8List(width * height * 4);
    for (final MapEntry(key: (x, y), value: rgba) in paint.entries) {
      pixels.setAll((y * width + x) * 4, rgba);
    }
    return (pixels: pixels, width: width, height: height, channels: 4);
  }

  StillPixels filled(List<int> rgba) => picture({
    for (var y = 0; y < height; y += 1)
      for (var x = 0; x < width; x += 1) (x, y): rgba,
  });

  const red = [200, 10, 10, 255];
  const blue = [10, 20, 220, 255];
  const green = [10, 200, 30, 128];

  /// Ground, then a pass-through folder of a hidden multiply row at half
  /// strength and an empty one, then a row over it all.
  Uint8List document() {
    final builder = PsdBuilder(width: width, height: height)
      ..addLayer(name: 'Ground', picture: filled(red))
      ..openGroup(name: 'フォルダ 1')
      ..addLayer(
        name: '선화 A',
        picture: picture({
          (3, 2): blue,
          (4, 2): blue,
          (3, 3): blue,
          (4, 3): blue,
        }),
        opacity: 0.5,
        visible: false,
        blendMode: LayerBlendMode.multiply,
      )
      ..addLayer(name: 'Empty', picture: picture({}))
      ..closeGroup()
      ..addLayer(name: 'Top', picture: picture({(7, 5): green}));
    return builder.build(composite: filled(red));
  }

  test('reads back through the app\'s own reader, row for row: the folder '
      'brackets its members, and every name, mode, strength and eye is '
      'what was written', () {
    final read = readPsdDocument(document());

    expect((read.width, read.height), (width, height));
    expect(
      [for (final layer in read.layers) (layer.name, layer.role)],
      [
        ('Ground', PsdLayerRole.raster),
        ('</Layer group>', PsdLayerRole.groupClose),
        ('선화 A', PsdLayerRole.raster),
        ('Empty', PsdLayerRole.raster),
        ('フォルダ 1', PsdLayerRole.groupOpen),
        ('Top', PsdLayerRole.raster),
      ],
      reason: 'bottom-first, the names unicode (`luni`)',
    );
    final line = read.layers[2];
    expect(
      (line.blendKey, line.opacity, line.visible),
      ('mul ', 128, false),
    );
    expect(read.layers[4].blendKey, 'pass', reason: 'Photoshop\'s 「통과」');
    expect(read.warnings, isEmpty);
  });

  test('a row is stored where it holds anything, and nowhere else — its '
      'pixels at their place', () {
    final read = readPsdDocument(document());
    final line = read.layers[2];

    expect(
      (line.left, line.top, line.right, line.bottom),
      (3, 2, 5, 4),
    );
    expect(line.pixels, [for (var i = 0; i < 4; i += 1) ...blue]);
    final top = read.layers[5];
    expect((top.left, top.top, top.right, top.bottom), (7, 5, 8, 6));
    expect(top.pixels, green);
    final empty = read.layers[3];
    expect(empty.right - empty.left, 0);
    expect(
      empty.pixels,
      isNull,
      reason: 'a row with nothing in it is stored as nothing',
    );
  });

  test('the composite is the picture handed in, its alpha the fourth '
      'channel', () {
    final read = readPsdDocument(document());

    expect(read.composite, filled(red).pixels);
  });

  test('a reader that is not ours takes it too — the same rows, at the same '
      'places, with the same pixels and eyes', () {
    // `decodePsd` decodes, and is null where it cannot.
    final psd = img.PsdDecoder().decodePsd(document());
    expect(psd, isNotNull);

    expect(psd!.layers, hasLength(6));
    final line = psd.layers[2];
    expect(
      (line.left, line.top, line.width, line.height, line.isVisible()),
      (3, 2, 2, 2, false),
    );
    final pixel = line.layerImage!.getPixel(1, 1);
    expect(
      [pixel.r, pixel.g, pixel.b, pixel.a].map((c) => c.toInt()),
      blue,
    );
  });

  test('a folder shown closed is written closed', () {
    final bytes =
        (PsdBuilder(width: width, height: height)
              ..openGroup(name: 'Shut', collapsed: true)
              ..addLayer(name: 'Inside', picture: filled(blue))
              ..closeGroup())
            .build(composite: filled(blue));

    expect(readPsdDocument(bytes).layers.last.collapsed, isTrue);
  });

  group('refused', () {
    test('a folder left open', () {
      final builder = PsdBuilder(width: width, height: height)
        ..openGroup(name: 'Open');
      expect(
        () => builder.build(composite: filled(red)),
        throwsStateError,
      );
    });

    test('a row not at the document\'s size', () {
      expect(
        () => PsdBuilder(width: width + 1, height: height).addLayer(
          name: 'Wrong',
          picture: filled(red),
        ),
        throwsArgumentError,
      );
    });

    test('a side past what a Photoshop document can name', () {
      expect(
        () => PsdBuilder(width: psdMaxSide + 1, height: 1),
        throwsArgumentError,
      );
    });
  });

  group('PackBits', () {
    /// [row] packed, then unpacked by the reader's own decoder.
    Uint8List roundTrip(List<int> row) {
      final packed = packBitsRow(Uint8List.fromList(row));
      return decodePackBitsRows(
        PhotoshopByteReader(packed),
        rowLengths: [packed.length],
        bytesPerRow: row.length,
      );
    }

    test('three equal bytes start a run; two stay in the literal', () {
      expect(packBitsRow(Uint8List.fromList([5, 5, 5])), [254, 5]);
      expect(packBitsRow(Uint8List.fromList([5, 5, 9])), [2, 5, 5, 9]);
    });

    test('a run past 128 is two packets, as is a literal stretch', () {
      final run = List.filled(200, 7);
      expect(packBitsRow(Uint8List.fromList(run)), [129, 7, 185, 7]);
      expect(roundTrip(run), run);

      final mixed = [for (var i = 0; i < 300; i += 1) i % 2];
      expect(roundTrip(mixed), mixed);
      final stretched = [...mixed.take(130), ...List.filled(9, 3), 1, 2];
      expect(roundTrip(stretched), stretched);
    });
  });
}
