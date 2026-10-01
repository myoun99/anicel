import '../../models/cut.dart';
import '../../models/timesheet_document.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';

/// The word an O.L prints as on a sheet: the NOTATION language's (F-229).
String sheetOlWord(EditorSessionManager session) => AppStrings.of(
  session.languageSettings.value.notationLanguage,
).tlTransitionCutOl;

/// THE sheet [cut] prints, wherever it prints — the timesheet panel and the
/// export alike. [cutStartFrame] is where its conte starts on the active
/// track, the axis the track's SE rows and transitions are read on.
///
/// 🚨One function because the two gathered their inputs apart, and the
/// export's gathering stopped short: its sheets printed no O.L and no
/// のりしろ length while the panel printed both
/// (export-sheet-lacks-transitions, 2026-09-30).
TimesheetDocument cutSheetDocument(
  EditorSessionManager session, {
  required Cut cut,
  required int cutStartFrame,
  bool dataSheet = false,
}) {
  final track = session.activeTrack;
  return TimesheetDocument.fromCut(
    cut: cut,
    projectName: session.repository.requireProject().name,
    fps: session.projectSettings.projectFps,
    info: session.timesheetInfo,
    instructionDefById: session.camera.cameraInstructionSet.defById,
    trackSeLayers: track.seLayers,
    cutStartFrame: cutStartFrame,
    transitionSpans: session.transitions.activeTrackTransitionSpans,
    // D31: the transition row prints when its own timesheet flag is on —
    // through the SESSION'S cut-view projection (one walk for the sheet and
    // the cut timeline's row; spans re-keyed to this cut's local axis),
    // MINUS the D26-refused crossing fades (the sheet prints only what
    // applies — the row keeps them for the warning to sit on). Off = the
    // slot stays blank form space, the camera column's own precedent.
    transitionLayer: track.transitionLayer.onTimesheet
        ? session.transitions.trackTransitionSheetLayerFor(
            cutStart: cutStartFrame,
            duration: cut.duration,
            olWord: sheetOlWord(session),
          )
        : null,
    dataSheet: dataSheet,
  );
}
