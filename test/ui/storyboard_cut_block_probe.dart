import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';

/// The cut row's blocks are PAINTED, so tests read them off the painter's
/// probe instead of hunting for a widget key per cut.
///
/// Same idea as the timeline's row probes: the painter is the single source
/// of what the row shows, and a finder that walked widgets would only find
/// the chrome above it.
Finder cutBlocksFinder({String? trackId}) => trackId == null
    ? find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter is StoryboardCutBlocksPainter,
      )
    : find.byKey(ValueKey<String>('storyboard-cut-blocks-$trackId'));

List<StoryboardCutBlocksPainter> cutBlocksPainters(
  WidgetTester tester, {
  String? trackId,
}) => [
  for (final paint in tester.widgetList<CustomPaint>(
    cutBlocksFinder(trackId: trackId),
  ))
    paint.painter! as StoryboardCutBlocksPainter,
];

StoryboardCutBlocksPainter cutBlocksPainter(
  WidgetTester tester, {
  String? trackId,
}) => cutBlocksPainters(tester, trackId: trackId).first;

/// Every block the panel would draw, track by track.
List<StoryboardCutBlockVisual> cutBlocks(
  WidgetTester tester, {
  String? trackId,
}) => [
  for (final painter in cutBlocksPainters(tester, trackId: trackId))
    ...painter.blocks(),
];

/// One cut's block, or null when no row draws it (off-window, or no such
/// cut). Searches every V row unless [trackId] narrows it.
StoryboardCutBlockVisual? cutBlock(
  WidgetTester tester,
  String cutId, {
  String? trackId,
}) {
  for (final painter in cutBlocksPainters(tester, trackId: trackId)) {
    final block = painter.blockForCut(CutId(cutId));
    if (block != null) {
      return block;
    }
  }
  return null;
}

/// The block for [cutId], failing the test when the row does not draw it.
StoryboardCutBlockVisual requireCutBlock(
  WidgetTester tester,
  String cutId, {
  String? trackId,
}) {
  final block = cutBlock(tester, cutId, trackId: trackId);
  expect(block, isNotNull, reason: 'no painted cut block for $cutId');
  return block!;
}

/// [cutId]'s block in SCREEN coordinates — what a gesture needs.
Rect cutBlockScreenRect(WidgetTester tester, String cutId, {String? trackId}) {
  final finder = cutBlocksFinder(trackId: trackId);
  final painters = cutBlocksPainters(tester, trackId: trackId);
  for (var index = 0; index < painters.length; index += 1) {
    final block = painters[index].blockForCut(CutId(cutId));
    if (block != null) {
      return block.rect.shift(tester.getTopLeft(finder.at(index)));
    }
  }
  fail('no painted cut block for $cutId');
}

Offset cutBlockCenter(WidgetTester tester, String cutId, {String? trackId}) =>
    cutBlockScreenRect(tester, cutId, trackId: trackId).center;

/// A point on the cut's TOP BAND — the CUT's own handle.
///
/// The block's middle is the strip, and the strip belongs to the cut's
/// panels, so a drag that means "this cut" (slide it, select the run) has
/// to start on a band. The centre still works for a plain tap, which both
/// gestures pass through to the cells press underneath.
Offset cutBlockBandCenter(
  WidgetTester tester,
  String cutId, {
  String? trackId,
}) {
  final rect = cutBlockScreenRect(tester, cutId, trackId: trackId);
  return Offset(
    rect.center.dx,
    rect.top + StoryboardCutBlocksPainter.bandHeight / 2,
  );
}
