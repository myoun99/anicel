import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:anicel/src/ui/widgets/ellipsis_text.dart';

/// Where a hand takes [row] — a rail row, a lane's label — to stand on it,
/// sweep from it or carry it: by its NAME, written along the rail or stood
/// up on the sheet.
///
/// 🚨Not by the row's middle: a row's own buttons stand after its name, out
/// of its room (I-89 Q1), and a press on a button is the button's
/// (`control_press_claim.dart`). How much room the name has is the
/// columns' to say — F-606 (2026-11-16) gave 20 of it to the blend column,
/// and the tests that took a header by its middle took a button instead.
Finder theNameOf(Finder row) => find
    .descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) => widget is EllipsisText || widget is VerticalWritingText,
      ),
    )
    .first;
