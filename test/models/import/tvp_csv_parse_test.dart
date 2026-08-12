import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/import/tvp_csv_parse.dart';

/// The CSV is read for ONE question the JSON cannot answer: did the
/// animator name this instance, or is that number TVPaint's own counting?
///
/// The fixture is the shape of a real export, with the three cases that
/// matter side by side — a layer nobody named (`TAP`, `F`, `B`), a layer
/// named throughout (`D`, `A`), and a layer that changes its mind halfway
/// (`E` unnamed until frame 17, `C` named until frame 10). The last one is
/// why this is read per CELL: no per-layer rule can be right about it.
void main() {
  TvpCsvNames fixture() => parseTvpCsv(
    File('test/fixtures/tvpaint/named_and_unnamed.csv').readAsStringSync(),
  );

  group('the header pairs the CSV with its clip', () {
    test('it carries what a JSON export can be checked against', () {
      final csv = fixture();
      expect(csv.clipName, 'クリップ_001');
      expect(csv.width, 2150);
      expect(csv.height, 1518);
      expect(csv.frameCount, 24);
      expect(csv.layerCount, 7);
      expect(csv.layerNames, [
        'TAP',
        'F',
        'E',
        'D',
        'C',
        'B',
        'A',
      ]);
    });

    test('the pairing check accepts its own clip and refuses anything else', () {
      final csv = fixture();
      expect(
        csv.describesSameClipAs(
          clipName: 'クリップ_001',
          width: 2150,
          height: 1518,
          frameCount: 24,
          layerCount: 7,
        ),
        isTrue,
      );
      // A stale CSV kept beside a re-exported clip renames cels after
      // somebody else's drawings, so every field votes.
      expect(
        csv.describesSameClipAs(
          clipName: 'クリップ_001',
          width: 2150,
          height: 1518,
          frameCount: 25,
          layerCount: 7,
        ),
        isFalse,
        reason: 'a frame added since the CSV was written',
      );
      expect(
        csv.describesSameClipAs(
          clipName: 'クリップ_002',
          width: 2150,
          height: 1518,
          frameCount: 24,
          layerCount: 7,
        ),
        isFalse,
      );
    });
  });

  group('the label says whether the instance has a name', () {
    test('a label that is the LAYER name means it has none', () {
      final csv = fixture();
      expect(csv.nameAt(layerNumber: 1, frameNumber: 1), isNull, reason: 'TAP');
      expect(csv.nameAt(layerNumber: 2, frameNumber: 1), isNull, reason: 'F');
      expect(csv.nameAt(layerNumber: 6, frameNumber: 1), isNull, reason: 'B');
    });

    test('any other label IS the name', () {
      final csv = fixture();
      expect(csv.nameAt(layerNumber: 4, frameNumber: 1), '1');
      expect(csv.nameAt(layerNumber: 4, frameNumber: 4), '2');
      expect(csv.nameAt(layerNumber: 7, frameNumber: 7), '3');
    });

    test('one layer can be unnamed for a while and named after', () {
      // `E` is the layer's own name through frame 10 and `1` from 17 on.
      // A rule that decided per LAYER would have to be wrong about one
      // half of this row.
      final csv = fixture();
      expect(csv.nameAt(layerNumber: 3, frameNumber: 1), isNull);
      expect(csv.nameAt(layerNumber: 3, frameNumber: 10), isNull);
      expect(csv.nameAt(layerNumber: 3, frameNumber: 17), '1');
      expect(csv.nameAt(layerNumber: 3, frameNumber: 19), '1');

      // `C` runs the other way: named, then not.
      expect(csv.nameAt(layerNumber: 5, frameNumber: 1), '1');
      expect(csv.nameAt(layerNumber: 5, frameNumber: 7), '3');
      expect(csv.nameAt(layerNumber: 5, frameNumber: 10), isNull);
    });

    test('a cell the CSV never mentions has no name either', () {
      // Frames with nothing on that layer are simply absent from the row,
      // and an absent cell must not become a name.
      final csv = fixture();
      expect(csv.nameAt(layerNumber: 1, frameNumber: 4), isNull);
      expect(csv.nameAt(layerNumber: 99, frameNumber: 1), isNull);
    });

    test('a name may carry a comma or a dot — neither is a delimiter', () {
      // `arisu,おはよ` is a real SE label and `1.5` a real cel number, so
      // splitting the row on commas or the file name on dots loses them.
      final csv = fixture();
      expect(csv.nameAt(layerNumber: 5, frameNumber: 22), 'arisu,おはよ');
      expect(csv.nameAt(layerNumber: 7, frameNumber: 22), '1.5');
    });
  });

  group('what is not a TVPaint CSV says so', () {
    test('a file that never names TVPaint is refused', () {
      expect(
        () => parseTvpCsv('a,b,c\n1,2,3\n'),
        throwsA(isA<TvpCsvParseException>()),
      );
    });

    test('a header with no #Layers row is refused', () {
      expect(
        () => parseTvpCsv('UTF-8, TVPaint, "CSV 1.1"\n"c", 1, 1, 1, 1\n'),
        throwsA(isA<TvpCsvParseException>()),
      );
    });
  });
}
