import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../models/app_frame_grid_settings.dart';
import '../theme/app_theme.dart';
import 'axis_turn.dart';
import 'timeline_cell_style.dart';
import 'timeline_grid_metrics.dart' show timelineStrideHolding;
import 'timeline_second.dart';
import '../repaint_props.dart';

/// The frame grid, ONE SHEET per grid (UI-R10 #26 → UI-R13 #7 → UI-R18
/// #2/#8/#10/#12 — the storyboard recipe unified → I-44):
/// - the ROWS' GROUNDS: the host's own colour, the standing wash on the
///   active layer's row and on a lit lane, the lane wash under fx rows;
/// - BASE per-cell lines: flat faint ink, cadence-THINNED at small zooms
///   (never alpha-faded away) — the grid is always there, on every row
///   and lane;
/// - 6f/24f BEAT lines;
/// - ROW seams across the cross axis, over all of it: full-strength
///   hairlines at every row's trailing edge, zoom-independent (the
///   storyboard's row borders, generalized).
///
/// 🚨I-44 (유저 2026-09-23 → 09-24): 「가로선이랑 세로선이 2개 중복해서있고 …
/// 블록에도 세로선 3번째중복인데 이거 하나로 못합치나? 그리드오버레이위에
/// 행바닥 뭐지?」 → 「합친다 — 그리드 한 장」. The lines used to come from FOUR
/// places: this overlay (under the rows since D32, and under every row's
/// opaque ground — so drawn on every paint and seen nowhere), each row
/// redrawing the empty cells' lines and seams on its own ground (D43-2),
/// each block drawing seams on its paper, and each fx band its own grid
/// instance (F-7). The rows' grounds are THIS sheet's now, so the rows
/// paint paper and nothing else, and every line is drawn here, once.
///
/// 🗣️유저 2026-09-24: 「블록 세로선 역시 있는것도 좋아서 환경설정에 옵션으로
/// 두고싶어. 기본값은 있음으로」 — so a block's paper MAY carry this sheet's
/// lines again (Preferences ▸ Display, on by default). Still one line per
/// boundary: the paper hides the sheet's, and [timelineBlockFrameLine] draws
/// the same line — this file's cadence, weight and snap — onto the paper.
///
/// The painter lives in the scroll CONTENT's coordinate space (its size
/// is the full built content), so lines land on absolute frame
/// boundaries.
///
/// ⚠️ It used to say "a handful of `drawLine`s — no windowing needed",
/// and that was not true: the size is the whole content, so the count
/// scales with the timeline's LENGTH rather than with the window. An
/// audit put it at about 3% of the ops a window would remove here, so
/// the code is right to stay as it is — but for a reason it was not
/// giving. A comment that says "cheap" without saying why is how a
/// surface stops being looked at. (I-44 multiplies it by the stretches of
/// rows standing on a ground of their own — the active row and the fx
/// lanes, a handful — and the rows' tile bakes lost every line in return.)
/// D8/D32/D38 (2026-08-18): THE grid-line law, whole. This file already
/// owned the INK (R26 #40's "one grid language"); the position and the
/// ground treatment joined it so no drawer can restate a value:
/// - ink: the three named strengths below, dispatched per boundary;
/// - position: [timelineFrameBoundaryLinePosition] — every drawer lands
///   on boundary + [timelineGridLineSnap], the ruler's own pixel snap
///   (the overlay used to draw unsnapped, which was D8's "미묘하게 다름");
/// - on a ground: [timelineGridLineInkOnGround] — the line
///   channel-multiplied onto what it lies on (D32: a bright opaque line
///   glowing over blue paper was the report; multiply darkens instead),
///   computed in Dart so no advanced blend mode is ever asked of the
///   engine;
/// - cadence: one function answers for every drawer (D38: a zoom that
///   thins the 1f lines thins them everywhere — same question, same
///   answer).

