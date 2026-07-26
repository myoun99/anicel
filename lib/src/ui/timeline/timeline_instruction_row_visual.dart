import 'package:flutter/material.dart';

import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../models/timeline_coverage.dart' show TimelineBlockEdge;
import 'timeline_cell_exposure_state.dart';
import 'timeline_cell_style.dart';
import 'timeline_exposure_comma_drag_handle.dart';
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_frame_span_layout.dart';

/// Instruction rows render like the paper sheet's CAM column on white
/// frame blocks: the cells paint the paper (via
/// [instructionCellExposureState] feeding the shared cell style), this
/// overlay adds the mark — ONE unadorned continuous line for bar terms
/// (no end ticks, never broken for text) or a light-gray filled wedge for
/// the dedicated FI/FO/O.L marks (R4, user sketch) — with the A/B
/// instance names dead-centered in the start/end cells (frame-name style)
/// and the instruction name overlaid on the SPAN's true center. Shared by
/// both orientations (Axis policy); the printed sheet mirrors this
/// verbatim.

/// Paper-cell adapter: instruction events have no timeline entries, so
/// this maps a frame index onto the shared cell exposure states (span
/// start → drawingStart, covered → held) — the cells then paint the same
/// paper blocks, borders and rounding as drawing rows.
TimelineCellExposureState instructionCellExposureState(
  Layer layer,
  int frameIndex,
) {
  final instructions = layer.instructions;
  if (frameIndex < 0) {
    return TimelineCellExposureState.uncovered;
  }
  if (instructions.containsKey(frameIndex)) {
    return TimelineCellExposureState.drawingStart;
  }
  final startKey = instructions.lastKeyBefore(frameIndex);
  if (startKey == null) {
    return TimelineCellExposureState.uncovered;
  }
  final event = instructions[startKey]!;
  return frameIndex < startKey + event.length
      ? TimelineCellExposureState.held
      : TimelineCellExposureState.uncovered;
}

/// The mark/label overlays for every instruction span intersecting the
/// visible window.
List<Widget> timelineRowInstructionOverlays({
  required Layer layer,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required Axis axis,
  required CameraInstructionDef? Function(String instructionId) defById,
  String keyPrefix = 'timeline',
}) {
  final overlays = <Widget>[];
  for (final entry in layer.instructions.entries) {
    final start = entry.key;
    final endExclusive = start + entry.value.length;
    if (endExclusive <= frameStartIndex || start >= frameEndIndexExclusive) {
      continue;
    }
    final def = defById(entry.value.instructionId);
    overlays.add(
      TimelineFrameSpan(
        placement: TimelineFrameSpanPlacement(
          startIndex: start,
          endIndexExclusive: endExclusive,
        ),
        child: IgnorePointer(
          key: ValueKey<String>('$keyPrefix-instruction-${layer.id}-$start'),
          child: _InstructionSpan(axis: axis, event: entry.value, def: def),
        ),
      ),
    );
  }
  return overlays;
}

/// Edge grips over instruction spans: reuses the exposure grip widget and
/// callback shape — the session dispatches instruction rows to the span
/// editor internally, so both row types share one drag pipeline.
List<Widget> timelineRowInstructionEdgeGrips({
  required Layer layer,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required double Function() resolveFrameCellExtent,
  required TimelineCommaDragCallbacks commaDrag,
  required Axis axis,
}) {
  final grips = <Widget>[];
  var ordinal = 0;
  for (final entry in layer.instructions.entries) {
    final start = entry.key;
    final endExclusive = start + entry.value.length;
    final visible =
        endExclusive > frameStartIndex && start < frameEndIndexExclusive;
    if (visible) {
      for (final edge in TimelineBlockEdge.values) {
        grips.add(
          TimelineFrameSpan(
            placement: timelineBlockEdgeGripPlacement(
              edge: edge,
              startIndex: start,
              endIndexExclusive: endExclusive,
            ),
            child: TimelineBlockEdgeGrip(
              layerId: layer.id,
              blockStartIndex: start,
              blockOrdinal: ordinal,
              edge: edge,
              resolveFrameCellExtent: resolveFrameCellExtent,
              callbacks: commaDrag,
              axis: axis,
            ),
          ),
        );
      }
    }
    ordinal += 1;
  }
  return grips;
}

