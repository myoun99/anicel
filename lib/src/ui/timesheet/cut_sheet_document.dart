import '../../models/app_frame_grid_settings.dart';
import '../../models/cut.dart';
import '../../models/sheet_sources.dart';
import '../../models/timesheet_document.dart';
import '../../services/export/xdts_builder.dart';
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
    unnamedMark: AppFrameGridSettings.settings.value.unnamedMark,
  );
}

/// THE XDTS [cut] exports: the digital rendering of the projection its
/// printed sheet reads (`SheetSources`), handed the same track rows on the
/// same axis as [cutSheetDocument] hands it — the two sheets must read one
/// story. In a cut an O.L arrives into, that is the のりしろ before its
/// conte: the DIALOG tracks count from its own frame 0, as its cel tracks
/// do (I-73-ol-sheet-columns).
String cutXdtsContent(
  EditorSessionManager session, {
  required Cut cut,
  required int cutStartFrame,
}) => buildXdtsContent(
  cut: cut,
  cutLabel: cut.name,
  instructionDefById: session.camera.cameraInstructionSet.defById,
  trackSeLayers: session.activeTrack.seLayers,
  cutStartFrame: cutStartFrame,
  transitionSpans: session.transitions.activeTrackTransitionSpans,
);

/// How many rows [cut]'s sheet runs — its XDTS's duration, read off the
/// same projection with the same track rows ([cutXdtsContent]): the conte
/// 尺 and the のりしろ an O.L asks of either side. What a cut's AE comps run
/// (ae-script-export).
int cutSheetFrameCount(
  EditorSessionManager session, {
  required Cut cut,
  required int cutStartFrame,
}) => SheetSources.of(
  cut: cut,
  trackSeLayers: session.activeTrack.seLayers,
  cutStartFrame: cutStartFrame,
  transitionSpans: session.transitions.activeTrackTransitionSpans,
).drawnFrameCount;
