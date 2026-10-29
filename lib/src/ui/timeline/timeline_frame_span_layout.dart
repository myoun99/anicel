import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'axis_turn.dart';
import 'timeline_frame_geometry.dart';

/// Where a child sits along the FRAME axis, in frame terms.
///
/// Everything resolves against the live geometry at LAYOUT time, which is the
/// point: a span overlay described this way follows a zoom step without its
/// widget rebuilding.
@immutable
class TimelineFrameSpanPlacement {
  const TimelineFrameSpanPlacement({
    required this.startIndex,
    this.endIndexExclusive,
    this.mainExtent,
    this.mainInset = 0,
    this.anchorAtTrailingEdge = false,
    this.crossInset = 0,
    this.crossExtent,
    this.fitsIn,
    this.atMost,
  }) : assert(
         endIndexExclusive != null || mainExtent != null,
         'a placement needs a span end or a fixed extent',
       );

  /// The frame whose edge anchors this child.
  final int startIndex;

  /// The frame whose leading edge ends the span — the usual case, and the
  /// only one that stretches with the zoom by construction. One cell is the
  /// span to the next frame: ↩️a size in cells (cells × the zoom's width)
  /// missed the law's cells once they were not whole pixels (F-220).
  final int? endIndexExclusive;

  /// Fixed main-axis size in pixels, for chrome that must not scale (a
  /// marker glyph).
  final double? mainExtent;

  /// Extra offset from the anchor edge, in pixels.
  final double mainInset;

  /// Whether the resolved extent ends AT the anchor instead of starting from
  /// it — a block's END grip, a marker hanging off a span's tail.
  final bool anchorAtTrailingEdge;

  /// Cross-axis inset, and size (null = the row's full cross extent).
  final double crossInset;
  final double? crossExtent;

  /// The frames a fixed [mainExtent] has to fit in. While they are at least
  /// that long the child keeps its size at every zoom; when they are
  /// shorter it takes ONE CELL instead — a run's buttons BESIDE a run too
  /// short to hold them (`timelineRunClusterRect`).
  ///
  /// ↩️A block edge's grip asked this too (유저 2026-09-26: 「1코마처럼 공간
  /// 부족하면 … 그냥 가로 1칸 차지하도록」) until F-295 gave it [atMost]: a
  /// grip stands INSIDE its block, and one cell of a block three cells long
  /// was two cells smaller than it had to be.
  final ({int startIndex, int endIndexExclusive})? fitsIn;

  /// The frames a fixed [mainExtent] may not outgrow: the child keeps its
  /// size while they hold it and takes ALL of them when they do not — a
  /// block edge's grip in a block shorter than the grip (F-295, 유저
  /// 2026-10-05: 「지금 엄청 작은거있는데 최대한 크기 유지하도록. 띠의
  /// 앞부분/끝부분 닿아도 아무문제없으니 그냥 닿게해서 최대한 크기
  /// 유지하도록」).
  final ({int startIndex, int endIndexExclusive})? atMost;

  @override
  bool operator ==(Object other) =>
      other is TimelineFrameSpanPlacement &&
      other.startIndex == startIndex &&
      other.endIndexExclusive == endIndexExclusive &&
      other.mainExtent == mainExtent &&
      other.mainInset == mainInset &&
      other.anchorAtTrailingEdge == anchorAtTrailingEdge &&
      other.crossInset == crossInset &&
      other.crossExtent == crossExtent &&
      other.fitsIn == fitsIn &&
      other.atMost == atMost;

  @override
  int get hashCode => Object.hash(
    startIndex,
    endIndexExclusive,
    mainExtent,
    mainInset,
    anchorAtTrailingEdge,
    crossInset,
    crossExtent,
    fitsIn,
    atMost,
  );
}

class TimelineFrameSpanParentData extends ContainerBoxParentData<RenderBox> {
  TimelineFrameSpanPlacement? placement;
}

