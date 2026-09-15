import 'package:flutter/widgets.dart';

import '../layout/device_grid_scroll_controller.dart';
import 'timeline_frame_range_policy.dart';
import 'timeline_frame_window.dart';

/// The frame axis following its scroll controller — UI-R9 #12a: NO
/// setState per pixel. The offset notifier carries the offset to the
/// windows and to the frame math; the window bucket drives the
/// re-windowing (UI-R16: quantized span buckets, so the painters repaint
/// once per span crossing and the frames between are pure translation);
/// only an ENDLESS-extent growth (a real relayout, rare) still rebuilds
/// the host.
///
/// ↩️F-95: the notifier used to drive the ruler translate as well. It is a
/// COPY of the position, and a copy can fall behind ([rereadAfterLayout]
/// says when), so the rulers read the position itself now
/// ([ScrollFollower]).
///
/// 🚨One object for the rail, the sheet and the storyboard. Each kept its
/// own copy of this walk — three `handle…Scroll` bodies, three activity
/// watchers, three trailing-frame fields — and the audit's clone scan
/// (2026-09-03) found them. The host hands over its notifiers and its
/// numbers; the follower owns the watched position and the trailing count.
class TimelineFrameAxisFollower {
  TimelineFrameAxisFollower({
    required this.controller,
    required this.frameAxisOffset,
    required this.frameWindowBucket,
    required this.cellExtent,
    required this.baseFrameCount,
    required this.rebuild,
    required this.isMounted,
  });

  final ScrollController controller;

  /// The frame-axis pixel offset, for the surfaces that window and count.
  final ValueNotifier<double> frameAxisOffset;

  /// The quantized span bucket — the painters' repaint trigger.
  final ValueNotifier<int> frameWindowBucket;

  /// The frame cell's extent along the axis, read at event time (zoom
  /// changes it).
  final double Function() cellExtent;

  /// The frames the content holds before the endless trailing room.
  final int Function() baseFrameCount;

  /// The host's setState, for the rare relayout.
  final void Function(VoidCallback fn) rebuild;

  final bool Function() isMounted;

  /// The endless room past the content's end, in frames — grown as the
  /// user scrolls past the end, shrunk back once the scroll settles.
  int trailingFrames = 0;

  ScrollPosition? _watchedPosition;

  bool _rereadScheduled = false;

  /// The offset the axis is PAINTED at: the position itself, read now —
  /// what [ScrollFollower] moves a ruler by, so a press on that ruler
  /// counts its frame from the same number.
  double get paintedOffset =>
      singleScrollPixelsOf(controller) ?? frameAxisOffset.value;

  /// The controller's listener.
  void handleScroll() {
    if (!controller.hasClients) {
      return;
    }
    _watchScrollActivity();
    final offset = controller.offset;
    if (offset == frameAxisOffset.value) {
      return;
    }
    frameAxisOffset.value = offset;
    final bucket = timelineFrameWindowBucketOf(
      offset: offset,
      cellExtent: cellExtent(),
    );
    if (bucket != frameWindowBucket.value) {
      frameWindowBucket.value = bucket;
    }
    final position = controller.position;
    final next = endlessTrailingFrames(
      baseFrameCount: baseFrameCount(),
      currentTrailingFrames: trailingFrames,
      scrollOffset: offset,
      viewportExtent: position.viewportDimension,
      frameCellExtent: cellExtent(),
      allowShrink: !position.isScrollingNotifier.value,
    );
    if (next != trailingFrames) {
      rebuild(() => trailingFrames = next);
    }
  }

  /// Re-reads the position once this frame's layout is done.
  ///
  /// 🚨F-95 (유저 2026-09-12): 「패널의 스플리터로 좌우 길이 바꾸면 타임라인
  /// 룰러랑 내부 프레임 영역이랑 위치가 좌우 방향으로 어긋남」. A viewport
  /// that grows past the end of its content pulls its position back during
  /// layout (`correctBy`) and calls no listener, so [handleScroll] never
  /// ran. 🧪Measured on the timeline, scrolled to 2635 and widened from 700
  /// to 1300: the position went to 2035 and [frameAxisOffset] stayed at
  /// 2635, settled. Everything that reads the copy kept the old number —
  /// the windows, the scrub math, and the layout's clamp, which pulled the
  /// view back to 2335 when the panel narrowed again.
  ///
  /// The host calls this from the layout that sizes the axis's viewport:
  /// that pass is where every such correction happens. One callback a
  /// frame, however many layouts ask.
  void rereadAfterLayout() {
    if (_rereadScheduled) {
      return;
    }
    _rereadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rereadScheduled = false;
      if (isMounted()) {
        handleScroll();
      }
    });
  }

  void _watchScrollActivity() {
    final position = controller.position;
    if (identical(position, _watchedPosition)) {
      return;
    }
    _watchedPosition?.isScrollingNotifier.removeListener(handleScrollActivity);
    _watchedPosition = position;
    position.isScrollingNotifier.addListener(handleScrollActivity);
  }

  /// The scroll settling: the one moment the trailing room may shrink.
  void handleScrollActivity() {
    final position = _watchedPosition;
    if (position == null || position.isScrollingNotifier.value) {
      return;
    }
    final next = endlessTrailingFrames(
      baseFrameCount: baseFrameCount(),
      currentTrailingFrames: trailingFrames,
      scrollOffset: position.pixels,
      viewportExtent: position.viewportDimension,
      frameCellExtent: cellExtent(),
      allowShrink: true,
    );
    if (next != trailingFrames && isMounted()) {
      rebuild(() => trailingFrames = next);
    }
  }

  /// Drops the activity watch; the host disposes the controller itself.
  void dispose() {
    _watchedPosition?.isScrollingNotifier.removeListener(handleScrollActivity);
    _watchedPosition = null;
  }
}
