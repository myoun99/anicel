
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'axis_turn.dart' show offsetAlong;
import 'frame_window_semantics.dart';

import 'timeline_beat_lines.dart';
import 'timeline_cell_style.dart';
import 'timeline_frame_window.dart';
import 'timeline_glyph_cache.dart';
import 'timeline_grid_metrics.dart';
import '../repaint_props.dart';

/// The ruler's top-line SECOND mark at [frameIndex], or '' off a boundary.
///
/// 🚨COUNTED FROM 0, because a ruler mark is a POSITION on the time axis and
/// what has elapsed at the first frame is nothing (유저 2026-08-13: 「초
/// 표시하는곳. 1부터 시작하는데 그게아니라 0부터 시작하도록」). At 24fps the
/// mark on frame 25 is where exactly one second has passed, so `1` belongs
/// there and `0` belongs at the head.
///
/// ⛔This is NOT the `s+ff` notation of a cut's LENGTH
/// ([ProjectFrameRate]'s formatter, the conte sheet's totals). A length is a
/// count and 24 frames is `1+0`; the two look alike and answer different
/// questions, so they stay separate functions.
///
/// One function because the timeline, the storyboard and the x-sheet all ask
/// it: the expression used to be written out twice, letter for letter, and
/// fixing one would have left the sheet counting from 1.
String timelineRulerSecondsLabel({
  required int frameIndex,
  required int framesPerSecond,
}) {
  final safeFps = framesPerSecond > 0 ? framesPerSecond : 24;
  return frameIndex % safeFps == 0
      ? timelineRulerSecondOf(frameIndex: frameIndex, framesPerSecond: safeFps)
      : '';
}

/// The second [frameIndex] lies in, counted from 0 like the marks — what
/// the playhead writes on the seconds line wherever it stands (I-16); the
/// marks print it only where a second begins.
String timelineRulerSecondOf({
  required int frameIndex,
  required int framesPerSecond,
}) {
  final safeFps = framesPerSecond > 0 ? framesPerSecond : 24;
  return '${frameIndex ~/ safeFps}';
}

/// The playhead's own ink on a ruler strip (I-16 「볼드체로」): bold, on the
/// full-strength text colour — one answer for the ruler and the rail.
TextStyle timelineRulerPlayheadInk(ColorScheme colorScheme) =>
    TextStyle(fontWeight: FontWeight.w700, color: colorScheme.onSurface);

/// The resolved per-header model — THE probe surface for ruler tests
/// (labels, states and colors live here, not in widget trees), the ruler
/// counterpart of the cells painter's model (UI-R9 #12b → UI-R13 #1).
class TimelineRulerHeaderModel {
  const TimelineRulerHeaderModel({
    required this.frameIndex,
    required this.label,
    required this.secondsLabel,
    required this.selected,
    required this.outsidePlaybackRange,
    required this.background,
  });

  final int frameIndex;

  /// The bottom-line number ('' when the cell is unlabeled at this zoom).
  final String label;

  /// The top-line second index ('' off second boundaries).
  final String secondsLabel;

  final bool selected;
  final bool outsidePlaybackRange;
  final Color background;
}

/// The frame ruler strip as ONE CustomPainter (UI-R13 #1 — the same
/// painterization the drawing rows got in UI-R9 #12b): header cell
/// backgrounds/borders, the two-line labels (UI-R10 #27) and the cached
/// green strip paint in a single pass; the per-frame header widgets are
/// gone. Shared by the timeline header and the storyboard ruler (which
/// already share [TimelineFrameHeaderRow]); scrubbing stays on the
/// viewport-level listeners (G8) — the strip itself is passive.
class TimelineFrameRulerPainter extends CustomPainter with RepaintOnProps {
  TimelineFrameRulerPainter({required this.scale})
    : super(repaint: scale.windowBucket);

  /// The frame scale this strip draws — shared, field for field, with the
  /// X-sheet's rail painter, and the rect and the model with it.
  final TimelineRulerScale scale;