/// The frame AREA's own leading edge — the hairline that marks where the
/// frames begin, mirroring the rail row's right border (D8, UI-R10 #20's
/// seam law: the splitter gap between them means neither line doubles the
/// other).
///
/// 🚨D8-2 (유저 2026-08-22) — **AND THE RULER WEARS IT TOO.** The user gave
/// this as a standing law, not as one instruction:
///
/// > 「프레임영역 왼쪽 선 좋은데 **룰러도 통일.** 프레임영역은 **기본 뭔가
/// > 바뀌면 룰러랑 통일**임」
///
/// ⇒ ★So it is a WIDGET, not a `BoxDecoration` written out twice. Whoever
/// changes this line changes it once, and the ruler cannot fall behind the
/// rows again — which is exactly how it fell behind this time.
///
/// ⚠️Viewport-STATIC: it marks the AREA, so it must not scroll with the
/// content. Both wearers put it on the widget that owns the viewport, never
/// on the scrolled child.
///
/// ⚠️The border is drawn in the FOREGROUND and takes no layout room, so
/// wrapping a `LayoutBuilder` in it does not change the constraints that
/// builder reads.
class TimelineFrameAreaEdge extends StatelessWidget {
  const TimelineFrameAreaEdge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: child,
    );
  }
}

/// The BASE line's stroke — what its cadence keeps ground beside
/// ([timelineGridLineEveryFrames]).
const double timelineGridBaseLineStroke = 1.0;

/// BASE line — the faint per-cell cadence line.
({Color color, double strokeWidth}) timelineGridBaseLineInk(
  ColorScheme colorScheme,
) => (
  color: colorScheme.outlineVariant.withValues(alpha: timelineBaseGridAlpha),
  strokeWidth: timelineGridBaseLineStroke,
);

/// 6f BEAT line — the sheet convention, zoom-independent.
///
/// 🚨F-41 (유저 2026-08-28): 「그리드선이 너무 진함 … 포인트는 그리드선이
/// 진해서 **블록이 한 블록이아니라 나뉜것처럼 보이는 착시현상**이 문제」.
///
/// 🔬재보니 **이 파일이 적어 둔 순서가 깨져 있었다.** 블록 종이(L=0.906)
/// 위에서 어두워지는 정도: 기본 0.176 · **6f 0.649** · SECOND 0.451.
/// SECOND 를 「the strongest」라고 써 놓고 **6f 가 가장 진했다** — 그리고 6f 는
/// **여섯 칸마다** 오므로, 한 블록이 여섯 칸마다 가장 진한 선으로 잘렸다.
/// 유저가 본 착시가 그것이다.
///
/// ⛔원인은 `colorScheme.outline`(#45494E)이 어두운 회색이라 종이에 곱해지면
/// SECOND 의 `beatLine`(#7C8184)보다 훨씬 크게 깎였다는 것 — **어두운 테마의
/// 크롬 색을 밝은 종이 위의 잉크로 그대로 쓴** 결과다. 이제 SECOND 와 같은
/// 잉크를 쓰되 **알파로 한 단계 옅게** 둔다: 순서가 값에서 나오지, 두 색의
/// 우연한 밝기 차에서 나오지 않는다.
({Color color, double strokeWidth}) timelineGridSixLineInk(
  ColorScheme colorScheme,
) => (
  color: AppColors.beatLine.withValues(alpha: timelineSixGridAlpha),
  strokeWidth: 1.0,
);

/// SECOND (fps) line — the strongest.
({Color color, double strokeWidth}) timelineGridSecondLineInk() => (
  color: AppColors.beatLine.withValues(alpha: timelineSecondGridAlpha),
  strokeWidth: 1.5,
);

