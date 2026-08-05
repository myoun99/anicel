import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../timeline/layer_label_controls.dart' show layerKindIcon;
import '../timeline/timeline_cell_style.dart';
import '../timeline/timeline_glyph_cache.dart';
import 'flip_hud_controller.dart';
import 'flip_hud_model.dart';

/// The flip HUD's metrics. One place, because the two axes are the same
/// window turned ninety degrees.
abstract final class FlipHudMetrics {
  /// The label rail — kind icon plus name, right-aligned so it sits
  /// against the strip and trails off to the left.
  static const double railWidth = 88;

  static const double rowExtent = 40;

  /// A block-axis column: one drawing block, or one uncovered frame.
  static const double blockSlotWidth = 56;

  /// A frame-axis column.
  static const double frameCellWidth = 18;

  /// Five columns readable, with the sixth caught in the end fade.
  static const double visibleSlots = 5.5;
  static const double visibleRows = 5.4;

  /// The paper body's inset inside its column.
  static const double bodyInset = 3;
  static const double bodyRadius = 4;

  /// How far the end fade eats in, as a fraction of the extent.
  static const double edgeFade = 0.14;

  /// The rail's own fade, which runs one way only.
  static const double railFade = 0.34;

  /// Distance from the touch point, across the drag axis. A left/right
  /// flip puts the window ABOVE the hand (wrist and palm own everything
  /// below); an up/down flip puts it beside.
  static const double frameAxisLift = 72;
  static const double rowAxisSideOffset = 88;

  /// Never closer than this to the panel's edge.
  static const double edgeInset = 16;

  /// The strip's slide between steps, at its LONGEST — a leisurely flip.
  static const Duration slide = Duration(milliseconds: 120);

  /// Below this a leg is a cut in all but name; there is no point asking
  /// the compositor for a two-frame tween.
  static const Duration slideFloor = Duration(milliseconds: 16);

  /// How long this leg of the slide should take.
  ///
  /// An implicit animation restarts at FULL duration whenever its target
  /// moves, so a leg longer than the gap between steps never finishes:
  /// the strip falls behind the hand and stays there, and because the
  /// selection rides the strip the window ends up pointing at the wrong
  /// column while you sweep. Sizing the leg to the interval that preceded
  /// it makes the strip arrive just as the next step lands — smooth when
  /// flipping slowly, and honest when sweeping fast.
  static Duration slideFor(Duration? stepInterval) {
    if (stepInterval == null || stepInterval >= slide) {
      return slide;
    }
    return stepInterval <= slideFloor ? Duration.zero : stepInterval;
  }

  /// Where the current column's CENTRE sits in strip content pixels — the
  /// one number the slide animates.
  static double scrollCentreFor({
    required FlipHudSnapshot snapshot,
    required FlipHudAxis axis,
    required bool frameStep,
  }) {
    // The window outlives the snapshot: a cut can empty out (a close, a
    // gap) while the release hold is still drawing the last picture, and
    // clamping into an empty row list would throw rather than fade.
    if (snapshot.isEmpty) {
      return 0;
    }
    if (axis == FlipHudAxis.row) {
      return (snapshot.rowIndex.clamp(0, snapshot.rows.length - 1) + 0.5) *
          rowExtent;
    }
    final row = snapshot.currentRow;
    if (row == null) {
      return 0;
    }
    final slots = frameStep
        ? flipHudFrameSlots(row, snapshot.frameCount)
        : flipHudBlockSlots(row, snapshot.frameCount);
    if (slots.isEmpty) {
      return 0;
    }
    final width = frameStep ? frameCellWidth : blockSlotWidth;
    return (flipHudSlotIndexAt(slots, snapshot.frameIndex) + 0.5) * width;
  }

  static Size sizeFor(FlipHudAxis axis) => axis == FlipHudAxis.frame
      ? const Size(railWidth + visibleSlots * blockSlotWidth, rowExtent)
      : const Size(railWidth + blockSlotWidth, visibleRows * rowExtent);

