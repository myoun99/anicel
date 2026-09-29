import 'package:anicel/src/ui/timeline/timeline_block_word.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds a block word written in a line ([TimelineBlockText]) carrying
/// [text] — a lane key's name, an instruction's writing on the timeline, an
/// SE name on the sheet.
///
/// The word sets its own letters and paints them, so it emits no `Text`
/// widget and `find.text` sees nothing; this is the replacement finder.
Finder findBlockText(String text) {
  return find.byWidgetPredicate(
    (widget) => widget is TimelineBlockText && widget.text == text,
    description: 'block text "$text"',
  );
}

/// Where the word [finder] finds lands on screen, narrowed — its ink, not
/// its box: the box is the word's room.
Rect blockTextRect(WidgetTester tester, Finder finder) {
  final word = tester.renderObject<RenderTimelineBlockText>(finder);
  return MatrixUtils.transformRect(word.getTransformTo(null), word.wordRect);
}
