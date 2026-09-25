import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/frame.dart' show InbetweenMark, drawingHeadOf;
import '../canvas/flip_hud_model.dart';
import '../text/word_condensation.dart';
import '../theme/app_theme.dart';
import 'inbetween_mark_painter.dart';
import 'layer_label_controls.dart' show layerKindIcon;
import 'layer_rail_window.dart' show LayerRailExtent, LayerRailWindow;
import 'timeline_beat_lines.dart';
import 'timeline_cell_style.dart'
    show
        TimelineBlockWordGrowth,
        timelineBlockWordLayout,
        timelineBlockWordStyle;
import 'timeline_frame_geometry.dart';
import 'timeline_frame_grid_stack.dart';
import 'timeline_glyph_cache.dart';
import 'timeline_grid_metrics.dart';
import '../repaint_props.dart';
import 'memo_token.dart';

/// The row you are standing on, drawn over the artwork with NO ground under
/// it — what a collapsed frame panel says instead of disappearing.
///
/// 유저 확정 (2026-08-10), and the whole design is in the negative space:
///
///  * **no panel fill, no rail fill, no active-row wash, no seams.** The only
///    ground that survives is the out-of-cut shading, because that one IS the
///    information;
///  * blocks keep a translucent body so they read as paper, and the frame you
///    are standing on is the one thing painted solidly;
///  * an empty stretch prints `x` in its FIRST cell and nothing after —
///    the timesheet's own marker rule, not a box of its own invention;
///  * it never takes a pointer. Pressing it draws on the canvas, which is
///    what is underneath.
///
/// ★The material is [FlipHudSnapshot] — the same snapshot the flip window
/// reads, built from the rows the timeline is actually displaying. That is
/// not a convenience: two summaries of "where am I" built from two sources
/// would drift, and this one would be the one that lies, because the flip is
/// what moves the cursor. It already carries the two rules that would
/// otherwise have to be re-derived here — `emptyRunStartsAt` (where the `x`
/// goes) and `showsKindIcon` (a property lane is not stamped with its
/// owner's glyph).
///
/// ★The RAIL half is the real thing: the caller hands in an actual
/// `TimelineLayerControlsRow(chromeless: true)` — every slot the timeline
/// draws (fx twirl · timesheet · mark · kind · name · eye · opacity · blend ·
/// onion), painted with its ground removed.
///
/// ⛔It deliberately does NOT re-list those slots here. The first version did,
/// from the snapshot's `name` + `kind`, and that was the wrong shape twice
/// over: it showed three of twelve, and it would have needed editing again
/// every time the rail grew a column. Mounting the row means the overlay
/// follows it by construction. [railChild] is null on a property lane, whose
/// rail is a name and a value rather than a control cluster.
/// The folded row's translucency, as ONE number (유저 확정 2026-08-14:
/// 「반투명 = 오버레이 루트 하나, 70%」).
///
/// A constant rather than a literal at the install site because the whole
/// point is that there is only one of it: the two per-cell alphas it replaced
/// were `0x66` and `0x9E`, and having two was the bug.
const double collapsedRowOverlayOpacity = 0.7;

class CollapsedRowOverlay extends StatefulWidget {
  const CollapsedRowOverlay({
    super.key,
    required this.snapshot,
    required this.rail,
    required this.naturalRailWidth,
    required this.pixelsPerFrame,
    required this.framesPerSecond,
    this.height = defaultHeight,
    this.railChild,
    this.frameRowBuilder,
    this.frameAxisOffset,
    this.drawnFrameCount,
  });

  /// The rail row itself, chromeless — see the class doc. Null on a lane row.
  final Widget? railChild;

  /// How many frames the cut is DRAWN for — the open grid's own number
  /// ([TimelineFrameGridStack.drawnFrameCount]): the out-of-cut wash starts
  /// there, past the のりしろ, not at the snapshot's cut end. Null = no
  /// のりしろ, and the wash starts at the cut end.
  final int? drawnFrameCount;

  /// Where the open grid's FRAME axis stands, in pixels at [pixelsPerFrame]
  /// — the host's own value, the one the grid keeps (F-143). The frame half
  /// is laid out from it, so the folded row shows the frames the open one
  /// was showing. Null = the axis at its start.
  final ValueListenable<double>? frameAxisOffset;

