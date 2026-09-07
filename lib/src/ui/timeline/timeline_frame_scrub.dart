/// THE FRAME SCRUB — a press or a drag on a frame-axis strip picking the
/// frame under it, the clamp, the auto-pan at the edge and the tracking that
/// ends with the scrub.
library;

import 'package:flutter/widgets.dart';

import 'axis_turn.dart' show extentAlong;
import 'timeline_edge_auto_pan.dart';
import 'timeline_frame_coordinate_policy.dart';
import 'timeline_grid_hooks.dart';

/// The scrub on a strip whose frames run along [axis].
///
/// 🚨ONE object for both grids. The timeline's ruler runs the frame axis
/// ACROSS the top and the X-sheet's rail runs it DOWN the side, and each
/// carried its own copy of all six members — the same six sentences, once
/// with `.dx` and `viewport.size.width` and once with `.dy` and
/// `viewport.size.height` (the audit's clone scan, round 8). The axis is a
/// VALUE here, the way Flutter's own `Axis` serves Flex and ListView, so
/// there is one body and no side can lag the other.
///
/// Everything a scrub needs from its grid arrives as a getter, because the
/// metrics, the hooks and the rendered extent all change under it between
/// gestures; the controller and the viewport key are fixed for the grid's
/// life and arrive as themselves.
class TimelineFrameScrub {
  TimelineFrameScrub({
    required this.axis,
    required this.viewportKey,
    required this.controller,
    required this.hooks,
    required this.frameCellExtent,
    required this.renderedFrameCount,
    required this.scrolledFrameOffset,
  });

  /// The axis the FRAMES run along: horizontal on the timeline's ruler,
  /// vertical on the X-sheet's rail.
  final Axis axis;

  /// The strip's scroll VIEWPORT — the box a global position is read in.
  final GlobalKey viewportKey;

  /// The frame axis's scroll controller, the one an edge pan moves.
  final ScrollController controller;

  final TimelineGridHooks Function() hooks;
  final double Function() frameCellExtent;

  /// The BUILT extent the clamp answers against (UI-R12 #16).
  final int Function() renderedFrameCount;

  /// The effective frame-axis offset the last layout resolved.
  final double Function() scrolledFrameOffset;

  /// A scrub's per-gesture frame dedupe — see [FrameScrubDedupe] for why a
  /// scrub cannot report the same frame twice.
  final FrameScrubDedupe _scrubbedFrame = FrameScrubDedupe();

  int? _frameIndexAt(double alongLocal) => frameIndexFromLocalX(
    localX: alongLocal,
    horizontalScrollOffset: scrolledFrameOffset(),
    frameCellWidth: frameCellExtent(),
    visibleFrameCount: renderedFrameCount(),
  );

  void selectClampedFrame(int frameIndex) {
    // The endless runway IS the selectable tail now (UI-R10 #23 retired
    // the fixed safety frames): clamp against the BUILT extent.
    final frame = _scrubbedFrame.next(
      clampFrameIndex(
        frameIndex: frameIndex,
        visibleFrameCount: renderedFrameCount(),
      ),
    );
    if (frame == null) {
      return;
    }
    final grid = hooks();
    (grid.onScrubFrame ?? grid.onSelectFrame)(frame);
  }

  /// The scrub gesture's release (raw pointer up/cancel — fires for taps
  /// AND drags, wherever the pointer ends up). Tracking is NOT reset here
  /// so a strip's trailing onTap stays deduplicated.
  void endScrub() {
    hooks().onScrubEnd?.call();
  }

  void resetTracking() => _scrubbedFrame.reset();

  /// A PRESS on the strip: the frame under the pointer, and nothing else.
  ///
  /// 🚨LANDING NEAR AN END OF THE STRIP IS NOT A PUSH TOWARD IT. R10 R6
  /// found this the expensive way — the rail runs this from `onPointerDown`
  /// as well as from drag updates, so a plain tap inside the edge band
  /// scrolled the sheet under the finger before the frame was even
  /// resolved. The band is a fraction of the viewport, so the shorter the
  /// rail the larger the share of it that was untappable.
  ///
  /// ⚠️The horizontal ruler used to pan on its press too, and only its
  /// width hid it: same code, same law, both strips (round 8's unification
  /// of the two scrubs).
  void pressAt(Offset globalPosition) {
    final viewport = _viewport();
    if (viewport == null) {
      return;
    }
    _selectFrameAt(viewport, globalPosition);
  }

  /// A DRAG across the strip: the frame under the pointer, and the edge pan
  /// that reaches for the frames past the viewport.
  void dragTo(Offset globalPosition) {
    final viewport = _viewport();
    if (viewport == null) {
      return;
    }
    _autoPanEdge(viewport, _alongLocal(viewport, globalPosition));
    _selectFrameAt(viewport, globalPosition);
  }

  RenderBox? _viewport() {
    final renderObject = viewportKey.currentContext?.findRenderObject();
    return renderObject is RenderBox ? renderObject : null;
  }

  /// The pointer's position ALONG the strip, in the viewport's own frame.
  double _alongLocal(RenderBox viewport, Offset globalPosition) {
    final local = viewport.globalToLocal(globalPosition);
    return axis == Axis.horizontal ? local.dx : local.dy;
  }

  void _selectFrameAt(RenderBox viewport, Offset globalPosition) {
    final frameIndex = _frameIndexAt(_alongLocal(viewport, globalPosition));
    if (frameIndex == null) {
      return;
    }
    selectClampedFrame(frameIndex);
  }

  /// Edge auto-pan (UI-R10 #24, the pro-standard ruler drag): a scrub
  /// pointer past the viewport edge scrolls the frame axis under it. Toward
  /// the end it deliberately OVERSHOOTS the built extent (UI-R12 #16): the
  /// strip drag is THE way past the last built cell — the growth listener
  /// materializes the frames the overshot view needs, while the scrollbar
  /// and scroll physics stay clamped at the built cells. With the endless
  /// growth feeding cells ahead, the strip drag alone reaches ANY frame.
  void _autoPanEdge(RenderBox viewport, double alongLocal) {
    if (!viewport.hasSize) {
      return;
    }
    edgeAutoPanOvershoot(
      controller,
      edgeAutoPanDelta(alongLocal, extentAlong(axis, viewport.size)),
    );
  }
}
