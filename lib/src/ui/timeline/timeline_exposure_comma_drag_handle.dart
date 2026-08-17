import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragStartBehavior, PointerDeviceKind;
import 'package:flutter/material.dart';

import '../input/app_input_settings.dart' show AppInput;

import '../../models/layer_id.dart';
import '../../models/timeline_coverage.dart';
import 'timeline_cell_style.dart';
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_frame_span_layout.dart';

/// How a grip reads right now. The ONLY thing a state change moves is the
/// ink (R28 #3) — geometry is constant, so this is the whole visual state.
enum BlockEdgeGripInk { rest, hovered, dragging }

/// Back to 3.5 (R10). R9 #11 widened it to 4.5 on the theory that the
/// then-outline ate into the bar from both sides, and 4.5 read as a fat
/// rung across the block either way. The outline itself is gone now
/// (2026-08-17): the bar reads by the ground law's ink instead.
const double _gripBarThickness = 3.5;
const double _gripBarInset = 2.5;

/// R28 #3: the bar's cross-axis length as a fraction of the row — a
/// CONSTANT. Hover and drag change the bar's color, never its size.
const double _gripBarLengthFactor = 0.55;

/// A third of the edge CELL, never thinner than [_minimumHitExtent] where
/// the block can afford it, and never wider than [TimelineBlockEdgeGrip.hitExtent].
///
/// The cell measure is what keeps a block's body tappable: the fixed 12px
/// strips this replaced covered whole cells and swallowed cell selection,
/// and widening it back to a third of the BLOCK brings that straight back
/// (six timeline cell-edit tests said so).
///
/// The FLOOR is the storyboard's half of it (user, 2026-07-28). A cut row
/// draws at 8px a frame, so a third of a cell is under three pixels and the
/// edges answered only on the boundary line itself — nothing like the
/// timeline's feel. A floor fixes that wherever the block is wide enough to
/// give the pixels up, and a one-frame block still keeps its body because
/// the floor itself is capped by a third of the block.
double blockEdgeGripHitExtent(double frameCellExtent, {double? blockExtent}) {
  final byCell = frameCellExtent / 3;
  final floor = blockExtent == null
      ? 0.0
      : math.min(_minimumHitExtent, blockExtent / 3);
  final wanted = byCell > floor ? byCell : floor;
  return wanted > TimelineBlockEdgeGrip.hitExtent
      ? TimelineBlockEdgeGrip.hitExtent
      : wanted;
}

/// Thin enough to leave a long block's middle alone, thick enough to aim
/// at with a finger on a zoomed-out row.
const double _minimumHitExtent = 6;

/// Where a block-edge grip sits on a SPARSE row, as a frame-span placement
/// that resolves to [blockEdgeGripHitExtent]'s EXACT width — a third of the
/// edge cell, floored at min([_minimumHitExtent], a third of the block),
/// capped at [TimelineBlockEdgeGrip.hitExtent].
///
/// ⛔This form used to skip the block floor on purpose ("the sparse rows
/// draw crossing marks in the same cells") — and that exemption is what the
/// user reported as B5②/B6 (2026-08-17): at the storyboard's 8px-a-frame
/// zoom a third of a cell is under three pixels, so the visible grip bar
/// sat OUTSIDE its own hit strip and the edges read as answering "at the
/// block's tip, not at the edge". One law now; the dense rows' chrome and
/// this placement resolve the same zone (`block_edge_grip_placement_parity`
/// pins them together).
TimelineFrameSpanPlacement timelineBlockEdgeGripPlacement({
  required TimelineBlockEdge edge,
  required int startIndex,
  required int endIndexExclusive,
}) => TimelineFrameSpanPlacement(
  startIndex: edge == TimelineBlockEdge.start ? startIndex : endIndexExclusive,
  mainExtentCells: 1 / 3,
  maxMainExtent: TimelineBlockEdgeGrip.hitExtent,
  minMainExtent: _minimumHitExtent,
  minMainExtentCells: (endIndexExclusive - startIndex) / 3,
  anchorAtTrailingEdge: edge == TimelineBlockEdge.end,
);

