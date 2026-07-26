import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

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
    this.mainExtentCells,
    this.mainExtent,
    this.maxMainExtent,
    this.mainInsetCells = 0,
    this.mainInset = 0,
    this.anchorAtTrailingEdge = false,
    this.crossInset = 0,
    this.crossExtent,
  }) : assert(
         endIndexExclusive != null ||
             mainExtentCells != null ||
             mainExtent != null,
         'a placement needs a span end, an extent in cells, or a fixed extent',
       );

  /// The frame whose edge anchors this child.
  final int startIndex;

  /// The frame whose leading edge ends the span — the usual case, and the
  /// only one that stretches with the zoom by construction.
  final int? endIndexExclusive;

  /// Size in CELLS, for chrome that scales with the cell but is not a span
  /// (an edge grip is a third of a cell). Capped by [maxMainExtent].
  final double? mainExtentCells;

  /// Fixed main-axis size in pixels, for chrome that must not scale (a
  /// marker glyph).
  final double? mainExtent;

  /// Pixel cap on a [mainExtentCells] size.
  final double? maxMainExtent;

  /// Extra offset from the anchor edge in CELLS — how a glyph centers on its
  /// cell (0.5) at any zoom.
  final double mainInsetCells;

  /// Extra offset from the anchor edge, in pixels.
  final double mainInset;

  /// Whether the resolved extent ends AT the anchor instead of starting from
  /// it — a block's END grip, a marker hanging off a span's tail.
  final bool anchorAtTrailingEdge;

  /// Cross-axis inset, and size (null = the row's full cross extent).
  final double crossInset;
  final double? crossExtent;

  @override
  bool operator ==(Object other) =>
      other is TimelineFrameSpanPlacement &&
      other.startIndex == startIndex &&
      other.endIndexExclusive == endIndexExclusive &&
      other.mainExtentCells == mainExtentCells &&
      other.mainExtent == mainExtent &&
      other.maxMainExtent == maxMainExtent &&
      other.mainInsetCells == mainInsetCells &&
      other.mainInset == mainInset &&
      other.anchorAtTrailingEdge == anchorAtTrailingEdge &&
      other.crossInset == crossInset &&
      other.crossExtent == crossExtent;

  @override
  int get hashCode => Object.hash(
    startIndex,
    endIndexExclusive,
    mainExtentCells,
    mainExtent,
    maxMainExtent,
    mainInsetCells,
    mainInset,
    anchorAtTrailingEdge,
    crossInset,
    crossExtent,
  );
}

class TimelineFrameSpanParentData extends ContainerBoxParentData<RenderBox> {
  TimelineFrameSpanPlacement? placement;
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
        > {
  RenderTimelineFrameSpanLayout({
    required TimelineFrameGeometryHandle geometry,
    required double crossAxisExtent,
    required Axis axis,
  }) : _geometry = geometry,
       _crossAxisExtent = crossAxisExtent,
       _axis = axis;

  TimelineFrameGeometryHandle _geometry;
  TimelineFrameGeometryHandle get geometry => _geometry;
  set geometry(TimelineFrameGeometryHandle value) {
    if (identical(_geometry, value)) {
      return;
    }
    if (attached) {
      _geometry.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _geometry = value;
    markNeedsLayout();
  }

  double _crossAxisExtent;
  double get crossAxisExtent => _crossAxisExtent;
  set crossAxisExtent(double value) {
    if (_crossAxisExtent == value) {
      return;
    }
    _crossAxisExtent = value;
    markNeedsLayout();
  }

  Axis _axis;
  Axis get axis => _axis;
  set axis(Axis value) {
    if (_axis == value) {
      return;
    }
    _axis = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _geometry.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _geometry.removeListener(markNeedsLayout);
    super.detach();
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
  ) {
    final cellExtent = frames.frameCellExtent;
    final anchor =
        frames.edgeAt(placement.startIndex) +
        placement.mainInsetCells * cellExtent +
        placement.mainInset;
    final end = placement.endIndexExclusive;
    final cells = placement.mainExtentCells;
    var mainExtent = end != null
        ? frames.edgeAt(end) - frames.edgeAt(placement.startIndex)
        : cells != null
        ? cells * cellExtent
        : placement.mainExtent!;
    final cap = placement.maxMainExtent;
    if (cap != null && mainExtent > cap) {
      mainExtent = cap;
    }
    if (mainExtent < 0) {
      mainExtent = 0;
    }
    final main = placement.anchorAtTrailingEdge ? anchor - mainExtent : anchor;
    final cross = placement.crossExtent ?? _crossAxisExtent;
    return _axis == Axis.horizontal
        ? Rect.fromLTWH(main, placement.crossInset, mainExtent, cross)
        : Rect.fromLTWH(placement.crossInset, main, cross, mainExtent);
  }

  @override
  void performLayout() {
    final frames = _geometry.value;
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as TimelineFrameSpanParentData;
      final placement = parentData.placement;
      if (placement == null) {
        // A child without a placement is a bug in the caller, not a crash:
        // give it nothing and leave it at the origin.
        child.layout(const BoxConstraints.tightFor(width: 0, height: 0));
        parentData.offset = Offset.zero;
        child = parentData.nextSibling;
        continue;
      }
      final rect = rectFor(placement, frames);
      child.layout(BoxConstraints.tight(rect.size));
      parentData.offset = rect.topLeft;
      child = parentData.nextSibling;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