  @override
  void paint(Canvas canvas, Size size) {
    final colorScheme = scale.colorScheme;
    final fillPaint = Paint();
    final linePaint = Paint()..strokeWidth = 1;

    // Self-windowing (UI-R15): only the headers under the live viewport
    // record — a scroll is a repaint of this thin pass, never a rebuild.
    final window = scale.visibleWindow();

    // PASS 1 — paper, and on it the SAME grid the cells use (R26 #40):
    // base cadence lines, 6f stronger, second boundaries strongest
    // ([TimelineRulerScale.paintCellPaper] — the rail's and the playhead
    // writing's too). Painting every cell's paper BEFORE any label is what
    // keeps a narrow cell's label alive: the old single pass let the next
    // cell's fill erase the half that overflowed (R26 #39, "텍스트 절반이
    // 사라짐"). The cached-range strip is NOT here — it moved to
    // [TimelineRulerCursorOverlay] with the cursor tint, because its
    // truth is derived state that no gate can compare.
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      scale.paintCellPaper(
        canvas,
        frameIndex,
        fill: fillPaint,
        line: linePaint,
      );
    }
    linePaint.strokeWidth = 1;

    // PASS 2 — labels last, so nothing can paint over them.
    for (
      var frameIndex = window.startIndex;
      frameIndex < window.endIndexExclusive;
      frameIndex += 1
    ) {
      for (final glyph in glyphsAt(scale, frameIndex, current: false)) {
        glyph.paint(canvas);
      }
    }

    // The strip's structural BASELINE (the ruler/body divider) — full
    // strength, once, whatever the zoom; per-cell borders above stay
    // faint (UI-R14 #4).
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      linePaint..color = colorScheme.outlineVariant,
    );

    // And the strip's TOP edge, drawn the same way. The ruler is the grid's
    // first row, and the command bar above it is now the SAME chrome fill,
    // so the seam between the panel's toolbar and its content has to be a
    // line — without it the row of frame numbers reads as the bottom half of
    // the toolbar. It lands collinear with the legend header's own top
    // border beside it, so the grid keeps one continuous top edge.
    canvas.drawLine(
      const Offset(0, 0.5),
      Offset(size.width, 0.5),
      linePaint..color = colorScheme.outlineVariant,
    );
  }

  /// Where the ruler writes at [frameIndex] — the frame number on the
  /// bottom line and the second on the top corner (UI-R10 #27). With
  /// [current] it is the playhead's own pair there (I-16): the number
  /// whatever the cadence says, the second whatever the boundary says, both
  /// in [timelineRulerPlayheadInk].
  static List<TimelineGlyphPlacement> glyphsAt(
    TimelineRulerScale scale,
    int frameIndex, {
    required bool current,
  }) {
    final writing = scale.writingAt(frameIndex, current: current);
    final rect = scale.cellRectFor(frameIndex);
    final colorScheme = scale.colorScheme;
    final everyFrame = scale.metrics.frameLabelEveryFrames == 1;
    final glyphs = <TimelineGlyphPlacement>[];
    if (writing.number.isNotEmpty) {
      // Labels keep one ink whatever the playhead range (UI-R18 #9), and
      // SHRINK rather than vanish at deep zoom-outs (R26 #38).
      final style = everyFrame
          ? TextStyle(
              fontSize: timelineFittedGlyphFontSize(
                11,
                scale.metrics.frameCellWidth,
                crossExtent: scale.crossExtent,
              ),
              color: colorScheme.onSurface,
            )
          : TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant);
      final painter = timelineGlyphPainter(
        writing.number,
        scale.inkOf(style, current: current),
      );
      // Bottom line: in-cell centered when every cell labels itself, the
      // every-Nth overlay style (left-anchored) otherwise (UI-R10 #27).
      glyphs.add((
        painter: painter,
        offset: Offset(
          everyFrame ? rect.center.dx - painter.width / 2 : rect.left + 2,
          rect.bottom - painter.height - 1,
        ),
      ));
    }
    // Top line: the second index on fps boundaries (UI-R10 #27).
    final second = secondsCornerGlyph(rect, (
      text: writing.second,
      fontSize: 9,
      color: scale.secondsInk(current: current),
    ));
    if (second != null) {
      glyphs.add(second);
    }
    return glyphs;
  }

  // Labels come from the shared laid-out-TextPainter cache (UI-R16):
  // fresh layout per label per repaint was the priciest slice of a
  // scroll-time repaint in debug.
  @override
  Object get props => (scale,);

  // One node per labeled header (the old per-cell widgets' surface),
  // windowed with the paint pass.
  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) =>
      frameWindowSemantics(
        window: scale.visibleWindow(),
        rectFor: scale.cellRectFor,
        labelFor: (frameIndex) => scale.modelAt(frameIndex).label.isEmpty
            ? null
            : 'frame ${frameIndex + 1}',
      );
}

