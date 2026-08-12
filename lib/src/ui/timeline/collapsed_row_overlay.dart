import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../canvas/flip_hud_model.dart';
import '../theme/app_theme.dart';
import 'layer_label_controls.dart' show layerKindIcon;
import 'timeline_beat_lines.dart';
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
class CollapsedRowOverlay extends StatelessWidget {
  const CollapsedRowOverlay({
    super.key,
    required this.snapshot,
    required this.railWidth,
    required this.pixelsPerFrame,
    required this.framesPerSecond,
    this.railChild,
    this.laneValue,
  });

  /// The rail row itself, chromeless — see the class doc. Null on a lane row.
  final Widget? railChild;

  final FlipHudSnapshot snapshot;

  /// The rail's window, straight off the timeline's own splitter
  /// (`LayerRailId.timeline`). 유저 확정: 좁혀놨으면 좁힌 대로 — and the rail
  /// model's rule comes with it, because it is the same number: nothing
  /// inside rearranges, the tail is simply cut off.
  final double railWidth;

  final double pixelsPerFrame;
  final int framesPerSecond;

  /// A property lane's value at the cursor, printed after its name the way
  /// the rail prints it. Null on layer rows.
  final String? laneValue;

  /// One timeline row tall — this is a row, and it should measure as one.
  static const double height = timelineLayerRowHeight;

  @override
  Widget build(BuildContext context) {
    final row = snapshot.currentRow;
    if (row == null || snapshot.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: SizedBox(
        height: height,
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
              SizedBox(
                width: math.min(railWidth, constraints.maxWidth),
              // ★THE RAIL MODEL, verbatim: 「레일은 자기 자연 크기로 눕고,
              // 스플리터는 그 위의 창을 정하고, 꼬리가 그냥 잘린다」. The
              // `OverflowBox` is what lets it lie at its natural width —
              // without it the row is squeezed into the window and its own
              // Row overflows, which is what a narrow region actually did.
              // And the clip is why there is no `…`: an ellipsis in this app
              // means a LABEL overflowing its own slot, and a narrowed
              // window is not that.
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  maxWidth: double.infinity,
                  child: _haloed(
                    context,
                    // A layer row is the REAL row, chromeless. A property
                    // lane is its name and its value, which is what the rail
                    // shows there — so the caller hands null instead.
                    railChild ?? _rail(row, colorScheme),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ClipRect(
                child: CustomPaint(
                  painter: _CollapsedStripPainter(
                    snapshot: snapshot,
                    row: row,
                    pixelsPerFrame: pixelsPerFrame,
                    framesPerSecond: framesPerSecond,
                    colorScheme: colorScheme,
                  ),
                ),
              ),
            ),
          ],
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
          if (laneValue case final value?) ...[
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
      canvas.drawLine(
        Offset(x(frame), 0),
        Offset(x(frame), size.height),
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
          ..color = covered
              ? colorScheme.primary
              : const Color(0x9EE9E7E2),
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
          shadows: CollapsedRowOverlay._halo,
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