/// ROW SEAM — the grid's CROSS-axis line, between one row and the next.
/// Full strength and zoom-independent (UI-R18 #10/#12: the rows' hairline
/// language extended into the cell area).
///
/// 🚨D43-2 재개 d (유저 2026-08-23): 「**fx행엔 그리드의 가로선 있는데
/// 레이어쪽 프레임쪽엔 없거든?** 그거 통일로 추가해주고」
///
/// ⛔The value used to be spelled out wherever a seam was drawn — an inline
/// tuple inside the overlay, a `BorderSide(outlineVariant, 0.5)` on the fx
/// band, and NOTHING at all on the frame cells rows, which paint an opaque
/// ground straight over the overlay's (D32's z-order). Three spellings, one
/// of them silence. Named here so a seam is one line however it is reached.
///
/// 🚨F-3 (유저 2026-08-25): 「가로선만 레이어영역 흰색계열로 통일. 세로나 그 외는
/// 그대로」. ⛔THE SEAM IS NEVER MULTIPLIED ONTO ITS GROUND, while the frame
/// boundary line always is. They look like one law and they are two: the
/// boundary line belongs to the FRAME grid, which rules whatever it crosses
/// and so must darken it; the seam is the LAYER area's row divider
/// continued into the cells, and the rail draws it flat over whatever the
/// row's ground happens to be. Stated by CONCEPT, not by screen direction:
/// on the X-sheet it is the vertical line between two layer COLUMNS.
({Color color, double strokeWidth}) timelineGridRowSeamInk(
  ColorScheme colorScheme,
) => (
  color: colorScheme.outlineVariant,
  strokeWidth: timelineGridRowSeamStroke,
);

/// The ROW SEAM's width — the last pixel of every row, across the cross
/// axis, is the seam's.
const double timelineGridRowSeamStroke = 1.0;

/// How far across a row its BLOCK PAPER reaches: the whole row but its seam.
///
/// 🚨I-44: the seam is drawn by the grid sheet UNDER the rows now, so paper
/// that covered the row's last pixel would hide the one line the user kept
/// on blocks (「세로선 지움(가로선 남김)」). Every block-shaped thing that has
/// to sit exactly on the paper — the paper itself on both raster paths, the
/// edge triangles, the run pattern, the warning line, the SE audio strip —
/// reads its box from here, and its corner from THIS extent, so a corner
/// cannot come out of a different box than the paper's.
double timelineRowPaperExtent(double rowExtent) =>
    rowExtent - timelineGridRowSeamStroke;

/// The position convention: a boundary line's center sits half a pixel
/// past the boundary — the frame ruler's own snap, now the law's.
const double timelineGridLineSnap = 0.5;

/// The ground two neighbouring marks on the frame axis keep between them:
/// two lines of the grid ([timelineGridLineEveryFrames]) and two numbers on
/// a ruler (`TimelineRulerScale.labelEveryFrames`). I-22 「겹칠때 생략」: a
/// mark thins out only where it would stand closer than this to the next.
const double timelineMarkGap = 2.0;

/// The base grid's line CADENCE at [frameCellExtent] (UI-R18 #8/#12, the
/// storyboard recipe adopted everywhere): instead of alpha-fading away at
/// small zooms, the per-cell lines THIN to every Nth frame and never
/// disappear — "the grid is always there".
///
/// 🚨I-22 (유저 2026-09-12): 「33.3%배율에서 3f마다의 그리드 세로선이랑 글자,
/// 아직 존재해도 안겹칠거같은데 뭔가 벌써 사라져? … 1f마다 그리드선이랑
/// 글자도 똑같음. 최대한 버텨보자」. ↩️The Nth was the ruler's LABEL cadence
/// below 16px, so lines 8px apart went wherever a number would have crowded.
/// A line's measure is its own stroke: the rung that holds a base line and
/// [timelineMarkGap] of ground beside it ([timelineStrideHolding]).
int timelineGridLineEveryFrames(double frameCellExtent) =>
    timelineStrideHolding(
      timelineGridBaseLineStroke + timelineMarkGap,
      frameCellExtent,
    );

/// Where the line at the boundary STARTING [frameIndex] is drawn, along
/// the frame axis in content coordinates.
double timelineFrameBoundaryLinePosition(
  int frameIndex,
  double frameCellExtent,
) => frameIndex * frameCellExtent + timelineGridLineSnap;

