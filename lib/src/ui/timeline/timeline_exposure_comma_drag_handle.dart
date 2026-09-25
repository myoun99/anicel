import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../models/layer_id.dart';
import '../../models/timeline_coverage.dart';
import 'axis_turn.dart';
import 'timeline_beat_lines.dart' show timelineRowPaperExtent;
import 'timeline_cell_style.dart';
import 'timeline_exposure_comma_drag_policy.dart';
import 'timeline_frame_span_layout.dart';
import 'timeline_frame_geometry.dart';
import 'timeline_zoom_limits.dart';
import '../effective_device_pixel_ratio.dart';
import '../widgets/owning_axis_grip.dart';
import '../repaint_props.dart';

/// How a grip reads right now. The ONLY thing a state change moves is the
/// ink (R28 #3) — geometry is constant, so this is the whole visual state.
enum BlockEdgeGripInk { rest, hovered, dragging }

/// 🚨★★★I-43 (유저 2026-09-23): THE EDGE IS A TRIANGLE IN THE BLOCK'S CORNER.
///
/// > 「줌 작아지면 특히 프레임이름이랑 엣지 겹치는거나, 엣지끼리 겹치는거나,
/// > 코마텍스트랑 엣지랑 겹치는 등의 문제가 너무 신경쓰였음 … 엣지를
/// > 삼각형으로 바꿔서 왼쪽아래, 오른쪽위에 두는것임. 그러면 안겹치니까」
///
/// The name sits in the middle of the first cell and the 코마 number at the
/// far end of the last one. The start edge takes the first cell's far corner
/// (the timeline's bottom-left), the end edge the last cell's near corner
/// (its top-right) — the two corners nothing else uses.
///
/// 🚨A THIRD OF A CELL ALONG THE FRAME AXIS, HALF THE ROW ACROSS IT (유저
/// 2026-09-23, the same day): 「지금 세로 1/3, 가로 1/2인데, 그게아니라 세로
/// 1/2, 가로 1/3로 해서 모서리의 방향같은게 좌우로 향한다는 느낌내고싶어」 —
/// the long leg runs across, so the wedge points along the frame axis.
/// ↩️It shipped as half a cell by a third of the row (「세로길이가 한 칸
/// 세로의 1/3크기, 가로가 한 칸 가로의 1/2」).
///
/// ↩️Before that it was a 3.5px bar 2.5px inside each edge, 55% of the row
/// tall: constant pixels, so at a third-scale zoom one bar covered the name,
/// the number and the other bar of a one-frame block.
///
/// 🚨★★★100%'S SIZE AT EVERY ZOOM (유저 2026-09-26): 「지금 가로길이를
/// 1칸기준으로 했는데, 100%일땐 좋은데 10%등 줄일수록 1칸기준으로 하니까 너무
/// 가로가 작거든? 그래서 블록 이름 텍스트가 칸 넘어서 크기 지키는거마냥 크기
/// 최대한 지키게하고싶어 … 정해진 크기대로 유지하다가, 1코마처럼 공간
/// 부족하면 … 그냥 가로 1칸 차지하도록 해도되고」 — the length along the
/// frame axis is the third of a cell it had at 100%, kept at every zoom the
/// way a block's name keeps its type; a block too short for it gives the
/// grip one cell ([TimelineFrameSpanPlacement.fitsIn]). ↩️The third was of
/// the CURRENT cell until then, so at 10% the wedge was under a pixel wide.
/// Across it is still half the paper.
const double _gripMainExtent = TimelineZoomLimits.defaultPixelsPerFrame / 3;
const double _gripCrossShare = 1 / 2;

