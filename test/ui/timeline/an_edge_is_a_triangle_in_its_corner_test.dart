import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show TimelineBlockEdge;
import 'package:anicel/src/ui/timeline/timeline_beat_lines.dart'
    show timelineRowPaperExtent;
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_comma_drag_handle.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_span_layout.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeight;
import 'package:anicel/src/ui/timeline/timeline_row_edit_chrome.dart'
    show
        TimelineRowChromeResolver,
        TimelineRowEditChromePainter,
        timelineRowEditChromeModel;

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
  // I-44: the grips sit on the PAPER, which stops short of the row seam the
  // grid sheet draws under the row.
  final paper = timelineRowPaperExtent(cross);
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
      // The rows hand the grip their PAPER (I-44).
      crossAxisExtent: paper,
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

  test('the box is a third of a cell along and half the row across, in the '
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
        expect(lead.width, moreOrLessEquals(cell / 3), reason: why);
        expect(lead.height, moreOrLessEquals(paper / 2), reason: why);
        expect(lead.left, moreOrLessEquals(blockStart), reason: why);
        expect(lead.bottom, moreOrLessEquals(paper), reason: why);
        expect(tail.width, moreOrLessEquals(cell / 3), reason: why);
        expect(tail.height, moreOrLessEquals(paper / 2), reason: why);
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
        expect(leadV.right, moreOrLessEquals(paper), reason: why);
        expect(leadV.width, moreOrLessEquals(paper / 2), reason: why);
        expect(leadV.height, moreOrLessEquals(cell / 3), reason: why);
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

  test('🚨the triangle IS the paper\'s corner, inked: ink exactly where the '
      'triangle and the block\'s own rounded paper overlap — at every zoom, '
      'the ones whose along leg is shorter than the paper\'s round included '
      '(유저 09-23: 「모서리랑 블록이랑 모서리가 통일안되서 … 확실하게 '
      '통일해줘」)', () {
    for (final cell in cells) {
      for (final edge in TimelineBlockEdge.values) {
        final box = gripBox(edge, length: 5, cell: cell);
        final path = triangle(edge, box);
        // The block's paper, drawn the way the cells painter draws it: the
        // block corner law on the paper box (I-44: the row short of its seam).
        final block = Rect.fromLTWH(start * cell, 0, 5 * cell, paper);
        final rounded = RRect.fromRectAndRadius(
          block,
          timelineBlockCornerRadiusAt(cellExtent: cell, crossExtent: paper),
        );
        final lead = edge == TimelineBlockEdge.start;
        // A corner-anchored right triangle: ink iff inside both.
        bool inTriangle(Offset p) {
          final u = lead ? p.dx - box.left : box.right - p.dx;
          final v = lead ? box.bottom - p.dy : p.dy - box.top;
          return u >= 0 &&
              v >= 0 &&
              u / box.width + v / box.height <= 1;
        }

        // Stay a hair off every boundary: the question is the shape, not
        // which side a point exactly on an edge rounds to.
        bool nearBoundary(Offset p) {
          const eps = 0.02;
          for (final dx in const [-eps, eps]) {
            for (final dy in const [-eps, eps]) {
              final q = p.translate(dx, dy);
              if (inTriangle(q) != inTriangle(p) ||
                  rounded.contains(q) != rounded.contains(p)) {
                return true;
              }
            }
          }
          return false;
        }

        const steps = 40;
        for (var i = 0; i <= steps; i += 1) {
          for (var j = 0; j <= steps; j += 1) {
            final p = Offset(
              box.left + box.width * i / steps,
              box.top + box.height * j / steps,
            );
            if (nearBoundary(p)) {
              continue;
            }
            expect(
              path.contains(p),
              inTriangle(p) && rounded.contains(p),
              reason: 'cell $cell, ${edge.name}: $p',
            );
          }
        }
      }
    }
  });

  test('the round end grows by the bleed and nothing else does — the paper\'s '
      'edge pixels are covered, the neighbours\' are not', () {
    const cell = 24.0;
    const bleed = 1.0;
    for (final edge in TimelineBlockEdge.values) {
      final box = gripBox(edge, length: 5, cell: cell);
      final plain = triangle(edge, box);
      final grown = blockEdgeGripPath(
        box,
        edge: edge,
        axis: Axis.horizontal,
        arcBleed: bleed,
      );
      final bounds = grown.getBounds();
      expect(bounds.left, greaterThanOrEqualTo(box.left - 1e-4));
      expect(bounds.top, greaterThanOrEqualTo(box.top - 1e-4));
      expect(bounds.right, lessThanOrEqualTo(box.right + 1e-4));
      expect(bounds.bottom, lessThanOrEqualTo(box.bottom + 1e-4));
      // Half the bleed outside the paper's circle, on the diagonal toward
      // the corner: the grown mark has it, the plain one does not.
      const r = 6.0;
      final lead = edge == TimelineBlockEdge.start;
      final corner = lead ? box.bottomLeft : box.topRight;
      final inward = lead ? const Offset(1, -1) : const Offset(-1, 1);
      final center = corner + inward * r;
      final probe = center - inward / inward.distance * (r + bleed / 2);
      expect(plain.contains(probe), isFalse, reason: edge.name);
      expect(grown.contains(probe), isTrue, reason: edge.name);
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
      // As the cells row hands its chrome: the paper (I-44).
      crossAxisExtent: paper,
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
    // edge high in the last — on the PAPER (I-44).
    expect(
      hit(Offset(blockStart + cell / 4, paper - paper / 6)),
      'block-edge-grip-start-probe-0',
    );
    expect(
      hit(Offset(blockEnd - cell / 4, paper / 6)),
      'block-edge-grip-end-probe-0',
    );
    // The same edge cells anywhere else — just above the start box and just
    // below the end box right by the edge, just past each box along the
    // frame axis, the opposite corners, and the row seam's own pixel under
    // the start box — belong to the cell: a press there selects or moves.
    for (final point in [
      Offset(blockStart + 1, paper / 2 - 1),
      const Offset(blockStart + 1, 1),
      Offset(blockStart + cell / 3 + 1, paper - 1),
      Offset(blockStart + cell / 6, paper + 0.5),
      Offset(blockEnd - 1, paper / 2 + 1),
      Offset(blockEnd - 1, paper - 1),
      const Offset(blockEnd - cell / 3 - 1, 1),
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

  test('the name stays off the start triangle and the 코마 number off the '
      'end triangle, at every zoom — 「프레임이름이랑 엣지 · 코마텍스트랑 '
      '엣지」', () {
    for (final cell in cells) {
      final lead = gripBox(TimelineBlockEdge.start, length: 4, cell: cell);
      final tail = gripBox(TimelineBlockEdge.end, length: 4, cell: cell);
      final firstCell = start * cell;
      final nameSize = timelineFittedGlyphFontSize(
        14,
        cell,
        crossExtent: cross,
      );
      // A one-digit name — the common case — at a digit's advance. ⚠️The
      // smallest rung is the open question's (below), not this one's.
      if (cell >= 3) {
        final digit = name(firstCell, cell, nameSize, nameSize * 0.6);
        expect(
          touches(triangle(TimelineBlockEdge.start, lead), digit),
          isFalse,
          reason: 'cell $cell: the name $digit meets the start triangle',
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

  test('⚠️OPEN (I-43-Q1): with the half-row triangle a name wider than its '
      'cell reaches the start triangle when zoomed out — the proportion 유저 '
      'asked for (09-23) against the clearance I-43 was for, until they '
      'choose', () {
    for (final cell in cells.where((cell) => cell < 12)) {
      final lead = gripBox(TimelineBlockEdge.start, length: 4, cell: cell);
      final size = timelineFittedGlyphFontSize(14, cell, crossExtent: cross);
      final wide = name(start * cell, cell, size, cell * 3);
      expect(
        touches(triangle(TimelineBlockEdge.start, lead), wide),
        isTrue,
        reason: 'cell $cell: I-43-Q1 is answered — rewrite this pin',
      );
    }
    // …and at the smallest rung even a one-digit name grazes its apex.
    final lead = gripBox(TimelineBlockEdge.start, length: 4, cell: 2.4);
    final size = timelineFittedGlyphFontSize(14, 2.4, crossExtent: cross);
    expect(
      touches(
        triangle(TimelineBlockEdge.start, lead),
        name(start * 2.4, 2.4, size, size * 0.6),
      ),
      isTrue,
    );
  });

  test('both painters draw the round end grown by ONE DEVICE PIXEL — the dense '
      'rows\' chrome and the widget grip alike, so the paper\'s edge never '
      'shows past a hovered mark', () {
    const cell = 24.0;
    const r = 6.0;
    for (final ratio in const [1.0, 2.0]) {
      // Half a device pixel outside the paper's circle, on the diagonal
      // toward the end edge's corner: ink only if the bleed is there.
      Offset probe(Rect box) {
        final center = box.topRight + const Offset(-r, r);
        const inward = Offset(-1, 1);
        return center -
            inward / inward.distance * (r + 0.5 / ratio);
      }

      // The widget grip paints into its own box, at its own origin.
      final widgetBox = gripBox(TimelineBlockEdge.end, length: 5, cell: cell);
      final widgetSpy = _PathSpy();
      BlockEdgeGripPainter(
        edge: TimelineBlockEdge.end,
        axis: Axis.horizontal,
        ink: BlockEdgeGripInk.hovered,
        devicePixelRatio: ratio,
      ).paint(widgetSpy, widgetBox.size);
      expect(
        widgetSpy.paths.single.contains(probe(Offset.zero & widgetBox.size)),
        isTrue,
        reason: 'the widget grip at ${ratio}x',
      );

      final geometry = ValueNotifier(frames(cell));
      addTearDown(geometry.dispose);
      final chromeSpy = _PathSpy();
      TimelineRowEditChromePainter(
        resolver: TimelineRowChromeResolver(
          gripBlocks: const [
            (
              ordinal: 0,
              startIndex: start,
              endIndexExclusive: start + 5,
              startGrip: false,
              endGrip: true,
            ),
          ],
          gripIdScope: 'probe',
          layer: null,
          baseLayer: null,
          crossAxisExtent: paper,
          axis: Axis.horizontal,
          includeRunEdges: false,
        ),
        geometry: geometry,
        colorScheme: const ColorScheme.dark(),
        hoveredId: null,
        operatingId: null,
        draggingGripId: null,
        devicePixelRatio: ratio,
      ).paint(chromeSpy, const Size(1000, cross));
      expect(
        chromeSpy.paths.single.contains(
          probe(gripBox(TimelineBlockEdge.end, length: 5, cell: cell)),
        ),
        isTrue,
        reason: 'the dense rows\' chrome at ${ratio}x',
      );
    }
  });
}

class _PathSpy implements Canvas {
  final paths = <Path>[];

  @override
  void drawPath(Path path, Paint paint) => paths.add(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
