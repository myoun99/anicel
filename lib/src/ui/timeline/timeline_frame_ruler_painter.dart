
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../../core/bounded_memo.dart';
import '../../core/neighbour_pairs.dart';
import 'axis_turn.dart' show extentAlong, offsetAlong, startAlong;
import 'frame_ruler_view.dart';
import 'frame_window_semantics.dart';

import 'timeline_beat_lines.dart';
import 'timeline_cell_style.dart';
import 'timeline_frame_coordinate_policy.dart' show frameVisibleX;
import 'timeline_frame_window.dart';
import '../text/laid_out_glyph.dart';
import '../text/text_measure.dart' show everyDigitIn;
import 'timeline_glyph_cache.dart';
import 'timeline_grid_metrics.dart';
import 'timeline_second.dart';
import '../repaint_props.dart';
import '../text/word_bake.dart' show RepaintOnWordBakes;
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
///
/// Under the page view ([pages], I-81) the seconds are the frames view's,
/// and a page's head writes the page beside its second ([timelinePageMark])
/// — 🗣️I-81-Q4 (유저 2026-10-30): 「페이지뷰는 초 옆에 페이지 넘어가는곳마다
/// p1 p2라고 쓸뿐임 그 외는 프레임뷰랑 똑같음」 — every `everyPages`-th
/// page's only, past where a page holds its mark
/// ([TimelineRulerScale.pagesLabelEvery], I-22's 「겹칠때 생략」). A second
/// that would run into a page's mark writes nothing: within a rung before
/// it, or within its `clearFrames` after. ⚠️Mine: the mark after its
/// second, a space between (`6 p2`). ↩️The seconds counted again from each
/// page's head, which wrote its page instead — 유저 10-06 「초나 프레임
/// 표시가 장수마다 리셋되는데」, of the paper, read as the ruler's two lines.
String timelineRulerSecondsLabel({
  required int frameIndex,
  required int framesPerSecond,
  int everySeconds = 1,
  TimelinePageMarks? pages,
}) {
  final rung = timelineSecondFrames(framesPerSecond) * everySeconds;
  final second = frameIndex % rung == 0
      ? timelineRulerSecondOf(
          frameIndex: frameIndex,
          framesPerSecond: framesPerSecond,
        )
      : '';
  if (pages == null) {
    return second;
  }
  final (:frames, :everyPages, :clearFrames) = pages;
  final marked = frames * everyPages;
  final sinceMark = frameIndex % marked;
  if (sinceMark == 0) {
    final mark = timelinePageMark(frameIndex ~/ frames);
    return second.isEmpty ? mark : '$second $mark';
  }
  return sinceMark >= clearFrames && marked - sinceMark >= rung ? second : '';
}

/// How the page view writes its pages' marks ([timelineRulerSecondsLabel]):
/// a page's frames, every how many pages a mark is written, and how many
/// frames past one the next second keeps clear of it.
typedef TimelinePageMarks = ({int frames, int everyPages, int clearFrames});

/// The page [pageIndex] (from 0) as the page view writes it: `p1`, `p2` …
/// (I-81 「p1 p2라는식으로 룰러에 적는다」).
String timelinePageMark(int pageIndex) => 'p${pageIndex + 1}';

/// The second [frameIndex] lies in, counted from 0 like the marks — what
/// the playhead writes on the seconds line wherever it stands (I-16); the
/// marks print it only where a second begins.
String timelineRulerSecondOf({
  required int frameIndex,
  required int framesPerSecond,
}) {
  final safeFps = timelineSecondFrames(framesPerSecond);
  return timelineSecondsMark(frameIndex ~/ safeFps);
}

