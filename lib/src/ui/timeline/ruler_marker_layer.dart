import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/ruler_marker.dart';
import '../../models/se_dialogue_spacing.dart';
import '../repaint_props.dart';
import '../theme/app_theme.dart' show AppCursors;
import '../theme/ruler_marker_palette.dart';
import '../widgets/app_tooltip.dart';
import '../widgets/tick_layer.dart';
import 'axis_turn.dart';
import 'dialogue_fit_text.dart';
import 'timeline_cut_end_handle.dart' show WholeFramesGrip;
import 'timeline_double_tap.dart';
import 'timeline_drag_preview.dart';
import 'timeline_frame_coordinate_policy.dart' show frameAtVisibleX;
import 'timeline_frame_ruler_painter.dart' show TimelineRulerScale;

/// What a ruler is handed to show its markers, move them and open one
/// (I-169): whose they are ([holder]), the set the project holds
/// ([markers]), the drag channel a step is read off ([dragPreview]), and the
/// session's verbs.
///
/// One value for every ruler that takes markers — the timeline's, the
/// X-sheet's rail and the conte panel's — so the three cannot be handed
/// three halves.
class RulerMarkerHooks {
  const RulerMarkerHooks({
    required this.holder,
    required this.markers,
    required this.dragPreview,
    required this.onBeginDrag,
    required this.onUpdateDrag,
    required this.onEndDrag,
    required this.onCancelDrag,
    required this.onOpen,
  });

  final RulerMarkerHolder holder;
  final RulerMarkers markers;
  final ValueListenable<TimelineDragPreview?> dragPreview;

  /// Starts a drag of the marker at this place of [markers].
  final bool Function(int index) onBeginDrag;

  /// Reports the cumulative whole-frame delta since the drag began.
  final ValueChanged<int> onUpdateDrag;
  final VoidCallback onEndDrag;
  final VoidCallback onCancelDrag;

  /// A double click on the ruler's cell of this frame: the marker standing
  /// over it opens, or a new one is made there.
  final ValueChanged<int> onOpen;
}

/// How much of a ruler's breadth its markers stand in: the half the seconds
/// are written in — the top of a ruler that runs across, the leading side of
/// a rail that runs down.
///
/// 🗣️I-169-Q1 (유저 2026-11-13): 「룰러 한 칸에서 위쪽절반은 마크위젯,
/// 아래는 기존처럼 룰러위젯으로 대응하도록 … 룰러위젯 드래그해서 바로바로
/// 움직일수있게」 — a press on a marker is the marker's, and the other half
/// of the cell stays the ruler's to scrub by.
const double rulerMarkerBandShare = 0.5;

/// How far into its ribbon a marker's notch is cut — the bookmark's tail the
/// mock-up drew, the same on a point and on a span (I-169-Q4: 「깃발이랑
/// 동일한 모양으로 옆으로 늘린모양으로. 즉 모양 통일」).
const double _notchShare = 0.3;

/// A marker's letters: the SE block's law as it stands
/// ([DialogueFitText]), a glyph to a frame.
///
/// 🗣️I-169-Q4 (유저 2026-11-13): 「글자 어느정도 작게해서 넣어서 … 글자는
/// 약간 칸마다 1글자씩 보인단느낌? … 그냥 그런거없이 심플하게 se블록
/// 텍스트에서 쓰는 법 그대로 쓰자」. So a text longer than its marker narrows
/// into it as a dialogue does into its block, and none of it is left out.
const SeDialogueSpacing _letterSpacing = SeDialogueSpacing(komaPerGlyph: 1);
const double _letterSize = 9;

/// Where [marker] stands on the strip [scale] draws: over its frames, in
/// the markers' half of the breadth.
Rect rulerMarkerRect(TimelineRulerScale scale, RulerMarker marker) {
  final axis = scale.axis;
  return rectAlong(
    axis,
    along: (
      from: startAlong(axis, scale.cellRectFor(marker.start)),
      to: endAlong(axis, scale.cellRectFor(marker.endExclusive - 1)),
    ),
    across: (from: 0, to: scale.crossExtent * rulerMarkerBandShare),
  );
}

/// The frame of [scale]'s strip a point of it stands in.
int _frameAt(TimelineRulerScale scale, Offset local) => frameAtVisibleX(
  visibleX: partAlong(scale.axis, local),
  frameStartIndex: scale.frameStartIndex,
  frameCellWidth: scale.metrics.frameCellWidth,
  leadingFrameSpacerWidth: scale.leadingFrameSpacer,
);

/// A ruler's MARKERS, over its strip and under the playhead's writing
/// (I-169): each a ribbon over its frames wearing its text, dragged by the
/// whole-frames grip, and the ruler's double click that opens one.
///
/// 🗣️I-169-Q1 (유저 2026-11-13): 「룰러는 따로 움직일상황 많으니 층 나눠서
/// 효율적으로 하는건 알아서 맡김」 — on a layer of their own ([TickLayer]): a
/// drag's step lays out and paints the ribbons, and the strip under them,
/// a glyph to every numbered frame, stays as it was recorded.
class RulerMarkerLayer extends StatelessWidget {
  const RulerMarkerLayer({super.key, required this.hooks, required this.scale});

  final RulerMarkerHooks hooks;
  final TimelineRulerScale scale;

