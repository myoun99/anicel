import '../brush_frame_key.dart';
import '../cut_id.dart';
import '../frame_id.dart';
import '../layer_id.dart';
import '../project.dart';
import '../project_id.dart';
import '../timeline_exposure.dart';
import '../track_id.dart';

/// The conte ink's cel-key contract (R5) — the ONE place its namespace is
/// minted and recognized, shared by the ink controller (UI), the session's
/// archive routing and the exporters. The namespace keeps sheet ink out of
/// every cel-rendering path; a key carries the REAL CutId and the
/// storyboard block's own ink id (`ExposureMemo.inkId`) — the block's
/// stable identity (the memo's rule: it moves and copies with the block)
/// and the load-time GC unit ("ink dies with the block").
///
/// ⛔No paper plane. 유저 09-26 (H44): 「잉크가 종이 어디던간에 그려지는데
/// 그게아니라 칸에만 넣고싶거든? 그래서 컷 이동하면 따라오도록 구조적으로
/// 강제하고싶으니까 칸에만 그려지도록」 — ink the page kept for itself stayed
/// where it was drawn while the cuts moved under it.
const ProjectId conteInkProjectId = ProjectId('conte-ink');
const TrackId conteInkTrackId = TrackId('conte-ink');
const LayerId conteInkRowLayerId = LayerId('conte-row');

/// Cell-anchored plane: one surface per storyboard BLOCK — the block's own
/// [inkId] (`ExposureMemo.inkId`) in the frame slot, not its drawing's id:
/// two exposures of one cel write each for itself.
BrushFrameKey conteInkRowKey(CutId cutId, String inkId) {
  return BrushFrameKey(
    projectId: conteInkProjectId,
    trackId: conteInkTrackId,
    cutId: cutId,
    layerId: conteInkRowLayerId,
    frameId: FrameId(inkId),
  );
}

/// The block [key] is the handwriting of — the `ExposureMemo.inkId`
/// [conteInkRowKey] was given — or null for any other key.
String? conteInkRowIdOf(BrushFrameKey key) =>
    isConteInkRowKey(key) ? key.frameId.value : null;

/// Every block [project] has written on, by its cut and its handwriting id
/// — what a loaded row entry must still name.
Set<(CutId, String)> writtenConteBlocks(Project project) => {
  for (final track in project.tracks)
    for (final cut in track.cuts)
      for (final layer in cut.layers)
        for (final exposure in layer.timeline.values)
          if (exposure.memo?.inkId case final inkId? when inkId.isNotEmpty)
            (cut.id, inkId),
};

/// [exposures] as their COPY writes on the conte: every block written on
/// under an id of its own, minted by [mint] — and [copies], by each new id,
/// the handwriting it starts as a copy of.
///
/// 🚨EVERY copy, linked or not: 유저 2026-09-26 (cut-duplicate-sheet-ink-Q1)
/// 「복제는 전부 복사」 — a copy starts with the same handwriting and they go
/// on apart; and blocks of the same name are not linked (conte-drawing-
/// target). A link shares a drawing; the handwriting is the block's. So
/// each copied block takes its own id, even where two of the source wrote
/// under one.
({Map<int, TimelineExposure> exposures, Map<String, String> copies})
conteHandwritingOfACopy(
  Map<int, TimelineExposure> exposures,
  String Function() mint,
) {
  final copies = <String, String>{};
  TimelineExposure writtenAnew(TimelineExposure exposure) {
    final memo = exposure.memo;
    if (memo == null || memo.inkId.isEmpty) {
      return exposure;
    }
    final inkId = mint();
    copies[inkId] = memo.inkId;
    return exposure.copyWith(memo: () => memo.copyWith(inkId: inkId));
  }

  return (
    exposures: {
      for (final MapEntry(key: index, value: exposure) in exposures.entries)
        index: writtenAnew(exposure),
    },
    copies: copies,
  );
}

/// Whether [key] is cell-anchored conte ink — [conteInkRowKey]'s plane.
bool isConteInkRowKey(BrushFrameKey key) =>
    isConteInkKey(key) && key.layerId == conteInkRowLayerId;

/// Whether [key] belongs to the conte ink namespace at all.
bool isConteInkKey(BrushFrameKey key) => key.projectId == conteInkProjectId;
