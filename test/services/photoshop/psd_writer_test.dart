import 'dart:typed_data';

import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/services/media/still_file_writing.dart'
    show StillPixels;
import 'package:anicel/src/services/photoshop/photoshop_byte_reader.dart';
import 'package:anicel/src/services/photoshop/psd_blend_modes.dart';
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

  /// A blank picture of [channels] at [w]×[h].
  StillPixels blank(int w, int h, int channels) => (
    pixels: Uint8List(w * h * channels),
    width: w,
    height: h,
    channels: channels,
  );

  const red = [200, 10, 10, 255];
  const blue = [10, 20, 220, 255];
  const green = [10, 200, 30, 128];
  const yellow = [250, 210, 0, 255];

  /// Ground, then a pass-through folder of a hidden multiply row at half
  /// strength and an empty one, then a row over it all.
  Uint8List document() {
    final builder = PsdBuilder(width: width, height: height)
      ..addLayer(name: 'Ground', pixels: packPsdLayer(filled(red)))
      ..openGroup(name: 'フォルダ 1')
      ..addLayer(
        name: '선화 A',
        pixels: packPsdLayer(
          picture({
            (3, 2): blue,
            (4, 2): blue,
            (3, 3): blue,
            (4, 3): blue,
          }),
        ),
        opacity: 0.5,
        visible: false,
        blendMode: LayerBlendMode.multiply,
      )
      ..addLayer(name: 'Empty', pixels: packPsdLayer(picture({})))
      ..closeGroup()
      ..addLayer(name: 'Top', pixels: packPsdLayer(picture({(7, 5): green})));
    return builder.build(composite: filled(red));
  }

  /// One row of [picture] in a document of its own, over [picture].
  Uint8List oneRow(String name, StillPixels picture, {double opacity = 1}) {
    final builder = PsdBuilder(width: width, height: height)
      ..addLayer(name: name, pixels: packPsdLayer(picture), opacity: opacity);
    return builder.build(composite: picture);
  }

  test('a row and a folder clipped to the one under them are written with '
      'Photoshop\'s clipping byte, and nothing else is (I-92)', () {
    final builder = PsdBuilder(width: width, height: height)
      ..addLayer(name: 'Base', pixels: packPsdLayer(filled(red)))
      ..addLayer(
        name: 'Shade',
        pixels: packPsdLayer(picture({(1, 1): blue})),
        clipped: true,
      )
      ..openGroup(name: 'Glow', clipped: true)
      ..addLayer(name: 'Inside', pixels: packPsdLayer(picture({(2, 2): blue})))
      ..closeGroup();
    final read = readPsdDocument(builder.build(composite: filled(red)));

    expect(
      [for (final layer in read.layers) (layer.name, layer.clipping)],
      [
        ('Base', false),
        ('Shade', true),
        ('</Layer group>', false),
        ('Inside', false),
        ('Glow', true),
      ],
    );
  });

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
    final folder = read.layers[4];
    expect(folder.blendKey, 'pass', reason: 'Photoshop\'s 「통과」');
    expect(folder.collapsed, isFalse, reason: 'shown open unless asked shut');
    expect(
      [for (final layer in read.layers) layer.clipping],
      everyElement(isFalse),
      reason: 'no row is clipped to the one below it',
    );
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

  test('a row\'s box is its drawn pixels\' box — drawn by their alpha, '
      'wherever the scan meets the last of them', () {
    final two = readPsdDocument(
      oneRow('Two', picture({(5, 1): yellow, (2, 3): blue})),
    ).layers.single;

    expect((two.left, two.top, two.right, two.bottom), (2, 1, 6, 4));
  });

  test('the composite is the picture handed in, its alpha the fourth '
      'channel — and the count of rows says that channel is its '
      'transparency', () {
    final seen = picture({(1, 1): green, (6, 4): blue});

    expect(
      readPsdDocument(oneRow('Only', seen)).composite,
      seen.pixels,
      reason: 'a fourth channel the count does not claim is read opaque',
    );
    expect(readPsdDocument(document()).composite, filled(red).pixels);
  });

  test('a composite with no alpha is three channels, and the count of rows '
      'claims no transparency', () {
    final rgb = blank(width, height, 3);
    for (var i = 0; i < rgb.pixels.length; i += 3) {
      rgb.pixels.setAll(i, [1, 2, 3]);
    }
    final builder = PsdBuilder(width: width, height: height)
      ..addLayer(name: 'Only', pixels: packPsdLayer(filled(red)));
    final bytes = builder.build(composite: rgb);

    expect(readPsdDocument(bytes).composite, [
      for (var i = 0; i < width * height; i += 1) ...[1, 2, 3, 255],
    ]);
    expect(img.PsdDecoder().decodePsd(bytes)!.hasAlpha, isFalse);
  });

  test('a layer section of odd length is padded to two, as the format '
      'counts it', () {
    // A line whose colour planes pack to five bytes a row and whose alpha
    // to two: the section comes out odd.
    final bytes = oneRow(
      'Line',
      picture({
        (0, 0): [1, 5, 9, 255],
        (1, 0): [2, 6, 10, 255],
        (2, 0): [3, 7, 11, 255],
        (3, 0): [4, 8, 12, 255],
      }),
    );

    // Past the header (26), the palette's and the resources' lengths (8)
    // and the layer and mask section's (4): the layer section's length.
    expect(ByteData.sublistView(bytes).getUint32(38).isEven, isTrue);
    final pixel = img.PsdDecoder()
        .decodePsd(bytes)!
        .layers
        .single
        .layerImage!
        .getPixel(3, 0);
    expect(
      [pixel.r, pixel.g, pixel.b, pixel.a].map((c) => c.toInt()),
      [4, 8, 12, 255],
    );
  });

  test('a reader that is not ours takes it too — the same rows, at the same '
      'places, with the same pixels and eyes', () {
    // `decodePsd` decodes, and is null where it cannot.
    final psd = img.PsdDecoder().decodePsd(document());
    expect(psd, isNotNull);

    expect(psd!.layers, hasLength(6));
    expect(psd.hasAlpha, isTrue, reason: 'the composite\'s alpha is merged');
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
    expect(
      [psd.layers[1].flags & 0x18, psd.layers[4].flags & 0x18],
      [0x18, 0x18],
      reason: 'a folder\'s two records say their pixels are nothing to the '
          'picture, as Photoshop writes them',
    );
  });

  test('a folder that hides, fades and buffers is written so', () {
    final folder = readPsdDocument(
      (PsdBuilder(width: width, height: height)
            ..openGroup(
              name: 'Box',
              opacity: 0.25,
              visible: false,
              blendMode: LayerBlendMode.normal,
            )
            ..addLayer(name: 'Inside', pixels: packPsdLayer(filled(blue)))
            ..closeGroup())
          .build(composite: filled(blue)),
    ).layers.last;

    expect(
      (folder.role, folder.blendKey, folder.opacity, folder.visible),
      (PsdLayerRole.groupOpen, 'norm', 64, false),
    );
  });

  test('a folder shown closed is written closed', () {
    final bytes =
        (PsdBuilder(width: width, height: height)
              ..openGroup(name: 'Shut', collapsed: true)
              ..addLayer(name: 'Inside', pixels: packPsdLayer(filled(blue)))
              ..closeGroup())
            .build(composite: filled(blue));

    expect(readPsdDocument(bytes).layers.last.collapsed, isTrue);
  });

  test('a folder\'s section block is the twelve bytes its blend rides in, '
      'and its length says so — a reader walks the blocks by it', () {
    final bytes =
        (PsdBuilder(width: width, height: height)
              ..openGroup(name: 'Box', blendMode: LayerBlendMode.multiply)
              ..addLayer(name: 'Inside', pixels: packPsdLayer(filled(blue)))
              ..closeGroup())
            .build(composite: filled(blue));
    String ascii(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
    final blocks = [
      for (var at = 0; at + 4 <= bytes.length; at += 1)
        if (ascii(at) == 'lsct') at,
    ];

    expect(blocks, hasLength(2), reason: 'the folder\'s end, and the folder');
    for (final at in blocks) {
      expect(ByteData.sublistView(bytes).getUint32(at + 4), 12);
      expect(ascii(at + 12), '8BIM');
    }
    expect(ascii(blocks.last + 16), 'mul ');
  });

  test('every blend the app has is one Photoshop has, and reads back as '
      'itself', () {
    for (final mode in LayerBlendMode.values) {
      expect(psdBlendModes[psdBlendKeyOf(mode)], mode);
    }
  });

  test('a name is whole in the unicode name; in the short one — all a reader '
      'that knows no other takes — 「?」 stands for each letter past ASCII, '
      'and it stops at 255', () {
    final long = 'n' * 300;
    final bytes = (PsdBuilder(width: width, height: height)
          ..addLayer(name: '선화 A', pixels: packPsdLayer(filled(red)))
          ..addLayer(name: long, pixels: packPsdLayer(filled(red))))
        .build(composite: filled(red));

    expect(
      [for (final layer in readPsdDocument(bytes).layers) layer.name],
      ['선화 A', long],
    );
    final theirs = img.PsdDecoder().decodePsd(bytes)!;
    expect(
      [for (final layer in theirs.layers) layer.name],
      ['?? A', 'n' * 255],
    );
  });

  test('a strength a hair past full is full, not wrapped round to none', () {
    expect(
      readPsdDocument(
        oneRow('Full', filled(red), opacity: 1.002),
      ).layers.single.opacity,
      255,
    );
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

    test('a folder closed that was never opened', () {
      expect(
        () => PsdBuilder(width: width, height: height).closeGroup(),
        throwsStateError,
      );
    });

    test('a picture that is not RGBA — said so, not run off its end', () {
      expect(
        () => packPsdLayer(blank(width, height, 3)),
        throwsA(allOf(isArgumentError, isNot(isRangeError))),
      );
    });

    test('a row that is not at the document\'s size', () {
      final builder = PsdBuilder(width: width, height: height);
      for (final row in [
        blank(width + 1, height, 4),
        blank(width, height + 1, 4),
      ]) {
        expect(
          () => builder.addLayer(name: 'Wrong', pixels: packPsdLayer(row)),
          throwsArgumentError,
        );
      }
    });

    test('a composite that is not RGB or RGBA at the document\'s size', () {
      for (final composite in [
        blank(width + 1, height, 4),
        blank(width, height + 1, 3),
        blank(width, height, 2),
      ]) {
        final builder = PsdBuilder(width: width, height: height);
        expect(() => builder.build(composite: composite), throwsArgumentError);
      }
    });

    test('a side of nothing, or past what a Photoshop document can name', () {
      for (final (w, h) in [
        (0, 1),
        (1, 0),
        (psdMaxSide + 1, 1),
        (1, psdMaxSide + 1),
      ]) {
        expect(() => PsdBuilder(width: w, height: h), throwsArgumentError);
      }
      expect(
        PsdBuilder(width: psdMaxSide, height: psdMaxSide).width,
        psdMaxSide,
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