/// Where a block-edge grip sits, as a frame-span placement: a box 100%'s
/// third of a cell along the frame axis — one cell in a block shorter than
/// that — and half the block's PAPER across it, in the paper's corner.
///
/// ★THE BOX IS THE GRIP (유저 답 2026-09-23: 「(가) 삼각형 상자 — 보이는 것 =
/// 잡는 것」): the triangle fills half of it, and a press anywhere in it takes
/// the edge. ⛔No floor and no cap. The strip this replaced carried both (a
/// third of a cell, at least 6px, at most 12px) because its bar was narrower
/// than the strip it answered in, and B5②/B6 (2026-08-17) was that bar
/// overhanging its strip at the storyboard's zoom. A mark that IS its box
/// cannot overhang it. (The 09-26 size is not a floor under a proportion —
/// it IS the size, and the one-cell answer is the block's, not a cap's.)
///
/// 🚨I-44: [crossAxisExtent] is the PAPER's — the box the block's paper
/// fills across its host. A timeline row's paper stops short of the row
/// seam the grid sheet draws under the row, so the rows hand in
/// [timelineRowPaperExtent] of their own height; the storyboard's cut row
/// hands in its whole plate, which no seam crosses. A triangle measured
/// on the wrong box stands a seam's width off the corner it has to be (유저
/// 2026-09-23: 「모서리랑 블록이랑 모서리가 통일안되서 … 확실하게 통일해줘」).
/// ↩️The cut row handed in its picture strip until 유저 2026-09-25 (「제대로
/// 컷블록의 위치에 존재하지않아. 내부에 존재하는느낌」): the triangles sat in
/// the strip's corners, inside the plate.
///
/// THE law for both kinds of mount: the sparse rows lay a widget out by it,
/// and the dense rows' chrome resolves the same placement through
/// [timelineFrameSpanRect] — one statement, two readers.
TimelineFrameSpanPlacement timelineBlockEdgeGripPlacement({
  required TimelineBlockEdge edge,
  required int startIndex,
  required int endIndexExclusive,
  required double crossAxisExtent,
}) {
  final start = edge == TimelineBlockEdge.start;
  final across = crossAxisExtent * _gripCrossShare;
  return TimelineFrameSpanPlacement(
    startIndex: start ? startIndex : endIndexExclusive,
    mainExtent: _gripMainExtent,
    fitsIn: (startIndex: startIndex, endIndexExclusive: endIndexExclusive),
    anchorAtTrailingEdge: !start,
    crossInset: start ? crossAxisExtent - across : 0,
    crossExtent: across,
  );
}

/// The corner radius of the block a grip [box] sits in — THE block corner
/// ([timelineBlockCornerRadiusAt]) over cells of [frameCellExtent], on the
/// paper the box takes half of.
///
/// ↩️It read the cell back off the box (a third of a cell along) until the
/// box stopped following the cell (유저 2026-09-26, above): a box of 100%'s
/// size says nothing about the zoom, so the cell is handed in.
double blockEdgeGripCornerRadius(
  Rect box, {
  required Axis axis,
  required double frameCellExtent,
}) => timelineBlockCornerRadiusAt(
  cellExtent: frameCellExtent,
  crossExtent: extentAcross(axis, box.size) / _gripCrossShare,
).x;

/// A grip triangle's ROUND END: the corner of the paper under it, and how
/// far past that circle its ink reaches ([blockEdgeGripPath]).
///
/// [paperCorner] is that paper's radius — the block's own
/// ([blockEdgeGripCornerRadius]), or, where the paper is not the block the
/// box was laid out for, that paper's: the storyboard's cut plate, round at
/// the cut's ends and straight between its panels ([TimelineGripPaper]).
typedef BlockEdgeGripRound = ({double paperCorner, double bleed});

