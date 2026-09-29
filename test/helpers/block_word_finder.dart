import 'package:anicel/src/ui/timeline/timeline_block_word.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds a built block word written in a line ([TimelineBlockText]) that
/// carries [text] — a lane key's name, an instruction's writing on the
/// timeline, an SE name on the sheet.
///
/// A built word sets its own letters and paints them, so it emits no `Text`
/// or `VerticalWritingText` widget and neither's finder sees it; these are
/// the replacement finders.
Finder findBlockText(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is TimelineBlockText && widget.text == text,
    description: 'block text "$text"',
  );
}

/// Finds a built block word written down a column ([TimelineBlockColumn])
/// that carries [text] — an SE name on the timeline, an instruction's
/// writing on the sheet.
Finder findBlockColumn(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is TimelineBlockColumn && widget.text == text,
    description: 'block column "$text"',
  );
}

/// Where the built word [finder] finds lands on screen, narrowed — its
/// word, not its box: the box is the word's room.
Rect blockWordRect(WidgetTester tester, Finder finder) {
  final word = tester.renderObject<RenderTimelineBuiltWord>(finder);
  return MatrixUtils.transformRect(word.getTransformTo(null), word.wordRect);
}