/// The bar's rect INSIDE a hit strip whose origin is the strip's top-left:
/// [hitExtent] along the frame axis, [crossAxisExtent] across it.
///
/// THE geometry source (R28 #4 tier 2): the widget grip and the dense rows'
/// chrome painter both read it, so a grip drawn by a painter and one drawn
/// by a widget cannot drift.
Rect blockEdgeGripBarRect({
  required TimelineBlockEdge edge,
  required double hitExtent,
  required double crossAxisExtent,
  required Axis axis,
}) {
  final isStart = edge == TimelineBlockEdge.start;
  final barLength = crossAxisExtent * _gripBarLengthFactor;
  if (axis == Axis.horizontal) {
    return Rect.fromLTWH(
      isStart ? _gripBarInset : hitExtent - _gripBarInset - _gripBarThickness,
      (crossAxisExtent - barLength) / 2,
      _gripBarThickness,
      barLength,
    );
  }
  return Rect.fromLTWH(
    (crossAxisExtent - barLength) / 2,
    isStart ? _gripBarInset : hitExtent - _gripBarInset - _gripBarThickness,
    barLength,
    _gripBarThickness,
  );
}

/// Quiet at rest, full on hover, accent while dragging — state carried by
/// ink ALONE (R28 #3).
///
/// [ground] is the color of what the bar sits ON, not the theme's
/// brightness (feedback #11 gave it two inks by surface; 2026-08-17 made
/// the pick the text's own ground law, [timelineTextOnColor]). A paper
/// block takes the black bar — the purple paper included — and the dark
/// cut-block strip takes the white one. The white OUTLINE the bar used to
/// wear went with the pick ("애초에 통일하기로 했잖아"): the ink already
/// contrasts with the ground it was chosen against, so a silhouette had
/// nothing left to say. The accent of a live drag reads on both and is
/// left alone: a drag in progress must not change colour with its row.
Color blockEdgeGripBarColor(
  BlockEdgeGripInk ink, {
  Color ground = timelineDrawingHeldColor,
}) {
  if (ink == BlockEdgeGripInk.dragging) {
    return timelineSelectedFrameBorderColor;
  }
  final base = timelineTextOnColor(ground);
  final lightBar = base == timelineTextOnDarkGroundColor;
  // A light bar needs more alpha than a dark one to read as the same
  // weight — the same asymmetry [storyboardCutBlockEdgeColor] carries.
  return base.withValues(
    alpha: ink == BlockEdgeGripInk.hovered
        ? (lightBar ? 0.98 : 0.95)
        : (lightBar ? 0.55 : 0.38),
  );
}

/// Draws one grip bar at [barRect]. THE drawing source, shared by the widget
/// grip and the dense rows' row-wide chrome painter.
///
/// ⛔No outline arm (2026-08-17). R9 #11 wrapped the bar in the text's
/// white outline so a resting grip read on a busy block; #1104 took the
/// text's outline off and the bar kept its — the last white silhouette on
/// the blocks, which the user called out on device. The ground law is the
/// visibility answer now, for the bar exactly as for the writing.
void paintBlockEdgeGripBar(
  Canvas canvas,
  Rect barRect,
  BlockEdgeGripInk ink, {
  Color ground = timelineDrawingHeldColor,
}) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(barRect, const Radius.circular(2)),
    Paint()..color = blockEdgeGripBarColor(ink, ground: ground),
  );
}

/// The widget grip's bar, painted rather than boxed: the sparse surfaces
/// (storyboard cut trim, SE spans, instruction rows) still mount a widget
/// per grip, and this keeps their pixels identical to the painted rows'.
class BlockEdgeGripBarPainter extends CustomPainter {
  const BlockEdgeGripBarPainter({
    required this.edge,
    required this.axis,
    required this.ink,
  });

  final TimelineBlockEdge edge;
  final Axis axis;
  final BlockEdgeGripInk ink;

  /// The strip's own BOX gives the geometry — the grip is laid out at the
  /// hit extent, so nothing needs the cell width passed in (that is what
  /// used to drag every grip through a rebuild on each zoom step). Still the
  /// shared [blockEdgeGripBarRect], so the painted rows cannot drift.
  @override
  void paint(Canvas canvas, Size size) => paintBlockEdgeGripBar(
    canvas,
    blockEdgeGripBarRect(
      edge: edge,
      hitExtent: axis == Axis.horizontal ? size.width : size.height,
      crossAxisExtent: axis == Axis.horizontal ? size.height : size.width,
      axis: axis,
    ),
    ink,
  );

  @override
  bool shouldRepaint(covariant BlockEdgeGripBarPainter oldDelegate) =>
      oldDelegate.edge != edge ||
      oldDelegate.axis != axis ||
      oldDelegate.ink != ink;
}

/// The drag hooks a grip needs once its identity is already bound by the
/// caller (R28 #3). The timeline binds layer + block, the storyboard binds
/// the cut — below this line the two are the same grip.
class BlockEdgeGripHooks {
  const BlockEdgeGripHooks({
    required this.onBegin,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
  });

