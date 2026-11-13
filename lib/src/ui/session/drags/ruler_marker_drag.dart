import 'package:flutter/foundation.dart';

import '../../../models/ruler_marker.dart';
import '../../timeline/timeline_drag_preview.dart';
import 'editor_drag_session.dart';

/// A ruler marker dragged along its ruler (I-169): the marker at [index] of
/// the set the drag found, moved by the frame blocks' own plan
/// ([RulerMarkers.moved]) — 🗣️I-169-Q1 (유저 2026-11-13): 「마커끼리 겹치는건
/// 불가능하고 어떻게 움직일지는 프레임블록 규칙이랑 동일하게」.
class RulerMarkerDrag implements EditorDragSession {
  /// Always begins: a press on a marker is a drag of it.
  RulerMarkerDrag({
    required this.holder,
    required RulerMarkers before,
    required this.index,
    required ValueNotifier<TimelineDragPreview?> preview,
    required void Function(RulerMarkers markers) commit,
  }) : _before = before,
       _preview = preview,
       _commit = commit;

  final RulerMarkerHolder holder;

  /// Which marker of the set the drag found the hand holds.
  final int index;

  /// The ruler's markers when the hand went down.
  final RulerMarkers _before;

  /// The set the drag has arrived at, or null while it shows 「no change」.
  /// The commit reads THIS, never [_preview].
  RulerMarkers? _after;

  final ValueNotifier<TimelineDragPreview?> _preview;

  /// The session's committer: one `UpdateRulerMarkersCommand` through
  /// history, plus the notify.
  final void Function(RulerMarkers markers) _commit;

  @override
  void update(int cumulativeDelta) {
    final next = _before.moved(index, cumulativeDelta);
    _after = next == _before ? null : next;
    _preview.value = next == _before
        ? null
        : RulerMarkerDragPreview(holder: holder, markers: next);
  }

  @override
  void commit() {
    final after = _after;
    _preview.value = null;
    if (after == null) {
      return;
    }
    _commit(after);
  }

  @override
  void cancel() {
    _preview.value = null;
  }
}
