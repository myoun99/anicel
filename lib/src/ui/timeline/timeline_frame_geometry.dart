import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'timeline_frame_coordinate_policy.dart';

/// The frame-axis geometry of a timeline row — everything a ZOOM STEP moves.
///
/// It travels as a [ValueListenable] rather than as constructor scalars so a
/// zoom step reaches the rows as a REPAINT/RELAYOUT instead of a rebuild
/// (R28 #4). `frameCellWidth` used to sit in the row memo key, which is
/// correct for a key made of build-time inputs and was exactly the problem:
/// every visible row missed the memo at once and re-built its whole subtree.
/// Measured at 24 layers, that rebuild was ~60% of the step; the painting the
/// rebuild existed to trigger was ~4%.
@immutable
class TimelineFrameGeometry {
  const TimelineFrameGeometry({
    required this.frameCellExtent,
    required this.frameStartIndex,
    required this.frameEndIndexExclusive,
    this.leadingFrameSpacerWidth = 0,
    this.trailingFrameSpacerWidth = 0,
    this.windowOriginPx = 0,
    this.windowExtentPx = 0,
  });

  /// Main-axis extent of one frame cell (cell width in the horizontal
  /// timeline, frame row height in the X-sheet).
  final double frameCellExtent;

  final int frameStartIndex;
  final int frameEndIndexExclusive;

  /// Main-axis offset of [frameStartIndex]'s leading edge in the ROW's own
  /// coordinates. Under a window (below) this is the content's leading spacer
  /// MINUS [windowOriginPx], so it goes negative as the view scrolls — every
  /// consumer that positions from it lands in window-local coordinates
  /// without knowing the window exists.
  final double leadingFrameSpacerWidth;
  final double trailingFrameSpacerWidth;

  /// THE frame-axis window (zoom round): where the row's laid-out box starts
  /// in content space, and how wide it is. Both zero = no window, and every
  /// getter below collapses to the pre-window behavior.
  ///
  /// The point is that [windowExtentPx] is a PIXEL quantity — viewport plus a
  /// fixed margin — so it does not move when the cell width does. A row whose
  /// box is `frames * cellWidth` re-lays-out its whole subtree on every zoom
  /// step (~25 render objects a row, measured); a row whose box is a constant
  /// window only re-lays-out the box itself and its children's constraints
  /// come back unchanged, which Flutter skips. The scrolled position rides
  /// [windowOriginPx] instead, quantized to the shared window bucket, so it
  /// moves once per bucket crossing rather than per pixel.
  final double windowOriginPx;
  final double windowExtentPx;

  bool get isWindowed => windowExtentPx > 0;

  /// The extent the row's box is LAID OUT at — the window when there is one.
  double get mainExtent => isWindowed ? windowExtentPx : contentMainExtent;

  /// The row's total main-axis extent in CONTENT space, spacers included —
  /// what the row still REPORTS as its size, so the grid's Stack, the
  /// scrolled content and every absolute overlay above see no change.
  double get contentMainExtent =>
      windowOriginPx +
      leadingFrameSpacerWidth +
      (frameEndIndexExclusive - frameStartIndex) * frameCellExtent +
      trailingFrameSpacerWidth;

  /// Row-local main-axis offset of [frameIndex]'s leading edge.
  double edgeAt(int frameIndex) => frameVisibleX(
    frameIndex: frameIndex,
    frameStartIndex: frameStartIndex,
    frameCellWidth: frameCellExtent,
    leadingFrameSpacerWidth: leadingFrameSpacerWidth,
  );

  bool contains(int frameIndex) =>
      frameIndex >= frameStartIndex && frameIndex < frameEndIndexExclusive;

  /// The frame whose cell holds [mainOffset] — [edgeAt] read backwards, and
  /// it lives beside it so the two cannot drift. Row-local coordinates, so a
  /// windowed row's scrolled offsets answer without knowing about the window.
  /// Clamped INTO the row: a drop past either end names the end frame rather
  /// than an index the row does not have.
  int frameIndexAt(double mainOffset) {
    if (frameCellExtent <= 0 || frameEndIndexExclusive <= frameStartIndex) {
      return frameStartIndex;
    }
    final cell = ((mainOffset - leadingFrameSpacerWidth) / frameCellExtent)
        .floor();
    return (frameStartIndex + cell).clamp(
      frameStartIndex,
      frameEndIndexExclusive - 1,
    );
  }

  /// The same geometry seen through a window starting at [originPx] and
  /// [extentPx] wide. Only the owner (the rows body) calls this.
  TimelineFrameGeometry windowed({
    required double originPx,
    required double extentPx,
  }) => TimelineFrameGeometry(
    frameCellExtent: frameCellExtent,
    frameStartIndex: frameStartIndex,
    frameEndIndexExclusive: frameEndIndexExclusive,
    leadingFrameSpacerWidth: leadingFrameSpacerWidth - originPx,
    trailingFrameSpacerWidth: trailingFrameSpacerWidth,
    windowOriginPx: originPx,
    windowExtentPx: extentPx,
  );

  @override
  bool operator ==(Object other) =>
      other is TimelineFrameGeometry &&
      other.frameCellExtent == frameCellExtent &&
      other.frameStartIndex == frameStartIndex &&
      other.frameEndIndexExclusive == frameEndIndexExclusive &&
      other.leadingFrameSpacerWidth == leadingFrameSpacerWidth &&
      other.trailingFrameSpacerWidth == trailingFrameSpacerWidth &&
      other.windowOriginPx == windowOriginPx &&
      other.windowExtentPx == windowExtentPx;

