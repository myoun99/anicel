import 'package:flutter/material.dart';

import '../canvas/flip_hud_model.dart';
import '../theme/app_theme.dart';
import 'layer_label_controls.dart' show layerKindIcon;
import 'layer_rail_window.dart' show LayerRailExtent, LayerRailWindow;
import 'timeline_beat_lines.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_grid_metrics.dart';

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
    this.railChild,
    this.frameRowBuilder,
    this.laneValue,
  });

  /// The rail row itself, chromeless — see the class doc. Null on a lane row.
  final Widget? railChild;

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

  /// A property lane's value at the cursor, printed after its name the way
  /// the rail prints it. Null on layer rows.
  final String? laneValue;

  /// One timeline row tall — this is a row, and it should measure as one.
  static const double height = timelineLayerRowHeight;

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
          height: CollapsedRowOverlay.height,
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
                      builder: (context, frameConstraints) {
                        final build = widget.frameRowBuilder;
                        if (build == null) {
                          return CustomPaint(
                            painter: _CollapsedStripPainter(
                              snapshot: snapshot,
                              row: row,
                              pixelsPerFrame: widget.pixelsPerFrame,
                              framesPerSecond: widget.framesPerSecond,
                              colorScheme: colorScheme,
                            ),
                          );
                        }
                        // Republished per layout, value only — the handle's
                        // identity is what the row memo keys on.
                        _geometry.value = TimelineFrameGeometry(
                          frameCellExtent: widget.pixelsPerFrame,
                          frameStartIndex: 0,
                          frameEndIndexExclusive: widget.pixelsPerFrame <= 0
                              ? 0
                              : (frameConstraints.maxWidth /
                                        widget.pixelsPerFrame)
                                    .ceil(),
                        );
                        // 🚨THE GRID LINES, and they were never removed — this
                        // painter was simply not mounted here. Every plain
                        // per-cell border is `Colors.transparent` on purpose
                        // (`timeline_cell_style`: 「the GRID OVERLAY owns every
                        // plain per-cell line now」), so a row without this
                        // overlay has no lines at all, and chromeless mode was
                        // wrongly blamed for erasing them.
                        //
                        // 🎁The cut-end shading rides in the same painter, so
                        // mounting it brings both back at once — and the shading
                        // is information rather than chrome (유저 확정 08-10),
                        // which is why it belongs on a folded row too.
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            build(context, _geometry),
                            IgnorePointer(
                              child: CustomPaint(
                                key: const ValueKey<String>(
                                  'collapsed-beat-lines',
                                ),
                                painter: TimelineBeatLinesPainter(
                                  frameCellExtent: widget.pixelsPerFrame,
                                  framesPerSecond: widget.framesPerSecond,
                                  colorScheme: colorScheme,
                                  // ⛔NULL: the folded row lies over the ARTWORK at
                                  // 70%, so there is no single ground to multiply
                                  // against — these lines stay source-over.
                                  ground: null,
                                  crossCellExtent: CollapsedRowOverlay.height,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
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
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.text,
                shadows: shadows,
              ),
            ),
          ),
          if (widget.laneValue case final value?) ...[
            const SizedBox(width: 8),
            Text(
              value,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: AppColors.textDim,
                shadows: shadows,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CollapsedStripPainter extends CustomPainter {
  const _CollapsedStripPainter({
    required this.snapshot,
    required this.row,
    required this.pixelsPerFrame,
    required this.framesPerSecond,
    required this.colorScheme,
  });

  final FlipHudSnapshot snapshot;
  final FlipHudRow row;
  final double pixelsPerFrame;
  final int framesPerSecond;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (pixelsPerFrame <= 0) {
      return;
    }
    final visibleFrames = (size.width / pixelsPerFrame).ceil() + 1;
    double x(int frame) => frame * pixelsPerFrame;

    // 1. THE GRID — the timeline's own line system, and nothing else under
    // it. One cadence per frame, 6f stronger, the second boundary
    // strongest; `timelineFrameBoundaryLineInk` thins it out at small zooms
    // rather than fading it, so this reads the same as the panel does.
    // Position from the LAW's snap (D8) — this pass used to draw at the
    // raw boundary, half a pixel off every other drawer.
    for (var frame = 1; frame < visibleFrames; frame += 1) {
      final ink = timelineFrameBoundaryLineInk(
        frameIndex: frame,
        frameCellExtent: pixelsPerFrame,
        framesPerSecond: framesPerSecond,
        colorScheme: colorScheme,
      );
      if (ink == null) {
        continue;
      }
      final position = timelineFrameBoundaryLinePosition(frame, pixelsPerFrame);
      canvas.drawLine(
        Offset(position, 0),
        Offset(position, size.height),
        Paint()
          ..color = ink.color
          ..strokeWidth = ink.strokeWidth,
      );
    }

    // 2. THE OUT-OF-CUT WASH — the one fill that stays. It is not chrome:
    // it says the frames past it are outside what plays.
    final playback = snapshot.playbackFrameCount;
    if (playback != null && x(playback) < size.width) {
      canvas.drawRect(
        Rect.fromLTRB(x(playback), 0, size.width, size.height),
        Paint()..color = const Color(0x66101214),
      );
    }

    // 3. THE BLOCKS — a translucent body so they read as paper, an outline
    // so they read as blocks, and their name. Uncovered stretches print the
    // sheet's `x` in their FIRST cell and nothing after.
    final current = snapshot.frameIndex;
    for (final run in row.runs) {
      final left = x(run.startIndex);
      if (left > size.width) {
        break;
      }
      final rect = Rect.fromLTRB(
        left + 1,
        4,
        x(run.endIndexExclusive) - 1,
        size.height - 4,
      );
      if (rect.right <= 0 || rect.width <= 0) {
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
      _label(canvas, rect, run.label.isEmpty ? '○' : run.label);
    }

    // The `x` markers, and the SELECTION when the cursor is not on a block.
    // 「빈 프레임이면 그 한 칸」 — same selected ink, one cell wide.
    for (var frame = 0; frame < visibleFrames; frame += 1) {
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
          center: true,
          color: const Color(0xB8E9E7E2),
        );
      }
    }

    // 4. THE CUT END — 2px of the app's one length-colour, and the playhead
    // over everything.
    if (playback != null && x(playback) <= size.width) {
      canvas.drawRect(
        Rect.fromLTWH(x(playback) - 1, 0, 2, size.height),
        Paint()..color = AppColors.danger,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(x(current), 0, 2, size.height),
      Paint()..color = colorScheme.primary,
    );
  }

  void _label(
    Canvas canvas,
    Rect rect,
    String text, {
    bool center = false,
    Color color = const Color(0xF2FFFFFF),
  }) {
    if (rect.width < 10) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 9.5,
          color: color,
          // ⑩: flat here too — see [_halo]. The frame half had its own copy
          // of the shadow, which is exactly how a look that was supposed to
          // be gone survives a deletion.
          shadows: _CollapsedRowOverlayState._halo,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '',
    )..layout(maxWidth: rect.width - 4);
    if (painter.width > rect.width - 3) {
      return;
    }
    painter.paint(
      canvas,
      Offset(
        center ? rect.center.dx - painter.width / 2 : rect.left + 3,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_CollapsedStripPainter old) =>
      old.snapshot != snapshot ||
      !identical(old.row, row) ||
      old.pixelsPerFrame != pixelsPerFrame ||
      old.framesPerSecond != framesPerSecond ||
      old.colorScheme != colorScheme;
}