/// The grid line's ink ON a painted ground (a row's ground): the law line
/// channel-multiplied onto the ground, weighted by the line's own alpha —
/// a faint base line darkens the ground faintly, an opaque beat line
/// darkens it fully. Computed here, once, as a plain opaque colour, so no
/// drawer ever asks the engine for a multiply blend (an advanced blend is
/// what old tablets pay for, and Impeller answers it with an extra pass).
Color timelineGridLineInkOnGround(
  ({Color color, double strokeWidth}) ink,
  Color ground,
) {
  final line = ink.color;
  final multiplied = Color.from(
    alpha: 1,
    red: line.r * ground.r,
    green: line.g * ground.g,
    blue: line.b * ground.b,
  );
  return Color.lerp(ground, multiplied, line.a)!;
}

/// 🚨THE GROUND [timelineGridLineInkOnGround] MUST BE HANDED — what the eye
/// actually sees at that pixel, after [painted] has gone down over [under].
///
/// ⛔The law above ends in `lerp(ground, multiplied, ink.a)`, which
/// interpolates the ALPHA as well as the colour. Hand it a TRANSLUCENT
/// colour and the result climbs toward opaque while its rgb stays where the
/// translucent colour was: the line comes out MORE opaque than everything
/// around it, which on a pale wash means a line LIGHTER than its ground.
///
/// 🧪That is not a hypothetical. An unworked block is the paper at 43%, and
/// the cell painter used to pass it straight through: ground L=0.461, line
/// L=0.471 — 유저 2026-08-22, 「블록이 회색일때 그리드선이 흰색」. The 6f and
/// second lines survived only by being dark enough to still read as darker,
/// at about half the strength the law asks for.
///
/// Every ground the grid is drawn on, and every translucent paper that has
/// to hide it, resolves through HERE — the lane wash over the host
/// ([timelineLaneGround]) and the unworked block's paper over its row
/// (I-44: pre-blended so the sheet's lines cannot show through it).
Color? timelineGridGroundOver({
  required Color? under,
  required Color? painted,
}) {
  if (painted == null) {
    return under;
  }
  // Opaque paint IS what is seen; nothing under it matters.
  if (painted.a >= 1) {
    return painted;
  }
  // No known ground below (a row lying over the ARTWORK): there is nothing
  // to composite against, so the line stays the law's raw ink, source-over,
  // exactly as the folded row's overlay does.
  if (under == null) {
    return painted.a <= 0 ? null : painted;
  }
  return Color.alphaBlend(painted, under);
}

/// 🚨THE GRID'S GROUND AND CADENCE, PUBLISHED ONCE PER HOST — the grid sheet
/// reads both, and a row reads the ground to know what its translucent
/// paper stands on.
///
/// The sheet sits UNDER the rows (D32) and paints their grounds itself
/// (I-44), so a row owes the grid nothing any more — but a TRANSLUCENT
/// paper would let the sheet's lines through, so it is pre-blended onto the
/// ground it would have shown. The hosts genuinely sit on different colours
/// (the timeline and X-sheet on `surfaceContainerHighest`, the storyboard on
/// `surface`, a folded row on the artwork = null), which is why this is
/// inherited rather than guessed.
///
/// ⛔Do not read the ground off `colorScheme` at the point of use. That
/// guess is right three times in four, which is the worst kind of wrong.
///
/// It carries the user's grid preference too ([AppFrameGridSettings]) —
/// read HERE, so every row under a host sees the same answer and no host
/// has to remember to hand it down.
class TimelineGridLaw extends StatelessWidget {
  const TimelineGridLaw({
    super.key,
    required this.ground,
    required this.framesPerSecond,
    required this.child,
  });

  /// The host's own Material colour under the overlay; null where the grid
  /// lies over the artwork and there is nothing to multiply against.
  final Color? ground;

  /// The counting fps — which boundaries are SECOND boundaries.
  final int framesPerSecond;

  final Widget child;

  /// The law in force at [context]; null where no host states one.
  static TimelineGridLawData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TimelineGridLawScope>()?.law;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppFrameGridSettings>(
        valueListenable: AppFrameGridSettings.settings,
        builder: (context, settings, child) => _TimelineGridLawScope(
          law: (
            ground: ground,
            framesPerSecond: framesPerSecond,
            blockFrameLines: settings.blockFrameLines,
          ),
          child: child!,
        ),
        child: child,
      );
}

