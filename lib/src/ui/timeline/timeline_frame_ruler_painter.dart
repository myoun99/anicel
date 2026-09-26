
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'axis_turn.dart' show extentAlong, offsetAlong;
import 'frame_window_semantics.dart';

import 'timeline_beat_lines.dart';
import 'timeline_cell_style.dart';
import 'timeline_frame_window.dart';
import 'timeline_glyph_cache.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_second.dart';
import '../repaint_props.dart';
import '../text/word_condensation.dart';

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
///
/// Every [everySeconds]-th second only (I-22 — the strip's measured rung,
/// [TimelineRulerScale.secondsLabelEverySeconds]); counted from 0, so the
/// head always writes.
String timelineRulerSecondsLabel({
  required int frameIndex,
  required int framesPerSecond,
  int everySeconds = 1,
}) =>
    frameIndex %
            (timelineSecondFrames(framesPerSecond) * everySeconds) ==
        0
    ? timelineRulerSecondOf(
        frameIndex: frameIndex,
        framesPerSecond: framesPerSecond,
      )
    : '';

/// The second [frameIndex] lies in, counted from 0 like the marks — what
/// the playhead writes on the seconds line wherever it stands (I-16); the
/// marks print it only where a second begins.
String timelineRulerSecondOf({
  required int frameIndex,
  required int framesPerSecond,
}) {
  final safeFps = timelineSecondFrames(framesPerSecond);
  return '${frameIndex ~/ safeFps}';
}

/// The least a digit of a frame number is narrowed to, in ems: HALF-WIDTH.
///
/// 🗣️ruler-digits-in-the-app-face-Q1 (유저 2026-09-24, 「룰러번호 추천대로」 —
/// 「매 칸 쓸 때는 칸 안으로 가로만 좁힌다; 눌러도 안 되는 줌에서만 I-22 가
/// 성기게」). The answer named no floor, and one is needed: narrowed without
/// one, every frame would always fit and I-22 would never thin. Half an em
/// is the width a digit takes in Japanese type (半角), where it still reads
/// as a digit; the app's face sets its digits at three quarters of an em and
/// offers no narrower figures (`tnum` · `hwid` · `pwid` · `palt`, measured
/// 2026-09-24: no change). Past it the strip thins instead, which is its own
/// answer to crowding.
const double timelineNumberNarrowestEm = 0.5;

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
    // ([TimelineRulerScale.paintPaperIn] — a stretch of one ground at a
    // time, not a cell at a time: I-22's floor puts ~19,000 in a window).
    scale.paintPaperIn(
      canvas,
      window.startIndex,
      window.endIndexExclusive,
      fill: fillPaint,
      line: linePaint,
    );
    linePaint.strokeWidth = 1;

    // PASS 2 — labels last, so nothing can paint over them; only the frames
    // a mark can stand on ([TimelineRulerScale.writingStep]).
    final step = scale.writingStep;
    for (
      var frameIndex = (window.startIndex + step - 1) ~/ step * step;
      frameIndex < window.endIndexExclusive;
      frameIndex += step
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
    final everyFrame = scale.labelEveryFrames == 1;
    final glyphs = <TimelineGlyphPlacement>[];
    if (writing.number.isNotEmpty) {
      // Labels keep one ink whatever the playhead range (UI-R18 #9), set in
      // the type the cadence measured ([TimelineRulerScale.numberType]).
      final style = scale
          .numberTypeAt(everyFrame: everyFrame)
          .copyWith(
            color: everyFrame
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          );
      final painter = timelineGlyphPainter(
        writing.number,
        scale.inkOf(style, current: current),
      );
      // Bottom line: in-cell centered — and narrowed into the cell — when
      // every cell labels itself, the every-Nth overlay style (left-anchored,
      // its stride's room held by the cadence) otherwise (UI-R10 #27). The
      // overlay stands [timelineMarkGap] in from its cell: the ground the
      // cadence keeps between one number and the next is this inset.
      final fit = everyFrame
          ? scale.numberFitIn(rect, painter)
          : wordFitsAsItIs;
      glyphs.add((
        painter: painter,
        offset: Offset(
          everyFrame
              ? rect.center.dx - painter.width * fit.x / 2
              : rect.left + timelineMarkGap,
          rect.bottom - painter.height - 1,
        ),
        fit: fit,
      ));
    }
    // Top line: the second index on fps boundaries (UI-R10 #27).
    final second = secondsCornerGlyph(rect, (
      text: writing.second,
      fontSize: scale.secondsFontSize,
      color: scale.secondsInk(current: current),
      face: scale.face,
    ));
    if (second != null) {
      glyphs.add(second);
    }
    return glyphs;
  }

  /// The type the RULER sets its numbers in ([TimelineRulerScale.numberType]):
  /// fitted into its cell while every cell carries one — SHRINKING rather
  /// than vanishing at deep zoom-outs (R26 #38) — and the every-Nth overlay
  /// at 10 (UI-R10 #27).
  static TextStyle numberType(
    TimelineRulerScale scale, {
    required bool everyFrame,
  }) => scale.face.copyWith(
    fontSize: everyFrame
        ? timelineFittedGlyphFontSize(
            11,
            scale.metrics.frameCellWidth,
            crossExtent: scale.crossExtent,
          )
        : 10,
  );

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