/// The frame SCALE a frame-axis strip draws: the bounds, the playhead and
/// playback range, the leading spacer along the main axis, the metrics and
/// colours, the fps and label mode, and the self-windowing inputs.
///
/// ONE value object for the ruler and the X-sheet's rail: the two painters
/// each carried these eleven fields and each spelled the same eleven-term
/// `shouldRepaint`, the same visible-window call and the same frame-number
/// label (the audit's clone scan, 2026-09-06). The field list exists once,
/// where the fields live, so a field cannot be compared on one strip and
/// forgotten on the other.
///
/// Round 8 brought the CELL RECT and the per-frame MODEL in after them —
/// the two the painters still each spelled, one with the frame axis across
/// and one with it down, one washing its past-playback tail and one not.
/// [axis] turns the rect and [pastPlaybackWash] is the wash, both VALUES,
/// so what is left on a painter is only the paint.
final class TimelineRulerScale {
  const TimelineRulerScale({
    required this.axis,
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    required this.currentFrameIndex,
    required this.playbackFrameCount,
    required this.leadingFrameSpacer,
    required this.crossExtent,
    required this.metrics,
    required this.colorScheme,
    this.framesPerSecond = 24,
    this.showSeconds = false,
    this.windowBucket,
    this.viewportMainExtent = 0,
    this.pastPlaybackWash,
  });

  /// The axis the FRAMES run along: across the timeline's ruler, down the
  /// X-sheet's rail.
  final Axis axis;

  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final int currentFrameIndex;
  final int playbackFrameCount;

  /// The spacer before frame [frameStartIndex] along the strip's MAIN axis
  /// — a width on the ruler, a height on the rail.
  final double leadingFrameSpacer;

  /// The strip's thickness ACROSS the frame axis — the ruler's height
  /// ([TimelineGridMetrics.layerRowHeight]) and the rail's width
  /// ([TimelineGridMetrics.layerControlsWidth]). Two different metrics for
  /// the same dimension, which is why it is stated and not derived.
  final double crossExtent;

  final TimelineGridMetrics metrics;
  final ColorScheme colorScheme;
  final int framesPerSecond;

  /// Seconds display mode: the bottom line repeats 1..fps per second
  /// instead of counting absolute frames.
  final bool showSeconds;

  /// PRO-TIMELINE scrolling (UI-R15→R16): with these set the strip
  /// windows ITSELF off the quantized bucket (repaint once per span
  /// crossing, pure translation between) — the header row builds once
  /// for the full bounds. Null keeps the classic pre-windowed contract.
  final ValueListenable<int>? windowBucket;
  final double viewportMainExtent;

  /// The ground under a cell PAST the playback range, or null when the
  /// strip leaves its tail the colour of its paper.
  ///
  /// ⛔No past-playback graying on the RULER (UI-R18 #9): small zooms made
  /// the strip read broken from the right; the cut-end boundary line marks
  /// the end, the BODY cells keep their own dim wash. The X-sheet's RAIL
  /// does wash its tail, so the two differ by this VALUE — not by a flag
  /// asking which strip is asking.
  final Color? pastPlaybackWash;

  /// The cell's rect in the strip's local coordinates — the header cell on
  /// the ruler, the number row on the rail (the probe geometry tests and
  /// taps share).
  ///
  /// The turn is [offsetAlong]'s, twice: the cell begins [leadingFrameSpacer]
  /// plus its own frames along the axis and spans the whole [crossExtent]
  /// across it.
  Rect cellRectFor(int frameIndex) {
    final along =
        leadingFrameSpacer +
        (frameIndex - frameStartIndex) * metrics.frameCellWidth;
    return Rect.fromPoints(
      offsetAlong(axis, along: along, across: 0),
      offsetAlong(
        axis,
        along: along + metrics.frameCellWidth,
        across: crossExtent,
      ),
    );
  }

