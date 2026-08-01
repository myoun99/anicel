import 'package:anicel/src/ui/text/vertical_writing_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds vertical writing carrying [text].
///
/// [VerticalWritingText] paints its whole column through ONE `CustomPaint`
/// — it has to, because a `Column` of `Text` cannot rotate a bracket or put
/// two digits in a cell — so it emits no `Text` widget and `find.text` sees
/// nothing. That is a loud failure rather than a wrong-glyph one, which is
/// what we want; this is the replacement finder.
///
/// Prefer this over `find.bySemanticsLabel`: the semantics node is there,
/// but reading it costs the test a `tester.ensureSemantics()` handle.
Finder findVerticalText(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is VerticalWritingText && widget.text == text,
    description: 'vertical writing "$text"',
  );
}