/// What a host's grid law says: the ground, the counting fps, and whether
/// the frame lines cross a block's paper.
typedef TimelineGridLawData = ({
  Color? ground,
  int framesPerSecond,
  bool blockFrameLines,
});

class _TimelineGridLawScope extends InheritedWidget {
  const _TimelineGridLawScope({required this.law, required super.child});

  final TimelineGridLawData law;

  @override
  bool updateShouldNotify(_TimelineGridLawScope oldWidget) =>
      oldWidget.law != law;
}

/// THE frame line across a block's paper — the sheet's own line at the
/// boundary starting [frameIndex] (the same cadence, weight and snap),
/// inked onto the [paper] it crosses; null where it is not drawn.
///
/// [boundary] is where that boundary lies along the frame axis in the
/// drawer's own coordinates, [across] the paper's extent across it.
///
/// ⛔Null over see-through paper as well as where the cadence thins the
/// boundary out: the sheet's own line already shows through such paper (a
/// folded row's unworked block, over the artwork), and a second line on it
/// is F-7's doubled line (「선이 이중적용되고있는건가?」).
///
/// Every block that shows the lines asks here — the rows, both raster paths
/// of them, and the paper spans — so a line on a block cannot come out of a
/// different law than the line beside it on the ground.
({Rect rect, Color color})? timelineBlockFrameLine({
  required Axis axis,
  required int frameIndex,
  required double boundary,
  required ({double from, double to}) across,
  required double frameCellExtent,
  required int framesPerSecond,
  required ColorScheme colorScheme,
  required Color paper,
}) {
  if (paper.a < 1) {
    return null;
  }
  final ink = timelineFrameBoundaryLineInk(
    frameIndex: frameIndex,
    frameCellExtent: frameCellExtent,
    framesPerSecond: framesPerSecond,
    colorScheme: colorScheme,
  );
  if (ink == null) {
    return null;
  }
  final from = boundary + timelineGridLineSnap - ink.strokeWidth / 2;
  final to = from + ink.strokeWidth;
  return (
    rect: axis == Axis.horizontal
        ? Rect.fromLTRB(from, across.from, to, across.to)
        : Rect.fromLTRB(across.from, from, across.to, to),
    color: timelineGridLineInkOnGround(ink, paper),
  );
}

/// The ground a LANE row stands on while nobody stands on it — the lane
/// wash composited onto the host's ground; the raw wash where the host has
/// none to composite onto.
///
/// 🚨F-7 (유저 2026-08-24): 「스토리보드패널, fx열면 프레임영역의 선이 두꺼운데
/// 선이 이중적용되고있는건가?」 — it was: the band washed at 60% over the
/// buried grid and then drew the law on top, two lines at one boundary.
/// ⇒ The wash is COMPOSITED, so a lane's ground is one opaque colour and the
/// grid is drawn on it once, in the ink that colour asks for. That is the
/// sheet's job now (I-44); this is the colour it paints, and the colour the
/// SE audio strip's translucent paper is pre-blended onto.
Color timelineLaneGround(Color? hostGround) {
  final wash = AppColors.washDown.withValues(alpha: 0.6);
  return timelineGridGroundOver(under: hostGround, painted: wash) ?? wash;
}

/// A row's ground while it is STOOD ON — the active layer's row, a lit fx
/// lane: the one standing wash, composited over the row's [resting] ground
/// (UI-R21 #2's wash, F-25's chain lit on both halves of the splitter).
Color timelineStandingGround(Color resting, ColorScheme colorScheme) =>
    Color.alphaBlend(timelineActiveRowWashColor(colorScheme), resting);

