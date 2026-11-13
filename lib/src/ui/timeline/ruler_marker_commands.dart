import 'package:flutter/widgets.dart';

import '../../models/ruler_marker.dart';
import '../../models/working_panel.dart';
import '../dialogs/dialog_verb.dart';
import '../dialogs/ruler_marker_dialog.dart';
import '../editor_session_manager.dart';
import 'ruler_marker_layer.dart' show RulerMarkerHooks;

/// A ruler's marker hooks over the session (I-169) — ONE builder for the
/// timeline's ruler and the sheet's rail (a cut's) and the conte panel's
/// ruler (the open timeline's), so no ruler is handed a verb another is
/// not.
RulerMarkerHooks rulerMarkerHooksOf(
  BuildContext context,
  EditorSessionManager session,
  RulerMarkerHolder holder,
) => RulerMarkerHooks(
  holder: holder,
  markers: session.rulerMarkers.markersOn(holder),
  dragPreview: session.dragPreview,
  onBeginDrag: (index) => session.rulerMarkers.beginDrag(holder, index),
  onUpdateDrag: session.rulerMarkers.updateDrag,
  onEndDrag: session.rulerMarkers.endDrag,
  onCancelDrag: session.rulerMarkers.cancelDrag,
  onOpen: (frame) => editRulerMarkerAt(context, session, holder, frame),
);

/// The marker window on [holder]'s ruler at [frame]: the marker standing
/// over that frame opens, and where none does a new one is made there.
///
/// 🗣️I-169-Q1 (유저 2026-11-13): 「룰러 칸 자체 더블클릭하면 편집페이지
/// 열리고 … 마커가 생기고 나서라도 더블클릭은 룰러 칸 자체 더블클릭해서
/// 대응하도록」. One step either way — the window's answer is the set as it
/// then stands, so a span made longer pushes what follows it in that same
/// step ([RulerMarkers.withMarker]).
Future<void> editRulerMarkerAt(
  BuildContext context,
  EditorSessionManager session,
  RulerMarkerHolder holder,
  int frame,
) async {
  final markers = session.rulerMarkers.markersOn(holder);
  final index = markers.indexAt(frame);
  final result = await showDialogVerb<RulerMarkerDialogResult>(
    context,
    (_) => RulerMarkerDialog(
      marker: index == null
          ? RulerMarker(start: frame)
          : markers.inOrder[index],
      editing: index != null,
      frameRate: session.projectSettings.projectFrameRate,
      onCountEntryChanged: session.appSettings.rememberFrameCountEntry,
    ),
  );
  if (result == null) {
    return;
  }
  session.rulerMarkers.setMarkers(holder, switch (result.marker) {
    final marker? => markers.withMarker(marker, replacing: index),
    // Delete is offered only on a marker that stands (`editing`).
    null => index == null ? markers : markers.without(index),
  });
}

/// The marker window of the panel being worked in, at its playhead — the
/// bound key's (`EditorActionIds.rulerMarkerEdit`): the cut's ruler on the
/// timeline and the sheet, the open timeline's on the conte panel
/// (I-169-Q2: 「컷(로컬)이랑 콘티(글로벌)이랑 마커 독립적으로」). Nothing
/// where that panel has no frame to stand on.
Future<void> editRulerMarkerAtPlayhead(
  BuildContext context,
  EditorSessionManager session,
) {
  final (holder, frame) = switch (session.workingPanel) {
    WorkingPanel.timeline => (
      switch (session.activeCutId) {
        null => null,
        final cutId => RulerMarkerHolder.cut(cutId),
      },
      session.currentFrameIndex,
    ),
    WorkingPanel.storyboard => (
      const RulerMarkerHolder.timeline(),
      session.playheadCursors.trackFrameNow(),
    ),
  };
  if (holder == null || frame == null) {
    return Future<void>.value();
  }
  return editRulerMarkerAt(context, session, holder, frame);
}
