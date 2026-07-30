import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/text_cel_style.dart';

/// The text cel's parameter models (R5): JSON round-trips (the truth
/// persists in project.json), sentinel copyWith on the nullable axes,
/// and value equality (the bake sweep's staleness check IS `==`).
void main() {
  group('TextCelStyle', () {
    test('round-trips through JSON with every axis set', () {
      const style = TextCelStyle(
        fontFamily: 'M PLUS 1p',
        fontSize: 96,
        bold: true,
        letterSpacing: 2.5,
        align: TextCelAlign.right,
        color: 0xFFFFFFFF,
        outlineColor: 0xFF202020,
        outlineWidth: 4,
        backgroundColor: 0xFFC95C5C,
      );
      expect(TextCelStyle.fromJson(style.toJson()), style);
    });

    test('defaults survive an empty JSON object (forward tolerance)', () {
      final style = TextCelStyle.fromJson(const {});
      expect(style, const TextCelStyle());
      expect(style.align, TextCelAlign.center);
    });

    test('copyWith clears the nullable axes through the sentinel', () {
      const style = TextCelStyle(
        fontFamily: 'M PLUS 1p',
        outlineColor: 0xFF000000,
        backgroundColor: 0xFFC95C5C,
      );
      final cleared = style.copyWith(
        fontFamily: null,
        outlineColor: null,
        backgroundColor: null,
      );
      expect(cleared.fontFamily, isNull);
      expect(cleared.outlineColor, isNull);
      expect(cleared.backgroundColor, isNull);
      expect(
        style.copyWith(bold: true).fontFamily,
        'M PLUS 1p',
        reason: 'untouched axes keep their values',
      );
    });
  });

  group('TextCelContent', () {
    test('round-trips through JSON, position included and omitted', () {
      const anchored = TextCelContent(
        text: 'カット 12\n3+12',
        style: TextCelStyle(fontSize: 24),
        position: Offset(120.5, 48),
      );
      expect(TextCelContent.fromJson(anchored.toJson()), anchored);

      const centered = TextCelContent(text: 'BG');
      final decoded = TextCelContent.fromJson(centered.toJson());
      expect(decoded, centered);
      expect(decoded.position, isNull);
    });

    test('equality is by value — the bake sweep depends on it', () {
      const a = TextCelContent(text: 'A', position: Offset(1, 2));
      const b = TextCelContent(text: 'A', position: Offset(1, 2));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(text: 'B'), isFalse);
      expect(a == a.copyWith(position: null), isFalse);
    });
  });
}