/// The ink of the grid line at the boundary STARTING frame [frameIndex]
/// — the one grid language shared by the cell grid overlay and the frame
/// ruler (R26 #40: "룰러도 프레임 셀 그리드랑 통일감").
///
/// Null when the base cadence thins this boundary out at the current
/// zoom. 6f boundaries read slightly stronger, second (fps) boundaries
/// strongest — the sheet convention, zoom-independent.
({Color color, double strokeWidth})? timelineFrameBoundaryLineInk({
  required int frameIndex,
  required double frameCellExtent,
  required int framesPerSecond,
  required ColorScheme colorScheme,
}) {
  if (frameIndex <= 0 || frameCellExtent <= 0) {
    return null;
  }
  if (frameIndex % 6 == 0) {
    return timelineOnSecondBoundary(frameIndex, framesPerSecond)
        ? timelineGridSecondLineInk()
        : timelineGridSixLineInk(colorScheme);
  }
  final cadence = timelineGridLineEveryFrames(frameCellExtent);
  if (frameIndex % cadence != 0) {
    return null;
  }
  return timelineGridBaseLineInk(colorScheme);
}

/// The OUT-OF-CUT wash: everything past the cut's last frame, greyed.
///
/// One rect over the whole grid, in the same content coordinate space the
/// line overlay uses — it used to be blended into every cell, inside the
/// baked substrate tiles, which is what tied those tiles to the cut's
/// LENGTH. A length that moved therefore could not be drawn without
/// re-rastering the row, so the drag showed the committed shading for its
/// whole duration and snapped on release. Lifted out, it costs one
/// `drawRect` and follows the drag for free (user's layering 2026-08-02).
///
/// The blend is the same colour and alpha the per-cell version used, and
/// over an already-painted cell it composites to the same pixels. Block
/// BORDERS differ slightly: they had their own dim ink, and one rect cannot
/// tell a border from its cell — accepted by the user, and the wash reads
/// as one region rather than as a run of separately shaded cells.
class TimelineOutsideCutWashPainter extends CustomPainter with RepaintOnProps {
  const TimelineOutsideCutWashPainter({
    required this.outsideStart,
    required this.colorScheme,
    this.axis = Axis.horizontal,
  });

  /// Where the cut ends, in content pixels along the frame axis.
  final double outsideStart;
  final ColorScheme colorScheme;
  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) {
    final mainExtent = extentAlong(axis, size);
    if (outsideStart >= mainExtent) {
      return;
    }
    final start = outsideStart < 0 ? 0.0 : outsideStart;
    canvas.drawRect(
      Rect.fromPoints(
        offsetAlong(axis, along: start, across: 0),
        offsetAlong(axis, along: mainExtent, across: extentAcross(axis, size)),
      ),
      Paint()..color = AppColors.washUp.withValues(alpha: 0.54),
    );
  }

  @override
  Object get props => (outsideStart, colorScheme, axis);
}


/// One row of a grid sheet, across the cross axis: how far it reaches and
/// the ground it stands on. Every row is ruled off at its trailing edge.
typedef TimelineGridRow = ({double extent, Color ground});

/// The rows a grid sheet lays down, in order from its cross-axis origin.
///
/// A VALUE, so a sheet rebuilt over the same rows repaints nothing: the
/// timeline rebuilds its grid area for reasons that have nothing to do with
/// the grounds (a row window sliding), and a list compared by identity
/// would re-record the whole content-long sheet each time.
@immutable
class TimelineGridRows {
  const TimelineGridRows(this.rows);

  /// No rows: the lines alone, over the host's ground and nothing else.
  static const TimelineGridRows none = TimelineGridRows([]);

  final List<TimelineGridRow> rows;

  @override
  bool operator ==(Object other) =>
      other is TimelineGridRows && listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hashAll(rows);
}

/// THE grid sheet — every host's frame grid, drawn once, UNDER its rows.
///
/// It reads the host's law ([TimelineGridLaw]) for the ground and the
/// counting fps, so neither is stated a second time at the mount.
class TimelineGridSheet extends StatelessWidget {
  const TimelineGridSheet({
    super.key,
    required this.frameCellExtent,
    this.rows = TimelineGridRows.none,
    this.axis = Axis.horizontal,
    this.frameStartIndex = 0,
  });

  final double frameCellExtent;
  final TimelineGridRows rows;
  final Axis axis;

