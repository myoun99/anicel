/// THE MODEL, in one sentence:
///
/// > The rail is always laid out at its own natural size. The splitter sets
/// > the size of a WINDOW over it, and scrolling pushes that window.
///
/// Nothing inside the rail rearranges when the window narrows — the tail is
/// simply cut off, so shrinking to the minimum leaves `A` `B` and nothing
/// else, with no `…` anywhere. An ellipsis means one thing only: a LABEL
/// overflowing its own slot.
///
/// This retires three separate mechanisms that used to answer "the panel is
/// too narrow": the x-sheet's whole-header scale-down, its per-surface
/// header layout arithmetic, and the ladder of controls that dropped out
/// one by one. The user's answer replaced all of them at once — "either way
/// the timeline panel doesn't fit when you dock it on the side" — so the
/// answer had to be common to all three surfaces.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../widgets/app_scrollbar.dart';
import '../widgets/dock_edge_splitter.dart';
import 'layer_rail_columns.dart';
import 'timeline_grid_metrics.dart';

/// The narrowest window the user can drag to: the leading cluster (the
/// section band and every control slot before the name) plus enough of the
/// name for its first character.
///
/// Derived, never typed: adding a control slot moves this floor with it.
const double layerRailMinimumWindowExtent = layerRailLeadingWidth + 14;

/// How thick a rail's own scrollbar lane is: the WIDE step, so the thumb's
/// 32px minimum has room to be grabbed — see [AppScrollbarGeometry].
const double layerRailScrollbarLaneExtent = AppScrollbarLane.wide;

/// What the FRAME area keeps whatever the rail wants: two cells at the
/// default zoom, the user's number — enough that its own scrollbar thumb
/// (32px minimum) still has somewhere to travel.
///
/// Stated in DEFAULT cell units, not live zoomed ones: measuring the
/// reserve in zoomed cells would move the rail's ceiling every time the
/// user touched the zoom slider.
const double layerRailFrameReserveExtent = 2 * timelineFrameCellWidth;

/// The rails that size themselves, one entry per PANEL.
///
/// Independent by the user's decision: the timeline, the x-sheet and the
/// storyboard each remember their own window, and the sheet no longer
/// derives its header block from the timeline's rail width.
abstract final class LayerRailId {
  static const String timeline = 'timeline';
  static const String xsheet = 'xsheet';
  static const String storyboard = 'storyboard';

  static const List<String> values = [timeline, xsheet, storyboard];
}

/// The user's chosen WINDOW size for one rail, as a listenable.
///
/// A listenable and not a metrics scalar, deliberately: `TimelineGridMetrics`
/// is a memo key on the rail rows and the legend header, so threading the
/// live splitter value through it would rebuild every visible row on every
/// drag frame — measured at ~60% of a step with 24 layers when the frame
/// geometry made the same mistake. The rows never see this value at all;
/// only the box that clips them does.
///
/// A null value means "as wide as the rail naturally is" — the state a
/// fresh install and a double-clicked splitter share, and the reason the
/// saved file simply omits rails the user never touched.
class LayerRailExtent extends ValueNotifier<double?> {
  LayerRailExtent([super.value]);

  /// How far the window has been PUSHED along the rail.
  ///
  /// Size and position of the same window, so they live together — and the
  /// separate notifier is what keeps a push from waking the layout: only
  /// the clip's Transform and the scrollbar's thumb subscribe. Not saved:
  /// a restart opens the rail at its head.
  final ValueNotifier<double> offset = ValueNotifier<double>(0);

  /// The window this rail actually gets.
  ///
  /// Two ceilings. NATURAL, because a window wider than the rail would open
  /// a gap. And [availableExtent] — what the panel has left after its own
  /// chrome and the frame area's reserve — because a rail is not allowed to
  /// overflow the panel it lives in. That second one is a LAYOUT clamp, not
  /// a stored value: shrink the panel and the rail gives ground, grow it
  /// again and the size the user chose comes back.
  double windowExtent(double naturalExtent, {double? availableExtent}) {
    final natural = math.max(naturalExtent, layerRailMinimumWindowExtent);
    var floor = layerRailMinimumWindowExtent;
    var ceiling = natural;
    if (availableExtent != null &&
        availableExtent.isFinite &&
        availableExtent >= 0) {
      ceiling = math.min(ceiling, availableExtent);
      // In a panel too small even for the floor, the panel wins: an
      // overflow stripe helps nobody.
      floor = math.min(floor, ceiling);
    }
    return (value ?? natural).clamp(floor, ceiling).toDouble();
  }