/// [seconds] as the seconds line writes it: the count alone below a
/// minute, then `m:ss`, then `h:mm:ss` — growing only as far as the count
/// needs.
///
/// 🗣️I-102 (유저 2026-10-15): 「분이나 시간도 표시가능하도록. 스토리보드프로
/// 보면 애초에 룰러가 00:00:00:01 이런식인데, 그정도로 관계없는숫자가
/// 보이게하는건 아니라도 분 표시가 되면 1:01 이런식으로. 필요할때마다
/// 늘어나도록. 위에는 항상 초니까 초+코마던 뭐던 이런식으로 표시」.
String timelineSecondsMark(int seconds) {
  if (seconds < 60) {
    return '$seconds';
  }
  String twoDigits(int value) => '$value'.padLeft(2, '0');
  final minutes = seconds ~/ 60;
  final ss = twoDigits(seconds % 60);
  return minutes < 60
      ? '$minutes:$ss'
      : '${minutes ~/ 60}:${twoDigits(minutes % 60)}:$ss';
}

/// The NUMBER the ruler writes at [frameIndex]: 1-based, counted again
/// every [restartsEvery] frames — absolute where it is null, 1..fps in
/// each second under the seconds display, 1..a page under the page view
/// (I-81) — beside [timelineRulerSecondOf], the other line of the same
/// scale.
String timelineRulerFrameNumberOf({
  required int frameIndex,
  int? restartsEvery,
}) =>
    '${(restartsEvery == null ? frameIndex : frameIndex % restartsEvery) + 1}';