  /// See [TimelineGridSheetPainter.frameStartIndex].
  final int frameStartIndex;

  @override
  Widget build(BuildContext context) {
    final law = TimelineGridLaw.maybeOf(context);
    return CustomPaint(
      painter: TimelineGridSheetPainter(
        frameCellExtent: frameCellExtent,
        framesPerSecond: law?.framesPerSecond ?? 0,
        colorScheme: Theme.of(context).colorScheme,
        ground: law?.ground,
        axis: axis,
        rows: rows,
        frameStartIndex: frameStartIndex,
      ),
    );
  }
}

class TimelineGridSheetPainter extends CustomPainter with RepaintOnProps {
  TimelineGridSheetPainter({
    required this.frameCellExtent,
    required this.framesPerSecond,
    required this.colorScheme,
    required this.ground,
    this.axis = Axis.horizontal,
    this.rows = TimelineGridRows.none,
    this.frameStartIndex = 0,
  });

  final double frameCellExtent;
  final int framesPerSecond;
  final ColorScheme colorScheme;

  /// The HOST's ground — what lies under this sheet wherever no row paints
  /// a ground of its own. A line takes the ink its ground asks for
  /// (유저, 2026-08-21: 「그리드 오버레이랑 블록 내부 이음매같은게 색이나 생긴게
  /// 달라서 통일하고싶다」).
  ///
  /// 🚨The two used to differ by OPERATION, not by value. Over empty ground
  /// the line was source-over — `lerp(ground, line, line.a)`, which in a
  /// dark theme is LIGHTER than its ground — while over a block the tile
  /// multiplied: `lerp(paper, line×paper, line.a)`, always DARKER. Same
  /// ink, same position, same cadence, two composites, so one grid changed
  /// character wherever paper began. Every line here goes through
  /// [timelineGridLineInkOnGround].
  ///
  /// ⚠️Null = "the ground is not a single known colour". The folded row
  /// lies over the ARTWORK at 70%, so there is nothing to multiply against
  /// and its lines stay source-over.
  final Color? ground;

  /// The FRAME axis' direction: horizontal (timeline, storyboard) draws
  /// vertical lines; vertical (X-sheet) draws horizontal ones.
  final Axis axis;

  /// The rows this sheet lays down, from the cross-axis origin. A row whose
  /// ground is not [ground] gets it painted here, and the frame lines over
  /// it in that ground's ink; every row is ruled off at its trailing edge.
  ///
  /// ⛔THE ROWS PAINT NO GROUND OF THEIR OWN (I-44). They used to — the
  /// surface underlay and the active wash of UI-R21 #2, the fx band's
  /// composited wash — and every one of them buried this sheet and then
  /// owed it a redraw (D43-2), which is how one grid came to be drawn in
  /// four places. The standing wash rides here now: the sheet repaints on
  /// a layer switch, and still no tile re-bakes (UI-R21 #2's reason holds).
  final TimelineGridRows rows;

  /// The ABSOLUTE frame at this canvas' origin — so a windowed surface (the
  /// folded row, which paints one screenful from the first visible frame)
  /// draws the boundaries that actually fall in its window rather than
  /// counting from its own left edge. 0 is the whole-panel sheet.
  final int frameStartIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (frameCellExtent <= 0) {
      return;
    }
    final mainExtent = extentAlong(axis, size);
    final crossExtent = extentAcross(axis, size);

    Rect across(double from, double to) => Rect.fromPoints(
      offsetAlong(axis, along: 0, across: from),
      offsetAlong(axis, along: mainExtent, across: to),
    );

    // The host's ground first, the whole cross extent at once: most rows
    // stand on it, so most of the sheet is one pass of lines.
    _paintLines(
      canvas,
      mainExtent,
      (from: 0, to: crossExtent, ground: ground),
    );