class _InstructionSpan extends StatelessWidget {
  const _InstructionSpan({
    required this.axis,
    required this.event,
    required this.def,
  });

  final Axis axis;
  final InstructionEvent event;
  final CameraInstructionDef? def;

  /// One cell-sized slot at [cellIndex] holding [child] at [alignment]; the
  /// child may overflow the cell (paper writing spills over neighbours
  /// freely).
  ///
  /// The slot is a FRACTION of the span, never a cell width in pixels: the
  /// span box is `event.length` cells wide by construction, so this widget
  /// needs nothing from the zoom and never rebuilds for it.
  Widget _cellSlot({
    required int cellIndex,
    required Widget child,
    AlignmentGeometry alignment = Alignment.center,
  }) {
    final overflowing = OverflowBox(
      alignment: alignment,
      // BOTH bounds must open up: OverflowBox only replaces what is set,
      // and the slot's TIGHT mins otherwise force the writing to fill the
      // slot — glyphs then paint from the start edge and the labels LOOK
      // top/left-aligned instead of centered (R5-⑤ root cause, all three
      // misalignment reports).
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: child,
    );
    final cells = event.length < 1 ? 1 : event.length;
    // Align spreads the child's FREE space, not the parent's: with a child
    // 1/cells wide, alignment a puts its left edge at (1 - 1/cells)(a+1)/2 of
    // the span. Solving that for cell `i` gives a = 2i/(cells-1) - 1.
    final fraction = cells <= 1 ? 0.0 : -1 + 2 * cellIndex / (cells - 1);
    return Align(
      alignment: axis == Axis.horizontal
          ? Alignment(fraction, 0)
          : Alignment(0, fraction),
      child: FractionallySizedBox(
        widthFactor: axis == Axis.horizontal ? 1 / cells : 1,
        heightFactor: axis == Axis.horizontal ? 1 : 1 / cells,
        child: overflowing,
      ),
    );
  }

  /// Instruction writing reads HORIZONTALLY in both orientations (R6-①c:
  /// the X-sheet glyph stack retired — frame names already read
  /// horizontally there, and the printed sheet writes these across too).
  Widget _writing(String text, TextStyle style) {
    return Text(text, maxLines: 1, softWrap: false, style: style);
  }

  @override
  Widget build(BuildContext context) {
    final markColor = def?.colorValue == null
        ? timelineDrawingInkColor
        : Color(def!.colorValue!);
    // The mark and the writing are independent: free per-event text wins,
    // the vocabulary name is the fallback.
    final name = event.displayLabel(def);
    // The A/B instance names read exactly like frame names on drawing
    // blocks: ink, bold, ambient size, centered in their cells.
    const valueStyle = TextStyle(
      color: timelineDrawingInkColor,
      fontWeight: FontWeight.bold,
      height: 1.1,
    );
    final nameStyle = TextStyle(
      color: markColor,
      fontSize: 11,
      fontWeight: FontWeight.bold,
      height: 1.1,
    );
    final valueA = event.valueA;
    final valueB = event.valueB;

    return Semantics(
      label: [
        'instruction $name',
        if (event.valueA != null) 'from ${event.valueA}',
        if (event.valueB != null) 'to ${event.valueB}',
      ].join(' '),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _InstructionMarkPainter(
                  axis: axis,
                  markType: def?.markType ?? CameraInstructionMarkType.bar,
                  eventLength: event.length,
                  color: markColor,
                  hasStartName: valueA != null && valueA.isNotEmpty,
                  hasEndName: valueB != null && valueB.isNotEmpty,
                ),
              ),
            ),
          ),
          if (valueA != null && valueA.isNotEmpty)
            _cellSlot(
              cellIndex: 0,
              child: ExcludeSemantics(child: _writing(valueA, valueStyle)),
            ),
          if (valueB != null && valueB.isNotEmpty)
            _cellSlot(
              cellIndex: event.length - 1,
              child: ExcludeSemantics(child: _writing(valueB, valueStyle)),
            ),
          // The name overlays the SPAN's true center, written over the
          // line/wedge (R4: the cell-snap anchor is retired — labels sit
          // dead center like handwriting on the sheet).
          if (name.isNotEmpty)
            Positioned.fill(
              child: OverflowBox(
                // Open mins too (see _cellSlot) — otherwise the name fills
                // the span and its glyphs paint from the FIRST frame
                // instead of sitting on the span's center.
                minWidth: 0,
                minHeight: 0,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: ExcludeSemantics(child: _writing(name, nameStyle)),
              ),
            ),
        ],
      ),
    );
  }
}