/// A FRAME'S PLACE as one word — what the ruler writes over it: its number,
/// and under the seconds display the second it lies in before it (`15`,
/// `0+15`, `1+1`).
///
/// 🗣️F-284 (유저 2026-10-04): 「se는 지금 S1 등 트랙이름까지만 표시되는데,
/// S1의 15. 이런식으로 15번 인덱스나. 이런 표기는 초+코마 표기로 바꾼거에
/// 대응하도록 법 통일」.
///
/// ⛔Built from the ruler's two lines and from nothing else: a place written
/// by a formula of its own would be the copy [timelineRulerSecondsLabel]
/// was made one function to end, and it would not be the number standing
/// over the block. It is no LENGTH either (see there): frame 24 of a
/// 24-frame second is `0+24`, where 24 frames long is `1+0`.
String timelineFramePlaceLabel({
  required int frameIndex,
  required int framesPerSecond,
  required bool showSeconds,
}) {
  final number = timelineRulerFrameNumberOf(
    frameIndex: frameIndex,
    restartsEvery: showSeconds ? timelineSecondFrames(framesPerSecond) : null,
  );
  if (!showSeconds) {
    return number;
  }
  final second = timelineRulerSecondOf(
    frameIndex: frameIndex,
    framesPerSecond: framesPerSecond,
  );
  return '$second+$number';
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

/// The playhead's own ink on a ruler strip (I-16 「볼드체로」): bold, in the
/// accent — one answer for the ruler and the rail, the timeline's, the
/// storyboard's and the sheet's alike.
///
/// 🗣️F-239 (유저 2026-09-29): 「재생헤드의 초수/코마 텍스트, 좀 더
/// 눈에띄게하고싶으니 색을 흰색이아니라 강조색으로」. ↩️It was the
/// full-strength text colour.
TextStyle timelineRulerPlayheadInk(ColorScheme colorScheme) =>
    TextStyle(fontWeight: FontWeight.w700, color: colorScheme.primary);

/// The resolved per-header model — THE probe surface for ruler tests
/// (labels, states and colors live here, not in widget trees), the ruler
/// counterpart of the cells painter's model (UI-R9 #12b → UI-R13 #1).
class TimelineRulerHeaderModel {
  const TimelineRulerHeaderModel({
    required this.frameIndex,
    required this.label,
    required this.secondsLabel,
    required this.outsidePlaybackRange,
    required this.background,
  });

  final int frameIndex;

  /// The bottom-line number ('' when the cell is unlabeled at this zoom).
  final String label;

  /// The top-line second index ('' off second boundaries).
  final String secondsLabel;

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
class TimelineFrameRulerPainter extends CustomPainter
    with RepaintOnProps, RepaintOnWordBakes {
  TimelineFrameRulerPainter({required this.scale})
    : super(repaint: scale.windowBucket);

  /// The frame scale this strip draws — shared, field for field, with the
  /// X-sheet's rail painter, and the rect and the model with it.
  final TimelineRulerScale scale;

  @override
  void paintWords(Canvas canvas, Size size) {
    final colorScheme = scale.colorScheme;
    final linePaint = Paint()..strokeWidth = 1;

    // The paper, on it the SAME grid the cells use (R26 #40), and the
    // labels last ([TimelineRulerScale.paintWindow]). The cached-range
    // strip is NOT here — it moved to [TimelineRulerCursorOverlay] with the
    // cursor tint, because its truth is derived state that no gate can
    // compare.
    scale.paintWindow(canvas, glyphsAt);

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
      final painter = laidOutGlyph(
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
  // windowed with the paint pass ([TimelineRulerScale.windowSemantics]).
  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => scale.windowSemantics();
}

/// How a strip sets its frame NUMBER at a cadence: the type alone — the ink
/// stays the painter's ([TimelineFrameRulerPainter.numberType] for the
/// ruler, `XSheetFrameRailPainter.numberType` for the rail).
typedef TimelineRulerNumberType =
    TextStyle Function(TimelineRulerScale scale, {required bool everyFrame});

/// Where a ruler strip writes at one frame — the strip's OWN layout
/// ([TimelineFrameRulerPainter.glyphsAt] across, `XSheetFrameRailPainter
/// .glyphsAt` down); [current] asks for the playhead's pair.
typedef TimelineRulerGlyphLayout =
    List<TimelineGlyphPlacement> Function(
      TimelineRulerScale scale,
      int frameIndex, {
      required bool current,
    });

/// [TimelineRulerScale.labelEveryFrames], measured once per scale.
final Expando<int> _labelEveryFramesOf = Expando<int>('labelEveryFrames');

/// [TimelineRulerScale.secondsLabelEverySeconds], measured once per scale.
final Expando<int> _secondsLabelEveryOf = Expando<int>('secondsLabelEvery');

/// [TimelineRulerScale._pageMarks], measured once per scale.
final Expando<TimelinePageMarks> _pageMarksOf = Expando<TimelinePageMarks>(
  'pageMarks',
);

/// [TimelineRulerScale.writtenAt]: what each scale has laid out, by layout,
/// frame and whether it is the playhead's pair.
final Expando<
  BoundedMemo<
    (TimelineRulerGlyphLayout, int, bool),
    List<TimelineGlyphPlacement>
  >
>
_writtenOf = Expando('written');

/// How many frames' writing a scale holds laid out ([TimelineRulerScale
/// .writtenAt]) before it lets them all go. A playing tick asks for a
/// dozen; a window that walks more frames than this lays itself out as it
/// did before a scale held any, and a run down a long cut lays the strip
/// out again rather than holding every frame it passed.
const int _writtenHeld = 512;

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
    required this.playbackFrameCount,
    required this.leadingFrameSpacer,
    required this.crossExtent,
    required this.metrics,
    required this.colorScheme,
    required this.face,
    required this.numberType,
    required this.secondsFontSize,
    this.framesPerSecond = 24,
    this.rulerView = FrameRulerView.frames,
    this.pageFrames,
    this.windowBucket,
    this.viewportMainExtent = 0,
    this.pastPlaybackWash,
  });

  /// The axis the FRAMES run along: across the timeline's ruler, down the
  /// X-sheet's rail.
  final Axis axis;

  final int frameStartIndex;
  final int frameEndIndexExclusive;
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

  /// How the strip counts ([FrameRulerView]): the seconds display repeats
  /// 1..fps on the bottom line per second, the page view 1..a page per
  /// page of [pageFrames], instead of counting absolute frames.
  final FrameRulerView rulerView;

  /// How many frames a page of the strip's cut's X-sheet holds — where the
  /// page view starts the strip's numbers again and writes the page's mark
  /// (I-81-Q1 「그 컷의 X시트 장을 따른다」). Null on a strip that is no one
  /// cut's — the
  /// storyboard's, which counts on as the frames view does until I-81-Q3
  /// says where its pages begin.
  final int? pageFrames;

  /// The page the strip counts again at — under the page view, and only
  /// where it has one.
  int? get _page => switch (pageFrames) {
    final frames? when rulerView == FrameRulerView.pages && frames > 0 =>
      frames,
    _ => null,
  };

  /// Every how many frames the bottom line's number starts again at 1.
  int? get _numberRestartsEvery => switch (rulerView) {
    FrameRulerView.secondsPlusFrames => timelineSecondFrames(framesPerSecond),
    _ => _page,
  };

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
    double edge(int frame) => frameVisibleX(
      frameIndex: frame,
      frameStartIndex: frameStartIndex,
      frameCellWidth: metrics.frameCellWidth,
      leadingFrameSpacerWidth: leadingFrameSpacer,
    );
    return Rect.fromPoints(
      offsetAlong(axis, along: edge(frameIndex), across: 0),
      offsetAlong(axis, along: edge(frameIndex + 1), across: crossExtent),
    );
  }

  /// What a strip writes at [frameIndex] — its number and its second — or,
  /// [current], the playhead's pair there (I-16): the number whatever the
  /// cadence says, the second whatever the boundary says. WHERE each goes
  /// and how big is the strip's own ([TimelineFrameRulerPainter.glyphsAt],
  /// `XSheetFrameRailPainter.glyphsAt`); what is written is this.
  ///
  /// The page view's pair is the frames view's, its number in its page
  /// (I-81-Q4 「그 외는 프레임뷰랑 똑같음」). ↩️It wrote the page it stood in
  /// on the seconds line (`p2`).
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
  /// Every frame is measured NARROWED ([numberFitIn]) — as far as half-width
  /// and no further (ruler-digits-in-the-app-face-Q1): only a number that
  /// would still touch the next thins the strip.
  ///
  /// 🗣️F-385 (유저 2026-10-17): 「초+코마 표시에서만 타임라인 룰러 숫자 억지로
  /// 넣으려고 … 글자 가로길이 줄이는데 룰러는 이렇게 안해도됨. 그냥 일반
  /// 프레임모드랑 법 통일해서 해도됨」 — the numbers measured are the frame
  /// numbers in either display. ↩️Under the seconds display it measured the
  /// 1..fps it writes there, two digits that fit narrowed into a cell the
  /// absolute numbers had already thinned out of: the same zoom wrote every
  /// third number in one display and squeezed every one in the other.
  ///
  /// 🗣️I-102 (유저 2026-10-15): 「줌 줄였을때 보이는 숫자는 서로 같은기준으로
  /// 통일 … 프레임쪽은 5 바로 밑 숫자가 아니라 97이 보인다던가. 어떤 줌하던
  /// 서로 기준은 같도록. 위 숫자(초)를 기준으로 해서 아래가 길어져서
  /// 힘들다 싶으면 아래를 2기준당 1개로 줄인다던가」. Inside a second the
  /// rungs are the ladder's that divide the second, so a number stands on
  /// every second's head; past one second the numbers stand under the
  /// seconds line's marks ([secondsLabelEverySeconds]) — every one of them,
  /// or every second, third … one, as their width asks. ↩️The ladder doubled
  /// on past 24, and 96 frames went under marks four seconds apart where the
  /// seconds were five apart.
  int get labelEveryFrames =>
      _labelEveryFramesOf[this] ??= _measuredLabelEveryFrames();

  int _measuredLabelEveryFrames() {
    final second = timelineSecondFrames(framesPerSecond);
    final widest = '${math.max(1, frameEndIndexExclusive)}';
    final cell = metrics.frameCellWidth;
    final everyFrame = numberTypeAt(everyFrame: true);
    final halfWidth =
        widest.length * (everyFrame.fontSize ?? double.infinity) *
        timelineNumberNarrowestEm;
    if (_widestWritten(everyFrame, widest, widthAtMost: halfWidth) +
            timelineMarkGap <=
        cell) {
      return 1;
    }
    // Past every frame the numbers are the every-Nth overlay: the rung that
    // holds the overlay's widest number, and never the first — that is the
    // every-frame writing the line above has already refused.
    final overlay =
        _widestWritten(numberTypeAt(everyFrame: false), widest) +
        timelineMarkGap;
    for (final stride in timelineFrameStrideLadder.skip(1)) {
      if (stride < second && second % stride == 0 && overlay <= stride * cell) {
        return stride;
      }
    }
    final marks = second * secondsLabelEverySeconds;
    return marks * math.max(1, (overlay / (marks * cell)).ceil());
  }

  /// A strip's window, both passes — the ruler's across and the rail's
  /// down, one code: the paper ([paintPaperIn]), then the marks, only on
  /// the frames a mark can stand on ([writingStep]), each where the strip's
  /// own [layout] sets it.
  ///
  /// Self-windowing (UI-R15): only the frames under the live viewport
  /// record — a scroll is a repaint of this thin pass, never a rebuild.
  /// Every cell's paper goes down BEFORE any label, which is what keeps a
  /// narrow cell's label alive: the old single pass let the next cell's
  /// fill erase the half that overflowed (R26 #39, "텍스트 절반이 사라짐").
  void paintWindow(Canvas canvas, TimelineRulerGlyphLayout layout) {
    final window = visibleWindow();
    paintPaperIn(canvas, window);
    final step = writingStep;
    for (
      var frameIndex = timelineFirstOnStride(window.startIndex, step);
      frameIndex < window.endIndexExclusive;
      frameIndex += step
    ) {
      for (final glyph in writtenAt(layout, frameIndex, current: false)) {
        glyph.paint(canvas);
      }
    }
  }

  /// What [layout] writes at [frameIndex] on this scale — laid out the
  /// first time it is asked and handed back after that.
  ///
  /// 🚨I-57 (10-15, profile, the user's project): the playhead's writing
  /// walks the frames round the playhead on every tick of a run, and laid
  /// each one's number and second out again — styles made, the glyph cache
  /// asked, the second's corner placed: a dozen layouts a tick at 12µs, the
  /// dearest paint of a playing frame (0.24ms). A layout reads nothing but
  /// the scale it is handed, and a scale is the strip as one build stands
  /// it, so a frame's writing is the same every time it is asked.
  /// Measured with the memo on and off by turns (same build): the layouts
  /// a drawn frame asks fall from eleven to under two — the frames a run
  /// meets for the first time, each a fresh layout — and the writing's
  /// share from 0.24 to about 0.20ms.
  List<TimelineGlyphPlacement> writtenAt(
    TimelineRulerGlyphLayout layout,
    int frameIndex, {
    required bool current,
  }) => (_writtenOf[this] ??= BoundedMemo(_writtenHeld)).resolve(
    (layout, frameIndex, current),
    () => layout(this, frameIndex, current: current),
  );

  /// The paper under [frames] — each stretch of one ground as ONE rect, and
  /// on it THE boundary line wherever the law rules one: the grid law's ink
  /// composited onto that ground, turned by [axis] (down the ruler's cell
  /// edge, across the rail's row edge). Both strips lay their window with
  /// it, and the playhead's writing lays the paper back with it under a
  /// glyph it covers (I-16).
  ///
  /// 🚨I-22 (the ten-minute floor): at an eighth of a pixel a window is
  /// ~19,000 cells, and a rect and a line check for every one of them was
  /// this strip's whole cost. A cell's ground moves only at the end of
  /// playback ([modelAt]), so that is the only edge a stretch has inside
  /// the window; the lines walk [timelineFrameLineStep]. ↩️The
  /// writing kept laying its paper a cell at a time until 09-27 — hundreds
  /// of rects under one glyph on every playback tick at that floor.
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
  /// unification. The fill has just laid this stretch's paper, so the ground
  /// is known exactly rather than assumed.
  void paintPaperIn(
    Canvas canvas,
    ({int startIndex, int endIndexExclusive}) frames,
  ) {
    final (startIndex: from, endIndexExclusive: to) = frames;
    final fill = Paint();
    final line = Paint();
    final edges = <int>{
      from,
      to,
      playbackFrameCount,
    }.where((edge) => edge >= from && edge <= to).toList()..sort();
    final step = timelineFrameLineStep(metrics.frameCellWidth, framesPerSecond);
    for (final (start, end) in neighbourPairs(edges)) {
      final ground = modelAt(start).background;
      canvas.drawRect(
        cellRectFor(start).expandToInclude(cellRectFor(end - 1)),
        fill..color = ground,
      );
      for (
        var frame = timelineFirstOnStride(start, step);
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
    final edge =
        startAlong(axis, cellRectFor(frameIndex)) + timelineGridLineSnap;
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
  /// widest second this strip writes ([_widestMark]). Every second, at
  /// every zoom the old floor allowed; I-22's 「겹칠때 생략」 past that.
  int get secondsLabelEverySeconds =>
      _secondsLabelEveryOf[this] ??= timelineSecondsHolding(
        _widestMark(timelineSecondsMark(_lastFrame ~/ _secondFrames)),
        _secondFrames * metrics.frameCellWidth,
      );

  /// Every how many PAGES the page view writes a page's mark; 1 off it.
  int get pagesLabelEvery => _pageMarks?.everyPages ?? 1;

  /// The page view's marks, measured once per scale: the rung of the
  /// seconds' ladder whose span of pages holds the widest mark a page's head
  /// writes — its last page beside its last second — the question
  /// [secondsLabelEverySeconds] asks of seconds, and the frames that mark
  /// takes. Null off the page view.
  TimelinePageMarks? get _pageMarks {
    final page = _page;
    if (page == null) {
      return null;
    }
    return _pageMarksOf[this] ??= () {
      final widest = _widestMark(
        '${timelineSecondsMark(_lastFrame ~/ _secondFrames)} '
        '${timelinePageMark(_lastFrame ~/ page)}',
      );
      return (
        frames: page,
        everyPages: timelineSecondsHolding(
          widest,
          page * metrics.frameCellWidth,
        ),
        clearFrames: (widest / metrics.frameCellWidth).ceil(),
      );
    }();
  }

  int get _secondFrames => timelineSecondFrames(framesPerSecond);

  int get _lastFrame => math.max(0, frameEndIndexExclusive - 1);

  /// [written] as wide as the seconds line can set it ([_widestWritten], in
  /// [secondsFontSize]), with [timelineMarkGap] to the next mark.
  double _widestMark(String written) =>
      _widestWritten(timelineSecondsType(face, secondsFontSize), written) +
      timelineMarkGap;

  /// The widest [written] this strip can set in [type] — every digit of it
  /// written as the widest digit, so a face with proportional figures
  /// cannot slip a wider number past the measure — measured along [axis]
  /// and as drawn no wider than [widthAtMost].
  double _widestWritten(
    TextStyle type,
    String written, {
    double widthAtMost = double.infinity,
  }) {
    var widest = 0.0;
    for (final run in everyDigitIn(
      (digit) => written.replaceAll(RegExp('[0-9]'), digit),
    )) {
      final glyph = laidOutGlyph(run, type);
      final extent = extentAlong(
        axis,
        Size(math.min(glyph.width, widthAtMost), glyph.height),
      );
      widest = extent > widest ? extent : widest;
    }
    return widest;
  }

  /// The strip's a11y surface: one node per frame it writes a number on,
  /// windowed and walked like its paint ([writingStep]) — the ruler's
  /// across and the rail's down, one code.
  List<CustomPainterSemantics> windowSemantics() => frameWindowSemantics(
    window: visibleWindow(),
    step: writingStep,
    rectFor: cellRectFor,
    labelFor: (frameIndex) =>
        modelAt(frameIndex).label.isEmpty ? null : 'frame ${frameIndex + 1}',
  );

  /// The step every frame this strip writes at is a multiple of — the gcd
  /// of the number cadence ([labelEveryFrames]) and the seconds'
  /// ([secondsLabelEverySeconds]), and under the page view the page's —
  /// so a painter walking it writes every mark and visits no cell that has
  /// none.
  int get writingStep {
    final step = labelEveryFrames.gcd(
      timelineSecondFrames(framesPerSecond) * secondsLabelEverySeconds,
    );
    final page = _page;
    return page == null ? step : step.gcd(page);
  }

  /// The resolved per-cell model — the probe surface.
  ///
  /// R9 #4: the cadence is the SHARED one ([labelEveryFrames], on the
  /// paper-timesheet ladder anchored at frame 1). The rail was a transposed
  /// re-implementation of the horizontal ruler and had never called it —
  /// so zooming out crowded every row's number into the next, while the
  /// horizontal ruler thinned out correctly. A ruler is a SCALE, not cell
  /// content: the "never disappears" rule is about what a cell holds.
  ///
  /// ⛔No current frame: the playhead's cell is the cursor overlay's, on a
  /// layer of its own ([TimelineRulerCursorOverlayPainter], F-212). ↩️The
  /// strip was handed one and tinted its cell 12% — every mount handed it
  /// -1 once the overlay took the tint, so only the tests ever saw it.
  TimelineRulerHeaderModel modelAt(int frameIndex) {
    final outside = frameIndex >= playbackFrameCount;
    final labeled = frameIndex % labelEveryFrames == 0;
    return TimelineRulerHeaderModel(
      frameIndex: frameIndex,
      label: labeled ? frameNumberLabel(frameIndex) : '',
      secondsLabel: timelineRulerSecondsLabel(
        everySeconds: secondsLabelEverySeconds,
        frameIndex: frameIndex,
        framesPerSecond: framesPerSecond,
        pages: _pageMarks,
      ),
      outsidePlaybackRange: outside,
      background: outside
          ? (pastPlaybackWash ?? colorScheme.surface)
          : colorScheme.surface,
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
  /// counted again each second or each page as [rulerView] has it.
  String frameNumberLabel(int frameIndex) => timelineRulerFrameNumberOf(
    frameIndex: frameIndex,
    restartsEvery: _numberRestartsEvery,
  );

  /// The last frame before [endIndexExclusive] carrying the WIDEST number
  /// this strip writes: where the count starts again — each second, each
  /// page — the last frame of a whole run, whose number is the run's
  /// length, the widest [frameNumberLabel] repeats; otherwise the window's
  /// last frame, whose absolute number is longest.
  ///
  /// 🚨★★★ONE PLACE, BESIDE [frameNumberLabel]. A surface that measured
  /// this for itself would divide by the rate again, which is exactly the
  /// copy `ruler_seconds_label_test` refuses — the timeline and the x-sheet
  /// each carried that expression once before, and fixing one left the
  /// other counting from 1. What the scale writes and how wide it can be
  /// are the same object's question.
  int widestNumberFrameBefore(int endIndexExclusive) {
    final run = _numberRestartsEvery;
    if (run == null) {
      return endIndexExclusive - 1;
    }
    return (endIndexExclusive ~/ run) * run - 1;
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
          other.playbackFrameCount == playbackFrameCount &&
          other.leadingFrameSpacer == leadingFrameSpacer &&
          other.metrics == metrics &&
          other.face == face &&
          other.numberType == numberType &&
          other.secondsFontSize == secondsFontSize &&
          other.framesPerSecond == framesPerSecond &&
          other.rulerView == rulerView &&
          other.pageFrames == pageFrames &&
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
    playbackFrameCount,
    leadingFrameSpacer,
    metrics,
    face,
    numberType,
    secondsFontSize,
    framesPerSecond,
    rulerView,
    pageFrames,
    identityHashCode(windowBucket),
    viewportMainExtent,
    colorScheme,
  ]);
}
