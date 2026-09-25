import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../models/timeline_coverage.dart' show TimelineBlockEdge;
import '../../models/track_frame_range.dart' show frameRangesOverlap;
import '../text/vertical_writing_text.dart';
import 'axis_turn.dart';
import 'timeline_cell_exposure_state.dart';
import 'timeline_cell_style.dart';
import 'timeline_exposure_comma_drag_handle.dart';
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_beat_lines.dart' show timelineRowPaperExtent;
import 'timeline_block_word.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_frame_span_layout.dart';
import 'timeline_se_row_visual.dart' show timelineBlockWarningBar;
import '../repaint_props.dart';

/// Instruction rows render like the paper sheet's CAM column on white
/// frame blocks: the cells paint the paper (via
/// [instructionCellExposureState] feeding the shared cell style), this
/// overlay adds the mark — ONE unadorned continuous line for bar terms
/// (no end ticks, never broken for text) or a light-gray filled wedge for
/// the dedicated FI/FO/O.L marks (R4, user sketch) — with the A/B
/// instance names dead-centered in the start/end cells (frame-name style,
/// and nothing is drawn under them) and the instruction NAME centred on
/// the span along the frame axis but stepped OFF the mark across it.
/// Shared by both orientations (Axis policy); the printed sheet mirrors
/// this verbatim.

/// How far the instruction NAME sits from the wall it aligns to — the top
/// of the row on the timeline, the right of the column on the sheet and in
/// print. Shared so the three surfaces cannot drift apart by a pixel.
const double instructionLabelInset = 1;

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

/// What a row's BAND shows: the span adapter on a row that is spans and
/// nothing else (the transition), its own cels everywhere else.
///
/// 🚨R27 #16 LEFT THE BAND EMPTY (유저 2026-08-27: 「지금 스샷보면 **블록의
/// 배경색 흰색이 사라졌는데?**」). Giving the direction row cels flipped
/// `LayerKind.bandIsInstructionsOnly` to false, so the band stopped reading
/// the span adapter — and started reading cels the row did not have yet.
/// Nothing was drawn at all. The row did not gain a feature; it lost its
/// blocks.
///
/// ↩️That fix was a UNION — the direction row's own cels where it had
/// them, its spans filling the rest — because its spans lived beside its
/// cels. Since R27 its spans ARE its blocks (`LayerKind.spansRideBlocks`),
/// so its own cels are the whole answer, and the union's second half had
/// nothing left to fill.
///
/// ⛔ONE FUNCTION, because there are TWO readers — the cells row and the
/// cursor layer's range measure — and a row that DRAWS a block it will not
/// SELECT is worse than one that draws none ([[no-copy-to-share]]).
TimelineCellExposureState bandExposureState(
  Layer layer,
  int frameIndex, {
  required TimelineCellExposureState Function(Layer, int) ownCels,
}) => layer.kind.bandIsInstructionsOnly
    ? instructionCellExposureState(layer, frameIndex)
    : ownCels(layer, frameIndex);

/// The instruction spans of [layer] that reach the half-open window
/// [frameStartIndex]..[frameEndIndexExclusive], in map order.
List<({int start, int endExclusive, InstructionEvent event})>
_instructionSpansIn(
  Layer layer,
  int frameStartIndex,
  int frameEndIndexExclusive,
) {
  final spans = <({int start, int endExclusive, InstructionEvent event})>[];
  for (final entry in layer.instructions.entries) {
    final endExclusive = entry.key + entry.value.length;
    if (frameRangesOverlap(
      entry.key,
      endExclusive,
      frameStartIndex,
      frameEndIndexExclusive,
    )) {
      spans.add((
        start: entry.key,
        endExclusive: endExclusive,
        event: entry.value,
      ));
    }
  }
  return spans;
}