/// The grip's triangle inside its [box]: the right angle in the block's
/// corner, the two legs along the block's own edges, and the corner cut by
/// the PAPER'S OWN CIRCLE — the triangle is the paper's corner, inked.
///
/// 🚨유저 2026-09-23: 「모서리 호버하니까 티나는데 오른쪽 엣지라면 모서리의
/// 오른쪽윗부분에 흰 블록 배경 보이거든? 이거 모서리랑 블록이랑 모서리가
/// 통일안되서 그런거같은데 확실하게 통일해줘. 모양새.」 Two things showed there,
/// and both are answered here:
///
///  * ⛔THE MARK ROUNDED ITSELF. It clamped its own radius to its legs, so
///    wherever a leg was shorter than the paper's radius the ink kept a
///    sharper corner than the paper it sits on — and with a third of a cell
///    along, every zoom under 75% is that case. The corner is the paper's
///    circle now, cut where it crosses the hypotenuse, whatever the legs are.
///  * ⛔THE PAPER'S EDGE SHOWED THROUGH. Two shapes anti-aliased on the same
///    curve blend twice: the paper's edge pixel is already part paper, and
///    the mark covering it by the same fraction leaves that fraction of paper
///    lit. 🧪Measured through the tile rasterizer's reference at 1×/1.5×/2×:
///    a hovered mark on the white paper wore a light rim along its round end
///    at every ratio — the paper's white leaking up to a quarter strength.
///    [BlockEdgeGripRound.bleed] grows the ROUND END ONLY by that much — one
///    device pixel is the paper's whole edge ramp — so the mark covers the
///    paper's edge pixels outright and its own edge falls on the row's
///    ground. The straight legs stay exactly on the block's edges: there the
///    next cell's grid line and the row above sit a pixel away, and a bleed
///    would ink them.
///
/// Stated along the frame axis and across it, so the X-sheet reads it turned
/// on its side like every other mark: the start edge's corner is the box's
/// LEADING end on its FAR side (the timeline's bottom-left, the X-sheet's
/// top-right), the end edge's the TRAILING end on the NEAR side (top-right,
/// bottom-left).
Path blockEdgeGripPath(
  Rect box, {
  required TimelineBlockEdge edge,
  required Axis axis,
  required BlockEdgeGripRound round,
}) {
  final horizontal = axis == Axis.horizontal;
  final a0 = horizontal ? box.left : box.top;
  final a1 = horizontal ? box.right : box.bottom;
  final c0 = horizontal ? box.top : box.left;
  final c1 = horizontal ? box.bottom : box.right;
  final start = edge == TimelineBlockEdge.start;
  // (u, v): how far in from the block's corner — along the frame axis, and
  // across the row.
  Offset at(Offset uv) => offsetAlong(
    axis,
    along: start ? a0 + uv.dx : a1 - uv.dx,
    across: start ? c1 - uv.dy : c0 + uv.dy,
  );
  final legAlong = a1 - a0;
  final legAcross = c1 - c0;
  final path = Path();
  if (legAlong <= 0 || legAcross <= 0) {
    return path;
  }
  void moveTo(Offset uv) => path.moveTo(at(uv).dx, at(uv).dy);
  void lineTo(Offset uv) => path.lineTo(at(uv).dx, at(uv).dy);
  final alongEnd = Offset(legAlong, 0);
  final acrossEnd = Offset(0, legAcross);

  final radius = round.paperCorner;
  final reach = radius + round.bleed;
  if (radius <= 0 || reach >= radius * math.sqrt2) {
    // No paper corner to follow — or a bleed wide enough to swallow it.
    moveTo(alongEnd);
    lineTo(acrossEnd);
    lineTo(Offset.zero);
    path.close();
    return path;
  }
  final center = Offset(radius, radius);
  // Where the circle meets each leg, the same distance in from the corner.
  final inset = radius - math.sqrt(reach * reach - radius * radius);
  // The minor arc of the circle from [from] to [to], as the conic that IS it:
  // the tangents' meeting point for control, the half-angle's cosine for
  // weight. With no bleed that is the corner itself and √½.
  void arcTo(Offset from, Offset to) {
    final toMid = (from + to) / 2 - center;
    final control = center + toMid * (reach * reach / toMid.distanceSquared);
    path.conicTo(
      at(control).dx,
      at(control).dy,
      at(to).dx,
      at(to).dy,
      toMid.distance / reach,
    );
  }

  // Where the hypotenuse crosses the circle: t runs from the along leg's end
  // (0) to the across leg's end (1).
  Offset onHypotenuse(double t) =>
      Offset(legAlong * (1 - t), legAcross * t);
  final p = legAlong - radius;
  final qa = legAlong * legAlong + legAcross * legAcross;
  final qb = -2 * (legAlong * p + legAcross * radius);
  final qc = p * p + radius * radius - reach * reach;
  final disc = qb * qb - 4 * qa * qc;
  final root = disc > 0 ? math.sqrt(disc) : 0.0;
  final enters = onHypotenuse((-qb - root) / (2 * qa));
  final leaves = onHypotenuse((-qb + root) / (2 * qa));

  final alongEndCut = legAlong < inset;
  final acrossEndCut = legAcross < inset;
  if (!alongEndCut && !acrossEndCut) {
    moveTo(alongEnd);
    lineTo(acrossEnd);
    lineTo(Offset(0, inset));
    arcTo(Offset(0, inset), Offset(inset, 0));
  } else if (!acrossEndCut) {
    // The along leg is shorter than the paper's round: the circle takes the
    // tip, and the hypotenuse runs from where it leaves the paper.
    moveTo(enters);
    lineTo(acrossEnd);
    lineTo(Offset(0, inset));
    arcTo(Offset(0, inset), enters);
  } else if (!alongEndCut) {
    moveTo(alongEnd);
    lineTo(leaves);
    arcTo(leaves, Offset(inset, 0));
  } else if (disc > 0 && enters.dy >= 0 && leaves.dx >= 0) {
    // Both legs inside the round: only the sliver the circle keeps.
    moveTo(enters);
    lineTo(leaves);
    arcTo(leaves, enters);
  } else {
    return path;
  }
  path.close();
  return path;
}

