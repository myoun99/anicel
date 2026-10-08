import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/font_face_facts.dart';
import 'package:anicel/src/services/font_file_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/font_file_fixture.dart';

/// R9-rest (the text tool's faces): WHAT A FONT FILE SAYS OF ITSELF, and
/// which bytes are not a font file at all.
///
/// 🚨The reader is the wall: the engine takes any bytes as a font and says
/// nothing (measured 2026-10-06), so what is refused is refused here.
void main() {
  FontFaceFacts read(Uint8List bytes) => readFontFaceFacts(bytes)!;

  group('the app\'s own files, as they ship', () {
    Uint8List asset(String name) =>
        File('assets/fonts/$name').readAsBytesSync();

    test('each says its family, its weight, and that it may ride', () {
      expect(
        read(asset('BIZUDPGothic-Regular.ttf')),
        const FontFaceFacts(
          family: 'BIZ UDPGothic',
          weight: 400,
          italic: false,
          fsType: 0,
        ),
      );
      expect(read(asset('BIZUDPGothic-Bold.ttf')).weight, 700);
      expect(
        read(asset('NanumGothic-Regular.ttf')),
        const FontFaceFacts(
          family: 'NanumGothic',
          weight: 400,
          italic: false,
          fsType: 0,
        ),
      );
      expect(read(asset('NanumGothic-Bold.ttf')).weight, 700);
      expect(read(asset('NanumGothic-Bold.ttf')).family, 'NanumGothic');
    });

    test('a file of them cut short is not a font', () {
      final whole = asset('NanumGothic-Regular.ttf');

      expect(readFontFaceFacts(whole.sublist(0, whole.length ~/ 2)), isNull);
      expect(readFontFaceFacts(whole.sublist(0, 200)), isNull);
      expect(readFontFaceFacts(whole.sublist(0, 11)), isNull);
    });
  });

  group('what is not a font', () {
    test('bytes of something else', () {
      expect(readFontFaceFacts(Uint8List(0)), isNull);
      expect(readFontFaceFacts(Uint8List.fromList(List.filled(64, 7))), isNull);
      expect(
        readFontFaceFacts(File('pubspec.yaml').readAsBytesSync()),
        isNull,
      );
    });

    test('a web font — the same tables, packed another way', () {
      // 'wOFF' and 'wOF2' where the kind is.
      expect(readFontFaceFacts(fontFileSaying(kind: 0x774F4646)), isNull);
      expect(readFontFaceFacts(fontFileSaying(kind: 0x774F4632)), isNull);
    });

    test('a file with no head, a head that is not one, or no map from '
        'letters to glyphs', () {
      expect(readFontFaceFacts(fontFileSaying(withHead: false)), isNull);
      expect(readFontFaceFacts(fontFileSaying(headMagic: 0x12345678)), isNull);
      // A head too short to be one — though it says the right thing where
      // the mark is looked for.
      expect(readFontFaceFacts(fontFileSaying(headLength: 53)), isNull);
      expect(readFontFaceFacts(fontFileSaying(withCmap: false)), isNull);
      // ⛔fixture: the same file with all three is one.
      expect(readFontFaceFacts(fontFileSaying()), isNotNull);
    });

    test('a file with no family name to call it by', () {
      expect(readFontFaceFacts(fontFileSaying(names: const [])), isNull);
      expect(readFontFaceFacts(fontFileSaying(family: '')), isNull);
      expect(readFontFaceFacts(fontFileSaying(family: '  \u0000 ')), isNull);
      // Another name of the file is not its family's.
      expect(
        readFontFaceFacts(
          fontFileSaying(
            names: const [
              (
                platform: 3,
                encoding: 1,
                language: 0x0409,
                nameId: 4,
                text: 'Probe Sans Regular',
              ),
            ],
          ),
        ),
        isNull,
      );
    });

    test('a file whose table says it lies past the file\'s end', () {
      final bytes = fontFileSaying();
      final data = ByteData.sublistView(bytes);
      // The first table's length, grown past everything.
      data.setUint32(12 + 12, bytes.length * 2);

      expect(readFontFaceFacts(bytes), isNull);
    });

    test('a name record that points outside the name table is passed over', () {
      final bytes = fontFileSaying(
        names: [
          windowsEnglishFamily('Probe Sans'),
          (platform: 0, encoding: 3, language: 0, nameId: 1, text: 'Other'),
        ],
      );
      final at = _tableOffset(bytes, 'name');
      // The English record's length, past the table's end.
      ByteData.sublistView(bytes).setUint16(at + 6 + 8, 60000);

      expect(read(bytes).family, 'Other');
    });
  });

  group('the family\'s name', () {
    FontNameRecord named(
      String text, {
      required int platform,
      int encoding = 1,
      int language = 0x0409,
    }) => (
      platform: platform,
      encoding: encoding,
      language: language,
      nameId: 1,
      text: text,
    );

    test('🚨is the one written for Windows in English, whatever else the '
        'file has and wherever in the table it stands', () {
      final records = [
        named('고딕', platform: 3, language: 0x0412),
        named('Mac Name', platform: 1, encoding: 0, language: 0),
        named('Unicode Name', platform: 0, encoding: 3, language: 0),
        named('Probe Sans', platform: 3),
      ];

      expect(read(fontFileSaying(names: records)).family, 'Probe Sans');
      expect(
        read(fontFileSaying(names: records.reversed.toList())).family,
        'Probe Sans',
      );
    });

    test('a Windows name in the full repertoire is read as one in the '
        'basic plane is', () {
      expect(
        read(
          fontFileSaying(names: [named('Probe Sans', platform: 3, encoding: 10)]),
        ).family,
        'Probe Sans',
      );
    });

    test('of two names as good as each other, the one that stands first in '
        'the table', () {
      final korean = named('고딕', platform: 3, language: 0x0412);
      final japanese = named('ゴシック', platform: 3, language: 0x0411);

      expect(read(fontFileSaying(names: [korean, japanese])).family, '고딕');
      expect(read(fontFileSaying(names: [japanese, korean])).family, 'ゴシック');
    });

    test('a Macintosh name is read in whatever language it is written for', () {
      expect(
        read(
          fontFileSaying(
            names: [named('Nom Mac', platform: 1, encoding: 0, language: 1)],
          ),
        ).family,
        'Nom Mac',
      );
    });

    test('then another Windows one, then a Unicode one, then a Macintosh '
        'one', () {
      final other = named('고딕', platform: 3, language: 0x0412);
      final unicode = named('Unicode Name', platform: 0, encoding: 3);
      final mac = named('Mac Name', platform: 1, encoding: 0, language: 0);

      expect(
        read(fontFileSaying(names: [mac, unicode, other])).family,
        '고딕',
      );
      expect(
        read(fontFileSaying(names: [mac, unicode])).family,
        'Unicode Name',
      );
      expect(read(fontFileSaying(names: [mac])).family, 'Mac Name');
    });

    test('a record in an encoding this does not read is not a name', () {
      // Windows, Shift-JIS; Macintosh, Japanese.
      expect(
        readFontFaceFacts(
          fontFileSaying(
            names: [
              named('x', platform: 3, encoding: 2),
              named('y', platform: 1, encoding: 1, language: 11),
            ],
          ),
        ),
        isNull,
      );
    });

    test('is one line: the control characters in it are not kept, nor the '
        'space around it', () {
      expect(
        read(fontFileSaying(family: '  Probe\nSans\u0000 ')).family,
        'ProbeSans',
      );
    });

    test('is not longer than a name is: the longest taken is 128 letters', () {
      expect(read(fontFileSaying(family: 'n' * 128)).family, 'n' * 128);
      expect(readFontFaceFacts(fontFileSaying(family: 'n' * 129)), isNull);
    });
  });

  group('which face of the family it is', () {
    test('its weight and its slant, as its OS/2 table says', () {
      final facts = read(fontFileSaying(weight: 300, italic: true));

      expect(facts.weight, 300);
      expect(facts.italic, isTrue);
      expect(read(fontFileSaying(weight: 900)).italic, isFalse);
    });

    test('a weight of nothing is a regular, and one past the scale is its '
        'end', () {
      expect(read(fontFileSaying(weight: 0)).weight, 400);
      expect(read(fontFileSaying(weight: 5000)).weight, 1000);
    });

    test('a slant the file calls OBLIQUE is a slant; a bold is not one', () {
      expect(read(fontFileSaying(fsSelection: 0x0200)).italic, isTrue);
      expect(read(fontFileSaying(fsSelection: 0x0201)).italic, isTrue);
      expect(read(fontFileSaying(fsSelection: 0x0020)).italic, isFalse);
      expect(read(fontFileSaying(fsSelection: 0x0040)).italic, isFalse);
    });

    test('an OS/2 table too short to say anything is no OS/2 table: no '
        'word on embedding, and the face as head has it', () {
      final facts = read(fontFileSaying(os2Length: 9, macStyle: 0x1));

      expect((facts.weight, facts.fsType), (700, null));
      // Ten bytes is enough for the weight and the word.
      final enough = read(
        fontFileSaying(os2Length: 10, weight: 300, fsType: 8, macStyle: 0x1),
      );
      expect((enough.weight, enough.fsType), (300, 8));
    });

    test('an OS/2 table too short to carry the slant leaves it to head', () {
      expect(
        read(fontFileSaying(os2Length: 12, macStyle: 0x2)).italic,
        isTrue,
      );
      expect(
        read(fontFileSaying(os2Length: 12, macStyle: 0x1)).italic,
        isFalse,
      );
    });

    test('🚨with NO OS/2 table: weight and slant as head has them, and no '
        'word on embedding at all', () {
      final bold = read(fontFileSaying(fsType: null, macStyle: 0x1));
      final slanted = read(fontFileSaying(fsType: null, macStyle: 0x2));

      expect((bold.weight, bold.italic, bold.fsType), (700, false, null));
      expect((slanted.weight, slanted.italic), (400, true));
      expect(bold.ridesInEditedDocuments, isFalse);
    });

    test('the maker\'s word on embedding is read as it is written', () {
      for (final said in [0, 2, 4, 8, 0x0200, 0x0108]) {
        expect(read(fontFileSaying(fsType: said)).fsType, said);
      }
    });
  });

  group('a collection (.ttc)', () {
    test('🚨is read as its FIRST face — the one the engine draws with', () {
      final collection = fontCollectionOf([
        fontFileSaying(family: 'First Face', weight: 500, fsType: 8),
        fontFileSaying(family: 'Second Face', fsType: 2),
      ]);

      expect(
        read(collection),
        const FontFaceFacts(
          family: 'First Face',
          weight: 500,
          italic: false,
          fsType: 8,
        ),
      );
    });

    test('one with no face in it is not a font', () {
      expect(readFontFaceFacts(fontCollectionOf(const [])), isNull);
    });
  });

  test('a file is kept under the extension of what it IS, whatever it was '
      'called', () {
    expect(fontFileExtensionOf(fontFileSaying()), 'ttf');
    expect(fontFileExtensionOf(fontFileSaying(kind: 0x4F54544F)), 'otf');
    expect(fontFileExtensionOf(fontCollectionOf([fontFileSaying()])), 'ttc');
    expect(fontFileExtensionOf(Uint8List(2)), 'ttf');
    // PostScript outlines are a font this reads.
    expect(readFontFaceFacts(fontFileSaying(kind: 0x4F54544F)), isNotNull);
    // And Apple's own mark for TrueType.
    expect(readFontFaceFacts(fontFileSaying(kind: 0x74727565)), isNotNull);
  });
}

/// Where [tag]'s table begins in [bytes].
int _tableOffset(Uint8List bytes, String tag) {
  final data = ByteData.sublistView(bytes);
  final count = data.getUint16(4);
  for (var index = 0; index < count; index += 1) {
    final record = 12 + index * 16;
    if (String.fromCharCodes(bytes.sublist(record, record + 4)) == tag) {
      return data.getUint32(record + 8);
    }
  }
  throw StateError('no $tag table');
}