/// The instruction mark background on the paper block: bar marks draw the
/// sheet's completely straight duration line between the endpoint cells
/// (names own them; a nameless endpoint gets the solid triangle cap
/// instead — R7-①), FI/FO the light-gray fade wedges (wide where the
/// screen is covered), O.L the translucent bowtie (two triangles meeting
/// at the span's center).
class _InstructionMarkPainter extends CustomPainter {
  _InstructionMarkPainter({
    required this.axis,
    required this.markType,
    required this.eventLength,
    required this.color,
    this.hasStartName = true,
    this.hasEndName = true,
  });

  final Axis axis;
  final CameraInstructionMarkType markType;
  final int eventLength;
  final Color color;

  /// The cell width, DERIVED from the box: the span is [eventLength] cells
  /// wide, so the painter needs no zoom-dependent field — that field was what
  /// made every instruction span rebuild on a zoom step.
  double _cellExtent(double mainExtent) =>
      eventLength < 1 ? mainExtent : mainExtent / eventLength;

  /// Whether the A/B writing occupies the endpoint cells. A NAMELESS bar
  /// endpoint carries the sheet's solid triangle mark instead (real
  /// Japanese timesheets, R7-①), apex pointing INTO the span at either
  /// end (start ▼ / end ▲ on the sheet — R8-①), with the line running
  /// through the freed cell to meet it.
  final bool hasStartName;
  final bool hasEndName;

  /// Main/cross coordinates → canvas offset for the current [axis].
  Offset _at(double main, double cross) =>
      axis == Axis.horizontal ? Offset(main, cross) : Offset(cross, main);

  /// The dedicated marks' light-gray fill — laid under the writing, with
  /// the cell borders showing through (R4: hatching and outlines retired).
  Paint get _wedgeFill => Paint()..color = color.withValues(alpha: 0.15);

  @override
  void paint(Canvas canvas, Size size) {
    switch (markType) {
      case CameraInstructionMarkType.bar:
        _paintDurationLine(canvas, size);
      case CameraInstructionMarkType.fi:
        _paintFadeWedge(canvas, size, wideAtStart: false);
      case CameraInstructionMarkType.fo:
        _paintFadeWedge(canvas, size, wideAtStart: true);
      case CameraInstructionMarkType.ol:
        _paintBowtie(canvas, size);
    }
  }

  /// ONE unadorned continuous line BETWEEN the endpoint cells — the first
  /// and last cells stay completely empty for their names (R6-①b: the
  /// centers-to-centers line left half a stroke inside them; the sheet
  /// matches this exactly). No ticks, no gap for the writing (the name
  /// overlays it); spans of one or two cells carry writing only. A
  /// NAMELESS endpoint carries the solid triangle mark instead and the
  /// line extends through its cell to meet it (R7-①).
  void _paintDurationLine(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final mainExtent = axis == Axis.horizontal ? size.width : size.height;
    final crossExtent = axis == Axis.horizontal ? size.height : size.width;
    final crossCenter = crossExtent / 2;
    final frameCellExtent = _cellExtent(mainExtent);
    var start = frameCellExtent;
    var end = mainExtent - frameCellExtent;
    if (!hasStartName) {
      start = _paintEndpointTriangle(
        canvas,
        mainExtent: mainExtent,
        crossCenter: crossCenter,
        crossExtent: crossExtent,
        atStart: true,
      );
    }
    if (!hasEndName) {
      end = _paintEndpointTriangle(
        canvas,
        mainExtent: mainExtent,
        crossCenter: crossCenter,
        crossExtent: crossExtent,
        atStart: false,
      );
    }
    if (end - start < 2) {
      return;
    }
    canvas.drawLine(_at(start, crossCenter), _at(end, crossCenter), paint);
  }

