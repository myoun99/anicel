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
/// every cel-rendering path; the ROW plane's key carries the REAL CutId
/// and the storyboard block's own ink id (`ExposureMemo.inkId`) — the
/// block's stable identity (the memo's rule: it moves and copies with the
/// block) and the load-time GC unit ("ink dies with the block").
const ProjectId conteInkProjectId = ProjectId('conte-ink');
const TrackId conteInkTrackId = TrackId('conte-ink');
const CutId conteInkCutId = CutId('conte-ink');
const LayerId conteInkPageLayerId = LayerId('conte-page');
const LayerId conteInkRowLayerId = LayerId('conte-row');

/// The conte ink's resolution: its surfaces' pixels per page point — what
/// the ink is drawn at and what every printer lays it back at.
///
/// ONE, the canvas's grade (유저 2026-09-26, one-paper-brush-width-Q2:
/// 「해상도를 캔버스처럼 낮추기」): a brush of a size at 100% draws on the
/// sheet as wide as on the canvas, and a surface pixel is a pixel of the
/// brush's own size. It was 4 — a brush four times thinner than on the
/// canvas at the same size, and sixteen times the memory; zoomed in, the ink
/// now shows its pixels as the canvas does.
///
/// ↩️The page painter kept a copy of the controller's number so as not to
/// import the input side; two numbers that must agree are two chances to
/// print ink at a scale it was not drawn at.
const int conteInkScale = 1;

/// The paper plane's frame id is this plus the page — minted by
/// [conteInkPageKey] and read back by [conteInkPageIndexOf], one spelling.
const String _conteInkPagePrefix = 'conte-page-p';

/// Paper-anchored plane: one surface per page.
BrushFrameKey conteInkPageKey(int page) {
  return BrushFrameKey(
    projectId: conteInkProjectId,
    trackId: conteInkTrackId,
    cutId: conteInkCutId,
    layerId: conteInkPageLayerId,
    frameId: FrameId('$_conteInkPagePrefix$page'),
  );
}

/// The page [key] is paper-plane ink for — the `page` [conteInkPageKey] was
/// given — or null when it is any other key.
int? conteInkPageIndexOf(BrushFrameKey key) {
  final frame = key.frameId.value;
  if (!isConteInkKey(key) ||
      key.layerId != conteInkPageLayerId ||
      !frame.startsWith(_conteInkPagePrefix)) {
    return null;
  }
  return int.tryParse(frame.substring(_conteInkPagePrefix.length));
}

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
