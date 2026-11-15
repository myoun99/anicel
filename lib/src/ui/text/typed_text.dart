import 'package:flutter/services.dart';

/// 🐛F-584 (검증/서피스 2026-11-15, 서피스 프로 11): two lines copied on
/// Windows and pasted into a block's dialogue left a ⊠ where they broke —
/// on the field, and on the block. A Windows clipboard ends a line in
/// CR LF; a one-line field's own filter takes the LF alone
/// (`FilteringTextInputFormatter.singleLineFormatter`), and a field of
/// many lines kept both.
///
/// ONE LAW FOR EVERY FIELD THE APP BUILDS: a carriage return is never
/// text the app takes. Dropped, it leaves a field of many lines its LF
/// (CR LF → LF), and a one-line field — whose own filter took the LF
/// first — nothing at all. 🗣️관제 2026-11-15 (F-584): 「CR 을 지운다」
/// 하나로 — one law in both shapes, a lone CR (an old Mac's line end)
/// going with no break in its place. Every field takes it through
/// [typedText], and `every_text_field_types_by_one_law_test.dart` finds
/// a field that does not.
class NoCarriageReturnFormatter extends TextInputFormatter {
  const NoCarriageReturnFormatter();

  static final TextInputFormatter _dropped =
      FilteringTextInputFormatter.deny('\r');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // A draft the IME is still composing is the IME's, as the numerals'
    // law leaves it (F-355, `HalfWidthNumeralsFormatter`): Flutter formats
    // again the moment it is committed.
    if (!newValue.composing.isCollapsed || !newValue.text.contains('\r')) {
      return newValue;
    }
    return _dropped.formatEditUpdate(oldValue, newValue);
  }
}

/// THE formatters of a text field: the law every field keeps
/// ([NoCarriageReturnFormatter]), and then [own] — the field's.
List<TextInputFormatter> typedText([
  List<TextInputFormatter> own = const [],
]) => own.isEmpty ? _theLawAlone : [const NoCarriageReturnFormatter(), ...own];

const List<TextInputFormatter> _theLawAlone = [NoCarriageReturnFormatter()];