  /// ⑩ 뿌리 C: the FRAME half, built by the caller from the same row widget
  /// the timeline draws — the other half of "the overlay owns no drawing
  /// code of its own".
  ///
  /// It is a builder rather than a child because the row needs the live
  /// [TimelineFrameGeometryHandle], and only this widget knows how much room
  /// there is: the handle is owned here (its IDENTITY is the row memo's key,
  /// so it must outlive the values it reports) and republished from the
  /// layout below.
  ///
  /// Null falls back to the painter — see [_CollapsedStripPainter].
  final Widget Function(BuildContext, TimelineFrameGeometryHandle)?
  frameRowBuilder;

  final FlipHudSnapshot snapshot;

  /// The timeline's own rail window (`LayerRailId.timeline`), WHOLE.
  ///
  /// 유저 확정: 좁혀놨으면 좁힌 대로 — 「레이어영역의 가로길이같은거 타임라인
  /// 그대로 가져와. 그래야 **열의 규격이 맞을** 거니까」.
  ///
  /// 🚨⛔It used to be a `double` read as `rail?.value ?? layerRailMinimumWindowExtent`,
  /// and that one line is where the columns came apart. A null `value` means
  /// **「자연폭」** — lay the rail out at its own size — and the overlay read
  /// it as **「최소폭」**, which is `layerRailLeadingWidth + 14`: the leading
  /// cluster plus the first letter of the name. That is exactly the
  /// `▸ ▦ ● 🎞 A` the user photographed, and it made three complaints out of
  /// one bug — 「버튼이 없다」, 「길이가 다르다」, 「열이 안 맞는다」. The
  /// buttons were never removed; they were cut off outside the window.
  ///
  /// Taking the object instead of a number means [LayerRailWindow] answers
  /// all three of its questions the way the panel's own rail does: null is
  /// natural, `offset` is the push, and `availableExtent` is the clamp.
  final LayerRailExtent? rail;

  /// The rail's own size when nothing windows it — [TimelineGridMetrics.layerControlsWidth],
  /// the same number `layer_timeline_grid` calls `_naturalRailWidth`.
  final double naturalRailWidth;

  final double pixelsPerFrame;
  final int framesPerSecond;

  /// THE ROW'S OWN HEIGHT (유저 확정 2026-08-21: 「간편오버레이 높이도 해당
  /// 행 높이에따라서 맞춤. 이 높이 맞추는건 타임라인의 간편오버레이든
  /// 동일하게」).
  ///
  /// ⛔It used to be `static const height = timelineLayerRowHeight`, and a
  /// constant cannot be a row's height — it can only be one KIND of row's.
  /// That was invisible while the folded row was always a timeline layer
  /// row (every timeline row is `timelineDisplayRowExtent`, one number),
  /// and wrong the moment the storyboard folded: a V track is as tall as
  /// its own splitter left it. The host asks the row and passes the
  /// answer, so a row height that changes anywhere changes here for free.
  final double height;

  /// The height of a plain timeline layer row — the value the constant
  /// used to be, kept for hosts that mount the overlay without a row to
  /// measure (tests, and the fallback strip).
  static const double defaultHeight = timelineLayerRowHeight;

  @override
  State<CollapsedRowOverlay> createState() => _CollapsedRowOverlayState();
}

class _CollapsedRowOverlayState extends State<CollapsedRowOverlay> {
  /// The fallback window for a host that has no stored one — the same
  /// `?? (owned ??= …)` shape `layer_timeline_grid` uses, and for the same
  /// reason: a fresh [LayerRailExtent] per build would drop the offset every
  /// pass. A default one reports null, which means natural width.
  LayerRailExtent? _ownedRail;

  /// 🚨Owned by the State, not rebuilt per pass: the row memo keys on this
  /// handle's IDENTITY, so a fresh one each build would defeat the repaint
  /// gating it exists for. Republished (value only) from the layout —
  /// `timeline_frame_geometry.dart` spells out why publishing from build is
  /// safe: every listener is a render object.
  final TimelineFrameGeometryHandle _geometry = TimelineFrameGeometryHandle(
    const TimelineFrameGeometry(
      frameCellExtent: 8,
      frameStartIndex: 0,
      frameEndIndexExclusive: 0,
    ),
  );

  /// The axis at frame 0, for a host that keeps no offset — a listenable
  /// that never moves, so the frame half has ONE way to be laid out.
  static const ValueListenable<double> _axisAtItsStart =
      AlwaysStoppedAnimation<double>(0);