  /// What a strip writes at [frameIndex] — its number and its second — or,
  /// [current], the playhead's pair there (I-16): the number whatever the
  /// cadence says, the second whatever the boundary says. WHERE each goes
  /// and how big is the strip's own ([TimelineFrameRulerPainter.glyphsAt],
  /// `XSheetFrameRailPainter.glyphsAt`); what is written is this.
  ({String number, String second}) writingAt(
    int frameIndex, {
    required bool current,
  }) {
    if (!current) {
      final model = modelAt(frameIndex);
      return (number: model.label, second: model.secondsLabel);
    }
    return (
      number: frameNumberLabel(frameIndex),
      second: timelineRulerSecondOf(
        frameIndex: frameIndex,
        framesPerSecond: framesPerSecond,
      ),
    );
  }

  /// [base] as a strip writes it — or, [current], in the playhead's ink.
  TextStyle inkOf(TextStyle base, {required bool current}) =>
      current ? base.merge(timelineRulerPlayheadInk(colorScheme)) : base;

  /// The second's ink: the marks' surface variant, the pair's full ink.
  Color secondsInk({required bool current}) => current
      ? timelineRulerPlayheadInk(colorScheme).color!
      : colorScheme.onSurfaceVariant;

  /// The paper under one cell: its ground, and on it THE boundary line —
  /// the grid law's ink composited onto that ground — turned by [axis]: down
  /// the ruler's cell edge, across the rail's row edge. Both strips lay their
  /// paper here, and so does the playhead's writing when it uncovers a cell
  /// (I-16); [fill] and [line] are the caller's, reused across its cells.
  ///
  /// D8 (2026-08-18): the rail used to stroke a faint RECT around every row
  /// — no cadence, no 6f/second strengthening, half a pixel off the ruler's
  /// snap: one of the "미묘하게 다른 가이드선". The snap is the LAW's (it was
  /// this ruler's own +0.5 first — D8 promoted it so the overlay lands on
  /// the same pixel).
  ///
  /// D43 (유저, 2026-08-21): and the LAW's over-ground treatment too. The ink
  /// and the position were already shared; the COMPOSITE was not — the ruler
  /// laid its line over the header paper source-over while a block's
  /// interior seam multiplied, so one grid read lighter here and darker
  /// there; the rail was the half still missing it until round 8's grid
  /// unification. The fill has just laid this cell's paper, so the ground is
  /// known exactly rather than assumed.
  void paintCellPaper(
    Canvas canvas,
    int frameIndex, {
    required Paint fill,
    required Paint line,
  }) {
    final model = modelAt(frameIndex);
    final rect = cellRectFor(frameIndex);
    canvas.drawRect(rect, fill..color = model.background);
    final ink = timelineFrameBoundaryLineInk(
      frameIndex: frameIndex,
      frameCellExtent: metrics.frameCellWidth,
      framesPerSecond: framesPerSecond,
      colorScheme: colorScheme,
    );
    if (ink == null) {
      return;
    }
    final edge =
        (axis == Axis.horizontal ? rect.left : rect.top) + timelineGridLineSnap;
    canvas.drawLine(
      offsetAlong(axis, along: edge, across: 0),
      offsetAlong(axis, along: edge, across: crossExtent),
      line
        ..color = timelineGridLineInkOnGround(ink, model.background)
        ..strokeWidth = ink.strokeWidth,
    );
  }

