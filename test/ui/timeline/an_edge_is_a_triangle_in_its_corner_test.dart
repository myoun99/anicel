import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart'
    show timelineRowEditChromeModel;

/// 🚨I-43 (유저 2026-09-23): the edge is a triangle in the block's corner —
/// 「프레임이름이랑 엣지 겹치는거나, 엣지끼리 겹치는거나, 코마텍스트랑 엣지랑
/// 겹치는 등의 문제 … 엣지를 삼각형으로 바꿔서 왼쪽아래, 오른쪽위에 두는것임.
/// 그러면 안겹치니까」.
///
/// The three non-collisions the user named are pinned here as geometry, on
/// every rung of the zoom ladder, together with 「보이는 것 = 잡는 것」: the
/// drawn triangle is its own hit box (유저 답 09-23, (가)).
void main() {
  const cross = timelineLayerRowHeight;
  const cells = [2.4, 3.0, 4.0, 8.0, 12.0, 14.0, 24.0, 48.0, 96.0];
  const blockLengths = [1, 2, 5, 20];
  const start = 3;

  TimelineFrameGeometry frames(double cell) => TimelineFrameGeometry(
    frameCellExtent: cell,
    frameStartIndex: 0,
    frameEndIndexExclusive: 1000,
  );

  Rect gripBox(
    TimelineBlockEdge edge, {
    required int length,
    required double cell,
    int from = start,
    Axis axis = Axis.horizontal,
  }) => timelineFrameSpanRect(
    timelineBlockEdgeGripPlacement(
      edge: edge,
      startIndex: from,
      endIndexExclusive: from + length,
      crossAxisExtent: cross,
    ),
    frames(cell),
    crossAxisExtent: cross,
    axis: axis,
  );

  Path triangle(
    TimelineBlockEdge edge,
    Rect box, {
    Axis axis = Axis.horizontal,
  }) => blockEdgeGripPath(box, edge: edge, axis: axis);

  bool apart(Rect a, Rect b) {
    final overlap = a.intersect(b);
    return overlap.width <= 0 || overlap.height <= 0;
  }

  test('the box is half a cell along and a third of the row across, in the '
      'block corner — the start edge far, the end edge near, on both '
      'axes', () {
    for (final cell in cells) {
      for (final length in blockLengths) {
        final blockStart = start * cell;
        final blockEnd = (start + length) * cell;
        final why = 'cell $cell × $length frames';
        final lead = gripBox(
          TimelineBlockEdge.start,
          length: length,
          cell: cell,
        );
        final tail = gripBox(
          TimelineBlockEdge.end,
          length: length,
          cell: cell,
        );
        expect(lead.width, moreOrLessEquals(cell / 2), reason: why);
        expect(lead.height, moreOrLessEquals(cross / 3), reason: why);
        expect(lead.left, moreOrLessEquals(blockStart), reason: why);
        expect(lead.bottom, moreOrLessEquals(cross), reason: why);
        expect(tail.width, moreOrLessEquals(cell / 2), reason: why);
        expect(tail.height, moreOrLessEquals(cross / 3), reason: why);
        expect(tail.right, moreOrLessEquals(blockEnd), reason: why);
        expect(tail.top, 0, reason: why);

        // The X-sheet turns it on its side: the start edge's box sits on the
        // column's far (right) side of the first cell, the end edge's on the
        // near (left) side of the last.
        final leadV = gripBox(
          TimelineBlockEdge.start,
          length: length,
          cell: cell,
          axis: Axis.vertical,
        );
        final tailV = gripBox(
          TimelineBlockEdge.end,
          length: length,
          cell: cell,
          axis: Axis.vertical,
        );
        expect(leadV.top, moreOrLessEquals(blockStart), reason: why);
        expect(leadV.right, moreOrLessEquals(cross), reason: why);
        expect(leadV.width, moreOrLessEquals(cross / 3), reason: why);
        expect(leadV.height, moreOrLessEquals(cell / 2), reason: why);
        expect(tailV.bottom, moreOrLessEquals(blockEnd), reason: why);
        expect(tailV.left, 0, reason: why);
      }
    }
  });

  test('the drawn triangle never leaves its box and fills its corner half — '
      'the mark IS the grip, so it cannot overhang it (B5②/B6)', () {
    for (final cell in cells) {
      for (final axis in Axis.values) {
        for (final edge in TimelineBlockEdge.values) {
          final box = gripBox(edge, length: 5, cell: cell, axis: axis);
          final path = triangle(edge, box, axis: axis);
          final why = 'cell $cell, $axis, ${edge.name}';
          // A path keeps single-precision points, hence the tolerance.
          final bounds = path.getBounds();
          expect(bounds.left, greaterThanOrEqualTo(box.left - 1e-4),
              reason: why);
          expect(bounds.top, greaterThanOrEqualTo(box.top - 1e-4),
              reason: why);
          expect(bounds.right, lessThanOrEqualTo(box.right + 1e-4),
              reason: why);
          expect(bounds.bottom, lessThanOrEqualTo(box.bottom + 1e-4),
              reason: why);

          // Measured from the block's corner, in the corner's own terms: a
          // quarter of each leg in is ink, three quarters of each is not.
          final horizontal = axis == Axis.horizontal;
          final lead = edge == TimelineBlockEdge.start;
          final along = horizontal ? box.width : box.height;
          final across = horizontal ? box.height : box.width;
          Offset fromCorner(double alongShare, double acrossShare) {
            final a = lead
                ? (horizontal ? box.left : box.top) + along * alongShare
                : (horizontal ? box.right : box.bottom) - along * alongShare;
            final c = lead
                ? (horizontal ? box.bottom : box.right) - across * acrossShare
                : (horizontal ? box.top : box.left) + across * acrossShare;
            return horizontal ? Offset(a, c) : Offset(c, a);
          }

          expect(path.contains(fromCorner(0.25, 0.25)), isTrue, reason: why);
          expect(path.contains(fromCorner(0.75, 0.75)), isFalse, reason: why);
          // …and the very corner is rounded off exactly as the paper is.
          expect(path.contains(fromCorner(0.01, 0.01)), isFalse, reason: why);
        }
      }
    }
  });

  test('the dense rows answer a press in the box and ONLY in the box — the '
      'rest of the edge cell stays the cell\'s (유저 답 (가))', () {
    const cell = 24.0;
    final model = timelineRowEditChromeModel(
      gripBlocks: const [
        (
          ordinal: 0,
          startIndex: start,
          endIndexExclusive: start + 4,
          startGrip: true,
          endGrip: true,
        ),
      ],
      gripIdScope: 'probe',
      geometry: frames(cell),
      crossAxisExtent: cross,
      axis: Axis.horizontal,
      includeRunEdges: false,
    );
    String? hit(Offset point) {
      for (final target in model.targets) {
        if (target.rect.contains(point)) {
          return target.id;
        }
      }
      return null;
    }

    const blockStart = start * cell;
    const blockEnd = (start + 4) * cell;
    // The boxes themselves: the start edge low in the first cell, the end
    // edge high in the last.
    expect(
      hit(const Offset(blockStart + cell / 4, cross - cross / 6)),
      'block-edge-grip-start-probe-0',
    );
    expect(
      hit(const Offset(blockEnd - cell / 4, cross / 6)),
      'block-edge-grip-end-probe-0',
    );
    // The same edge cells anywhere else — mid-row right by the edge, and the
    // opposite corner — belong to the cell: a press there selects or moves.
    for (final point in const [
      Offset(blockStart + 1, cross / 2),
      Offset(blockStart + 1, 1),
      Offset(blockEnd - 1, cross / 2),
      Offset(blockEnd - 1, cross - 1),
    ]) {
      expect(hit(point), isNull, reason: 'a press at $point is the cell\'s');
    }
  });

  test('a one-frame block\'s two triangles never meet, and neither do the '
      'end of one block and the start of the next — 「엣지끼리 겹치는거」', () {
    for (final cell in cells) {
      final lead = gripBox(TimelineBlockEdge.start, length: 1, cell: cell);
      final tail = gripBox(TimelineBlockEdge.end, length: 1, cell: cell);
      expect(apart(lead, tail), isTrue, reason: 'cell $cell: $lead · $tail');
      final next = gripBox(
        TimelineBlockEdge.start,
        length: 1,
        cell: cell,
        from: start + 1,
      );
      expect(apart(tail, next), isTrue, reason: 'cell $cell: $tail · $next');
    }
  });

  test('the name stays off the start triangle and the 코마 number off the '
      'end triangle, at every zoom — 「프레임이름이랑 엣지 · 코마텍스트랑 '
      '엣지」', () {
    // Sample a glyph box's edges against a triangle: no sample may be ink.
    bool touches(Path path, Rect glyph) {
      for (var i = 0; i <= 8; i += 1) {
        final t = i / 8;
        for (final point in [
          Offset(glyph.left + glyph.width * t, glyph.bottom),
          Offset(glyph.left + glyph.width * t, glyph.top),
          Offset(glyph.left, glyph.top + glyph.height * t),
          Offset(glyph.right, glyph.top + glyph.height * t),
        ]) {
          if (path.contains(point)) {
            return true;
          }
        }
      }
      return false;
    }

    // Where the cells painter puts a word of [extent] in [cellStart]'s cell:
    // along by the block-word law, centred across.
    Rect name(double cellStart, double cell, double size, double extent) =>
        Rect.fromLTWH(
          timelineBlockWordStart(
            cellStart: cellStart,
            cellExtent: cell,
            wordExtent: extent,
            growth: TimelineBlockWordGrowth.towardBlockEnd,
          ),
          (cross - size) / 2,
          extent,
          size,
        );

    for (final cell in cells) {
      final lead = gripBox(TimelineBlockEdge.start, length: 4, cell: cell);
      final tail = gripBox(TimelineBlockEdge.end, length: 4, cell: cell);
      final firstCell = start * cell;
      final nameSize = timelineFittedGlyphFontSize(
        14,
        cell,
        crossExtent: cross,
      );
      // A one-digit name — the common case — at a digit's advance.
      final digit = name(firstCell, cell, nameSize, nameSize * 0.6);
      expect(
        touches(triangle(TimelineBlockEdge.start, lead), digit),
        isFalse,
        reason: 'cell $cell: the name $digit meets the start triangle',
      );
      // Zoomed out the name is FITTED, and a fitted name clears the triangle
      // however wide it runs — the zooms the report was about.
      if (cell < 12) {
        final wide = name(firstCell, cell, nameSize, cell * 3);
        expect(
          touches(triangle(TimelineBlockEdge.start, lead), wide),
          isFalse,
          reason: 'cell $cell: a long name $wide meets the start triangle',
        );
      }

      // The 코마 number: at the far end of the last cell, 1px in.
      final komaSize = timelineFittedGlyphFontSize(
        9,
        cell,
        crossExtent: cross,
      );
      final komaHeight = komaSize * 1.25;
      final koma = Rect.fromLTWH(
        (start + 4) * cell - cell * 2,
        cross - 1 - komaHeight,
        cell * 2,
        komaHeight,
      );
      expect(
        touches(triangle(TimelineBlockEdge.end, tail), koma),
        isFalse,
        reason: 'cell $cell: the 코마 number $koma meets the end triangle',
      );
    }
  });
}