  @override
  int get hashCode => Object.hash(
    frameCellExtent,
    frameStartIndex,
    frameEndIndexExclusive,
    leadingFrameSpacerWidth,
    trailingFrameSpacerWidth,
    windowOriginPx,
    windowExtentPx,
  );

  @override
  String toString() =>
      'TimelineFrameGeometry(cell $frameCellExtent, '
      '[$frameStartIndex, $frameEndIndexExclusive), '
      'spacers $leadingFrameSpacerWidth/$trailingFrameSpacerWidth'
      '${isWindowed ? ', window $windowOriginPx+$windowExtentPx' : ''})';
}

/// Margin the frame-axis window keeps on both sides of the viewport.
///
/// It has to cover everything the view can reveal while the scroll offset
/// stays inside one window bucket, plus the painters' own overscan: a bucket
/// spans at most 4 cells and a cell is at most
/// [TimelinePanel.maxPixelsPerFrame] (96), so 384 + 2 cells = 576px is the
/// worst case. 1024 keeps a wide margin AND is a constant, which is the whole
/// point — a zoom-dependent margin would put the cell width back into the
/// row's constraints.
const double timelineFrameWindowMarginPx = 1024;

/// The live geometry handle a row holds. Its IDENTITY is what the row memo
/// keys on, so it must outlive the zoom steps it reports — owners keep it in
/// their `State` and republish the value.
///
/// Publishing from inside `build` is deliberate and safe HERE because every
/// listener is a render object ([TimelineFrameAxisBox], the row painters'
/// `repaint`): they mark themselves dirty for layout/paint, both of which run
/// after build in the same frame. Do NOT attach a `ValueListenableBuilder` or
/// any `setState` listener to it — that would be a rebuild during build.
typedef TimelineFrameGeometryHandle = ValueNotifier<TimelineFrameGeometry>;

/// Sizes its child along the frame axis from the live geometry.
///
/// This is the geometry's LAYOUT arm: a zoom step changes the row's total
/// width, and this render object relays that out without a single widget
/// rebuilding. Faithful to the `SizedBox` it replaced — the incoming
/// constraints still win.
class TimelineFrameAxisBox extends SingleChildRenderObjectWidget {
  const TimelineFrameAxisBox({
    super.key,
    required this.geometry,
    required this.crossAxisExtent,
    required this.axis,
    required super.child,
  });

  final TimelineFrameGeometryHandle geometry;
  final double crossAxisExtent;
  final Axis axis;

  @override
  RenderTimelineFrameAxisBox createRenderObject(BuildContext context) =>
      RenderTimelineFrameAxisBox(
        geometry: geometry,
        crossAxisExtent: crossAxisExtent,
        axis: axis,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTimelineFrameAxisBox renderObject,
  ) => renderObject
    ..geometry = geometry
    ..crossAxisExtent = crossAxisExtent
    ..axis = axis;
}

class RenderTimelineFrameAxisBox extends RenderProxyBox {
  RenderTimelineFrameAxisBox({
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

  Size _sizeFor(double main) => _axis == Axis.horizontal
      ? Size(main, _crossAxisExtent)
      : Size(_crossAxisExtent, main);

  /// What the CHILD is laid out at. Windowed, it is the constant window
  /// extent and the incoming constraints are deliberately NOT enforced: the
  /// parent's max is the content width, and clamping to it would put the
  /// content — and so the cell width — back into the child's constraints,
  /// which is the whole thing this exists to avoid. Overflow past the box is
  /// off-screen by construction (the window covers the viewport with margin)
  /// and nothing here clips.
  BoxConstraints _innerConstraints(BoxConstraints constraints) {
    final geometry = _geometry.value;
    final inner = BoxConstraints.tight(_sizeFor(geometry.mainExtent));
    return geometry.isWindowed ? inner : inner.enforce(constraints);
  }

  /// The box's OWN size stays content-space, so everything above the row —
  /// the grid Stack, the scrolled content, the absolute overlays — sees the
  /// row it always saw.
  Size _outerSize(BoxConstraints constraints) =>
      constraints.constrain(_sizeFor(_geometry.value.contentMainExtent));

  /// Where the child sits inside this box.
  Offset get _childOffset {
    final origin = _geometry.value.windowOriginPx;
    if (origin == 0) {
      return Offset.zero;
    }
    return _axis == Axis.horizontal ? Offset(origin, 0) : Offset(0, origin);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = _outerSize(constraints);
      return;
    }
    child.layout(_innerConstraints(constraints), parentUsesSize: true);
    size = _geometry.value.isWindowed ? _outerSize(constraints) : child.size;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) {
      context.paintChild(child, offset + _childOffset);
    }
  }

  /// Paint and hit-test read the SAME [_childOffset] — the two cannot drift
  /// into a row that draws in one place and answers pointers in another.
  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    final childOffset = _childOffset;
    transform.translateByDouble(childOffset.dx, childOffset.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) {
      return false;
    }
    return result.addWithPaintOffset(
      offset: _childOffset,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) => _axis == Axis.horizontal
      ? _geometry.value.contentMainExtent
      : _crossAxisExtent;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      computeMinIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => _axis == Axis.horizontal
      ? _crossAxisExtent
      : _geometry.value.contentMainExtent;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    if (_geometry.value.isWindowed) {
      return _outerSize(constraints);
    }
    return child?.getDryLayout(_innerConstraints(constraints)) ??
        _innerConstraints(constraints).smallest;
  }
}
