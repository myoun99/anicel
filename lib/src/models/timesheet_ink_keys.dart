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
const LayerId timesheetInkStripLayerId = LayerId('sheet-strip');
const LayerId timesheetInkPageLayerId = LayerId('sheet-page');

/// The timesheet ink's resolution: its surfaces' pixels per sheet unit (a
/// frame row is 18 of them).
///
/// ONE, the canvas's grade — the conte's reason (`conteInkScale`,
/// one-paper-brush-width-Q2); it was 4.
const int timesheetInkScale = 1;

/// Frame-anchored ink: one surface per page BAND of frame rows, so writing
/// follows its frames through the paged and the continuous view alike.
BrushFrameKey timesheetInkStripKey(CutId cutId, int band) {
  return BrushFrameKey(
    projectId: timesheetInkProjectId,
    trackId: timesheetInkTrackId,
    cutId: cutId,
    layerId: timesheetInkStripLayerId,
    frameId: FrameId('sheet-strip-${cutId.value}-b$band'),
  );
}

/// Paper-anchored ink: one surface per page — the header, the memo band,
/// the margins.
BrushFrameKey timesheetInkPageKey(CutId cutId, int page) {
  return BrushFrameKey(
    projectId: timesheetInkProjectId,
    trackId: timesheetInkTrackId,
    cutId: cutId,
    layerId: timesheetInkPageLayerId,
    frameId: FrameId('sheet-page-${cutId.value}-p$page'),
  );
}

/// Whether [key] belongs to the timesheet ink namespace at all.
bool isTimesheetInkKey(BrushFrameKey key) =>
    key.projectId == timesheetInkProjectId;