  /// Applies one splitter drag frame; positive [delta] grows the rail.
  ///
  /// Returns the part of [delta] the rail actually took. The rest is travel
  /// spent pushing against the floor or the ceiling, and [DockEdgeSplitter]
  /// holds it so the hand has to come back to the edge before the edge
  /// moves (유저, R4 #13: 커서가 스플리터까지 가고 나서 오른쪽으로 가야
  /// 이동되는 게 맞는데 지금은 바로 오른쪽으로 이동해버린다).
  double resizeBy(
    double delta, {
    required double naturalExtent,
    double? availableExtent,
  }) {
    final current = windowExtent(
      naturalExtent,
      availableExtent: availableExtent,
    );
    var ceiling = math.max(naturalExtent, layerRailMinimumWindowExtent);
    var floor = layerRailMinimumWindowExtent;
    if (availableExtent != null &&
        availableExtent.isFinite &&
        availableExtent >= 0) {
      ceiling = math.min(ceiling, availableExtent);
      floor = math.min(floor, ceiling);
    }
    final next = (current + delta).clamp(floor, ceiling).toDouble();
    final used = next - current;
    if (next != value) {
      value = next;
      // A wider window has less room to be pushed into: without this the
      // tail would stay scrolled off and snap back the next time the
      // window narrowed.
      pushTo(
        offset.value,
        naturalExtent: naturalExtent,
        availableExtent: availableExtent,
      );
    }
    return used;
  }

  /// Pushes the window to [next], clamped to what the rail can give.
  void pushTo(
    double next, {
    required double naturalExtent,
    double? availableExtent,
  }) {
    final clamped = clampOffset(
      next,
      windowExtent: windowExtent(
        naturalExtent,
        availableExtent: availableExtent,
      ),
      naturalExtent: naturalExtent,
    );
    if (clamped != offset.value) {
      offset.value = clamped;
    }
  }

  /// Back to the rail's natural size (double-click on the splitter).
  ///
  /// The push goes home with it. At the natural size there is nothing left
  /// to push into, so a surviving offset is invisible until the next
  /// narrowing drag — at which point the rail would jump to its tail.
  void reset() {
    value = null;
    offset.value = 0;
  }

  /// How far the window may be pushed along the rail.
  static double maximumOffset({
    required double windowExtent,
    required double naturalExtent,
  }) => math.max(0, naturalExtent - windowExtent);

  static double clampOffset(
    double offset, {
    required double windowExtent,
    required double naturalExtent,
  }) => offset
      .clamp(
        0.0,
        maximumOffset(windowExtent: windowExtent, naturalExtent: naturalExtent),
      )
      .toDouble();

  @override
  void dispose() {
    offset.dispose();
    super.dispose();
  }
}

/// The window itself: a box [windowExtent] long that CLIPS a rail laid out
/// at its natural extent, pushed along by [offset].
///
/// [axis] is the rail's own direction — horizontal for the timeline's and
/// the storyboard's rows, vertical for the x-sheet's stood-up column
/// headers. ACROSS that axis the window is transparent: the host's
/// constraint reaches the rail untouched and the rail's own size comes
/// back, because the rail's cross extent is the row geometry it shares
/// with the frame cells and nothing here may reinterpret it.
class LayerRailWindow extends StatelessWidget {
  const LayerRailWindow({
    super.key,
    required this.axis,
    required this.rail,
    required this.naturalExtent,
    this.availableExtent,
    required this.child,
  });

  final Axis axis;

  /// The window's size AND position. Both come from the one object so a
  /// surface cannot clip at one width while its scrollbar drives another
  /// — the hosts derive their own layout from `rail.windowExtent` too, but
  /// there is only ever the one formula.
  final LayerRailExtent rail;

  final double naturalExtent;

  /// What the panel can spare (see [LayerRailExtent.windowExtent]). Every
  /// part of one rail must be given the SAME value — the host computes it
  /// once per build and hands it to the window, the scrollbar and the
  /// splitter alike.
  final double? availableExtent;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final windowExtent = rail.windowExtent(
      naturalExtent,
      availableExtent: availableExtent,
    );
    final content = math.max(naturalExtent, windowExtent);
    // Per-pixel pushes move the paint offset only — the rail's own subtree
    // is handed through as the builder's stable child and never rebuilds.
    return ValueListenableBuilder<double>(
      valueListenable: rail.offset,
      child: child,
      builder: (context, value, child) => _RailWindowBox(
        axis: axis,
        windowExtent: windowExtent,
        naturalExtent: content,
        offset: LayerRailExtent.clampOffset(
          value,
          windowExtent: windowExtent,
          naturalExtent: content,
        ),
        child: child,
      ),
    );
  }
}

class _RailWindowBox extends SingleChildRenderObjectWidget {
  const _RailWindowBox({
    required this.axis,
    required this.windowExtent,
    required this.naturalExtent,
    required this.offset,
    required super.child,
  });

