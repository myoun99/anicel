import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/photoshop/psd_pixels.dart';
import 'package:anicel/src/services/photoshop/psd_reader.dart';

import '../../helpers/psd_fixture.dart';

/// The document reader, exercised against documents the fixture BUILDS.
///
/// The builder moved to `test/helpers/psd_fixture.dart` when the expansion
/// tests needed the same documents; it explains there why these are built
/// rather than checked in as bytes.
void main() {
  group('signature', () {
    test('recognises a document and refuses anything else', () {
      expect(looksLikePsdBytes(buildPsd(width: 1, height: 1)), isTrue);
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
        buildPsd(
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
        buildPsd(width: 3, height: 2, compositePlanes: planes),
      );
      final rle = readPsdDocument(
        buildPsd(
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
        buildPsd(
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
        buildPsd(
          width: 2,
          height: 1,
          channels: 4,
          compositePlanes: planes,
          mergedAlpha: true,
          layers: [
            PsdTestLayer(
              name: 'only',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: psdSolidPlanes(2, 1, [255, 255, 255]),
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
        buildPsd(
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
        buildPsd(
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
        buildPsd(
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
        buildPsd(
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
        buildPsd(
          width: 4,
          height: 4,
          layers: [
            PsdTestLayer(
              name: 'BG',
              left: 1,
              top: 2,
              right: 3,
              bottom: 4,
              opacity: 128,
              hidden: true,
              blend: 'mul ',
              planes: psdSolidPlanes(2, 2, [10, 20, 30]),
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
        buildPsd(
          width: 2,
          height: 2,
          layers: [
            PsdTestLayer(
              name: 'ascii-only',
              unicodeName: '原画A',
              left: 0,
              top: 0,
              right: 2,
              bottom: 2,
              planes: psdSolidPlanes(2, 2, [1, 2, 3]),
            ),
          ],
        ),
      );
      expect(document.layers.single.name, '原画A');
    });

    test('alpha rides in on channel -1', () {
      final document = readPsdDocument(
        buildPsd(
          width: 2,
          height: 1,
          layers: [
            PsdTestLayer(
              name: 'a',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: psdSolidPlanes(2, 1, [200, 200, 200]),
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
        buildPsd(
          width: 2,
          height: 2,
          layers: [
            PsdTestLayer(
              name: '</Layer group>',
              left: 0,
              top: 0,
              right: 0,
              bottom: 0,
              sectionType: 3,
              planes: const [],
            ),
            PsdTestLayer(
              name: 'inside',
              left: 0,
              top: 0,
              right: 2,
              bottom: 2,
              planes: psdSolidPlanes(2, 2, [9, 9, 9]),
            ),
            PsdTestLayer(
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
        buildPsd(
          width: 2,
          height: 2,
          layers: [
            PsdTestLayer(
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
        buildPsd(
          width: 2,
          height: 2,
          layers: [
            PsdTestLayer(
              name: 'colour',
              left: 0,
              top: 0,
              right: 2,
              bottom: 2,
              clipping: true,
              planes: psdSolidPlanes(2, 2, [1, 1, 1]),
            ),
          ],
        ),
      );
      expect(document.layers.single.clipping, isTrue);
    });

    test('zip-compressed channels read the same as raw ones', () {
      final document = readPsdDocument(
        buildPsd(
          width: 2,
          height: 2,
          layers: [
            PsdTestLayer(
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
        buildPsd(
          width: 2,
          height: 2,
          layers: [
            PsdTestLayer(
              name: 'a',
              left: 0,
              top: 0,
              right: 2,
              bottom: 2,
              planes: psdSolidPlanes(2, 2, [1, 2, 3]),
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
        buildPsd(
          width: 2,
          height: 1,
          layers: [
            PsdTestLayer(
              name: 'masked',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: psdSolidPlanes(2, 1, [255, 255, 255]),
              mask: PsdTestMask(
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
        buildPsd(
          width: 2,
          height: 1,
          layers: [
            PsdTestLayer(
              name: 'masked',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: psdSolidPlanes(2, 1, [255, 255, 255]),
              mask: PsdTestMask(
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
        buildPsd(
          width: 2,
          height: 1,
          layers: [
            PsdTestLayer(
              name: 'masked',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: psdSolidPlanes(2, 1, [255, 255, 255]),
              mask: PsdTestMask(
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
        buildPsd(
          width: 2,
          height: 1,
          psb: true,
          layers: [
            PsdTestLayer(
              name: 'big',
              left: 0,
              top: 0,
              right: 2,
              bottom: 1,
              planes: psdSolidPlanes(2, 1, [7, 8, 9]),
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

