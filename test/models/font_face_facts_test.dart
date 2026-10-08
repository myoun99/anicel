import 'package:anicel/src/models/font_face_facts.dart';
import 'package:flutter_test/flutter_test.dart';

/// R9-rest (the text tool's faces): WHICH FONTS MAY RIDE INSIDE A PROJECT.
///
/// 🗣️유저 2026-10-06 (R9-rest-Q1 ⓐ): 「그럼 a로 가자 … 프로들이 하는
/// 방식대로하자고」 — a font whose maker forbids putting it in a document
/// that is edited stays on this device and is never written into a project.
/// The maker's word is the `fsType` of the font's OS/2 table, and this is
/// how it is read.
void main() {
  FontFaceFacts saying(int? fsType) => FontFaceFacts(
    family: 'Probe Sans',
    weight: 400,
    italic: false,
    fsType: fsType,
  );

  group('a font rides in a document that is edited', () {
    test('when its maker set no licence bit at all — installable', () {
      expect(saying(0).ridesInEditedDocuments, isTrue);
    });

    test('when its maker allows EDITABLE embedding', () {
      expect(saying(0x0008).ridesInEditedDocuments, isTrue);
    });

    test('whatever it says of subsetting, which is not asked of a file '
        'carried whole', () {
      expect(saying(0x0100).ridesInEditedDocuments, isTrue);
      expect(saying(0x0108).ridesInEditedDocuments, isTrue);
    });

    test('and where a file sets several licence bits, by the least '
        'restrictive of them', () {
      expect(saying(0x000C).ridesInEditedDocuments, isTrue);
      expect(saying(0x000A).ridesInEditedDocuments, isTrue);
    });
  });

  group('🚨a font stays on this device', () {
    test('when its licence is restricted', () {
      expect(saying(0x0002).ridesInEditedDocuments, isFalse);
    });

    test('when it allows preview and print alone — a document nobody edits', () {
      expect(saying(0x0004).ridesInEditedDocuments, isFalse);
      expect(saying(0x0006).ridesInEditedDocuments, isFalse);
    });

    test('when only bitmaps of it may be embedded, whatever its licence', () {
      expect(saying(0x0200).ridesInEditedDocuments, isFalse);
      expect(saying(0x0208).ridesInEditedDocuments, isFalse);
    });

    test('when it sets the reserved bit alone, which the format gives no '
        'meaning to', () {
      expect(saying(0x0001).ridesInEditedDocuments, isFalse);
    });

    test('when it says nothing: a file with no OS/2 table has given no '
        'permission', () {
      expect(saying(null).ridesInEditedDocuments, isFalse);
    });
  });

  group('the same face of the same family', () {
    const regular = FontFaceFacts(
      family: 'Probe Sans',
      weight: 400,
      italic: false,
      fsType: 0,
    );

    test('is one of the same name, weight and slant — whatever it says of '
        'embedding', () {
      expect(
        regular.isSameFaceAs(
          const FontFaceFacts(
            family: 'Probe Sans',
            weight: 400,
            italic: false,
            fsType: 2,
          ),
        ),
        isTrue,
      );
    });

    test('and not another weight, another slant, another family', () {
      FontFaceFacts but({String? family, int? weight, bool? italic}) =>
          FontFaceFacts(
            family: family ?? regular.family,
            weight: weight ?? regular.weight,
            italic: italic ?? regular.italic,
            fsType: regular.fsType,
          );

      expect(regular.isSameFaceAs(but(weight: 700)), isFalse);
      expect(regular.isSameFaceAs(but(italic: true)), isFalse);
      expect(regular.isSameFaceAs(but(family: 'Probe Serif')), isFalse);
    });
  });

  test('facts come back from their own json as they went — a missing word '
      'on embedding too', () {
    for (final facts in [
      const FontFaceFacts(
        family: '고딕 Probe',
        weight: 700,
        italic: true,
        fsType: 0x0108,
      ),
      saying(null),
    ]) {
      final back = FontFaceFacts.fromJson(facts.toJson());

      expect(back, facts);
      expect(back.hashCode, facts.hashCode);
      expect(back.fsType, facts.fsType);
    }
  });

  test('two facts that differ in the word on embedding alone are not equal', () {
    expect(saying(0), isNot(saying(2)));
  });
}
