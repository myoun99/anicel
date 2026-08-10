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
/// ⚠️NOT YET the rail's full control cluster (fx twirl · timesheet · mark ·
/// eye · opacity · blend · onion). Those are row STATE the snapshot does not
/// carry, and inventing a second path to read them is exactly what the
/// paragraph above warns about. What is here is the kind glyph, the name and
/// a lane's value.
class CollapsedRowOverlay extends StatelessWidget {
  const CollapsedRowOverlay({
    super.key,
    required this.snapshot,
    required this.railWidth,
    required this.pixelsPerFrame,
    required this.framesPerSecond,
    this.laneValue,
  });

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: railWidth,
              // The rail's own rule, and the reason this is a ClipRect and
              // not an ellipsis: 「꼬리가 잘린다, `…` 없이」. An ellipsis in
              // this app means one thing only — a LABEL overflowing its own
              // slot — and a narrowed window is not that.
              child: ClipRect(child: _rail(row, colorScheme)),
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
    );
  }

  Widget _rail(FlipHudRow row, ColorScheme colorScheme) {
    // A halo rather than a plate. The panel's fill is what was removed, so
    // legibility has to come from the glyph itself — over a bright sheet a
    // translucent light label simply is not there. ⛔Not a backdrop blur:
    // a live blur over the drawing surface is the class of cost the raster
    // round just finished removing.
    final shadows = [
      const Shadow(color: Color(0xE6000000), blurRadius: 3),
      const Shadow(color: Color(0x99000000), blurRadius: 7),
    ];
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
          shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 3)],
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
