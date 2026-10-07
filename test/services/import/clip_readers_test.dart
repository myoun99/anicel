import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/import/clip_cmt.dart';
import 'package:anicel/src/services/import/clip_container.dart';
import 'package:anicel/src/services/import/clip_offscreen.dart';

import '../../helpers/temp_dir.dart';
import 'clip_test_builder.dart';

/// The byte readers under the CLIP STUDIO PAINT import (card
/// `csp-clip-import-analysis`): the container, the track documents, the
/// pictures — each against bytes laid out the way the format notes say.
void main() {
  group('the container', () {
    late Directory folder;
    setUp(() => folder = Directory.systemTemp.createTempSync('qa_clip_'));
    tearDown(() => deleteTempQuietly(folder));

    ClipContainer indexed(
      List<int> bytes, [
      void Function(RandomAccessFile)? then,
    ]) {
      final file = File('${folder.path}/cut.clip')..writeAsBytesSync(bytes);
      final open = file.openSync();
      try {
        final container = ClipContainer.indexOf(open);
        then?.call(open);
        return container;
      } finally {
        open.closeSync();
      }
    }

    test('names where the database and every external chunk lie', () {
      final database = List.generate(300, (i) => i & 0xff);
      final pixels = List.generate(70, (i) => 255 - i);
      final track = List.generate(9, (i) => i * 3);
      final bytes = clipFileBytes(
        database: database,
        externals: {externalId(1): pixels, externalId(2): track},
      );
      late Uint8List readDatabase;
      late Uint8List readPixels;
      late Uint8List readTrack;
      final container = indexed(bytes, (file) {
        final self = ClipContainer.indexOf(file);
        readDatabase = readClipPlace(file, self.database);
        readPixels = readClipPlace(file, self.externals[externalId(1)]!);
        readTrack = readClipPlace(file, self.externals[externalId(2)]!);
      });

      expect(container.externals.keys, [externalId(1), externalId(2)]);
      expect(readDatabase, database);
      expect(readPixels, pixels);
      expect(readTrack, track);
    });

    test('a file that is not one is refused, not misread', () {
      final bytes = clipFileBytes(database: [1, 2, 3])
        ..setRange(0, 8, 'NOTACLIP'.codeUnits);
      expect(() => indexed(bytes), throwsA(isA<ClipFormatException>()));
    });

    test('a chunk that runs past the end of the file is refused', () {
      final whole = clipFileBytes(database: List.filled(100, 1));
      final cut = Uint8List.sublistView(whole, 0, whole.length - 40);
      expect(() => indexed(cut), throwsA(isA<ClipFormatException>()));
    });

    test('a file with no database is refused', () {
      final bytes = clipFileBytes(database: const [], withDatabase: false);
      expect(() => indexed(bytes), throwsA(isA<ClipFormatException>()));
    });
  });

  group('a track document', () {
    const tree = CmtSpec(
      'celsysdocument',
      'null',
      attributes: {'version': '1'},
      children: [
        CmtSpec(
          'ActionNodeClip',
          'null',
          attributes: {'Name': 'clip'},
          children: [
            CmtSpec('TimeClip', 'Double3', value: [0, 168, 60]),
            CmtSpec(
              'FCurve',
              'null',
              attributes: {'Type': 'ImageCelName'},
              children: [
                CmtSpec('Frame', 'Double[]', value: [0, 2.5, 398.88]),
                CmtSpec('Tag', 'String[]', value: ['1', '2', '10a']),
                CmtSpec('Interp', 'String', value: 'Constant'),
                CmtSpec('Count', 'UInt32', value: 3),
                CmtSpec('Offset', 'Int32', value: -40),
                CmtSpec('Turn', 'Quat', value: [0, 0, 0.5, 1]),
              ],
            ),
          ],
        ),
      ],
    );

    test('reads the 0110 version — names, values, attributes, children', () {
      final root = parseCmtDocument(cmtDocumentBytes(tree));
      final curve = root.child('ActionNodeClip')!.child('FCurve')!;

      expect(root.name, 'celsysdocument');
      expect(root.attributes, {'version': '1'});
      expect(curve.attributes['Type'], 'ImageCelName');
      expect(curve.child('Frame')!.value, [0, 2.5, 398.88]);
      expect(curve.child('Tag')!.value, ['1', '2', '10a']);
      expect(curve.child('Interp')!.value, 'Constant');
      expect(curve.child('Count')!.value, 3);
      expect(curve.child('Offset')!.value, -40);
      expect(curve.child('Turn')!.value, [0, 0, 0.5, 1]);
      expect(
        root.child('ActionNodeClip')!.child('TimeClip')!.value,
        [0, 168, 60],
      );
      expect(
        [for (final node in root.everyNode) node.name],
        [
          'celsysdocument',
          'ActionNodeClip',
          'TimeClip',
          'FCurve',
          'Frame',
          'Tag',
          'Interp',
          'Count',
          'Offset',
          'Turn',
        ],
      );
    });

    test('reads the 0100 version, whose reals are singles', () {
      const singles = CmtSpec(
        'FCurve',
        'null',
        children: [
          CmtSpec('Frame', 'Single[]', value: [0, 398.88]),
          CmtSpec('Point', 'Float2', value: [1.5, -2]),
        ],
      );
      final root = parseCmtDocument(cmtDocumentBytes(singles, doubles: false));
      final frames = root.child('Frame')!.value! as List<Object?>;

      expect(frames[0], 0);
      expect(frames[1], closeTo(398.88, 1e-4));
      expect(frames[1], isNot(398.88), reason: 'a single, not the double');
      expect(root.child('Point')!.value, [1.5, -2]);
    });

    test('a 0110 node of an unknown type is stepped over by its offsets', () {
      const odd = CmtSpec(
        'AnimInfo',
        'null',
        children: [
          CmtSpec(
            'Mystery',
            'Thing',
            rawValue: [1, 2, 3, 4, 5, 6, 7],
            attributes: {'Name': 'after'},
            children: [CmtSpec('Inner', 'UInt32', value: 9)],
          ),
          CmtSpec('Next', 'String', value: 'still read'),
        ],
      );
      final root = parseCmtDocument(cmtDocumentBytes(odd));
      final mystery = root.child('Mystery')!;

      expect(mystery.value, isNull);
      expect(mystery.attributes, {'Name': 'after'});
      expect(mystery.child('Inner')!.value, 9);
      expect(root.child('Next')!.value, 'still read');
    });

    test('a 0100 node of an unknown type has no way past it, so the '
        'document is refused', () {
      const odd = CmtSpec(
        'AnimInfo',
        'null',
        children: [
          CmtSpec('Mystery', 'Thing', rawValue: [1, 2, 3, 4]),
        ],
      );
      expect(
        () => parseCmtDocument(cmtDocumentBytes(odd, doubles: false)),
        throwsA(isA<ClipFormatException>()),
      );
    });

    test('a string longer than 127 bytes is read by its multi-byte length', () {
      final long = 'セル' * 40;
      final root = parseCmtDocument(
        cmtDocumentBytes(CmtSpec('Name', 'String', value: long)),
      );
      expect(root.value, long);
    });

    test('a track\'s data is its document, compressed behind its length', () {
      final document = cmtDocumentBytes(tree);
      final root = cmtDocumentOfTrackData(trackDataBytes(document));
      expect(
        root.child('ActionNodeClip')!.child('FCurve')!.child('Tag')!.value,
        ['1', '2', '10a'],
      );
    });

    test('something that is no cmt document is refused', () {
      expect(
        () => parseCmtDocument(Uint8List.fromList(List.filled(40, 0x41))),
        throwsA(isA<ClipFormatException>()),
      );
    });
  });

  group('a picture', () {
    test('its attribute says its size, its grid, its channels, its fill', () {
      final shape = parseClipOffscreenAttribute(
        offscreenAttributeBytes(
          width: 300,
          height: 260,
          columns: 2,
          rows: 2,
          fill: 255,
        ),
      );

      expect(shape.width, 300);
      expect(shape.height, 260);
      expect(shape.columns, 2);
      expect(shape.rows, 2);
      expect(shape.isColour, isTrue);
      expect(shape.isSingleChannel, isFalse);
      expect(shape.fill, 255);
    });

    test('a mask is one channel, not a picture', () {
      final shape = parseClipOffscreenAttribute(
        offscreenAttributeBytes(
          width: 256,
          height: 256,
          columns: 1,
          rows: 1,
          alphaChannels: 0,
          colourChannels: 1,
        ),
      );
      expect(shape.isColour, isFalse);
      expect(shape.isSingleChannel, isTrue);
    });

    test('its blocks are read by number — an empty one as empty', () {
      final first = colourBlock((x, y) => (x, y, 7, 255));
      final last = colourBlock((_, _) => (1, 2, 3, 4));
      final blocks = clipBlocksOf(
        blockRecordsBytes({0: first, 1: null, 3: last}),
      );

      expect(blocks.keys, [0, 1, 3]);
      expect(blocks[0], first);
      expect(blocks[1], isNull);
      expect(blocks[3]!.length, 256 * 256 * 5);
    });

    test('a colour picture comes out as straight RGBA, each block in its '
        'place, cut at the picture\'s edge', () {
      const shape = ClipOffscreenShape(
        width: 300,
        height: 260,
        columns: 2,
        rows: 2,
        alphaChannels: 1,
        colourChannels: 4,
        fill: 0,
      );
      final rgba = clipColourRgba(shape, {
        0: colourBlock((x, y) => (x, y, 200, 128)),
        // Block 1 (top right) was never stored — transparent.
        2: null,
        3: colourBlock((x, y) => (10, 20, 30, x == 0 && y == 0 ? 255 : 99)),
      })!;
      (int, int, int, int) at(int x, int y) {
        final i = (y * 300 + x) * 4;
        return (rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3]);
      }

      expect(rgba.length, 300 * 260 * 4);
      expect(at(0, 0), (0, 0, 200, 128));
      expect(
        at(17, 33),
        (17, 33, 200, 128),
        reason: 'R · G · B, not B · G · R',
      );
      expect(at(255, 255), (255, 255, 200, 128));
      expect(at(256, 0), (0, 0, 0, 0), reason: 'a block never stored');
      expect(at(0, 256), (0, 0, 0, 0), reason: 'a block stored empty');
      expect(at(256, 256), (10, 20, 30, 255), reason: 'block 3 starts here');
      expect(at(299, 259), (10, 20, 30, 99), reason: 'and is cut at the edge');
    });

    test('a picture of another channel bundle is not turned into colour', () {
      const mask = ClipOffscreenShape(
        width: 256,
        height: 256,
        columns: 1,
        rows: 1,
        alphaChannels: 0,
        colourChannels: 1,
        fill: 0,
      );
      expect(clipColourRgba(mask, {0: Uint8List(256 * 256)}), isNull);
    });
  });
}