  /// Pins the window beside the hand, clamped inside the panel.
  static Offset placementFor({
    required Offset anchor,
    required Size size,
    required FlipHudAxis axis,
    required Size bounds,
  }) {
    double left;
    double top;
    if (axis == FlipHudAxis.frame) {
      left = anchor.dx - size.width / 2;
      top = anchor.dy - frameAxisLift - size.height;
    } else {
      // Away from the nearer wall, so the window has room to be read.
      final toTheLeft = anchor.dx > bounds.width / 2;
      left = toTheLeft
          ? anchor.dx - rowAxisSideOffset - size.width
          : anchor.dx + rowAxisSideOffset;
      top = anchor.dy - size.height / 2;
    }
    final maxLeft = math.max(edgeInset, bounds.width - size.width - edgeInset);
    final maxTop = math.max(edgeInset, bounds.height - size.height - edgeInset);
    return Offset(left.clamp(edgeInset, maxLeft), top.clamp(edgeInset, maxTop));
  }
}

/// The flip HUD: a timeline window that appears beside the hand while a
/// one-finger flip is live.
///
/// It draws nothing the timeline does not — paper blocks, the timesheet
/// `X` on an empty run's first cell, lane diamonds, the selected-cell
/// border and the active-row wash — and reads its colours from
/// `timeline_cell_style.dart` rather than restating them, so a later
/// change there (frame blocks taking the layer's label colour) arrives
/// here for free.
class FlipHudOverlay extends StatelessWidget {
  const FlipHudOverlay({super.key, required this.controller});