  /// The resolved per-cell model — the probe surface.
  ///
  /// R9 #4: the cadence is the SHARED one
  /// ([TimelineGridMetrics.frameLabelEveryFrames], the paper-timesheet
  /// ladder anchored at frame 1). The rail was a transposed
  /// re-implementation of the horizontal ruler and had never called it —
  /// so zooming out crowded every row's number into the next, while the
  /// horizontal ruler thinned out correctly. A ruler is a SCALE, not cell
  /// content: the "never disappears" rule is about what a cell holds.
  TimelineRulerHeaderModel modelAt(int frameIndex) {
    final selected = frameIndex == currentFrameIndex;
    final outside = frameIndex >= playbackFrameCount;
    final labeled = frameIndex % metrics.frameLabelEveryFrames == 0;
    final ground = outside
        ? (pastPlaybackWash ?? colorScheme.surface)
        : colorScheme.surface;
    return TimelineRulerHeaderModel(
      frameIndex: frameIndex,
      label: labeled ? frameNumberLabel(frameIndex) : '',
      secondsLabel: timelineRulerSecondsLabel(
        frameIndex: frameIndex,
        framesPerSecond: framesPerSecond,
      ),
      selected: selected,
      outsidePlaybackRange: outside,
      background: selected
          ? Color.alphaBlend(
              timelineSelectedFrameBorderColor.withValues(alpha: 0.12),
              colorScheme.surface,
            )
          : ground,
    );
  }

  /// The frame window paint() actually draws (probe surface).
  ({int startIndex, int endIndexExclusive}) visibleWindow() =>
      visibleFrameWindowFor(
        bucket: windowBucket,
        viewportMainExtent: viewportMainExtent,
        cellExtent: metrics.frameCellWidth,
        frameStartIndex: frameStartIndex,
        frameEndIndexExclusive: frameEndIndexExclusive,
      );

  /// The bottom-line number at [frameIndex]: absolute and 1-based, or
  /// 1..fps repeating per second in [showSeconds] mode.
  String frameNumberLabel(int frameIndex) {
    if (!showSeconds) {
      return '${frameIndex + 1}';
    }
    final safeFps = framesPerSecond > 0 ? framesPerSecond : 24;
    return '${frameIndex % safeFps + 1}';
  }

  /// The last frame before [endIndexExclusive] carrying the WIDEST number
  /// this strip writes: in [showSeconds] the frame whose label is the fps
  /// itself — the widest of the 1..fps run [frameNumberLabel] repeats — and
  /// otherwise the window's last frame, whose absolute number is longest.
  ///
  /// 🚨★★★ONE PLACE, BESIDE [frameNumberLabel]. A surface that measured
  /// this for itself would divide by the rate again, which is exactly the
  /// copy `ruler_seconds_label_test` refuses — the timeline and the x-sheet
  /// each carried that expression once before, and fixing one left the
  /// other counting from 1. What the scale writes and how wide it can be
  /// are the same object's question.
  int widestNumberFrameBefore(int endIndexExclusive) {
    if (!showSeconds) {
      return endIndexExclusive - 1;
    }
    final safeFps = framesPerSecond > 0 ? framesPerSecond : 24;
    return (endIndexExclusive ~/ safeFps) * safeFps - 1;
  }

  // Value-compared, never `identical`: Theme.of(context).colorScheme
  // hands back a fresh instance every build (AnimatedTheme), so an
  // identity check re-recorded this whole strip on every rebuild. The
  // window bucket is the one field compared by identity — the painter is
  // subscribed to that notifier, so a different instance IS a change.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineRulerScale &&
          other.axis == axis &&
          other.crossExtent == crossExtent &&
          other.pastPlaybackWash == pastPlaybackWash &&
          other.frameStartIndex == frameStartIndex &&
          other.frameEndIndexExclusive == frameEndIndexExclusive &&
          other.currentFrameIndex == currentFrameIndex &&
          other.playbackFrameCount == playbackFrameCount &&
          other.leadingFrameSpacer == leadingFrameSpacer &&
          other.metrics == metrics &&
          other.framesPerSecond == framesPerSecond &&
          other.showSeconds == showSeconds &&
          identical(other.windowBucket, windowBucket) &&
          other.viewportMainExtent == viewportMainExtent &&
          other.colorScheme == colorScheme;

  @override
  int get hashCode => Object.hashAll([
    axis,
    crossExtent,
    pastPlaybackWash,
    frameStartIndex,
    frameEndIndexExclusive,
    currentFrameIndex,
    playbackFrameCount,
    leadingFrameSpacer,
    metrics,
    framesPerSecond,
    showSeconds,
    identityHashCode(windowBucket),
    viewportMainExtent,
    colorScheme,
  ]);
}