  final Axis axis;
  final double windowExtent;
  final double naturalExtent;
  final double offset;

  @override
  _RenderRailWindowBox createRenderObject(BuildContext context) =>
      _RenderRailWindowBox(
        axis: axis,
        windowExtent: windowExtent,
        naturalExtent: naturalExtent,
        railOffset: offset,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRailWindowBox renderObject,
  ) {
    renderObject
      ..axis = axis
      ..windowExtent = windowExtent
      ..naturalExtent = naturalExtent
      ..railOffset = offset;
  }
}

/// Lays the child out at the rail's NATURAL extent, takes the window's
/// extent for itself, and paints the child shifted and clipped.
///
/// A render object rather than `SizedBox` + `ClipRect` + `OverflowBox`
/// because that trio has to be told the cross extent as a number —
/// `OverflowBox` sizes itself to the parent's constraint, which is
/// unbounded inside a scroll body. The rails would then have had to
/// publish a cross-axis scalar each, and the storyboard has none to
/// publish (its row heights are per-track).
class _RenderRailWindowBox extends RenderShiftedBox {
  _RenderRailWindowBox({
    required Axis axis,
    required double windowExtent,
    required double naturalExtent,
    required double railOffset,
  }) : _axis = axis,
       _windowExtent = windowExtent,
       _naturalExtent = naturalExtent,
       _railOffset = railOffset,
       super(null);

  Axis _axis;
  Axis get axis => _axis;
  set axis(Axis value) {
    if (_axis != value) {
      _axis = value;
      markNeedsLayout();
    }
  }

  double _windowExtent;
  double get windowExtent => _windowExtent;
  set windowExtent(double value) {
    if (_windowExtent != value) {
      _windowExtent = value;
      markNeedsLayout();
    }
  }

  double _naturalExtent;
  double get naturalExtent => _naturalExtent;
  set naturalExtent(double value) {
    if (_naturalExtent != value) {
      _naturalExtent = value;
      markNeedsLayout();
    }
  }

  double _railOffset;
  double get railOffset => _railOffset;
  set railOffset(double value) {
    if (_railOffset != value) {
      _railOffset = value;
      // A push moves the child's PAINT offset only — no relayout, which is
      // the whole reason the rail can be pushed at pointer speed. That is
      // why the shift is not in the child's parentData: parentData is set
      // during layout, so writing it there would have made every pixel of
      // a push a relayout of the rail and everything in it.
      markNeedsPaint();
    }
  }

  bool get _horizontal => _axis == Axis.horizontal;

  /// Where the child paints relative to the window's origin.
  Offset get _shift =>
      _horizontal ? Offset(-_railOffset, 0) : Offset(0, -_railOffset);

  BoxConstraints _childConstraints(BoxConstraints constraints) => _horizontal
      ? BoxConstraints(
          minWidth: _naturalExtent,
          maxWidth: _naturalExtent,
          minHeight: constraints.minHeight,
          maxHeight: constraints.maxHeight,
        )
      : BoxConstraints(
          minWidth: constraints.minWidth,
          maxWidth: constraints.maxWidth,
          minHeight: _naturalExtent,
          maxHeight: _naturalExtent,
        );

  Size _windowSize(BoxConstraints constraints, Size childSize) =>
      constraints.constrain(
        _horizontal
            ? Size(_windowExtent, childSize.height)
            : Size(childSize.width, _windowExtent),
      );

  @override
  double computeMinIntrinsicWidth(double height) =>
      _horizontal ? _windowExtent : super.computeMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _horizontal ? _windowExtent : super.computeMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _horizontal ? super.computeMinIntrinsicHeight(width) : _windowExtent;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _horizontal ? super.computeMaxIntrinsicHeight(width) : _windowExtent;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) {
      return constraints.constrain(
        _horizontal ? Size(_windowExtent, 0) : Size(0, _windowExtent),
      );
    }
    return _windowSize(
      constraints,
      child.getDryLayout(_childConstraints(constraints)),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(
        _horizontal ? Size(_windowExtent, 0) : Size(0, _windowExtent),
      );
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = _windowSize(constraints, child.size);
    // Zero: the push is a PAINT offset (see [railOffset]), applied in
    // paint/hitTest/applyPaintTransform below rather than here.
    (child.parentData! as BoxParentData).offset = Offset.zero;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      return;
    }
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => context.paintChild(child, offset + _shift),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) {
      return false;
    }
    // The window's own `hitTest` already rejects anything outside `size`,
    // so a control pushed out of view cannot be tapped.
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(_shift.dx, _shift.dy, 0, 1);
  }

  @override
  Rect? describeApproximatePaintClip(covariant RenderObject child) =>
      Offset.zero & size;
}

