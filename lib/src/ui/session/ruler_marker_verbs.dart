import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../models/ruler_marker.dart';
import '../../services/commands/update_ruler_markers_command.dart';
import '../sliced_value_listenable_builder.dart' show SlicedValueListenable;
import '../timeline/timeline_drag_preview.dart'
    show RulerMarkerDragPreview, TimelineDragPreview;
import 'drags/ruler_marker_drag.dart';
import 'session_roles.dart';

/// THE RULER MARKERS' verbs (I-169): what stands on a ruler, a set written
/// as one undo step, and the steps of dragging one along it.
///
/// A collaborator of the session, as the movie-end drag is
/// (`MovieEndDragVerbs`): it names the roles it needs in its constructor.
class RulerMarkerVerbs {
  RulerMarkerVerbs({
    required ProjectAccess project,
    required ChangeSink changes,
    required ValueNotifier<TimelineDragPreview?> dragPreview,
  }) : _project = project,
       _changes = changes,
       _dragPreview = dragPreview;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final ValueNotifier<TimelineDragPreview?> _dragPreview;

  /// The drag channel as a ruler hears it: told only where a MARKER's drag
  /// moves ([RulerMarkerDragPreview]) — what it reads is the channel's.
  ///
  /// 🔬2026-11-14 (I-169): a ruler's writing heard the session's channel
  /// whole, so every step of a frame's drag on the sheet painted it again —
  /// and a dock's image cut at a ruler that moved while the rest stood
  /// still: 27,657,504 bytes over the 26,436,168 the dock test allows (the
  /// sheet-prints-only-its-drags precedent, `SlicedValueListenableScope`).
  /// ONE slice a session, as there is one channel: every ruler's hooks
  /// share it ([dispose]).
  late final dragPreview =
      SlicedValueListenable<TimelineDragPreview?, RulerMarkerDragPreview?>(
        _dragPreview,
        (preview) => preview is RulerMarkerDragPreview ? preview : null,
      );

  /// Lets [dragPreview] off the session's channel — before the channel
  /// itself goes.
  void dispose() => dragPreview.dispose();

  /// The in-flight marker drag ([RulerMarkerDrag]), or null.
  RulerMarkerDrag? _drag;

  /// The markers on [holder]'s ruler as the project holds them.
  RulerMarkers markersOn(RulerMarkerHolder holder) =>
      rulerMarkersOf(_project.repository.requireProject(), holder);

  /// Writes [markers] as [holder]'s — ONE undo step, and none where they
  /// are what it holds already.
  void setMarkers(RulerMarkerHolder holder, RulerMarkers markers) {
    if (markers == markersOn(holder)) {
      return;
    }
    _project.historyManager.execute(
      UpdateRulerMarkersCommand(
        repository: _project.repository,
        holder: holder,
        markers: markers,
      ),
    );
    _changes.notifyChanged();
  }

  /// Starts a drag of the marker at [index] of [holder]'s ruler.
  bool beginDrag(RulerMarkerHolder holder, int index) {
    final before = markersOn(holder);
    if (index < 0 || index >= before.inOrder.length) {
      return false;
    }
    _drag = RulerMarkerDrag(
      holder: holder,
      before: before,
      index: index,
      preview: _dragPreview,
      commit: (markers) => setMarkers(holder, markers),
    );
    return true;
  }

  void updateDrag(int cumulativeDelta) => _drag?.update(cumulativeDelta);

  void endDrag() {
    _drag?.commit();
    _drag = null;
  }

  void cancelDrag() {
    _drag?.cancel();
    _drag = null;
  }
}
