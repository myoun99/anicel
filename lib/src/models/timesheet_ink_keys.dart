import 'brush_frame_key.dart';
import 'cut_id.dart';
import 'frame_id.dart';
import 'layer_id.dart';
import 'project_id.dart';
import 'track_id.dart';

/// The timesheet ink's cel-key contract — the ONE place its namespace is
/// minted and recognized, shared by the ink controller, the session's
/// archive routing and the exporters: the conte's (R5) and the envelope's,
/// said of the third sheet.
///
/// A namespace of its own keeps handwriting out of every cel-rendering
/// path — sheet ink can never leak into artwork or export. The keys carry
/// the REAL [CutId]: a timesheet's ink dies with the cut the sheet
/// describes, the envelope's unit.
///
/// ↩️The keys were minted inside the ink controller (UI) when the ink was
/// never saved; an archive reading them back has to recognize them below
/// the UI.
const ProjectId timesheetInkProjectId = ProjectId('timesheet-ink');
const TrackId timesheetInkTrackId = TrackId('timesheet-ink');
const LayerId timesheetInkPageLayerId = LayerId('sheet-page');

/// A page's frame id is this plus the page — minted by
/// [timesheetInkPageKey] and read back by [timesheetInkKeyOfCut], one
/// spelling.
String _pageFramePrefix(CutId cutId) => 'sheet-page-${cutId.value}-p';

/// The ink of one page of the sheet: everything written on that paper.
///
/// 🗣️F-252 (유저 2026-10-01): 「잉크는 용지에 귀속됨. 더이상 칸에
/// 귀속되지않음. 내용물이 뭐가 바뀌던 독립적」 — the writing stays where it
/// was written on the paper, whatever the sheet prints under it. ↩️Ink on
/// the column grid lived on a second, frame-anchored plane (one surface
/// per band of frame rows, `sheet-strip-<cut>-b<n>`) that followed its
/// frames through a sheet-kind switch; F-252-Q1 (10-08: 「잔재 싹 삭제」)
/// took it out.
BrushFrameKey timesheetInkPageKey(CutId cutId, int page) {
  return BrushFrameKey(
    projectId: timesheetInkProjectId,
    trackId: timesheetInkTrackId,
    cutId: cutId,
    layerId: timesheetInkPageLayerId,
    frameId: FrameId('${_pageFramePrefix(cutId)}$page'),
  );
}

/// The ink [key] is — the same page — on the sheet of the cut [cutId]
/// instead (a duplicated cut's copy, cut-duplicate-sheet-ink); null for a
/// key that names no page of a timesheet.
BrushFrameKey? timesheetInkKeyOfCut(BrushFrameKey key, CutId cutId) {
  if (!isTimesheetInkKey(key)) {
    return null;
  }
  final prefix = _pageFramePrefix(key.cutId);
  final frame = key.frameId.value;
  final page = frame.startsWith(prefix)
      ? int.tryParse(frame.substring(prefix.length))
      : null;
  return page == null ? null : timesheetInkPageKey(cutId, page);
}

/// Whether [key] belongs to the timesheet ink namespace at all.
bool isTimesheetInkKey(BrushFrameKey key) =>
    key.projectId == timesheetInkProjectId;
