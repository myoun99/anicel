import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Text by what it is. ⛔`find.byType` asks for the EXACT type, and a line
/// the app can cut is a kind of each (`EllipsisText`): `find.byType(Text)`
/// misses it, and a test that expects to find none would pass for it
/// (`every_cut_word_says_itself_test`).
extension TextFinders on CommonFinders {
  /// Every [Text], `EllipsisText` with them.
  Finder anyText({bool skipOffstage = true}) => byWidgetPredicate(
    (widget) => widget is Text,
    description: 'any Text',
    skipOffstage: skipOffstage,
  );

  /// Every [RichText], the one under an `EllipsisText` with them.
  Finder anyRichText({bool skipOffstage = true}) => byWidgetPredicate(
    (widget) => widget is RichText,
    description: 'any RichText',
    skipOffstage: skipOffstage,
  );
}
