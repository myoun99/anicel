import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../models/ruler_marker.dart';
import '../../services/commands/update_ruler_markers_command.dart';
import '../timeline/timeline_drag_preview.dart' show TimelineDragPreview;
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