  /// The solid triangle capping a nameless bar endpoint, its APEX pointing
  /// INTO the span at both ends (R8-① direction fix: on the sheet the
  /// start cap reads ▼ and the end cap ▲ — the R7 both-point-downstream
  /// reading was wrong). The base sits FLUSH on the span edge (compact —
  /// no inset padding) and the cap fills half the cell each way: half a
  /// frame cell along the time axis, half the row across it (user-sized).
  /// Returns the main-axis coordinate the duration line meets it at (the
  /// apex).
  double _paintEndpointTriangle(
    Canvas canvas, {
    required double mainExtent,
    required double crossCenter,
    required double crossExtent,
    required bool atStart,
  }) {
    final length = _cellExtent(mainExtent) / 2;
    final crossHalf = crossExtent / 4;
    final baseMain = atStart ? 0.0 : mainExtent;
    final apexMain = atStart ? length : mainExtent - length;
    canvas.drawPath(
      Path()..addPolygon([
        _at(baseMain, crossCenter - crossHalf),
        _at(apexMain, crossCenter),
        _at(baseMain, crossCenter + crossHalf),
      ], true),
      Paint()..color = color,
    );
    return apexMain;
  }

  /// The fade wedge, a plain light-gray fill following the light: FI opens
  /// narrow → wide (the picture grows in), FO wide → narrow (R4
  /// orientation fix; hatching retired).
  void _paintFadeWedge(Canvas canvas, Size size, {required bool wideAtStart}) {
    final mainExtent = axis == Axis.horizontal ? size.width : size.height;
    final crossExtent = axis == Axis.horizontal ? size.height : size.width;
    final crossCenter = crossExtent / 2;
    final wideHalf = crossCenter - 2;
    if (mainExtent < 6 || wideHalf < 2) {
      return;
    }
    final wideMain = wideAtStart ? 1.0 : mainExtent - 1;
    final pointMain = wideAtStart ? mainExtent - 1 : 1.0;
    canvas.drawPath(
      Path()..addPolygon([
        _at(wideMain, crossCenter - wideHalf),
        _at(pointMain, crossCenter),
        _at(wideMain, crossCenter + wideHalf),
      ], true),
      _wedgeFill,
    );
  }

  void _paintBowtie(Canvas canvas, Size size) {
    final paint = _wedgeFill;
    final mainExtent = axis == Axis.horizontal ? size.width : size.height;
    final mid = mainExtent / 2;
    final startTriangle = Path();
    final endTriangle = Path();
    if (axis == Axis.horizontal) {
      startTriangle
        ..moveTo(0, 0)
        ..lineTo(mid, size.height / 2)
        ..lineTo(0, size.height)
        ..close();
      endTriangle
        ..moveTo(size.width, 0)
        ..lineTo(mid, size.height / 2)
        ..lineTo(size.width, size.height)
        ..close();
    } else {
      startTriangle
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, mid)
        ..lineTo(size.width, 0)
        ..close();
      endTriangle
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, mid)
        ..lineTo(size.width, size.height)
        ..close();
    }
    canvas.drawPath(startTriangle, paint);
    canvas.drawPath(endTriangle, paint);
  }

  @override
  bool shouldRepaint(_InstructionMarkPainter oldDelegate) {
    return axis != oldDelegate.axis ||
        markType != oldDelegate.markType ||
        eventLength != oldDelegate.eventLength ||
        color != oldDelegate.color ||
        hasStartName != oldDelegate.hasStartName ||
        hasEndName != oldDelegate.hasEndName;
  }
}
