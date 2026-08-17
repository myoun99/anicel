import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';

/// B5②/B6 (2026-08-17): the SPARSE rows' grip placement resolves to the
/// SAME hit width as the dense rows' [blockEdgeGripHitExtent] — one law.
///
/// The placement form used to skip the block floor, so at the storyboard's
/// 8px-a-frame zoom a grip was a ~2.7px sliver whose painted bar overhung
/// its own hit strip: hover engaged "at the block's tip, not at the edge".
/// This sweep pins the two forms together across zooms and block lengths;
/// reverting the placement to cell-only goes red here.
void main() {
  const cellExtents = [4.0, 8.0, 12.0, 24.0, 36.0, 60.0];
  const blockLengths = [1, 2, 5, 20];

  Rect resolve(TimelineFrameSpanPlacement placement, double cellExtent) {
    final geometry = TimelineFrameGeometry(
      frameCellExtent: cellExtent,
      frameStartIndex: 0,
      frameEndIndexExclusive: 1000,
    );
    final layout = RenderTimelineFrameSpanLayout(
      geometry: ValueNotifier<TimelineFrameGeometry>(geometry),
      crossAxisExtent: 30,
      axis: Axis.horizontal,
    );
    return layout.rectFor(placement, geometry);
  }

  test('the placement grip resolves to blockEdgeGripHitExtent, every zoom, '
      'every block length, both edges', () {
    for (final cellExtent in cellExtents) {
      for (final blockLength in blockLengths) {
        const start = 3;
        final endExclusive = start + blockLength;
        final lawWidth = blockEdgeGripHitExtent(
          cellExtent,
          blockExtent: blockLength * cellExtent,
        );
        for (final edge in TimelineBlockEdge.values) {
          final rect = resolve(
            timelineBlockEdgeGripPlacement(
              edge: edge,
              startIndex: start,
              endIndexExclusive: endExclusive,
            ),
            cellExtent,
          );
          expect(
            rect.width,
            moreOrLessEquals(lawWidth),
            reason:
                'cell $cellExtent × $blockLength frames, ${edge.name} edge: '
                'the sparse form must resolve the dense law\'s width',
          );
          // And ON the edge: the start grip leads from the block's leading
          // edge, the end grip trails INTO the block's trailing edge.
          if (edge == TimelineBlockEdge.start) {
            expect(rect.left, moreOrLessEquals(start * cellExtent));
          } else {
            expect(rect.right, moreOrLessEquals(endExclusive * cellExtent));
          }
        }
      }
    }
  });

  test('where the law grants the 6px floor, the painted bar fits INSIDE the '
      'hit strip again — the overhang was the reported symptom', () {
    // 8px cells, 5-frame block: the storyboard's resting zoom and the
    // user's repro shape. Floor = 6px.
    final width = blockEdgeGripHitExtent(8, blockExtent: 40);
    expect(width, 6);
    for (final edge in TimelineBlockEdge.values) {
      final bar = blockEdgeGripBarRect(
        edge: edge,
        hitExtent: width,
        crossAxisExtent: 30,
        axis: Axis.horizontal,
      );
      expect(bar.left, greaterThanOrEqualTo(0));
      expect(bar.right, lessThanOrEqualTo(width));
    }
  });
}