/// Quiet at rest, full on hover, accent while dragging — state carried by
/// ink ALONE (R28 #3). 유저 답 2026-09-23 kept exactly this ladder for the
/// triangle (「반투명 먹」).
///
/// [ground] is the color of what the grip sits ON, not the theme's
/// brightness (feedback #11 gave it two inks by surface; 2026-08-17 made
/// the pick the text's own ground law, [timelineTextOnColor]). A paper
/// block takes the black mark — the purple paper included — and the dark
/// cut-block strip takes the white one. The white OUTLINE the bar used to
/// wear went with the pick ("애초에 통일하기로 했잖아"): the ink already
/// contrasts with the ground it was chosen against, so a silhouette had
/// nothing left to say. The accent of a live drag reads on both and is
/// left alone: a drag in progress must not change colour with its row.
Color blockEdgeGripColor(
  BlockEdgeGripInk ink, {
  Color ground = timelineDrawingHeldColor,
}) {
  if (ink == BlockEdgeGripInk.dragging) {
    return timelineSelectedFrameBorderColor;
  }
  final base = timelineTextOnColor(ground);
  final lightInk = base == timelineTextOnDarkGroundColor;
  // A light mark needs more alpha than a dark one to read as the same
  // weight — the asymmetry the cut block's outline carried (R26 #8) until
  // the outline went (2026-09-26).
  return base.withValues(
    alpha: ink == BlockEdgeGripInk.hovered
        ? (lightInk ? 0.98 : 0.95)
        : (lightInk ? 0.55 : 0.38),
  );
}

/// Draws one grip's [triangle] ([blockEdgeGripPath]) in its ink. THE drawing
/// source, shared by the widget grip and the dense rows' row-wide chrome
/// painter.
///
/// ⛔No outline arm (2026-08-17). R9 #11 wrapped the bar in the text's
/// white outline so a resting grip read on a busy block; #1104 took the
/// text's outline off and the bar kept its — the last white silhouette on
/// the blocks, which the user called out on device. The ground law is the
/// visibility answer now, for the grip exactly as for the writing.
void paintBlockEdgeGrip(
  Canvas canvas,
  Path triangle,
  BlockEdgeGripInk ink, {
  Color ground = timelineDrawingHeldColor,
}) {
  canvas.drawPath(
    triangle,
    Paint()..color = blockEdgeGripColor(ink, ground: ground),
  );
}

/// The widget grip's triangle, painted rather than boxed: the sparse
/// surfaces (storyboard SE and transition strips, instruction rows) still
/// mount a widget per grip, and this keeps their pixels identical to the
/// painted rows'.
class BlockEdgeGripPainter extends CustomPainter with RepaintOnProps {
  BlockEdgeGripPainter({
    required this.edge,
    required this.axis,
    required this.ink,
    required this.devicePixelRatio,
    required this.geometry,
  }) : super(repaint: geometry);

  final TimelineBlockEdge edge;
  final Axis axis;
  final BlockEdgeGripInk ink;

  /// For the round end's one-device-pixel bleed ([blockEdgeGripPath]).
  final double devicePixelRatio;

  /// The LIVE frame-axis geometry, for the round end: the block's corner
  /// follows the cell, and the box — 100%'s size since 2026-09-26 — no
  /// longer does, so a zoom step may leave the box as it was and still
  /// owe the corner a repaint.
  ///
  /// ↩️The box WAS the geometry — a third of a cell along — so nothing
  /// needed the cell passed in (that is what used to drag every grip
  /// through a rebuild on each zoom step), and a zoom step that resized the
  /// box repainted it. Listening keeps that: no rebuild, only a repaint.
  final ValueListenable<TimelineFrameGeometry> geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    paintBlockEdgeGrip(
      canvas,
      blockEdgeGripPath(
        box,
        edge: edge,
        axis: axis,
        round: (
          paperCorner: blockEdgeGripCornerRadius(
            box,
            axis: axis,
            frameCellExtent: geometry.value.frameCellExtent,
          ),
          bleed: 1 / devicePixelRatio,
        ),
      ),
      ink,
    );
  }

  @override
  // The cell by VALUE: a host that rebuilds on a zoom hands in a fresh
  // handle, and the new cell is what must repaint — not the new object.
  Object get props => (
    edge,
    axis,
    ink,
    devicePixelRatio,
    geometry.value.frameCellExtent,
  );
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