/// The grip between a rail window and the frame cells.
///
/// Dragging toward the cells widens the window; double-clicking restores
/// the rail's natural size.
class LayerRailSplitter extends StatelessWidget {
  const LayerRailSplitter({
    super.key,
    required this.axis,
    required this.extent,
    required this.naturalExtent,
    this.availableExtent,
  });

  /// The RAIL's axis — the splitter itself stands across it.
  final Axis axis;
  final LayerRailExtent extent;
  final double naturalExtent;
  final double? availableExtent;

  static const double thickness = DockEdgeSplitter.thickness;

  @override
  Widget build(BuildContext context) {
    return DockEdgeSplitter(
      axis: axis == Axis.horizontal ? Axis.vertical : Axis.horizontal,
      tooltip: 'Drag to resize the layer rail (double-click to reset)',
      onDragDelta: (delta) => extent.resizeBy(
        delta,
        naturalExtent: naturalExtent,
        availableExtent: availableExtent,
      ),
      onDoubleTap: extent.reset,
    );
  }
}

/// The grid's top-left corner cell: the frames↔seconds toggle.
///
/// It used to sit in the command bar between the frame counter and the
/// zoom slider. It moved here whole (the user's word was "완전 이동")
/// because the corner is where the two axes meet, and what the button
/// changes is how the frame axis LABELS itself.
class TimelineSecondsToggleCorner extends StatelessWidget {
  const TimelineSecondsToggleCorner({
    super.key = const ValueKey<String>('timeline-time-display-toggle-button'),
    required this.showSeconds,
    required this.onChanged,
    required this.width,
    required this.height,
  });

  final bool showSeconds;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onChanged = this.onChanged;
    if (onChanged == null) {
      return SizedBox(width: width, height: height);
    }
    return Tooltip(
      message: showSeconds ? 'Show Frames' : 'Show Seconds',
      child: InkWell(
        onTap: () => onChanged(!showSeconds),
        child: SizedBox(
          width: width,
          height: height,
          child: Center(
            child: Icon(
              showSeconds ? Icons.timer : Icons.timer_outlined,
              // The corner is only as wide as a scrollbar lane, so the
              // glyph is the compact one.
              size: 13,
              color: showSeconds
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// The rail's OWN scrollbar — the third of a panel's three (layer axis,
/// rail, frame axis).
///
/// Offset-driven rather than controller-driven: the rail is not a
/// [Scrollable], it is a clipped box, so the position is a plain notifier
/// that this bar and [LayerRailWindow] share. Always visible, like every
/// scrollbar in the app.
class LayerRailScrollbar extends StatelessWidget {
  const LayerRailScrollbar({
    super.key,
    required this.axis,
    required this.rail,
    required this.naturalExtent,
    this.availableExtent,
    this.laneExtent = layerRailScrollbarLaneExtent,
    this.keyPrefix = 'layer-rail',
  });

  final Axis axis;
  final LayerRailExtent rail;
  final double naturalExtent;
  final double? availableExtent;
  final double laneExtent;

  /// Addresses the surface: 'timeline' | 'xsheet' | 'storyboard'.
  final String keyPrefix;

  static const double _minimumThumbExtent = 32;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final horizontal = axis == Axis.horizontal;
    final windowExtent = rail.windowExtent(
      naturalExtent,
      availableExtent: availableExtent,
    );
    final content = math.max(naturalExtent, windowExtent);
    return Container(
      key: ValueKey<String>('$keyPrefix-rail-scrollbar'),
      // The bar is exactly as long as the window it drives, so it sits
      // under the rail and stops at the splitter.
      width: horizontal ? windowExtent : laneExtent,
      height: horizontal ? laneExtent : windowExtent,
      // No hairline anywhere on this lane — the fill alone separates it from
      // the rail rows, which are the panel surface, so it has to be the level
      // BELOW them: a lane is a groove, not a panel. Its two siblings, the
      // frame-axis rails, say the same thing.
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
      child: ValueListenableBuilder<double>(
        valueListenable: rail.offset,
        builder: (context, value, _) => AppScrollbar(
          axis: axis,
          offset: LayerRailExtent.clampOffset(
            value,
            windowExtent: windowExtent,
            naturalExtent: content,
          ),
          viewportExtent: windowExtent,
          contentExtent: content,
          minThumbExtent: _minimumThumbExtent,
          laneKey: ValueKey<String>('$keyPrefix-rail-scrollbar-track'),
          thumbKey: ValueKey<String>('$keyPrefix-rail-scrollbar-thumb'),
          onOffsetChanged: (next) => rail.pushTo(
            next,
            naturalExtent: naturalExtent,
            availableExtent: availableExtent,
          ),
        ),
      ),
    );
  }
}
