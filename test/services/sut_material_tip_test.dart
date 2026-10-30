import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anicel/src/services/sut/sut_material_tip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/temp_dir.dart';
import 'import/clip_test_builder.dart';

/// The materials the reader was measured on came from work and stay out of
/// the repository, so its pins stand on bytes made here, the way the format
/// notes lay them out.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sut_material_tip');
  });

  tearDown(() => deleteTempQuietly(directory));

  /// A plane of noise, so the blocks do not deflate into one page.
  Uint8List noise(int length, {int seed = 1, int bound = 256}) {
    final random = math.Random(seed);
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(bound)),
    );
  }

  /// [width] × [height] of [planes], a block's worth each pixel of a block.
  ({Uint8List attribute, Uint8List blocks}) offscreen(
    int width,
    int height, {
    required List<Uint8List> planes,
    int colourChannels = 0,
  }) {
    const side = 256;
    final columns = (width / side).ceil();
    final rows = (height / side).ceil();
    return (
      attribute: offscreenAttributeBytes(
        width: width,
        height: height,
        columns: columns,
        rows: rows,
        colourChannels: colourChannels,
      ),
      blocks: blockRecordsBytes({
        for (var row = 0; row < rows; row += 1)
          for (var column = 0; column < columns; column += 1)
            row * columns + column: Uint8List.fromList([
              for (final plane in planes)
                ...Iterable.generate(side * side, (i) {
                  final x = column * side + i % side;
                  final y = row * side + i ~/ side;
                  return x < width && y < height ? plane[y * width + x] : 0;
                }),
            ]),
      }),
    );
  }

  Uint8List material(Uint8List layer) => sutMaterialBytes({
    'catalog.zip': Uint8List(40),
    'data/material_0.layer': layer,
    'thumbnail/thumbnail.png': Uint8List(30),
  });

  test('a tip of one plane comes in pixel for pixel, across its blocks and '
      'through its overflow pages', () {
    final plane = noise(300 * 20);
    final tip = sutMaterialTipCoverage(
      material(
        sutMaterialLayerBytes(
          directory,
          offscreens: [
            offscreen(300, 20, planes: [plane]),
          ],
        ),
      ),
    )!;

    expect((tip.width, tip.height), (300, 20));
    expect(tip.coverage, plane);
  });

  test('🚨a tip of two planes lays alpha shaped by darkness, as a PNG of it '
      'would', () {
    final alpha = Uint8List.fromList([255, 255, 128, 0]);
    final gray = Uint8List.fromList([0, 51, 0, 200]);
    final tip = sutMaterialTipCoverage(
      material(
        sutMaterialLayerBytes(
          directory,
          offscreens: [
            offscreen(4, 1, planes: [alpha, gray], colourChannels: 1),
          ],
        ),
      ),
    )!;

    expect(tip.coverage, [255, 204, 128, 0]);
  });

  test('a two-plane tip all white on transparent lays its alpha', () {
    final alpha = Uint8List.fromList([255, 90]);
    final gray = Uint8List.fromList([255, 255]);
    final tip = sutMaterialTipCoverage(
      material(
        sutMaterialLayerBytes(
          directory,
          offscreens: [
            offscreen(2, 1, planes: [alpha, gray], colourChannels: 1),
          ],
        ),
      ),
    )!;

    expect(tip.coverage, alpha);
  });

  test('📏a layer of 4096-byte pages is found after 1024 finds nothing', () {
    final plane = noise(64 * 64);
    final tip = sutMaterialTipCoverage(
      material(
        sutMaterialLayerBytes(
          directory,
          pageSize: 4096,
          offscreens: [
            offscreen(64, 64, planes: [plane]),
          ],
        ),
      ),
    )!;

    expect(tip.coverage, plane);
  });

  test('the largest picture that holds anything is the tip', () {
    final plane = noise(32 * 32);
    final tip = sutMaterialTipCoverage(
      material(
        sutMaterialLayerBytes(
          directory,
          offscreens: [
            offscreen(8, 8, planes: [noise(8 * 8, seed: 2)]),
            offscreen(32, 32, planes: [plane]),
            offscreen(64, 64, planes: [Uint8List(64 * 64)]),
          ],
        ),
      ),
    )!;

    expect((tip.width, tip.height), (32, 32));
    expect(tip.coverage, plane);
  });

  group('⚠️reads nothing, and the preview stands in, for', () {
    test('a material that is no TAR', () {
      final bytes = Uint8List.fromList([
        ...Uint8List(600),
        ...noise(2000, bound: 200),
      ]);

      expect(sutMaterialTipCoverage(bytes), isNull);
    });

    test('a layer that is no C2F', () {
      expect(sutMaterialTipCoverage(material(noise(9000))), isNull);
    });

    test('a picture that holds nothing', () {
      expect(
        sutMaterialTipCoverage(
          material(
            sutMaterialLayerBytes(
              directory,
              offscreens: [
                offscreen(16, 16, planes: [Uint8List(16 * 16)]),
              ],
            ),
          ),
        ),
        isNull,
      );
    });

    test('rows that lie in the ciphered part', () {
      expect(
        sutMaterialTipCoverage(
          material(
            sutMaterialLayerBytes(
              directory,
              cipherOverRows: true,
              offscreens: [
                offscreen(300, 20, planes: [noise(300 * 20)]),
              ],
            ),
          ),
        ),
        isNull,
      );
    });

    test('a row whose overflow runs through a page that is not there', () {
      final layer = sutMaterialLayerBytes(
        directory,
        pagesCut: 2,
        offscreens: [
          offscreen(300, 20, planes: [noise(300 * 20)]),
        ],
      );

      expect(sutMaterialTipCoverage(material(layer)), isNull);
    });
  });
}