    // Then every stretch of rows standing on a ground of its own — the
    // active layer's row, the fx lanes — laid over those lines, with the
    // lines drawn again on it in the ink it asks for.
    var start = 0.0;
    for (var index = 0; index < rows.rows.length;) {
      final stretchGround = rows.rows[index].ground;
      var end = start;
      while (index < rows.rows.length &&
          rows.rows[index].ground == stretchGround) {
        end += rows.rows[index].extent;
        index += 1;
      }
      if (stretchGround != ground) {
        canvas.drawRect(across(start, end), Paint()..color = stretchGround);
        _paintLines(canvas, mainExtent, (
          from: start,
          to: end,
          ground: stretchGround,
        ));
      }
      start = end;
    }

    // ROW seams (UI-R18 #10/#12), over everything: full-strength,
    // zoom-independent — the rail's own hairline language continued into
    // the cells, at each row's LAST pixel, so the next row's first is
    // untouched. F-3: FLAT, never through the ground law
    // ([timelineGridRowSeamInk] says why).
    final seam = timelineGridRowSeamInk(colorScheme);
    final seamPaint = Paint()..color = seam.color;
    var edge = 0.0;
    for (final row in rows.rows) {
      edge += row.extent;
      canvas.drawRect(across(edge - seam.strokeWidth, edge), seamPaint);
    }
  }

  /// The frame lines across one [stretch] of the cross axis — `from` to
  /// `to` — in the ink its `ground` asks for.
  void _paintLines(Canvas canvas, double mainExtent, _Stretch stretch) {
    final (:from, :to, :ground) = stretch;
    Color inkOn(({Color color, double strokeWidth}) ink) =>
        ground == null ? ink.color : timelineGridLineInkOnGround(ink, ground);
    void line(double position, Paint paint) => canvas.drawLine(
      offsetAlong(axis, along: position, across: from),
      offsetAlong(axis, along: position, across: to),
      paint,
    );
    // The first boundary of period [period] at or after the window start —
    // the hoisted form of "which absolute frames does this canvas show".
    int firstBoundary(int period) => frameStartIndex <= 0
        ? period
        : ((frameStartIndex + period - 1) ~/ period) * period;
    double positionOf(int frame) => timelineFrameBoundaryLinePosition(
      frame - frameStartIndex,
      frameCellExtent,
    );
    bool shown(int frame) =>
        (frame - frameStartIndex) * frameCellExtent <= mainExtent;

    // BASE grid: flat faint, cadence-thinned (UI-R18 #8 — the storyboard
    // look; beat frames skip, the beat pass draws them stronger). The ink
    // comes from the LAW's named functions and the position from its snap
    // — the stride loops below are the law's own cadence hoisted, so no
    // per-boundary allocation happens on this content-length walk.
    final baseInk = timelineGridBaseLineInk(colorScheme);
    final basePaint = Paint()
      ..color = inkOn(baseInk)
      ..strokeWidth = baseInk.strokeWidth;
    final cadence = timelineGridLineEveryFrames(frameCellExtent);
    for (var frame = firstBoundary(cadence); shown(frame); frame += cadence) {
      if (frame % 6 == 0) {
        continue;
      }
      line(positionOf(frame), basePaint);
    }

    final sixInk = timelineGridSixLineInk(colorScheme);
    final sixPaint = Paint()
      ..color = inkOn(sixInk)
      ..strokeWidth = sixInk.strokeWidth;
    final secondInk = timelineGridSecondLineInk();
    final secondPaint = Paint()
      ..color = inkOn(secondInk)
      ..strokeWidth = secondInk.strokeWidth;
    // 6f is the sheet convention regardless of fps.
    const beatPeriod = 6;
    for (
      var frame = firstBoundary(beatPeriod);
      shown(frame);
      frame += beatPeriod
    ) {
      final paint = timelineOnSecondBoundary(frame, framesPerSecond)
          ? secondPaint
          : sixPaint;
      line(positionOf(frame), paint);
    }
  }

  @override
  Object get props => (
    frameCellExtent,
    framesPerSecond,
    colorScheme,
    ground,
    axis,
    frameStartIndex,
    rows,
  );
}

/// One stretch of a grid sheet's cross axis and the ground it stands on —
/// what [TimelineGridSheetPainter] lines at a time.
typedef _Stretch = ({double from, double to, Color? ground});