  /// Returns whether the drag may start (e.g. the block still exists).
  final bool Function() onBegin;

  /// Reports the cumulative whole-frame delta since drag start.
  final ValueChanged<int> onUpdate;
  final VoidCallback onEnd;
  final VoidCallback onCancel;
}

/// The ONE block-edge grip (R28 #3): an inset bar just inside a block's
/// start or end edge, with the whole hover/drag state machine.
///
/// Both surfaces mount THIS — the timeline through [TimelineBlockEdgeGrip]
/// and the storyboard through its cut-trim binder. The storyboard used to
/// carry a private copy that had drifted (no hover state at all), which is
/// exactly the split the user called out; a change to the grip's feel now
/// lands in both places by construction.
///
/// Dragging reports the CUMULATIVE whole-frame delta since drag start; the
/// session recomputes the preview from its drag-start snapshot, so the grip
/// needs no per-step accounting.
class BlockEdgeGrip extends StatefulWidget {
  const BlockEdgeGrip({
    super.key,
    required this.edge,
    required this.resolveFrameCellExtent,
    required this.hooks,
    this.axis = Axis.horizontal,
    this.supportedDevices,
  });

  final TimelineBlockEdge edge;

  /// The cell extent, READ AT DRAG TIME rather than captured: the grip fills
  /// whatever box its mount hands it, and a mount that positions by frame
  /// span (the sparse rows) does not rebuild it on a zoom step — so a value
  /// frozen at build time would convert pixels to frames at the wrong scale.
  final double Function() resolveFrameCellExtent;

  final BlockEdgeGripHooks hooks;

  /// The frame axis direction; geometry and gesture transpose with it.
  final Axis axis;

  /// Null = every device operates the grip (the storyboard track, which
  /// has no competing touch scroll).
  final Set<PointerDeviceKind>? supportedDevices;

  @override
  State<BlockEdgeGrip> createState() => _BlockEdgeGripState();
}

/// One comma-drag grip on a TIMELINE block: binds the layer/block identity
/// onto the shared [BlockEdgeGrip]. Every block shows both grips
/// (TVPaint-style comma adjustment), in both orientations via [axis].
class TimelineBlockEdgeGrip extends StatelessWidget {
  const TimelineBlockEdgeGrip({
    super.key,
    required this.layerId,
    required this.blockStartIndex,
    required this.blockOrdinal,
    required this.edge,
    required this.resolveFrameCellExtent,
    required this.callbacks,
    this.axis = Axis.horizontal,
  });

  final LayerId layerId;

  /// The block's start frame index at build time (its identity for the
  /// drag; the session snapshots the layer on begin).
  final int blockStartIndex;

  /// The block's position among the layer's blocks. Keys derive from THIS,
  /// not the start index: a start-edge drag moves the start index every
  /// step, and a key change there would rebuild the gesture subtree and
  /// kill the active drag.
  final int blockOrdinal;
  final TimelineBlockEdge edge;

  /// See [BlockEdgeGrip.resolveFrameCellExtent].
  final double Function() resolveFrameCellExtent;

  final TimelineCommaDragCallbacks callbacks;

  /// The frame axis direction; geometry and gesture transpose with it.
  final Axis axis;

  /// The grip strip's nominal main-axis extent; [blockEdgeGripHitExtent]
  /// caps it against the cell width.
  static const double hitExtent = 12;

  /// The identity finders (and tests) look for. It rides a [KeyedSubtree]
  /// rather than a `Positioned`, because WHERE a grip sits is now the mount
  /// site's business: a frame-span layout on the sparse rows, a `Positioned`
  /// on the storyboard.
  Key get subtreeKey => ValueKey<String>(
    'timeline-block-edge-grip-${edge.name}-$layerId-$blockOrdinal',
  );

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: subtreeKey,
      child: BlockEdgeGrip(
        edge: edge,
        resolveFrameCellExtent: resolveFrameCellExtent,
        axis: axis,
        // Drag-only grip: touch follows the timeline input policy (UI-R22F —
        // when touch scrolls the timeline, a finger pan starting on a grip
        // must scroll too, not comma-drag).
        supportedDevices: AppInput.timelineEditPanDevices,
        hooks: BlockEdgeGripHooks(
          onBegin: () => callbacks.onBegin(layerId, blockStartIndex, edge),
          onUpdate: callbacks.onUpdate,
          onEnd: callbacks.onEnd,
          onCancel: callbacks.onCancel,
        ),
      ),
    );
  }
}