/// The mark/label overlays for every instruction span intersecting the
/// visible window.
///
/// [crossingWarningTooltip] is the D26 marker's resolver — the
/// seClipMarkerTooltip threading convention: null (or a null answer for a
/// span's start key) mounts nothing, a string mounts the shared red
/// warning line on that span's block with that hover text. The block
/// itself keeps drawing either way — a warning must have something to sit
/// on, and the refusal is the EFFECT's, never the display's.
List<Widget> timelineRowInstructionOverlays({
  required Layer layer,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required Axis axis,
  required CameraInstructionDef? Function(String instructionId) defById,
  String keyPrefix = 'timeline',
  String? Function(int spanStartKey)? crossingWarningTooltip,
  Color? crossingWarningColor,
  double crossAxisExtent = 0,
}) {
  assert(
    crossingWarningTooltip == null || crossingWarningColor != null,
    'a crossing warning needs its ink — pass colorScheme.error, the SE '
    'clip marker convention',
  );
  // The two passes draw over exactly the same spans, so the window is
  // asked once and both walk the answer.
  final visible = _instructionSpansIn(
    layer,
    frameStartIndex,
    frameEndIndexExclusive,
  );
  final overlays = <Widget>[];
  for (final span in visible) {
    final start = span.start;
    final endExclusive = span.endExclusive;
    final def = defById(span.event.instructionId);
    overlays.add(
      TimelineFrameSpan(
        placement: TimelineFrameSpanPlacement(
          startIndex: start,
          endIndexExclusive: endExclusive,
        ),
        child: IgnorePointer(
          key: ValueKey<String>('$keyPrefix-instruction-${layer.id}-$start'),
          child: _InstructionSpan(axis: axis, event: span.event, def: def),
        ),
      ),
    );
  }
  // Markers AFTER every span, so a warning is never painted under a
  // neighbouring block's body.
  final resolveWarning = crossingWarningTooltip;
  if (resolveWarning != null) {
    for (final span in visible) {
      final start = span.start;
      final endExclusive = span.endExclusive;
      final tooltip = resolveWarning(start);
      if (tooltip == null) {
        continue;
      }
      overlays.add(
        timelineBlockWarningBar(
          blockStart: start,
          blockEndExclusive: endExclusive,
          crossAxisExtent: crossAxisExtent,
          axis: axis,
          tooltip: tooltip,
          color: crossingWarningColor!,
          markerKey: ValueKey<String>(
            '$keyPrefix-instruction-crossing-${layer.id}-$start',
          ),
        ),
      );
    }
  }
  return overlays;
}