/// The rect [placement] resolves to under [frames], in a row [crossAxisExtent]
/// across — THE resolution.
///
/// The span layout lays its children out by it and the dense rows' edit
/// chrome hit-tests by it, so an edge grip placed as a widget on a sparse row
/// and one painted by a dense row's chrome land on the same pixels by
/// construction rather than by a parity test between two formulas.
Rect timelineFrameSpanRect(
  TimelineFrameSpanPlacement placement,
  TimelineFrameGeometry frames, {
  required double crossAxisExtent,
  required Axis axis,
}) {
  final anchor = frames.edgeAt(placement.startIndex) + placement.mainInset;
  final end = placement.endIndexExclusive;
  var mainExtent = end != null
      ? frames.edgeAt(end) - frames.edgeAt(placement.startIndex)
      : placement.mainExtent!;
  if (placement.fitsIn case final room?
      when frames.edgeAt(room.endIndexExclusive) -
              frames.edgeAt(room.startIndex) <
          mainExtent) {
    // The one cell the anchor edge bounds, as the law laid it (F-220).
    final cell = placement.anchorAtTrailingEdge
        ? placement.startIndex - 1
        : placement.startIndex;
    mainExtent = frames.edgeAt(cell + 1) - frames.edgeAt(cell);
  }
  if (placement.atMost case final room?) {
    final most =
        frames.edgeAt(room.endIndexExclusive) - frames.edgeAt(room.startIndex);
    if (most < mainExtent) {
      mainExtent = most;
    }
  }
  if (mainExtent < 0) {
    mainExtent = 0;
  }
  final main = placement.anchorAtTrailingEdge ? anchor - mainExtent : anchor;
  final cross = placement.crossExtent ?? crossAxisExtent;
  return rectAlong(
    axis,
    along: (from: main, to: main + mainExtent),
    across: (from: placement.crossInset, to: placement.crossInset + cross),
  );
}

/// Positions its children by frame span off the LIVE geometry.
///
/// This is the sparse rows' counterpart to the painted rows' painter: the SE
/// name boxes, dialogue, waveforms, drop targets, CAM chips and edge grips
/// stay widgets, but their positions resolve during LAYOUT instead of being
/// baked in at build time. That is what lets those rows keep their memo
/// through a zoom step — before this, a zoom moved a build-time scalar and
/// every span widget in every sparse row was reconstructed (measured at 24
/// layers: three sparse rows owned 156 of a zoom step's 439 rebuilds and 141
/// of its 272 layouts).
///
/// Both orientations share it: the horizontal timeline row and the X-sheet
/// column differ only by [axis], exactly like every other frame-axis widget.
class TimelineFrameSpanLayout extends MultiChildRenderObjectWidget {
  const TimelineFrameSpanLayout({
    super.key,
    required this.geometry,
    required this.crossAxisExtent,
    required this.axis,
    required super.children,
  });

  final TimelineFrameGeometryHandle geometry;
  final double crossAxisExtent;
  final Axis axis;

  @override
  RenderTimelineFrameSpanLayout createRenderObject(BuildContext context) =>
      RenderTimelineFrameSpanLayout(
        geometry: geometry,
        crossAxisExtent: crossAxisExtent,
        axis: axis,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTimelineFrameSpanLayout renderObject,
  ) => renderObject
    ..geometry = geometry
    ..crossAxisExtent = crossAxisExtent
    ..axis = axis;
}

/// A span layer for surfaces that have no LIVE geometry handle: the dialog
/// previews and the storyboard's strips, which know their cell extent as a
/// plain number and rebuild when it changes.
///
/// It exists so those surfaces mount the same span vocabulary as the rows
/// instead of keeping a parallel set of `Positioned` math — the overlays are
/// shared code, and this is what lets them stay shared.
class TimelineFixedFrameSpanLayer extends StatefulWidget {
  const TimelineFixedFrameSpanLayer({
    super.key,
    required this.geometry,
    required this.crossAxisExtent,
    required this.axis,
    required this.children,
  });

  final TimelineFrameGeometry geometry;
  final double crossAxisExtent;
  final Axis axis;
  final List<Widget> children;

  @override
  State<TimelineFixedFrameSpanLayer> createState() =>
      _TimelineFixedFrameSpanLayerState();
}

class _TimelineFixedFrameSpanLayerState
    extends State<TimelineFixedFrameSpanLayer> {
  late final TimelineFrameGeometryHandle _handle = ValueNotifier(
    widget.geometry,
  );

  @override
  void didUpdateWidget(covariant TimelineFixedFrameSpanLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _handle.value = widget.geometry;
  }

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TimelineFrameSpanLayout(
    geometry: _handle,
    crossAxisExtent: widget.crossAxisExtent,
    axis: widget.axis,
    children: widget.children,
  );
}

/// Gives one child its [TimelineFrameSpanPlacement] — `Positioned`'s role,
/// for [TimelineFrameSpanLayout].
class TimelineFrameSpan extends ParentDataWidget<TimelineFrameSpanParentData> {
  const TimelineFrameSpan({
    super.key,
    required this.placement,
    required super.child,
  });

  final TimelineFrameSpanPlacement placement;

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData! as TimelineFrameSpanParentData;
    if (parentData.placement == placement) {
      return;
    }
    parentData.placement = placement;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => TimelineFrameSpanLayout;
}

class RenderTimelineFrameSpanLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, TimelineFrameSpanParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          TimelineFrameSpanParentData
        >,
        TimelineFrameAxisRenderMixin {
  RenderTimelineFrameSpanLayout({
    required TimelineFrameGeometryHandle geometry,
    required double crossAxisExtent,
    required Axis axis,
  }) {
    this.geometry = geometry;
    this.crossAxisExtent = crossAxisExtent;
    this.axis = axis;
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! TimelineFrameSpanParentData) {
      child.parentData = TimelineFrameSpanParentData();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  /// The rect [placement] resolves to under [frames] — the single source the
  /// layout and the tests both read.
  Rect rectFor(
    TimelineFrameSpanPlacement placement,
    TimelineFrameGeometry frames,
  ) => timelineFrameSpanRect(
    placement,
    frames,
    crossAxisExtent: crossAxisExtent,
    axis: axis,
  );

  /// How far along the frame axis the children reach, free of the window
  /// ([performLayout]) — what [paint] asks whether to clip.
  ({double from, double to})? _reach;

  /// 🚨THE CHILDREN ARE LAID FREE OF THE WINDOW (frame-axis-box-at-window-
  /// size, 2026-10-30): each at its rect with the window's origin added back,
  /// and painted, hit and placed back by where the window stands now
  /// ([windowShift]) — so a window that moved lays nothing out here
  /// ([TimelineFrameAxisRenderMixin]).
  @override
  void performLayout() {
    final frames = layOutUnder();
    final free = offsetAlong(axis, along: frames.windowOriginPx, across: 0);
    ({double from, double to})? reach;
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as TimelineFrameSpanParentData;
      final placement = parentData.placement;
      if (placement == null) {
        // A child without a placement is a bug in the caller, not a crash:
        // give it nothing and leave it at the origin.
        child.layout(const BoxConstraints.tightFor(width: 0, height: 0));
        parentData.offset = free;
        child = parentData.nextSibling;
        continue;
      }
      final rect = rectFor(placement, frames).shift(free);
      child.layout(BoxConstraints.tight(rect.size));
      parentData.offset = rect.topLeft;
      final (start, end) = axis == Axis.horizontal
          ? (rect.left, rect.right)
          : (rect.top, rect.bottom);
      reach = reach == null
          ? (from: start, to: end)
          : (from: math.min(reach.from, start), to: math.max(reach.to, end));
      child = parentData.nextSibling;
    }
    _reach = reach;
  }

  /// Whether a child of a WINDOWED row runs past its window along the frame
  /// axis where the window stands now — what [paint] clips.
  bool get _runsPastTheWindow {
    final reach = _reach;
    final frames = geometry.value;
    if (reach == null || !frames.isWindowed) {
      return false;
    }
    final origin = frames.windowOriginPx;
    return reach.from - origin < 0 ||
        reach.to - origin > extentAlong(axis, size);
  }

  final LayerHandle<ClipRectLayer> _windowClip = LayerHandle<ClipRectLayer>();

  /// 🚨I-57 (10-13, profile, the user's project): a span longer than the
  /// window — a sound running on far past the cut — is drawn as far as the
  /// window and no further, so a painter that reads its canvas's clip knows
  /// what of it can be seen (`WaveformPainter`: a long sound's band was
  /// 6–20ms of a cut crossing's frame, built whole at every paint).
  ///
  /// Only a WINDOWED row, and only along the frame axis: past the window is
  /// off-screen by construction ([RenderTimelineFrameAxisBox] — the window
  /// covers the viewport with a margin, and the row is painted again when it
  /// moves), so the clip hides nothing anyone sees. A box that is not
  /// windowed spans its whole content, and across the axis what a span draws
  /// is not this clip's question — it reaches as far as it always did.
  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_runsPastTheWindow) {
      _windowClip.layer = null;
      _paintChildren(context, offset);
      return;
    }
    const largest = Rect.largest;
    _windowClip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      rectAlong(
        axis,
        along: (from: 0, to: extentAlong(axis, size)),
        across: (
          from: startAcross(axis, largest),
          to: endAcross(axis, largest),
        ),
      ),
      _paintChildren,
      oldLayer: _windowClip.layer,
    );
  }

  /// The children where the window stands now ([performLayout]).
  void _paintChildren(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset - windowShift);

  @override
  void dispose() {
    _windowClip.layer = null;
    super.dispose();
  }

  /// Paint, hit-test and the paint transform read the SAME place for a
  /// child — its laid-out offset back by [windowShift] — so it answers a
  /// pointer, and says where it is, where it is drawn.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final shift = windowShift;
    var child = lastChild;
    while (child != null) {
      final parentData = child.parentData! as TimelineFrameSpanParentData;
      final hitChild = child;
      if (result.addWithPaintOffset(
        offset: parentData.offset - shift,
        position: position,
        hitTest: (result, transformed) =>
            hitChild.hitTest(result, position: transformed),
      )) {
        return true;
      }
      child = parentData.previousSibling;
    }
    return false;
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    final offset =
        (child.parentData! as TimelineFrameSpanParentData).offset -
        windowShift;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }
}