  /// The ruler's cell a press landed in, as the double-click gate keeps it
  /// — the frame panels' one gate ([TimelineDoubleTapGate]).
  ({RulerMarkerHolder ruler, int frame}) _cellAt(Offset local) {
    final cells = (
      frameAt: (Offset at) => _frameAt(scale, at),
      axis: scale.axis,
      cellExtent: () => scale.metrics.frameCellWidth,
    );
    return (
      ruler: hooks.holder,
      frame: _frameAt(scale, timelineDoubleTapAim(local, cells)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🗣️I-169-Q1: 「룰러 칸 자체 더블클릭하면 편집페이지 열리고 … 마커가
    // 생기고 나서라도 더블클릭은 룰러 칸 자체 더블클릭해서 대응하도록」 — the
    // CELL's, either half of it and a marker's ribbon too. The record half
    // stands OUTSIDE the activation half: a press reaches the deepest
    // handler first, so the first press is read before the second one's
    // record replaces it (the cells' order).
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => TimelineDoubleTapGate.recordTapDown(
        _cellAt(event.localPosition),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTapDown: (details) {
          final cell = _cellAt(details.localPosition);
          if (TimelineDoubleTapGate.acceptsActivation(cell)) {
            hooks.onOpen(cell.frame);
          }
        },
        onDoubleTap: () {},
        child: TickLayer(
          child: ValueListenableBuilder<TimelineDragPreview?>(
            valueListenable: hooks.dragPreview,
            builder: (context, preview, _) => Stack(
              children: [
                for (final (index, marker) in rulerMarkersUnder(
                  preview,
                  hooks.holder,
                  hooks.markers,
                ).inOrder.indexed)
                  Positioned.fromRect(
                    key: ValueKey<String>('ruler-marker-$index'),
                    rect: rulerMarkerRect(scale, marker),
                    child: _RulerMarkerRibbon(
                      marker: marker,
                      axis: scale.axis,
                      cellExtent: scale.metrics.frameCellWidth,
                      onBegin: () => hooks.onBeginDrag(index),
                      onUpdate: hooks.onUpdateDrag,
                      onEnd: hooks.onEndDrag,
                      onCancel: hooks.onCancelDrag,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One marker as its ruler shows it: the ribbon, its text along it, and the
/// grip the whole of it is.
class _RulerMarkerRibbon extends StatelessWidget {
  const _RulerMarkerRibbon({
    required this.marker,
    required this.axis,
    required this.cellExtent,
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  final RulerMarker marker;
  final Axis axis;
  final double cellExtent;
  final bool Function() onBegin;
  final ValueChanged<int> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // The whole text on a hover: a ribbon a frame wide shows a sliver of it.
    return AppTooltip(
      message: marker.text,
      // 🚨A PRESS ON A MARKER IS THE MARKER'S (the control law): the strong
      // claim, so the ruler's scrub under it stands down and no scroller
      // takes a pull across it.
      child: WholeFramesGrip(
        axis: axis,
        cellExtent: cellExtent,
        cursor: AppCursors.pressWhen(live: true),
        onBegin: onBegin,
        onUpdate: onUpdate,
        onEnd: onEnd,
        onCancel: onCancel,
        child: CustomPaint(
          painter: RulerMarkerRibbonPainter(
            axis: axis,
            color: rulerMarkerRibbon(marker.color),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return Stack(
                children: [
                  // Clear of the notch: the letters stand on the ribbon's
                  // whole part.
                  Positioned.fromRect(
                    rect: rectAlong(
                      axis,
                      along: (from: 0, to: extentAlong(axis, size)),
                      across: (
                        from: _ribbonInset,
                        to: extentAcross(axis, size) * (1 - _notchShare),
                      ),
                    ),
                    child: DialogueFitText(
                      text: marker.text,
                      axis: axis,
                      color: rulerMarkerInk,
                      frames: marker.length,
                      spacing: _letterSpacing,
                      fontSize: _letterSize,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// What a ribbon keeps clear of its box's edges: the ruler's own top line
/// across, and half a pixel at each end so two that touch read as two.
const double _ribbonInset = 1;
const double _ribbonEndInset = 0.5;

/// A ribbon's outline in [box], the box its marker stands in
/// ([rulerMarkerRect]): its frames' breadth, a notch cut into the far edge
/// — the bookmark, on a ruler that runs across and on a rail that runs down
/// alike, over one frame or many (I-169-Q4: 「모양 통일」).
///
/// What paints the ribbon and what writes over it read this one outline
/// ([RulerMarkerRibbonPainter], the ruler's writing layer), so the strip's
/// writing shown on a ribbon ends exactly where the ribbon does.
Path rulerMarkerOutline(Axis axis, Rect box) {
  final along = extentAlong(axis, box.size);
  final across = extentAcross(axis, box.size);
  Offset at(double along, double across) =>
      box.topLeft + offsetAlong(axis, along: along, across: across);
  const from = _ribbonEndInset;
  final to = along - _ribbonEndInset;
  return Path()..addPolygon([
    at(from, _ribbonInset),
    at(to, _ribbonInset),
    at(to, across),
    at(along / 2, across * (1 - _notchShare)),
    at(from, across),
  ], true);
}

/// A marker's ribbon, in its colour ([rulerMarkerOutline]). Public for the
/// test probe.
class RulerMarkerRibbonPainter extends CustomPainter with RepaintOnProps {
  RulerMarkerRibbonPainter({required this.axis, required this.color});

  final Axis axis;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      rulerMarkerOutline(axis, Offset.zero & size),
      Paint()..color = color,
    );
  }

  @override
  Object get props => (axis, color);
}