/// Edge grips over instruction spans: reuses the exposure grip widget and
/// callback shape — the session dispatches instruction rows to the span
/// editor internally, so both row types share one drag pipeline.
///
/// [crossAxisExtent] is the ROW's: the grips stand on the row's paper, which
/// stops a seam short of it (I-44, [timelineRowPaperExtent]).
///
/// [spanTakesGrips] leaves out the spans a surface draws but does not edit
/// (a cut's O.L marks); [suppressStartGripAtZero] is the exposure grips'
/// spill-in rule.
List<Widget> timelineRowInstructionEdgeGrips({
  required Layer layer,
  required int frameStartIndex,
  required int frameEndIndexExclusive,
  required ValueListenable<TimelineFrameGeometry> geometry,
  required TimelineCommaDragCallbacks commaDrag,
  required Axis axis,
  required double crossAxisExtent,
  bool suppressStartGripAtZero = false,
  bool Function(InstructionEvent event)? spanTakesGrips,
}) {
  final grips = <Widget>[];
  var ordinal = 0;
  for (final entry in layer.instructions.entries) {
    final start = entry.key;
    final endExclusive = start + entry.value.length;
    final visible =
        endExclusive > frameStartIndex && start < frameEndIndexExclusive;
    if (visible && (spanTakesGrips?.call(entry.value) ?? true)) {
      for (final edge in TimelineBlockEdge.values) {
        // The exposure grips' rule ([timelineLayerGripBlocks]): the span at
        // frame 0 of a row whose first block began in an earlier cut keeps
        // its start there.
        if (edge == TimelineBlockEdge.start &&
            start == 0 &&
            suppressStartGripAtZero) {
          continue;
        }
        grips.add(
          TimelineFrameSpan(
            placement: timelineBlockEdgeGripPlacement(
              edge: edge,
              startIndex: start,
              endIndexExclusive: endExclusive,
              crossAxisExtent: timelineRowPaperExtent(crossAxisExtent),
            ),
            child: TimelineBlockEdgeGrip(
              layerId: layer.id,
              blockStartIndex: start,
              blockOrdinal: ordinal,
              edge: edge,
              geometry: geometry,
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

  /// A word of this span as a BLOCK word ([TimelineBlockWord]): its block is
  /// the span, split into `event.length` cells, and the word stays inside it.
  ///
  /// ↩️The writing used to run past the span onto the neighbours' cells
  /// (「paper writing spills over neighbours freely」 — mine, 2026-07-09, the
  /// paper-block slice) out of a slot that was a FRACTION of the span, so
  /// that this widget needed nothing from the zoom. It still needs nothing:
  /// the block word reads its own box. What changed is the law — 「이름은
  /// 블록안에서만」 and 「컷블록의 텍스트든 se텍스트든 뭐든」 (유저
  /// 2026-09-24): the writing keeps its type and narrows into the span.
  Widget _word(Widget writing, TimelineBlockWordCells place) =>
      Positioned.fill(
        child: TimelineBlockWord(
          place: place,
          child: ExcludeSemantics(child: writing),
        ),
      );

  /// Instruction writing follows the surface: across the row on the
  /// timeline, DOWN the column on the sheet.
  ///
  /// The sheet used to get horizontal text too, and that is what made
  /// `FOLLOW PAN` 112px wide in a 28px column — three clip opt-outs above
  /// then let it paint straight over the neighbouring layer's cells. A
  /// name written down its own column cannot reach the neighbour at all,
  /// which is the fix at the root rather than a clip on top.
  ///
  /// Down the column its LETTERS stand up (user, 2026-08-08): writing
  /// beside a duration bar is read at a glance, and the printed sheet is
  /// set the same way for the same reason.
  Widget _writing(String text, TextStyle style) {
    return axis == Axis.horizontal
        ? Text(text, maxLines: 1, softWrap: false, style: style)
        : VerticalWritingText(
            text: text,
            latinForm: VerticalLatinForm.upright,
            style: style,
          );
  }

  @override
  Widget build(BuildContext context) {
    final markColor = def?.colorValue == null
        ? timelineDrawingInkColor
        : Color(def!.colorValue!);
    // The mark and the writing are independent: free per-event text wins,
    // the vocabulary name is the fallback.
    final name = event.displayLabel(def);
    final base = DefaultTextStyle.of(context).style;
    // The A/B instance names read exactly like frame names on drawing
    // blocks — the block word's own print: ink, bold, ambient size.
    final valueStyle = timelineBlockWordStyle(
      base,
      ink: timelineDrawingInkColor,
      fontSize: base.fontSize ?? 12,
      bold: true,
    );
    final nameStyle = timelineBlockWordStyle(
      base,
      ink: markColor,
      fontSize: 11,
      bold: true,
    );
    final valueA = event.valueA;
    final valueB = event.valueB;
    final cells = event.length < 1 ? 1 : event.length;

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
          // The A/B values sit in the span's first and last cells, as a
          // block's name and its length do (F-96).
          if (valueA != null && valueA.isNotEmpty)
            _word(_writing(valueA, valueStyle), (
              axis: axis,
              cells: cells,
              cellIndex: 0,
              growth: TimelineBlockWordGrowth.towardBlockEnd,
              acrossAlignment: 0,
            )),
          if (valueB != null && valueB.isNotEmpty)
            _word(_writing(valueB, valueStyle), (
              axis: axis,
              cells: cells,
              cellIndex: cells - 1,
              growth: TimelineBlockWordGrowth.towardBlockStart,
              acrossAlignment: 0,
            )),
          // The name sits on the SPAN's centre along the FRAME axis and
          // steps OFF the mark across it (user, 2026-08-08): up on the
          // timeline, right on the sheet.
          //
          // Both used to be dead centre — which is exactly where the mark
          // is, since [_InstructionMarkPainter] draws every bar, wedge and
          // bowtie about `crossCenter`. So a duration line and the word
          // naming it were drawn through each other. The MARK keeps the
          // centre and the writing is what moves, because only one of the
          // two can say where the middle of the span is.
          if (name.isNotEmpty)
            Positioned.fill(
              // A hair off the wall, so the glyphs never sit on the cell
              // border they have just moved next to.
              child: Padding(
                padding: axis == Axis.horizontal
                    ? const EdgeInsets.only(top: instructionLabelInset)
                    : const EdgeInsets.only(right: instructionLabelInset),
                child: TimelineBlockWord(
                  place: (
                    axis: axis,
                    cells: 1,
                    cellIndex: 0,
                    growth: TimelineBlockWordGrowth.towardBlockEnd,
                    acrossAlignment: axis == Axis.horizontal ? -1 : 1,
                  ),
                  child: ExcludeSemantics(child: _writing(name, nameStyle)),
                ),
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
class _InstructionMarkPainter extends CustomPainter with RepaintOnProps {
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

  /// ONE isosceles triangle, base on [baseMain] spanning [crossHalf] either
  /// side of [crossCenter], apex at [apexMain] on the centre line. The bar's
  /// endpoint caps, the fade wedge and the bowtie's two halves are all this
  /// shape; each caller keeps choosing the values its own decision fixes.
  Path _isoscelesToward({
    required double baseMain,
    required double apexMain,
    required double crossCenter,
    required double crossHalf,
  }) => Path()
    ..addPolygon([
      offsetAlong(axis, along: baseMain, across: crossCenter - crossHalf),
      offsetAlong(axis, along: apexMain, across: crossCenter),
      offsetAlong(axis, along: baseMain, across: crossCenter + crossHalf),
    ], true);

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
    final mainExtent = extentAlong(axis, size);
    final crossExtent = extentAcross(axis, size);
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
    canvas.drawLine(
      offsetAlong(axis, along: start, across: crossCenter),
      offsetAlong(axis, along: end, across: crossCenter),
      paint,
    );
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
    final apexMain = atStart ? length : mainExtent - length;
    canvas.drawPath(
      _isoscelesToward(
        baseMain: atStart ? 0.0 : mainExtent,
        apexMain: apexMain,
        crossCenter: crossCenter,
        crossHalf: crossExtent / 4,
      ),
      Paint()..color = color,
    );
    return apexMain;
  }

  /// The fade wedge, a plain light-gray fill following the light: FI opens
  /// narrow → wide (the picture grows in), FO wide → narrow (R4
  /// orientation fix; hatching retired).
  void _paintFadeWedge(Canvas canvas, Size size, {required bool wideAtStart}) {
    final mainExtent = extentAlong(axis, size);
    final crossCenter = extentAcross(axis, size) / 2;
    final wideHalf = crossCenter - 2;
    if (mainExtent < 6 || wideHalf < 2) {
      return;
    }
    canvas.drawPath(
      _isoscelesToward(
        baseMain: wideAtStart ? 1.0 : mainExtent - 1,
        apexMain: wideAtStart ? mainExtent - 1 : 1.0,
        crossCenter: crossCenter,
        crossHalf: wideHalf,
      ),
      _wedgeFill,
    );
  }

  /// Two triangles meeting at the span's centre, each based on a span edge
  /// and spanning the whole row.
  void _paintBowtie(Canvas canvas, Size size) {
    final paint = _wedgeFill;
    final mainExtent = extentAlong(axis, size);
    final crossHalf = extentAcross(axis, size) / 2;
    final mid = mainExtent / 2;
    canvas.drawPath(
      _isoscelesToward(
        baseMain: 0,
        apexMain: mid,
        crossCenter: crossHalf,
        crossHalf: crossHalf,
      ),
      paint,
    );
    canvas.drawPath(
      _isoscelesToward(
        baseMain: mainExtent,
        apexMain: mid,
        crossCenter: crossHalf,
        crossHalf: crossHalf,
      ),
      paint,
    );
  }

  @override
  Object get props =>
      (axis, markType, eventLength, color, hasStartName, hasEndName);
}
