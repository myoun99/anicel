import '../brush_frame_key.dart';
import '../cut_id.dart';
import '../frame_id.dart';
import '../layer_id.dart';
import '../project_id.dart';
import '../track_id.dart';

/// The conte ink's cel-key contract (R5) — the ONE place its namespace is
/// minted and recognized, shared by the ink controller (UI), the session's
/// archive routing and the exporters. The namespace keeps sheet ink out of
/// every cel-rendering path; the ROW plane's key carries the REAL CutId
/// and the storyboard block's REAL [FrameId] — the cell's stable identity
/// (the memo's rule) and the load-time GC unit ("ink dies with the
/// drawing").
const ProjectId conteInkProjectId = ProjectId('conte-ink');
const TrackId conteInkTrackId = TrackId('conte-ink');
const CutId conteInkCutId = CutId('conte-ink');
const LayerId conteInkPageLayerId = LayerId('conte-page');
const LayerId conteInkRowLayerId = LayerId('conte-row');

/// Paper-anchored plane: one surface per page.
BrushFrameKey conteInkPageKey(int page) {
  return BrushFrameKey(
    projectId: conteInkProjectId,
    trackId: conteInkTrackId,
    cutId: conteInkCutId,
    layerId: conteInkPageLayerId,
    frameId: FrameId('conte-page-p$page'),
  );
}

/// Cell-anchored plane: one surface per storyboard drawing block.
BrushFrameKey conteInkRowKey(CutId cutId, FrameId frameId) {
  return BrushFrameKey(
    projectId: conteInkProjectId,
    trackId: conteInkTrackId,
    cutId: cutId,
    layerId: conteInkRowLayerId,
    frameId: frameId,
  );
}

/// Whether [key] belongs to the conte ink namespace at all.
bool isConteInkKey(BrushFrameKey key) => key.projectId == conteInkProjectId;
