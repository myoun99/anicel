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
  });

  /// Main-axis extent of one frame cell (cell width in the horizontal
  /// timeline, frame row height in the X-sheet).
  final double frameCellExtent;

  final int frameStartIndex;
  final int frameEndIndexExclusive;
  final double leadingFrameSpacerWidth;
  final double trailingFrameSpacerWidth;

  /// The row's total main-axis extent, spacers included.
  double get mainExtent =>
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

  @override
  bool operator ==(Object other) =>
      other is TimelineFrameGeometry &&
      other.frameCellExtent == frameCellExtent &&
      other.frameStartIndex == frameStartIndex &&
      other.frameEndIndexExclusive == frameEndIndexExclusive &&
      other.leadingFrameSpacerWidth == leadingFrameSpacerWidth &&
      other.trailingFrameSpacerWidth == trailingFrameSpacerWidth;

  @override
  int get hashCode => Object.hash(
    frameCellExtent,
    frameStartIndex,
    frameEndIndexExclusive,
    leadingFrameSpacerWidth,
    trailingFrameSpacerWidth,
  );

  @override
  String toString() =>
      'TimelineFrameGeometry(cell $frameCellExtent, '
      '[$frameStartIndex, $frameEndIndexExclusive), '
      'spacers $leadingFrameSpacerWidth/$trailingFrameSpacerWidth)';
}

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

  BoxConstraints _innerConstraints(BoxConstraints constraints) {
    final main = _geometry.value.mainExtent;
    return BoxConstraints.tightFor(
      width: _axis == Axis.horizontal ? main : _crossAxisExtent,
      height: _axis == Axis.horizontal ? _crossAxisExtent : main,
    ).enforce(constraints);
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = _innerConstraints(constraints).smallest;
      return;
    }
    child.layout(_innerConstraints(constraints), parentUsesSize: true);
    size = child.size;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _axis == Axis.horizontal ? _geometry.value.mainExtent : _crossAxisExtent;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      computeMinIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _axis == Axis.horizontal ? _crossAxisExtent : _geometry.value.mainExtent;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      child?.getDryLayout(_innerConstraints(constraints)) ??
      _innerConstraints(constraints).smallest;
}
