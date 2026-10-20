import 'brush_frame_key.dart';
import 'cut_id.dart';
import 'frame_id.dart';
import 'layer_id.dart';
import 'media_asset.dart';
import 'project_id.dart';
import 'track_id.dart';

/// The viewer ink's cel-key contract — the ONE place its namespace is
/// minted and recognized, shared by the ink controller and the session's
/// archive routing: the timesheet's, the conte's and the envelope's, said
/// of the fourth canvas-base panel that writes (I-114).
///
/// A namespace of its own keeps handwriting out of every cel-rendering
/// path — sheet ink can never leak into artwork or export.
///
/// 🗣️I-114 (유저 2026-10-20): 「다만 참조로 불러온 파일을 그리는건 힘들수있으니
/// 품어진 파일만 브러시 허용하도록?」 · I-114-Q1 「품은 파일만」 — the ink
/// belongs to a file the project CARRIES, so its keys carry that carry's
/// name ([MediaAsset.carriedAs]): minted whole, it goes where the carry
/// goes — a relink keeps the ink, a carry made again starts on blank paper.
const ProjectId viewerInkProjectId = ProjectId('viewer-ink');
const TrackId viewerInkTrackId = TrackId('viewer-ink');
const CutId viewerInkCutId = CutId('viewer-ink');

/// The ink of one page of a carried file — a still picture's one page, a
/// document's page, a movie's FRAME (「비디오면 해당 프레임에 그린다던가」).
BrushFrameKey viewerInkPageKey(String carry, int page) => BrushFrameKey(
  projectId: viewerInkProjectId,
  trackId: viewerInkTrackId,
  cutId: viewerInkCutId,
  layerId: LayerId(carry),
  frameId: FrameId('viewer-page-$page'),
);

/// Whether [key] belongs to the viewer ink namespace at all.
bool isViewerInkKey(BrushFrameKey key) => key.projectId == viewerInkProjectId;

/// The carry whose file [key]'s ink is written on.
String viewerInkCarryOf(BrushFrameKey key) => key.layerId.value;

/// Whether the viewer may write on [asset] — one the project carries, of a
/// kind with a picture to write on (an image, a movie's frames, a
/// document's pages); never a sound (「오디오파일처럼 못그리는건 대응불가」).
bool viewerInksOn(MediaAsset? asset) =>
    asset != null && asset.carried && asset.kind != MediaAssetKind.audio;