/// The ONE block-edge grip (R28 #3): the triangle in a block's start or end
/// corner, with the whole hover/drag state machine.
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
    required this.geometry,
    required this.hooks,
    this.axis = Axis.horizontal,
  });

  final TimelineBlockEdge edge;

  /// The LIVE frame-axis geometry — its cell READ AT DRAG TIME rather than
  /// captured: the grip fills whatever box its mount hands it, and a mount
  /// that positions by frame span (the sparse rows) does not rebuild it on a
  /// zoom step — so a value frozen at build time would convert pixels to
  /// frames at the wrong scale. The mark's round end reads the same cell
  /// ([BlockEdgeGripPainter.geometry]).
  ///
  /// ↩️A `double Function()` for the cell until 2026-09-26, when the mark
  /// started needing it too — and a function cannot say when it changed.
  final ValueListenable<TimelineFrameGeometry> geometry;

  final BlockEdgeGripHooks hooks;

  /// The frame axis direction; geometry and gesture transpose with it.
  final Axis axis;

  // ⛔No device set (F-163 재발, 유저 2026-09-23: 「버튼은 무조건
  // 강한클레임」). ↩️The timeline mount passed its edit-pan devices, so while
  // one finger scrolls the timeline a finger on a grip went to the scroller
  // (UI-R22F); only the storyboard's mount left it open. A grip is a control,
  // and a press on a control is the control's on every device.

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
    required this.geometry,
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

  /// See [BlockEdgeGrip.geometry].
  final ValueListenable<TimelineFrameGeometry> geometry;

  final TimelineCommaDragCallbacks callbacks;

  /// The frame axis direction; geometry and gesture transpose with it.
  final Axis axis;

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
        geometry: geometry,
        axis: axis,
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

  /// R27 #11: pointer resting on the grip — lights the mark.
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
      frameCellExtent: widget.geometry.value.frameCellExtent,
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
    // The triangle is PAINTED through the shared helpers (R28 #4 tier 2) so
    // the dense rows — which draw all their grips in one row-wide painter —
    // and these widget-mounted grips cannot drift apart.
    final mark = CustomPaint(
      painter: BlockEdgeGripPainter(
        edge: widget.edge,
        axis: widget.axis,
        ink: _dragging || _pressed
            ? BlockEdgeGripInk.dragging
            : _hovered
            ? BlockEdgeGripInk.hovered
            : BlockEdgeGripInk.rest,
        devicePixelRatio: EffectiveDevicePixelRatio.of(context),
        geometry: widget.geometry,
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
        // 🚨★★★**THE PRESS IS THE GRIP'S, SCROLLING INCLUDED** (F-163,
        // 유저 2026-09-18: 「엣지 클릭한채로 세로이동하면 **세로스크롤
        // 작동함** … **해당 법 재사용/통일해서**」). ↩️It mounted a plain
        // single-axis drag, so a vertical pull moved 0 along this grip's
        // own axis, never reached a threshold, and handed the timeline's
        // vertical scroller a walkover. [OwningAxisGrip] is the splitter's
        // own pair — the claim and the eager recogniser — reused.
        child: OwningAxisGrip(
          axis: widget.axis,
          configure: (recognizer) {
            recognizer
              // Drag from the DOWN position (R10): the slop the recognizer
              // spends winning the arena is real travel of the hand, and
              // Flutter's default throws it away — so the edge settled
              // ~18px BEHIND the pointer and stayed there for the whole
              // gesture. The timeline's other edit drags already read
              // `down`, the cut-end handle among them — and that one is an
              // edge too.
              ..dragStartBehavior = DragStartBehavior.down
              ..onStart = ((_) {
                _startDrag();
              })
              ..onUpdate = ((details) {
                _updateDrag(details.primaryDelta!);
              })
              ..onEnd = ((_) {
                _endDrag();
              })
              ..onCancel = _cancelDrag;
          },
          child: mark,
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