/// How a strip sets its frame NUMBER at a cadence: the type alone — the ink
/// stays the painter's ([TimelineFrameRulerPainter.numberType] for the
/// ruler, `XSheetFrameRailPainter.numberType` for the rail).
typedef TimelineRulerNumberType =
    TextStyle Function(TimelineRulerScale scale, {required bool everyFrame});

/// [TimelineRulerScale.labelEveryFrames], measured once per scale.
final Expando<int> _labelEveryFramesOf = Expando<int>('labelEveryFrames');

/// [TimelineRulerScale.secondsLabelEverySeconds], measured once per scale.
final Expando<int> _secondsLabelEveryOf = Expando<int>('secondsLabelEvery');

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
    required this.face,
    required this.numberType,
    required this.secondsFontSize,
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

  /// The app's face (`appFaceOf`) every number and second on the strip is
  /// set in — and measured in, since [labelEveryFrames] measures in
  /// [numberType]. The two strips set their type from scratch and named no
  /// face, so the rulers wrote in the OS's font (「앱은 한 글꼴」, 08-28).
  final TextStyle face;

  /// The type this strip sets its numbers in — the ruler's or the rail's
  /// (R10 R6: the corner is shared, the size is not).
  ///
  /// A VALUE on the scale rather than a style each painter keeps to itself
  /// (I-22): [labelEveryFrames] measures the numbers in this type and both
  /// painters set them in it, so what the cadence measured is what is
  /// painted.
  final TimelineRulerNumberType numberType;

  /// The size this strip sets its SECONDS in — the ruler's 9, the rail's 8
  /// (R10 R6: the corner is shared, the size is not). A value here for the
  /// reason [numberType] is one: [secondsLabelEverySeconds] measures the
  /// seconds in it and both painters write them in it.
  final double secondsFontSize;

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

  /// [numberType] at the cadence [everyFrame] names.
  TextStyle numberTypeAt({required bool everyFrame}) =>
      numberType(this, everyFrame: everyFrame);

  /// How a number written in a cell of its own is narrowed: its WIDTH into
  /// the cell, less the ground the cadence keeps between one number and the
  /// next — the block words' law (`wordCondensation`); its height never.
  ///
  /// 🗣️ruler-digits-in-the-app-face-Q1 (유저 2026-09-24, 「룰러번호
  /// 추천대로」): the app's face sets its digits wide — `000` at 11px is
  /// 25.1px against a 24px cell — and the default zoom thinned three-digit
  /// numbers to every third frame. [labelEveryFrames] counts on this, down
  /// to [timelineNumberNarrowestEm] a digit.
  WordFit numberFitIn(Rect cell, TextPainter number) => (
    x: wordCondensation(
      extent: number.width,
      room: cell.width - timelineMarkGap,
    ),
    y: 1.0,
  );

  /// Every how many frames a number is written, counted from frame 1: the
  /// densest rung of the paper-timesheet ladder ([timelineFrameStrideLadder])
  /// at which the widest number this strip writes, set in the type of that
  /// rung and measured along [axis], keeps [timelineMarkGap] to the next.
  ///
  /// 🚨I-22 (유저 2026-09-12): 「33.3%배율에서 3f마다의 그리드 세로선이랑 글자,
  /// 아직 존재해도 안겹칠거같은데 뭔가 벌써 사라져? … 1f마다 그리드선이랑
  /// 글자도 똑같음. 최대한 버텨보자. 룰러 텍스트 글자가 겹칠때 생략한다는
  /// 느낌으로」. ↩️The rung used to be a threshold on the cell alone (every
  /// frame from 20px, then the first rung spanning 40px) that never looked at
  /// a number: it gave up rungs the numbers still fit, and kept every frame
  /// where four digits ran into each other.
  ///
  /// The widest number is the widest digit, as many times over as the
  /// longest label has digits, so a face with proportional figures cannot
  /// slip a wider run past the measure.
  ///
  /// Every frame is measured NARROWED ([numberFitIn]) — as far as half-width
  /// and no further (ruler-digits-in-the-app-face-Q1): only a number that
  /// would still touch the next thins the strip.
  int get labelEveryFrames =>
      _labelEveryFramesOf[this] ??= _measuredLabelEveryFrames();

  int _measuredLabelEveryFrames() {
    final safeFps = timelineSecondFrames(framesPerSecond);
    final longest = showSeconds
        ? '$safeFps'
        : '${frameEndIndexExclusive > 1 ? frameEndIndexExclusive : 1}';
    final digits = longest.length;
    double widestIn(TextStyle type, {double widthAtMost = double.infinity}) {
      var widest = 0.0;
      for (var digit = 0; digit <= 9; digit += 1) {
        final glyph = timelineGlyphPainter('$digit' * digits, type);
        final extent = extentAlong(
          axis,
          Size(math.min(glyph.width, widthAtMost), glyph.height),
        );
        widest = extent > widest ? extent : widest;
      }
      return widest;
    }

    final cell = metrics.frameCellWidth;
    final everyFrame = numberTypeAt(everyFrame: true);
    final halfWidth =
        digits * (everyFrame.fontSize ?? double.infinity) *
        timelineNumberNarrowestEm;
    if (widestIn(everyFrame, widthAtMost: halfWidth) + timelineMarkGap <=
        cell) {
      return 1;
    }
    // Past every frame the numbers are the every-Nth overlay: the rung that
    // holds the overlay's widest number, and never the first — that is the
    // every-frame writing the line above has already refused.
    final overlay = widestIn(numberTypeAt(everyFrame: false)) + timelineMarkGap;
    final stride = timelineStrideHolding(overlay, cell);
    final overlayFloor = timelineFrameStrideLadder[1];
    return stride > overlayFloor ? stride : overlayFloor;
  }

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
    final ground = modelAt(frameIndex).background;
    canvas.drawRect(cellRectFor(frameIndex), fill..color = ground);
    _paintBoundaryLine(canvas, frameIndex, ground, line);
  }

  /// The paper under frames [from, to) — each stretch of one ground as ONE
  /// rect, and on it every line THE law rules there: what [paintCellPaper]
  /// lays one cell at a time, laid for a window at once.
  ///
  /// 🚨I-22 (the ten-minute floor): at an eighth of a pixel a window is
  /// ~19,000 cells, and a rect and a line check for every one of them was
  /// this strip's whole cost. A cell's ground moves only at the selected
  /// cell and at the end of playback ([modelAt]), so those are the only
  /// edges a stretch has; the lines walk [timelineFrameLineStep].
  void paintPaperIn(
    Canvas canvas,
    int from,
    int to, {
    required Paint fill,
    required Paint line,
  }) {
    final edges = <int>{
      from,
      to,
      currentFrameIndex,
      currentFrameIndex + 1,
      playbackFrameCount,
    }.where((edge) => edge >= from && edge <= to).toList()..sort();
    final step = timelineFrameLineStep(metrics.frameCellWidth, framesPerSecond);
    for (var index = 0; index + 1 < edges.length; index += 1) {
      final start = edges[index];
      final end = edges[index + 1];
      final ground = modelAt(start).background;
      canvas.drawRect(
        cellRectFor(start).expandToInclude(cellRectFor(end - 1)),
        fill..color = ground,
      );
      for (
        var frame = (start + step - 1) ~/ step * step;
        frame < end;
        frame += step
      ) {
        _paintBoundaryLine(canvas, frame, ground, line);
      }
    }
  }

  /// THE boundary line at [frameIndex]'s leading edge, on [ground] — the
  /// grid law's ink composited onto it, turned by [axis]; nothing where the
  /// law thins the boundary out.
  void _paintBoundaryLine(
    Canvas canvas,
    int frameIndex,
    Color ground,
    Paint line,
  ) {
    final ink = timelineFrameBoundaryLineInk(
      frameIndex: frameIndex,
      frameCellExtent: metrics.frameCellWidth,
      framesPerSecond: framesPerSecond,
      colorScheme: colorScheme,
    );
    if (ink == null) {
      return;
    }
    final rect = cellRectFor(frameIndex);
    final edge =
        (axis == Axis.horizontal ? rect.left : rect.top) + timelineGridLineSnap;
    canvas.drawLine(
      offsetAlong(axis, along: edge, across: 0),
      offsetAlong(axis, along: edge, across: crossExtent),
      line
        ..color = timelineGridLineInkOnGround(ink, ground)
        ..strokeWidth = ink.strokeWidth,
    );
  }

  /// Every how many SECONDS the seconds line writes a mark — the rung of
  /// the seconds ladder ([timelineSecondsHolding]) whose span holds the
  /// widest second this strip writes, set in [secondsFontSize] and measured
  /// along [axis], with [timelineMarkGap] to the next. Every second, at
  /// every zoom the old floor allowed; I-22's 「겹칠때 생략」 past that.
  int get secondsLabelEverySeconds =>
      _secondsLabelEveryOf[this] ??= _measuredSecondsLabelEvery();

  int _measuredSecondsLabelEvery() {
    final second = timelineSecondFrames(framesPerSecond);
    final digits = '${math.max(0, frameEndIndexExclusive - 1) ~/ second}'
        .length;
    final type = face.copyWith(
      fontSize: secondsFontSize,
      fontWeight: FontWeight.w700,
    );
    var widest = 0.0;
    for (var digit = 0; digit <= 9; digit += 1) {
      final glyph = timelineGlyphPainter('$digit' * digits, type);
      final extent = extentAlong(axis, Size(glyph.width, glyph.height));
      widest = extent > widest ? extent : widest;
    }
    return timelineSecondsHolding(
      widest + timelineMarkGap,
      second * metrics.frameCellWidth,
    );
  }

  /// The step every frame this strip writes at is a multiple of — the gcd
  /// of the number cadence ([labelEveryFrames]) and the seconds'
  /// ([secondsLabelEverySeconds]) — so a painter walking it writes every
  /// mark and visits no cell that has none.
  int get writingStep => labelEveryFrames.gcd(
    timelineSecondFrames(framesPerSecond) * secondsLabelEverySeconds,
  );

  /// The resolved per-cell model — the probe surface.
  ///
  /// R9 #4: the cadence is the SHARED one ([labelEveryFrames], on the
  /// paper-timesheet ladder anchored at frame 1). The rail was a transposed
  /// re-implementation of the horizontal ruler and had never called it —
  /// so zooming out crowded every row's number into the next, while the
  /// horizontal ruler thinned out correctly. A ruler is a SCALE, not cell
  /// content: the "never disappears" rule is about what a cell holds.
  TimelineRulerHeaderModel modelAt(int frameIndex) {
    final selected = frameIndex == currentFrameIndex;
    final outside = frameIndex >= playbackFrameCount;
    final labeled = frameIndex % labelEveryFrames == 0;
    final ground = outside
        ? (pastPlaybackWash ?? colorScheme.surface)
        : colorScheme.surface;
    return TimelineRulerHeaderModel(
      frameIndex: frameIndex,
      label: labeled ? frameNumberLabel(frameIndex) : '',
      secondsLabel: timelineRulerSecondsLabel(
        everySeconds: secondsLabelEverySeconds,
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
    final safeFps = timelineSecondFrames(framesPerSecond);
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
    final safeFps = timelineSecondFrames(framesPerSecond);
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
          other.face == face &&
          other.numberType == numberType &&
          other.secondsFontSize == secondsFontSize &&
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
    face,
    numberType,
    secondsFontSize,
    framesPerSecond,
    showSeconds,
    identityHashCode(windowBucket),
    viewportMainExtent,
    colorScheme,
  ]);
}
