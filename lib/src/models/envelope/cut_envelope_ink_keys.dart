import '../brush_frame_key.dart';
import '../cut_id.dart';
import '../frame_id.dart';
import '../layer_id.dart';
import '../project_id.dart';
import '../track_id.dart';

/// The envelope ink's cel-key contract — the ONE place its namespace is
/// minted and recognized, shared by the ink controller, the session's
/// archive routing and the exporters.
///
/// A namespace of its own keeps handwriting out of every cel-rendering
/// path, the same guard the conte and timesheet inks use: sheet ink can
/// never leak into artwork or export.
const ProjectId envelopeInkProjectId = ProjectId('envelope-ink');
const TrackId envelopeInkTrackId = TrackId('envelope-ink');
const LayerId envelopeInkLayerId = LayerId('envelope-box');

/// One surface per BOX of one envelope.
///
/// There is no page plane: every stroke belongs to a box, because the form
/// has no margin box and its cells simply meet (user, 2026-08-06 — "여백칸
/// 넣지마 … 그냥 칸끼리 딱 붙이면될문제야"). A box that stops existing
/// takes its ink with it, which is the whole point of anchoring here.
///
/// [cutId] is the envelope's OWNER cut — for a 겸용 envelope that is the
/// representative sibling, so the one sheet the siblings share carries one
/// set of annotations rather than a copy each.
BrushFrameKey envelopeInkBoxKey(CutId cutId, String boxId) {
  return BrushFrameKey(
    projectId: envelopeInkProjectId,
    trackId: envelopeInkTrackId,
    cutId: cutId,
    layerId: envelopeInkLayerId,
    frameId: FrameId('envelope-${cutId.value}-$boxId'),
  );
}

/// Whether [key] belongs to the envelope ink namespace at all.
bool isEnvelopeInkKey(BrushFrameKey key) =>
    key.projectId == envelopeInkProjectId;
