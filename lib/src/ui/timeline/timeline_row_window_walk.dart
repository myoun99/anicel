import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import 'timeline_row_edges.dart';
import 'timeline_visible_range.dart';

/// Where a rows' view stands: the rows' [edges], how far the view is
/// scrolled down them and how far it reaches.
typedef TimelineRowView = ({
  TimelineRowEdges edges,
  double scrollOffset,
  double viewportExtent,
});

/// THE WINDOW THE ROWS ARE LAID IN, walked to the one they stand in
/// ([TimelineRowEdges.window]) a unit a frame after the view moves — the
/// timeline's rows and the conte's alike, each its own walk of this one
/// law (frame-panels-build-in-one-frame ②: one window code).
///
/// 🗣️a-timeline-wheel-notch-lays-out-the-rail-Q2 = 1 (유저 2026-11-18,
/// 「칸 뒤 쉬는 프레임에 짓기」): the frame a notch moves the view in lays
/// no row while every row it shows stands laid — the margin
/// ([timelineRowWindowMargin]) laid them —, and the rows the window takes
/// in are laid in the frames after it, a unit a frame each way. A row that
/// comes into view unlaid (notches faster than the walk) is laid in its
/// frame, the whole window with it, as every move was before. 🔬What it
/// answers (brush/rendering 11-18 16:13, S5_BA cut 352, 68 rows, test VM):
/// every notch that moved the view stood at 33–45 ms, laying out inside its
/// own frame the ≈4 rows (≈600 elements) it took into the window — and the
/// margin's size does not change how many a notch takes in.
/// ↩️Every move of the window laid all of it in the frame it moved in.
class TimelineRowWindowWalk {
  TimelineRowWindowWalk({required this.view, required this.relay});

  /// Where the rows' view stands now — null while it has no extent, when
  /// every row is laid.
  final TimelineRowView? Function() view;

  /// Lays the rows again: what a step of the walk asks for.
  final VoidCallback relay;

  /// The rows [_laid] was cut from: a lay over other rows lays where the
  /// view stands, the indices of the old ones meaning nothing in it.
  TimelineRowEdges? _edges;
  TimelineVisibleRange? _laid;
  bool _stepAsked = false;
  bool _disposed = false;

  /// The rows a lay lays — every one when null: the window laid last
  /// while it still holds every row the view shows over the same rows,
  /// else the window the view stands in. A walk still to go goes on after
  /// this frame.
  TimelineVisibleRange? laid() {
    final now = view();
    if (now == null) {
      _edges = null;
      return _laid = null;
    }
    final laid = _laid;
    final window = laid != null && _shows(laid, now)
        ? laid
        : now.edges.window(
            scrollOffset: now.scrollOffset,
            viewportExtent: now.viewportExtent,
          );
    _edges = now.edges;
    _walkOn(now, window);
    return _laid = window;
  }

  /// The view moved: whether its rows are to be laid again in this frame —
  /// a row it shows now is not laid. Where none is, the walk takes in the
  /// rest after it.
  bool moved() {
    final now = view();
    final laid = _laid;
    if (now == null || laid == null || !_shows(laid, now)) {
      return true;
    }
    _walkOn(now, laid);
    return false;
  }

  void dispose() => _disposed = true;

  /// Whether [laid] holds every row [now] shows, over the rows it was cut
  /// from.
  bool _shows(TimelineVisibleRange laid, TimelineRowView now) {
    if (!identical(now.edges, _edges)) {
      return false;
    }
    final from = now.scrollOffset;
    final seen = now.edges.over(from, from + now.viewportExtent);
    return seen.isEmpty ||
        (laid.startIndex <= seen.startIndex &&
            seen.endIndexExclusive <= laid.endIndexExclusive);
  }

  /// Asks for the walk's next step after this frame while [laid] is not
  /// the window [now] stands in — and for the frame, which nothing else
  /// may ask for.
  void _walkOn(TimelineRowView now, TimelineVisibleRange laid) {
    final window = now.edges.window(
      scrollOffset: now.scrollOffset,
      viewportExtent: now.viewportExtent,
    );
    if (_stepAsked || laid == window) {
      return;
    }
    _stepAsked = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _step())
      ..ensureVisualUpdate();
  }

  /// A unit taken in on each side the window reaches past the rows laid,
  /// and every row it no longer reaches let go — laid in a frame of its
  /// own.
  void _step() {
    _stepAsked = false;
    final now = view();
    final laid = _laid;
    if (_disposed || now == null || laid == null || !_shows(laid, now)) {
      return;
    }
    final window = now.edges.window(
      scrollOffset: now.scrollOffset,
      viewportExtent: now.viewportExtent,
    );
    if (laid == window) {
      return;
    }
    final edges = now.edges;
    var start = laid.startIndex;
    var end = laid.endIndexExclusive;
    if (window.startIndex < start) {
      start = edges.unitOf(start - 1).first;
    } else {
      start = window.startIndex;
    }
    if (window.endIndexExclusive > end) {
      end = edges.unitOf(end).last + 1;
    } else {
      end = window.endIndexExclusive;
    }
    _laid = TimelineVisibleRange(startIndex: start, endIndexExclusive: end);
    relay();
  }
}