  final FlipHudController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final axis = controller.displayAxis;
          final anchor = controller.anchor;
          if (axis == null || anchor == null) {
            return const SizedBox.shrink();
          }
          final size = FlipHudMetrics.sizeFor(axis);
          return LayoutBuilder(
            builder: (context, constraints) {
              final offset = FlipHudMetrics.placementFor(
                anchor: anchor,
                size: size,
                axis: axis,
                bounds: constraints.biggest,
              );
              return Stack(
                children: [
                  Positioned(
                    key: const ValueKey<String>('flip-hud'),
                    left: offset.dx,
                    top: offset.dy,
                    width: size.width,
                    height: size.height,
                    // Tween rather than AnimatedOpacity: this subtree is
                    // BORN when the axis locks, and AnimatedOpacity would
                    // simply start at its end value — no fade in at all.
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0,
                        end: controller.visible ? 1 : 0,
                      ),
                      duration: _motion(
                        context,
                        controller.visible
                            ? const Duration(milliseconds: 90)
                            : FlipHudController.fadeOut,
                      ),
                      builder: (context, opacity, child) =>
                          Opacity(opacity: opacity, child: child),
                      child: _slidingStrip(context, axis),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static Duration _motion(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? Duration.zero
      : duration;

  /// The strip slides between steps rather than cutting: what makes the
  /// window read as one continuous film.
  ///
  /// The KEY carries the mode, so switching between block and frame
  /// columns starts a fresh animation at its own target instead of
  /// sliding through a distance measured in the other mode's units.
  Widget _slidingStrip(BuildContext context, FlipHudAxis axis) {
    final snapshot = controller.snapshot;
    final frameStep = controller.frameStep;
    final centre = FlipHudMetrics.scrollCentreFor(
      snapshot: snapshot,
      axis: axis,
      frameStep: frameStep,
    );
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('flip-hud-${axis.name}-$frameStep'),
      // begin is read only on this key's first build, where it equals end
      // and nothing moves; later builds animate from wherever it is.
      tween: Tween<double>(begin: centre, end: centre),
      duration: _motion(
        context,
        FlipHudMetrics.slideFor(controller.lastStepInterval),
      ),
      curve: Curves.easeOutCubic,
      builder: (context, scrollCentre, _) => CustomPaint(
        painter: FlipHudPainter(
          snapshot: snapshot,
          axis: axis,
          frameStep: frameStep,
          scrollCentre: scrollCentre,
          colorScheme: Theme.of(context).colorScheme,
        ),
      ),
    );
  }
}

class FlipHudPainter extends CustomPainter {
  const FlipHudPainter({
    required this.snapshot,
    required this.axis,
    required this.frameStep,
    required this.colorScheme,
    this.scrollCentre,
  });

  final FlipHudSnapshot snapshot;
  final FlipHudAxis axis;
  final bool frameStep;
  final ColorScheme colorScheme;

  /// The animating position of the current column's centre, in strip
  /// content pixels. Null pins it to wherever the snapshot says, which is
  /// what a still frame wants.
  final double? scrollCentre;

  double _scroll(FlipHudSnapshot snapshot) =>
      scrollCentre ??
      FlipHudMetrics.scrollCentreFor(
        snapshot: snapshot,
        axis: axis,
        frameStep: frameStep,
      );

  static const Color _railInk = Color(0xFF9DA2A6);
  static const Color _railInkActive = Color(0xFFE6E9EB);

  /// The rail is not a panel — it is a wash that thickens toward the
  /// strip and is gone by its left edge, so the window can sit over
  /// artwork without reading as a slab dropped on top.
  static const List<Color> _railWash = [
    Color(0x00181A1C),
    Color(0x8C181A1C),
    Color(0xED181A1C),
  ];
  static const List<double> _railWashStops = [0, 0.38, 1];

  @override
  void paint(Canvas canvas, Size size) {
    if (snapshot.isEmpty) {
      return;
    }
    final railRect = Rect.fromLTWH(0, 0, FlipHudMetrics.railWidth, size.height);
    final stripRect = Rect.fromLTWH(
      FlipHudMetrics.railWidth,
      0,
      size.width - FlipHudMetrics.railWidth,
      size.height,
    );
    if (axis == FlipHudAxis.frame) {
      _paintFrameAxis(canvas, railRect, stripRect);
    } else {
      _paintRowAxis(canvas, railRect, stripRect);
    }
  }

  // --- the frame axis: one row, its blocks running left to right --------

  void _paintFrameAxis(Canvas canvas, Rect railRect, Rect stripRect) {
    final row = snapshot.currentRow;
    if (row == null) {
      return;
    }
    final slotWidth = frameStep
        ? FlipHudMetrics.frameCellWidth
        : FlipHudMetrics.blockSlotWidth;
    final slots = frameStep
        ? flipHudFrameSlots(row, snapshot.frameCount)
        : flipHudBlockSlots(row, snapshot.frameCount);
    if (slots.isEmpty) {
      return;
    }
    final currentIndex = flipHudSlotIndexAt(slots, snapshot.frameIndex);

    _inFadedLayer(canvas, stripRect, true, () {
      // The current column sits at the strip's centre; the strip slides.
      final originX = stripRect.center.dx - _scroll(snapshot);
      final first = flipHudFirstPaintedIndex(
        slots,
        ((stripRect.left - originX) / slotWidth).floor() - 1,
      );
      final last = math.min(
        slots.length - 1,
        ((stripRect.right - originX) / slotWidth).ceil(),
      );
      for (var index = first; index <= last; index += 1) {
        final slot = slots[index];
        final run = slot.run;
        final isHead = run == null || run.startIndex == slot.startIndex;
        _paintSlot(
          canvas,
          Rect.fromLTWH(
            originX + index * slotWidth,
            stripRect.top,
            slotWidth,
            stripRect.height,
          ),
          row: row,
          slot: slot,
          // On the frame axis a block's body spans its whole run and only
          // its first cell carries the name — the timeline's own shape.
          spanWidth: frameStep && run != null
              ? run.length * slotWidth
              : slotWidth,
          isRunHead: isHead,
        );
      }
      _paintGridX(canvas, stripRect, originX: originX, step: slotWidth);
      _paintSelection(
        canvas,
        Rect.fromLTWH(
          originX + currentIndex * slotWidth,
          stripRect.top,
          slotWidth,
          stripRect.height,
        ),
      );
    });

    _inRailLayer(canvas, railRect, false, () {
      _paintRailRow(canvas, railRect, row, active: true);
    });
  }

  // --- the row axis: the row stack at one frame --------------------------

  void _paintRowAxis(Canvas canvas, Rect railRect, Rect stripRect) {
    final rows = snapshot.rows;
    final rowIndex = snapshot.rowIndex.clamp(0, rows.length - 1);
    const extent = FlipHudMetrics.rowExtent;
    final originY = stripRect.center.dy - _scroll(snapshot);
    final washTop = originY + rowIndex * extent;
    final first = math.max(0, ((stripRect.top - originY) / extent).floor() - 1);
    final last = math.min(
      rows.length - 1,
      ((stripRect.bottom - originY) / extent).ceil(),
    );

    _inFadedLayer(canvas, stripRect, false, () {
      canvas.drawRect(
        Rect.fromLTWH(stripRect.left, washTop, stripRect.width, extent),
        Paint()..color = timelineActiveRowWashColor(colorScheme),
      );
      for (var index = first; index <= last; index += 1) {
        final row = rows[index];
        _paintSlot(
          canvas,
          Rect.fromLTWH(
            stripRect.left,
            originY + index * extent,
            FlipHudMetrics.blockSlotWidth,
            extent,
          ),
          row: row,
          slot: FlipHudSlot(
            startIndex: snapshot.frameIndex,
            frames: 1,
            run: row.runAt(snapshot.frameIndex),
          ),
          spanWidth: FlipHudMetrics.blockSlotWidth,
          isRunHead: true,
        );
      }
      _paintGridY(canvas, stripRect, originY: originY, step: extent);
      _paintSelection(
        canvas,
        Rect.fromLTWH(
          stripRect.left,
          washTop,
          FlipHudMetrics.blockSlotWidth,
          extent,
        ),
      );
    });

    _inRailLayer(canvas, railRect, true, () {
      canvas.drawRect(
        Rect.fromLTWH(railRect.left, washTop, railRect.width, extent),
        Paint()..color = timelineActiveRowWashColor(colorScheme),
      );
      for (var index = first; index <= last; index += 1) {
        _paintRailRow(
          canvas,
          Rect.fromLTWH(
            railRect.left,
            originY + index * extent,
            railRect.width,
            extent,
          ),
          rows[index],
          active: index == rowIndex,
        );
      }
    });
  }

  // --- pieces ------------------------------------------------------------

  /// Paints [body] into its own layer, then eats both ends of it away.
  void _inFadedLayer(
    Canvas canvas,
    Rect rect,
    bool horizontal,
    VoidCallback body,
  ) {
    canvas.saveLayer(rect, Paint());
    canvas.save();
    canvas.clipRect(rect);
    body();
    canvas.restore();
    _fadeEnds(canvas, rect, horizontal: horizontal);
    canvas.restore();
  }

  /// The rail: its wash, its labels, then the leftward fade — plus the
  /// row-axis end fade, which multiplies with it in the same layer.
  void _inRailLayer(
    Canvas canvas,
    Rect rect,
    bool fadeAcross,
    VoidCallback body,
  ) {
    canvas.saveLayer(rect, Paint());
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: _railWash,
          stops: _railWashStops,
        ).createShader(rect),
    );
    body();
    canvas.restore();
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x00000000), Color(0xFF000000)],
          stops: [0, FlipHudMetrics.railFade],
        ).createShader(rect),
    );
    if (fadeAcross) {
      _fadeEnds(canvas, rect, horizontal: false);
    }
    canvas.restore();
  }

  void _paintRailRow(
    Canvas canvas,
    Rect rect,
    FlipHudRow row, {
    required bool active,
  }) {
    final ink = active ? _railInkActive : _railInk;
    final namePainter = timelineGlyphPainter(
      row.name,
      TextStyle(
        fontSize: row.isLane ? 10.5 : 11.5,
        fontWeight: row.isLane ? FontWeight.w400 : FontWeight.w600,
        color: row.isLane ? ink.withValues(alpha: 0.82) : ink,
      ),
      maxWidth: rect.width - (row.isLane ? 12 : 26),
    );
    const gap = 5.0;
    const rightPad = 9.0;
    final nameLeft = rect.right - rightPad - namePainter.width;
    namePainter.paint(
      canvas,
      Offset(nameLeft, rect.center.dy - namePainter.height / 2),
    );
    if (!row.showsKindIcon) {
      return;
    }
    final icon = layerKindIcon(row.kind);
    timelineGlyphPainter(
      String.fromCharCode(icon.codePoint),
      TextStyle(
        fontSize: 13,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: ink,
      ),
    ).paint(canvas, Offset(nameLeft - gap - 13, rect.center.dy - 6.5));
  }

  void _paintSlot(
    Canvas canvas,
    Rect rect, {
    required FlipHudRow row,
    required FlipHudSlot slot,
    required double spanWidth,
    required bool isRunHead,
  }) {
    final run = slot.run;
    if (run == null) {
      // The timesheet X, on the first cell of an empty stretch and only
      // on rows that hold drawings — the cells painter's own rule.
      if (row.holdsDrawings && row.emptyRunStartsAt(slot.startIndex)) {
        _paintGlyph(
          canvas,
          rect,
          'X',
          color: colorScheme.onSurface.withValues(alpha: 0.55),
          maxExtent: rect.width,
        );
      }
      return;
    }
    if (run.isKey) {
      _paintKey(canvas, rect, hold: run.holdKey);
      return;
    }
    if (!isRunHead) {
      // The head painted the whole body already.
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rect.left,
          rect.top + FlipHudMetrics.bodyInset,
          spanWidth,
          rect.height - FlipHudMetrics.bodyInset * 2,
        ),
        const Radius.circular(FlipHudMetrics.bodyRadius),
      ),
      Paint()..color = timelineDrawingHeldColor,
    );
    _paintGlyph(
      canvas,
      Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height),
      run.label.isEmpty ? '○' : run.label,
      color: timelineDrawingInkColor,
      bold: true,
      maxExtent: rect.width,
    );
  }

  void _paintKey(Canvas canvas, Rect rect, {required bool hold}) {
    const half = 4.5;
    final center = rect.center;
    final paint = Paint()..color = timelineDrawingHeldColor;
    if (hold) {
      canvas.drawRect(
        Rect.fromCenter(center: center, width: half * 2, height: half * 2),
        paint,
      );
      return;
    }
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy - half)
        ..lineTo(center.dx + half, center.dy)
        ..lineTo(center.dx, center.dy + half)
        ..lineTo(center.dx - half, center.dy)
        ..close(),
      paint,
    );
  }

  void _paintGlyph(
    Canvas canvas,
    Rect rect,
    String text, {
    required Color color,
    bool bold = false,
    required double maxExtent,
  }) {
    final painter = timelineGlyphPainter(
      text,
      TextStyle(
        fontSize: timelineFittedGlyphFontSize(
          bold ? 14 : 12,
          maxExtent,
          crossExtent: rect.height,
        ),
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        color: color,
      ),
      maxWidth: math.max(8, maxExtent - 4),
    );
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  /// ONE overlay owns every plain per-cell line, the way the timeline's
  /// grid does — a border per cell would fight the bodies that span.
  void _paintGridX(
    Canvas canvas,
    Rect rect, {
    required double originX,
    required double step,
  }) {
    final paint = Paint()
      ..color = timelineBaseGridInk(colorScheme, frameCellExtent: step)
      ..strokeWidth = 1;
    var x = originX + (((rect.left - originX) / step).ceil()) * step;
    for (; x <= rect.right; x += step) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
  }

  void _paintGridY(
    Canvas canvas,
    Rect rect, {
    required double originY,
    required double step,
  }) {
    final paint = Paint()
      ..color = timelineBaseGridInk(colorScheme, frameCellExtent: step)
      ..strokeWidth = 1;
    var y = originY + (((rect.top - originY) / step).ceil()) * step;
    for (; y <= rect.bottom; y += step) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
  }

  /// The timeline's selected-cell reading, verbatim: the accent tint under
  /// a two-pixel accent edge.
  void _paintSelection(Canvas canvas, Rect rect) {
    final accent = timelineSelectedFrameBorderColor;
    final inner = rect.deflate(1);
    canvas.drawRect(inner, Paint()..color = accent.withValues(alpha: 0.12));
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, const Radius.circular(5)),
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _fadeEnds(Canvas canvas, Rect rect, {required bool horizontal}) {
    const f = FlipHudMetrics.edgeFade;
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
          end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
          colors: const [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: const [0, f, 1 - f, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant FlipHudPainter oldDelegate) =>
      !identical(oldDelegate.snapshot, snapshot) ||
      oldDelegate.axis != axis ||
      oldDelegate.frameStep != frameStep ||
      oldDelegate.scrollCentre != scrollCentre ||
      oldDelegate.colorScheme != colorScheme;
}