  @override
  void dispose() {
    _geometry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final row = snapshot.currentRow;
    if (row == null || snapshot.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      // ★ONE translucency for the whole row (유저 확정 2026-08-14: 「반투명 =
      // 오버레이 루트 하나, 70%」).
      //
      // ⛔It used to be two per-cell alphas inside the cells painter, `0x66`
      // on a block's body and `0x9E` on its edge, which gave the folded row
      // an opacity SCHEME of its own — parts fading by different amounts. It
      // is supposed to be the open row seen through glass, and that is what
      // a single value on the root makes it, by construction.
      //
      // ⚠️The 08-10 confirmation 「the frame you are standing on is the one
      // thing painted SOLIDLY」 still holds, but RELATIVELY: the current cell
      // is still the only full one inside this row, and the row as a whole
      // sits at 70%.
      child: Opacity(
        opacity: collapsedRowOverlayOpacity,
        child: SizedBox(
          height: widget.height,
          // ★The rail window is CLAMPED to the room that exists. The stored
          // width is the splitter's answer for a panel as wide as the region,
          // and the collapsed row is laid over a region that can be pulled
          // narrower than that — an inflexible 434 beside an `Expanded` then
          // overflows by the difference rather than yielding, which is exactly
          // what the region tests caught. Clamping keeps the rail model's own
          // rule: the window never exceeds what there is to window.
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ★THE RAIL MODEL, from the widget that owns it rather than
                // rebuilt by hand: 「레일은 자기 자연 크기로 눕고, 스플리터는
                // 그 위의 창을 정하고, 꼬리가 그냥 잘린다」.
                //
                // ⛔This was a `SizedBox(min(railWidth, maxWidth))` wrapping a
                // `ClipRect` + `OverflowBox` — the same three jobs
                // [LayerRailWindow] does, spelled out a second time. The copy
                // could not answer the one question that mattered: a stored
                // extent of null means NATURAL, and only the window widget
                // knows that. `availableExtent` carries over the clamp the
                // `min()` was doing, which is what keeps a narrowed region
                // from overflowing.
                LayerRailWindow(
                  axis: Axis.horizontal,
                  rail: widget.rail ?? (_ownedRail ??= LayerRailExtent()),
                  naturalExtent: widget.naturalRailWidth,
                  availableExtent: constraints.maxWidth,
                  child: _haloed(
                    context,
                    // A layer row is the REAL row, chromeless. A property
                    // lane is its name and its value, which is what the rail
                    // shows there — so the caller hands null instead.
                    widget.railChild ?? _rail(row, colorScheme),
                  ),
                ),
                Expanded(
                  child: ClipRect(
                    child: LayoutBuilder(
                      builder: (context, frameConstraints) =>
                          ValueListenableBuilder<double>(
                            valueListenable:
                                widget.frameAxisOffset ?? _axisAtItsStart,
                            builder: (context, origin, _) => _frameHalf(
                              context,
                              row,
                              viewport: frameConstraints.maxWidth,
                              origin: origin,
                            ),
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The FRAME half: a viewport onto the row, standing where the open
  /// grid's frame axis stands.
  ///
  /// 🚨★★F-143 (유저 2026-09-16): 「꽤 오른쪽으로 스크롤한채로 접으면
  /// 간편오버레이는 첫 인덱스쪽을 보여주고있어서」. This half was laid out
  /// from frame 0 whatever the grid had been showing — `frameStartIndex: 0`
  /// was written here as a constant.
  ///
  /// ⛔ONE ORIGIN FOR EVERYTHING IN IT. The row, the grid sheet under it
  /// and the fallback strip are all laid out from the same
  /// first frame, and the one sub-cell remainder slides them together — the
  /// open grid's scroll view moves its content as one piece, and so does
  /// this. A painter handed the offset on its own is the one that drifts
  /// the day the others change.
  ///
  /// ⚠️The content begins at the first VISIBLE frame rather than at 0, one
  /// viewport (plus the partial cell) wide, so what is painted stays one
  /// screenful however far the axis has been scrolled — the open grid's
  /// rows window themselves for the same reason.
  ///
  /// [row] is the one the build already found standing — handed over rather
  /// than looked up again, so the two cannot disagree about it.
  Widget _frameHalf(
    BuildContext context,
    FlipHudRow row, {
    required double viewport,
    required double origin,
  }) {
    final snapshot = widget.snapshot;
    final colorScheme = Theme.of(context).colorScheme;
    final cell = widget.pixelsPerFrame;
    final at = math.max(0.0, origin);
    final first = cell <= 0 ? 0 : (at / cell).floor();
    final shift = cell <= 0 ? 0.0 : at - first * cell;
    final width = viewport + math.max(0.0, cell);
    final build = widget.frameRowBuilder;
    final Widget content;
    if (build == null) {
      content = CustomPaint(
        key: const ValueKey<String>('collapsed-strip'),
        painter: _CollapsedStripPainter(
          snapshot: snapshot,
          row: row,
          pixelsPerFrame: cell,
          colorScheme: colorScheme,
          baseTextStyle: DefaultTextStyle.of(context).style,
          frameStartIndex: first,
        ),
      );
    } else {
      // Republished per layout, value only — the handle's identity is what
      // the row memo keys on.
      _geometry.value = TimelineFrameGeometry(
        frameCellExtent: cell,
        frameStartIndex: first,
        frameEndIndexExclusive: cell <= 0
            ? first
            : first + (width / cell).ceil(),
      );
      content = build(context, _geometry);
    }
    // 🚨THE GRID, UNDER WHATEVER STANDS HERE — the timeline's own sheet, the
    // one the panel draws. A row does not rule its own frames (every plain
    // per-cell border is `Colors.transparent` on purpose — 「the GRID OVERLAY
    // owns every plain per-cell line now」), so a row without it has none,
    // and chromeless mode was once wrongly blamed for erasing them.
    //
    // ↩️It used to be laid OVER the row here, while the open panel had put
    // it under since D32 — and the row drew its own lines as well, so this
    // strip carried two grids. I-44 (「합친다 — 그리드 한 장」): one sheet,
    // under the row, as in the panel. The fallback strip draws on it too; it
    // used to walk the same boundaries with a loop of its own.
    //
    // ⛔NO GROUND in its law: the row lies over the ARTWORK (유저 확정
    // 2026-08-10: 「프레임셀쪽은 바탕색은 싹 없애고 그리드선 띄우고 … 반투명」),
    // so the lines stay the law's raw ink, no row is painted a colour, no
    // seam is ruled — and an unworked block's paper, with nothing to be
    // pre-blended onto, stays translucent (the cost the user took with I-44:
    // here alone the lines show faintly through it).
    final sheet = TimelineGridSheet(
      key: const ValueKey<String>('collapsed-grid-sheet'),
      frameCellExtent: cell,
      frameStartIndex: first,
    );
    return OverflowBox(
      alignment: Alignment.centerLeft,
      minWidth: width,
      maxWidth: width,
      child: Transform.translate(
        offset: Offset(-shift, 0),
        child: TimelineGridLaw(
          ground: null,
          framesPerSecond: widget.framesPerSecond,
          child: switch (snapshot.playbackFrameCount) {
            // A snapshot with no cut end — the storyboard's track — has
            // nowhere the film stops, and the open storyboard shades none.
            null => Stack(
              fit: StackFit.expand,
              children: [IgnorePointer(child: sheet), content],
            ),
            final playback => _whereTheFilmStops(
              sheet: sheet,
              content: content,
              cell: cell,
              stops: (
                cut: playback - first,
                drawn: switch (widget.drawnFrameCount) {
                  final drawn? => drawn - first,
                  null => null,
                },
              ),
            ),
          },
        ),
      ),
    );
  }

  /// WHERE THE FILM STOPS, stated over whatever stands here by the open
  /// grid's own stack ([TimelineFrameGridStack]): the grid sheet under the
  /// row, and over it the out-of-cut wash from the DRAWN end (유저
  /// 2026-08-11), the のりしろ mark and the cut-end line — so this is the open
  /// row seen through glass here too, and `one_cut_end_stack_test` keeps it
  /// the ONE stack that says so.
  ///
  /// 🚨The 08-10 design keeps ONE ground, and it is this wash: 「the only
  /// ground that survives is the out-of-cut shading, because that one IS the
  /// information」. ⛔It used to be the fallback strip's alone, painted from
  /// the cut end in a colour of its own beside a cut line of its own — and
  /// the folded row that mounts the REAL row (every folded timeline row since
  /// ⑩ 뿌리 C) painted neither, so the one ground the design kept was on the
  /// one path nobody saw.
  ///
  /// [stops] — the cut end and the drawn end — are counted from the first
  /// frame laid out here, which is this stack's origin: it lays every
  /// overlay at a frame count times the cell from its own left edge.
  Widget _whereTheFilmStops({
    required Widget sheet,
    required Widget content,
    required double cell,
    required ({int cut, int? drawn}) stops,
  }) => TimelineFrameGridStack(
    gridSheet: sheet,
    rowsBody: SizedBox.expand(child: content),
    // The cursor is the row's own layer — the real row mounts
    // [TimelineCursorLayer], the strip paints its own — so the stack's
    // playhead slot stands empty.
    playheadExtent: 0,
    playhead: const SizedBox.shrink(),
    frameCellExtent: cell,
    playbackFrameCount: stops.cut,
    drawnFrameCount: stops.drawn,
  );

  /// ⑩ 🚫NO HALO (유저 확정 2026-08-12): 「버튼 쪽 그림자(할로) 삭제.
  /// **흰캔버스에서 안보이든말든 신경쓰지말고 그냥 없애.** 간편 오버레이에서
  /// **다신 존재 안 하도록.** 입체감 없이 평면처럼 보이게 하고 싶은 거야」.
  ///
  /// It was two stacked shadows, argued for as legibility over a bright
  /// sheet. The user has read that argument and declined it: FLAT is the
  /// look, and being hard to read on white paper is the price they chose.
  ///
  /// ⛔Do not bring it back under another name — a plate, a scrim, a blur.
  /// The instruction is about the LOOK, not about this particular shadow.
  static const List<Shadow> _halo = [];

  /// Still the ONE place this overlay's ink is decided, so anything that
  /// ever changes it changes here rather than in six call sites.
  Widget _haloed(BuildContext context, Widget child) => IconTheme.merge(
    data: const IconThemeData(shadows: _halo),
    child: DefaultTextStyle.merge(
      style: const TextStyle(shadows: _halo),
      child: child,
    ),
  );

  Widget _rail(FlipHudRow row, ColorScheme colorScheme) {
    const shadows = _halo;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          if (row.showsKindIcon) ...[
            Icon(
              layerKindIcon(row.kind),
              size: 14,
              color: colorScheme.primary,
              shadows: shadows,
            ),
            const SizedBox(width: 5),
          ] else
            // A lane's name is indented under its owner's, exactly as the
            // rail indents it.
            const SizedBox(width: 19),
          Flexible(
            child: Text(
              row.name,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.text,
                shadows: shadows,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedStripPainter extends CustomPainter with RepaintOnProps {
  const _CollapsedStripPainter({
    required this.snapshot,
    required this.row,
    required this.pixelsPerFrame,
    required this.colorScheme,
    required this.baseTextStyle,
    this.frameStartIndex = 0,
  });

  final FlipHudSnapshot snapshot;
  final FlipHudRow row;
  final double pixelsPerFrame;
  final ColorScheme colorScheme;

  /// The ambient text style — the app's face for the strip's words.
  final TextStyle baseTextStyle;

  /// The frame at this painter's left edge — the grid sheet's convention
  /// ([TimelineGridSheetPainter.frameStartIndex]), so the strip and the
  /// row it stands in for share one origin (F-143).
  final int frameStartIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (pixelsPerFrame <= 0) {
      return;
    }
    // Positions stay ABSOLUTE (frame × cell) and the canvas moves instead,
    // so no drawing below learns about the origin — the same way a scroll
    // view moves its content rather than its children's arithmetic.
    canvas
      ..save()
      ..translate(-frameStartIndex * pixelsPerFrame, 0);
    _paintFrom(canvas, size);
    canvas.restore();
  }

  void _paintFrom(Canvas canvas, Size size) {
    final first = frameStartIndex;
    final visibleFrames = first + (size.width / pixelsPerFrame).ceil() + 1;
    double x(int frame) => frame * pixelsPerFrame;
    final right = x(first) + size.width;

    // The grid is not this painter's: the timeline's own sheet lies under
    // it ([TimelineGridSheet], I-44) — this strip used to walk the same
    // boundaries with a loop of its own. Nor is where the film stops: the
    // wash and the cut-end line are the open grid's stack, laid over this
    // strip and the real row alike ([_CollapsedRowOverlayState
    // ._whereTheFilmStops]).

    // THE BLOCKS — a translucent body so they read as paper, an outline
    // so they read as blocks, and their name. Uncovered stretches print the
    // sheet's `x` in their FIRST cell and nothing after.
    final current = snapshot.frameIndex;
    for (final run in row.runs) {
      final left = x(run.startIndex);
      if (left > right) {
        break;
      }
      final rect = Rect.fromLTRB(
        left + 1,
        4,
        x(run.endIndexExclusive) - 1,
        size.height - 4,
      );
      if (rect.right <= x(first) || rect.width <= 0) {
        continue;
      }
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      final covered = run.covers(current);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = covered
              ? colorScheme.primary.withValues(alpha: 0.30)
              : const Color(0x66E9E7E2),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = covered ? 2 : 1
          ..color = covered ? colorScheme.primary : const Color(0x9EE9E7E2),
      );
      final head = drawingHeadOf(run.label, kind: row.kind);
      final mark = head.mark;
      if (mark != null) {
        _headMark(canvas, rect, mark);
      } else {
        _label(canvas, rect, head.word);
      }
    }

    // The `x` markers, and the SELECTION when the cursor is not on a block.
    // 「빈 프레임이면 그 한 칸」 — same selected ink, one cell wide.
    for (var frame = first; frame < visibleFrames; frame += 1) {
      if (row.runs.isNotEmpty && row.runAt(frame) != null) {
        continue;
      }
      if (frame == current) {
        final cell = Rect.fromLTRB(
          x(frame) + 1,
          4,
          x(frame + 1) - 1,
          size.height - 4,
        );
        final rrect = RRect.fromRectAndRadius(cell, const Radius.circular(2));
        canvas
          ..drawRRect(
            rrect,
            Paint()..color = colorScheme.primary.withValues(alpha: 0.30),
          )
          ..drawRRect(
            rrect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = colorScheme.primary,
          );
      }
      // `holdsDrawings` and the playback range are the cells painter's own
      // two conditions for the marker; borrowed rather than re-decided.
      if (row.holdsDrawings &&
          !snapshot.outsidePlayback(frame) &&
          row.emptyRunStartsAt(frame)) {
        _label(
          canvas,
          Rect.fromLTRB(x(frame), 0, x(frame + 1), size.height),
          'x',
          color: const Color(0xB8E9E7E2),
        );
      }
    }

    // THE PLAYHEAD over everything this strip draws.
    canvas.drawRect(
      Rect.fromLTWH(x(current), 0, 2, size.height),
      Paint()..color = colorScheme.primary,
    );
  }

  /// A word of the strip, by the law every block word keeps: its type at
  /// every zoom, laid by F-96 from the first cell of its [room] and
  /// narrowed only past the room (B, 유저 2026-09-24: 「뭐든」).
  ///
  /// ↩️It was set in a monospace face of its own and VANISHED once its room
  /// was under 10px — against 「절대 안 사라지도록」 (R26 #38), which holds
  /// for every word a block writes.
  void _label(
    Canvas canvas,
    Rect room,
    String text, {
    Color color = _headInk,
  }) {
    final glyph = timelineGlyphPainter(
      text,
      timelineBlockWordStyle(
        baseTextStyle,
        ink: color,
        fontSize: _labelFontSize,
        bold: false,
      ).copyWith(
        // ⑩: flat here too — see [_halo]. The frame half had its own copy
        // of the shadow, which is exactly how a look that was supposed to
        // be gone survives a deletion.
        shadows: _CollapsedRowOverlayState._halo,
      ),
    );
    final layout = timelineBlockWordLayout(glyph.size, (
      axis: Axis.horizontal,
      room: room,
      cellStart: room.left,
      cellExtent: math.min(pixelsPerFrame, room.width),
      growth: TimelineBlockWordGrowth.towardBlockEnd,
      acrossAlignment: 0,
    ));
    paintFittedText(canvas, glyph, layout.origin, layout.fit);
  }

  /// The [mark] a block with no cel number wears where [_label] would lay
  /// its name: its first cell, at the size of the strip's type.
  void _headMark(Canvas canvas, Rect room, InbetweenMark mark) {
    final cellExtent = math.min(pixelsPerFrame, room.width);
    paintInbetweenMark(canvas, mark, (
      center: Offset(room.left + cellExtent / 2, room.center.dy),
      radius: timelineInbetweenMarkRadius(
        _labelFontSize,
        cellExtent: cellExtent,
        crossExtent: room.height,
      ),
    ), _headInk);
  }

  /// The strip's type — its own size, the one law every block word keeps.
  static const double _labelFontSize = 9.5;

  /// What a block's head is written in — its name, or its mark.
  static const Color _headInk = Color(0xF2FFFFFF);

  @override
  Object get props =>
      (
        snapshot,
        ByIdentity(row),
        pixelsPerFrame,
        colorScheme,
        baseTextStyle,
        frameStartIndex,
      );
}