class _BlockEdgeGripState extends State<BlockEdgeGrip> {
  double _accumulatedDelta = 0;
  int _lastReportedFrames = 0;
  bool _dragging = false;

  /// R27 #11: pointer resting on the grip — lights the bar.
  bool _hovered = false;

  /// R9 #12: pointer DOWN on the grip — reads as engaged straight away.
  /// The accent used to wait for the drag recognizer to win the arena,
  /// which is after the slop, so pressing and holding still looked like
  /// nothing had been grabbed. The Listener below is upstream of the
  /// arena, so it can answer at once — and it owns the release the old
  /// code never had.
  bool _pressed = false;

  void _startDrag() {
    final accepted = widget.hooks.onBegin();
    if (!accepted) {
      return;
    }
    setState(() {
      _dragging = true;
      _accumulatedDelta = 0;
      _lastReportedFrames = 0;
    });
  }

  void _updateDrag(double delta) {
    if (!_dragging) {
      return;
    }
    _accumulatedDelta += delta;
    final frames = commaDragFrameDelta(
      accumulatedDelta: _accumulatedDelta,
      frameCellExtent: widget.resolveFrameCellExtent(),
    );
    if (frames == _lastReportedFrames) {
      return;
    }
    _lastReportedFrames = frames;
    widget.hooks.onUpdate(frames);
  }

  void _endDrag() {
    if (!_dragging) {
      return;
    }
    setState(() => _dragging = false);
    widget.hooks.onEnd();
  }

  void _cancelDrag() {
    if (!_dragging) {
      return;
    }
    setState(() => _dragging = false);
    widget.hooks.onCancel();
  }

  @override
  void dispose() {
    // A grip can unmount mid-drag when its block scrolls out; the session
    // keeps the preview and the pointer-up never arrives here, so end the
    // drag as committed rather than leaking an open session.
    if (_dragging) {
      widget.hooks.onEnd();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    // R28 #3: the grip's GEOMETRY is constant — only its color reacts.
    // R27 #11 had a hover fatten the bar (longer and thicker), and the
    // size change read as the block itself resizing under the pointer.
    // State is carried by ink alone now: quiet at rest, full on hover,
    // accent while dragging. (Both surfaces mount this one widget, so
    // the timeline and the storyboard get the same feedback.)
    //
    // The bar is PAINTED through the shared helpers (R28 #4 tier 2) so the
    // dense rows — which draw all their grips in one row-wide painter —
    // and these widget-mounted grips cannot drift apart.
    final bar = CustomPaint(
      painter: BlockEdgeGripBarPainter(
        edge: widget.edge,
        axis: widget.axis,
        ink: _dragging || _pressed
            ? BlockEdgeGripInk.dragging
            : _hovered
            ? BlockEdgeGripInk.hovered
            : BlockEdgeGripInk.rest,
      ),
      child: const SizedBox.expand(),
    );

    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (_) {
          if (!_pressed) {
            setState(() => _pressed = true);
          }
        },
        onPointerUp: (_) => _releasePress(),
        onPointerCancel: (_) => _releasePress(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          supportedDevices: widget.supportedDevices,
          // Drag from the DOWN position (R10): the slop the recognizer
          // spends winning the arena is real travel of the hand, and
          // Flutter's default throws it away — so the edge settled ~18px
          // BEHIND the pointer and stayed there for the whole gesture.
          // The timeline's other edit drags already read `down`, the
          // cut-end handle among them — and that one is an edge too.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: horizontal ? (_) => _startDrag() : null,
          onHorizontalDragUpdate: horizontal
              ? (details) => _updateDrag(details.delta.dx)
              : null,
          onHorizontalDragEnd: horizontal ? (_) => _endDrag() : null,
          onHorizontalDragCancel: horizontal ? _cancelDrag : null,
          onVerticalDragStart: horizontal ? null : (_) => _startDrag(),
          onVerticalDragUpdate: horizontal
              ? null
              : (details) => _updateDrag(details.delta.dy),
          onVerticalDragEnd: horizontal ? null : (_) => _endDrag(),
          onVerticalDragCancel: horizontal ? null : _cancelDrag,
          child: bar,
        ),
      ),
    );
  }

  /// The pointer lifted (or the system took it). A drag that started keeps
  /// its own accent through [_dragging] until the drag itself ends.
  void _releasePress() {
    if (!_pressed) {
      return;
    }
    setState(() => _pressed = false);
  }
}
