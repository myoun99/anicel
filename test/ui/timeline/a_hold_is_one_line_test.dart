import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show endAlong, offsetAlong, partAcross, rectAlong, sizeAlong, startAlong;
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart'
    show timelineHoldLineInset, timelineJoiningLineWidth;
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_tile_raster_source.dart';

import '../../helpers/run_edge_fixtures.dart';
import 'timeline_frame_geometry_probe.dart';

/// A HOLD IS ONE LINE (I-73, 유저 2026-10-08).
///
/// 「점선말고 이어진선으로하자. 쓸데없이 보기힘들어. 잘 이어지도록」 · 「실선으로
/// 바꿈. 뒤집는거임」 — what it turns round is UI-R12 #18's dash a cell, each
/// with a 3px break at its boundaries (「이어진 느낌, 완벽하게는 안 이어지게」).
///
/// And where the line is did not move — 「블록에 그리는게아니라 성질이 홀드일때
/// 빈공간에 그리는것임」: the FREE cells beside a run whose edge property is
/// hold, never a block's own.
///
/// A hold is a ghost's ink, so no tile bakes it: the row strokes it over its
/// tiles (F-446), the one line the painter answers
/// ([TimelineRowCellsPainter.holdLinesIn]).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cut = 12;
  const cell = 24.0;
  const rowExtent = 28.0;
  const half = timelineJoiningLineWidth / 2;

  Layer rowOf(Map<int, TimelineExposure> timeline) => rederiveRunBehaviors(
    Layer(
      id: const LayerId('row'),
      name: 'A',
      frames: [
        Frame(id: const FrameId('a'), duration: 1, strokes: const []),
        Frame(id: const FrameId('b'), duration: 1, strokes: const []),
      ],
      timeline: timeline,
    ),
    drawnFrameCount: cut,
  );

  // A block over 2..4 that holds: its ghost is the free cells 5..11.
  final held = rowOf({
    2: const TimelineExposure.drawing(
      FrameId('a'),
      length: 3,
      endEdge: holdMark,
    ),
  });
  // A block over 6..8 that holds BEFORE itself: the lead-in 0..5.
  final ledIn = rowOf({
    6: const TimelineExposure.drawing(
      FrameId('a'),
      length: 3,
      startEdge: holdMark,
    ),
  });
  // A hold that meets the next run: its ghost is 3..7.
  final stopped = rowOf({
    1: const TimelineExposure.drawing(
      FrameId('a'),
      length: 2,
      endEdge: holdMark,
    ),
    8: const TimelineExposure.drawing(FrameId('b'), length: 2),
  });
  // A block that REPEATS into its free cells.
  final repeated = rowOf({
    2: const TimelineExposure.drawing(
      FrameId('a'),
      length: 2,
      endEdge: repeatMark,
    ),
  });

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  TimelineRowCellsPainter painterFor(
    Layer layer, {
    Axis axis = Axis.horizontal,
    double frameCellExtent = cell,
    int frameEndIndexExclusive = cut,
  }) => TimelineRowCellsPainter(
    layer: layer,
    geometry: testFrameGeometry(
      frameCellExtent: frameCellExtent,
      frameEndIndexExclusive: frameEndIndexExclusive,
    ),
    crossAxisExtent: rowExtent,
    exposureStateForLayer: stateFor,
    colorScheme: const ColorScheme.dark(),
    baseTextStyle: const TextStyle(fontSize: 11),
    axis: axis,
  );

  /// The box of a hold's whole line over the cells [first, last] of
  /// [painter]'s row: stood in from the two cells' outer edges, as thick as
  /// a hold's line about the row's middle.
  Rect wholeLineOver(TimelineRowCellsPainter painter, int first, int last) {
    final head = painter.cellRectFor(first);
    final tail = painter.cellRectFor(last);
    final axis = painter.axis;
    final middle = partAcross(axis, head.center);
    return rectAlong(
      axis,
      along: (
        from: startAlong(axis, head) + timelineHoldLineInset,
        to: endAlong(axis, tail) - timelineHoldLineInset,
      ),
      across: (from: middle - half, to: middle + half),
    );
  }

  group('a hold is one line', () {
    test('from the first of its free cells to the last — one line, however '
        'many cells it runs through', () {
      final painter = painterFor(held);
      final line = theOne(painter.holdLinesIn(0, cut));
      expect(line.box, rectMoreOrLessEquals(wholeLineOver(painter, 5, 11)));
      expect(line.startsHere, isTrue);
      expect(line.endsHere, isTrue);
      expect(
        line.ink,
        painter.foregroundInkFor(painter.cellModelAt(5)),
        reason: 'the ghost\'s own ink',
      );
    });

    test('in the free cells beside the run — never in a block\'s own', () {
      final painter = painterFor(held);
      expect(
        painter.holdLinesIn(0, 5),
        isEmpty,
        reason: 'the block stands on 2..4 and nothing before it holds',
      );
      final line = theOne(painter.holdLinesIn(0, cut));
      expect(
        line.box.left,
        greaterThan(painter.cellRectFor(4).right),
        reason: 'the line starts past the block\'s last cell',
      );
    });

    test('a lead-in hold is its mirror: the free cells BEFORE the run', () {
      final painter = painterFor(ledIn);
      final line = theOne(painter.holdLinesIn(0, cut));
      expect(line.box, rectMoreOrLessEquals(wholeLineOver(painter, 0, 5)));
      expect((line.startsHere, line.endsHere), (true, true));
    });

    test('it stops where the next run stands', () {
      final painter = painterFor(stopped);
      final line = theOne(painter.holdLinesIn(0, cut));
      expect(line.box, rectMoreOrLessEquals(wholeLineOver(painter, 3, 7)));
    });

    test('a repeat\'s ghost has no line — it prints its names', () {
      final painter = painterFor(repeated);
      expect(painter.cellModelAt(4).ghost, isTrue, reason: 'the fixture');
      expect(painter.holdLinesIn(0, cut), isEmpty);
    });

    test('down the sheet it runs down', () {
      final painter = painterFor(held, axis: Axis.vertical);
      final line = theOne(painter.holdLinesIn(0, cut));
      expect(line.box, rectMoreOrLessEquals(wholeLineOver(painter, 5, 11)));
      expect(line.box.height, greaterThan(line.box.width));
    });

    test('its cells write nothing of their own — the line is all a hold '
        'inks', () {
      final painter = painterFor(held);
      for (var frame = 5; frame < cut; frame += 1) {
        expect(
          painter.cellModelAt(frame).glyph,
          timelineHoldGlyph,
          reason: 'frame $frame reads as a hold',
        );
      }
      expect(painter.writingCellsIn(5, cut), isEmpty);
    });

    test('no room between its two ends, no line: a hold of one frame at a '
        'far zoom — and a long hold still shows there', () {
      // 2px cells: one frame leaves −1px between the two insets.
      final short = painterFor(
        rowOf({
          2: const TimelineExposure.drawing(
            FrameId('a'),
            length: 9,
            endEdge: holdMark,
          ),
        }),
        frameCellExtent: 2,
      );
      expect(short.cellModelAt(11).glyph, timelineHoldGlyph);
      expect(short.holdLinesIn(0, cut), isEmpty);

      // ↩️A dash a cell was dropped at 4px cells and under, every one of
      // them: zoomed out, a hold showed nothing at all.
      final long = painterFor(held, frameCellExtent: 2);
      expect(
        theOne(long.holdLinesIn(0, cut)).box,
        rectMoreOrLessEquals(wholeLineOver(long, 5, 11)),
      );
    });
  });

  group('a stretch of the row gets its part of the line', () {
    // ↩️It reached through the cell past the stretch, for the sliver a
    // tile's last pixel held (F-208). No tile holds a hold now (F-446).
    test('stopping inside the hold: to its own edges, square', () {
      final painter = painterFor(held);
      final part = theOne(painter.holdLinesIn(7, 9));
      expect((part.startsHere, part.endsHere), (false, false));
      expect(part.box.left, painter.cellRectFor(7).left);
      expect(part.box.right, painter.cellRectFor(8).right);
    });

    test('holding the hold\'s start: that end is the hold\'s own', () {
      final painter = painterFor(held);
      final part = theOne(painter.holdLinesIn(0, 7));
      expect((part.startsHere, part.endsHere), (true, false));
      expect(part.box.left, wholeLineOver(painter, 5, 11).left);
      expect(part.box.right, painter.cellRectFor(6).right);
    });

    test('holding the hold\'s end: that end is the hold\'s own', () {
      final painter = painterFor(held);
      final part = theOne(painter.holdLinesIn(7, cut));
      expect((part.startsHere, part.endsHere), (false, true));
      expect(part.box.left, painter.cellRectFor(7).left);
      expect(part.box.right, wholeLineOver(painter, 5, 11).right);
    });

    test('nothing reaches past the last cell the row has', () {
      // The row's cells stop at 9; the hold runs on to 11.
      final painter = painterFor(held, frameEndIndexExclusive: 9);
      final part = theOne(painter.holdLinesIn(5, 9));
      expect(part.endsHere, isFalse);
      expect(part.box.right, painter.cellRectFor(8).right);
    });

    test('a stretch the hold does not reach has none of it', () {
      final painter = painterFor(stopped);
      expect(painter.holdLinesIn(8, cut), isEmpty, reason: 'past its end');
      expect(painter.holdLinesIn(0, 3), isEmpty, reason: 'before its start');
    });
  });

  group('the classic pass strokes that line once', () {
    for (final axis in Axis.values) {
      test('$axis', () {
        final painter = painterFor(held, axis: axis);
        final spy = _StrokeSpy();
        painter.paint(
          spy,
          sizeAlong(axis, along: cut * cell, across: rowExtent),
        );
        final box = wholeLineOver(painter, 5, 11);
        final stroke = theOne(spy.strokes);
        final middle = partAcross(axis, box.center);
        // Round ends INSIDE the box: the stroke stops half its width short
        // of each of the hold's own ends.
        expect(
          stroke.from,
          offsetMoreOrLessEquals(
            offsetAlong(
              axis,
              along: startAlong(axis, box) + half,
              across: middle,
            ),
          ),
        );
        expect(
          stroke.to,
          offsetMoreOrLessEquals(
            offsetAlong(
              axis,
              along: endAlong(axis, box) - half,
              across: middle,
            ),
          ),
        );
        // A paint keeps its width in 32 bits.
        expect(
          stroke.width,
          moreOrLessEquals(timelineJoiningLineWidth, epsilon: 1e-6),
        );
        expect(stroke.cap, StrokeCap.round);
        // …and its colour in 8 bits a channel.
        expect(
          stroke.color.toARGB32(),
          painter.foregroundInkFor(painter.cellModelAt(5)).toARGB32(),
        );
      });
    }
  });

  // ↩️The tile baked that line as one capsule — round at the hold's own
  // ends, square where it ran out of the span. A hold is a ghost's ink, and
  // a ghost is what the cut's length draws: an end-line step moved it, and
  // the tile it ended in baked again, on every row (F-446).
  group('no tile bakes that line — the row strokes it over them', () {
    Future<List<int>> opsOf(
      TimelineRowCellsPainter painter,
      int from,
      int to, {
      required double dpr,
    }) => TimelineGridTileStore.instance.debugForegroundOps(
      painter: painter,
      spanStartIndex: from,
      spanEndIndexExclusive: to,
      devicePixelRatio: dpr,
    );

    for (final axis in Axis.values) {
      for (final dpr in [1.0, 1.5]) {
        test('a span inside the hold bakes no ink ($axis, dpr $dpr)', () async {
          final painter = painterFor(held, axis: axis);
          expect(
            await opsOf(painter, 0, 4, dpr: dpr),
            isNotEmpty,
            reason: '⛔CONTROL: the X before the block is baked',
          );
          for (final (from, to) in [(4, 8), (8, cut)]) {
            expect(
              await opsOf(painter, from, to, dpr: dpr),
              isEmpty,
              reason: '[$from, $to) holds only the block\'s tail and the hold',
            );
          }
        });
      }
    }
  });
}

/// Records what a paint strokes as lines — a hold's line is the one line a
/// row of blocks draws.
class _StrokeSpy implements Canvas {
  final strokes =
      <({Offset from, Offset to, double width, StrokeCap cap, Color color})>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    strokes.add((
      from: p1,
      to: p2,
      width: paint.strokeWidth,
      cap: paint.strokeCap,
      color: paint.color,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The only one of [found] — a pin that expects one fails by saying how
/// many there were.
T theOne<T>(Iterable<T> found) {
  final all = found.toList();
  expect(all, hasLength(1));
  return all.single;
}
