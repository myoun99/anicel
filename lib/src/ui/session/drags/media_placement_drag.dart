import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../models/drawing_block_move.dart';
import '../../../models/frame.dart';
import '../../../models/frame_id.dart';
import '../../../models/layer.dart';
import '../../../models/layer_id.dart';
import '../../../models/layer_kind.dart';
import '../../../models/media_asset.dart';
import '../../../models/timeline_empty_gaps.dart' show emptyGapsBetween;
import '../../../models/timeline_exposure.dart';
import '../../../models/timeline_repeat.dart' show rederiveRunBehaviors;
import '../../../models/track_se_window.dart';
import '../../../models/project_frame_rate.dart';
import '../../../services/audio/audio_peaks_extractor.dart';
import '../../timeline/timeline_drag_preview.dart';

/// A FILE FROM THE POOL, HELD OVER THE TIMELINE — 「끄는 동안 보이는 것은
/// 놓았을 때 생길 것이다」 (미디어 배치 라운드 2d 2부).
///
/// 🚨★★★**ONE PUBLISHER.** Every silhouette the round asks for is this
/// object's, on the ONE preview channel every other drag already uses
/// ([TimelineDragPreview]), so a file being dragged and a block being
/// dragged are shown by the same code. ⛔A second surface that drew its own
/// idea of the drop is exactly the split the user refused (2026-09-12:
/// 「법 하나로 통일하면서 기존에있는거 잘 쓰면서」).
///
/// ⛔**IT PLANS NOTHING OF ITS OWN.** What the blocks in the way do comes
/// back from [planDrawingRangeMove] — the planner the landing itself runs
/// ([ImportLanding] 의 `_landIntoRow`), which is the planner a BLOCK drag
/// runs. That is what makes 「밀림까지 실시간」 true rather than similar
/// (Q1, 2026-09-12).
///
/// ⚠️It mints NO ids. The cells a drop would author do not exist, so the
/// preview carries placeholder [FrameId]s that never reach the repository —
/// the commit reads its own plan, never this channel ([DrawingBlockMoveDrag]
/// says the same about its own preview). Minting here would burn an id per
/// pointer step on a drag that may never land.
class MediaPlacementDrag {
  MediaPlacementDrag({
    required ValueNotifier<TimelineDragPreview?> preview,
    required Layer? Function(LayerId layerId) layerById,
    required int Function() cutFrameCount,
    required MediaAsset? Function(String path) assetFor,
    required AudioPeaks? Function(String path) peaksFor,
    required ProjectFrameRate Function() frameRate,
    required Layer? Function(LayerId layerId) seRowFor,
    required TrackSeWindow Function() seWindow,
  }) : _preview = preview,
       _layerById = layerById,
       _cutFrameCount = cutFrameCount,
       _assetFor = assetFor,
       _peaksFor = peaksFor,
       _frameRate = frameRate,
       _seRowFor = seRowFor,
       _seWindow = seWindow;

  final ValueNotifier<TimelineDragPreview?> _preview;
  final Layer? Function(LayerId layerId) _layerById;
  final int Function() _cutFrameCount;

  /// The pool entry for a path — the PROJECT's own lookup
  /// ([Project.mediaAssetByPath]). ⛔Not a scan of its own: 「이 경로의 풀
  /// 항목」은 이미 답이 있는 질문이고, 두 번째 구현은 사본이다.
  final MediaAsset? Function(String path) _assetFor;
  final AudioPeaks? Function(String path) _peaksFor;
  final ProjectFrameRate Function() _frameRate;

  /// The SE row by id, in its TRACK-global form, and the converter between
  /// the cut's frames and the track's — the two doors `landSound` uses.
  /// ⛔[_layerById] is not one of them: it walks the open cut, and an SE row
  /// is not in it.
  final Layer? Function(LayerId layerId) _seRowFor;
  final TrackSeWindow Function() _seWindow;

  /// The file stands over [layerId]'s frame area at [frameIndex]: draw what
  /// letting go there would make.
  ///
  /// ⚠️Whether it may land there at all is NOT asked here — the entrance
  /// already asked it (`dropSpotFor`), and a second answer is a second rule.
  /// This draws what the caller says is a landing.
  void showOnFrames({
    required LayerId layerId,
    required int frameIndex,
    required String path,
  }) {
    final row = _layerById(layerId);
    if (row == null) {
      return clear();
    }
    final count = _cellsFor(path);
    if (count == null || count < 1) {
      // Nothing yet says how long this file is (a sound whose conform has
      // not answered). Nothing is drawn rather than a length invented.
      return clear();
    }
    final after = planDrawingRangeMove(
      source: _placedCells(frameIndex, count),
      target: row,
      rangeStartIndex: frameIndex,
      rangeEndIndexExclusive: frameIndex + count,
      // The cells are BUILT where they would land, so the plan moves them
      // nowhere — the same shape `_landIntoRow` hands it after the window.
      frameDelta: 0,
      cutFrameCount: _cutFrameCount(),
    )?.targetAfter;
    if (after == null) {
      return clear();
    }
    _preview.value = MediaPlacementPreview(
      previewLayers: {
        layerId: rederiveRunBehaviors(after, cutFrameCount: _cutFrameCount()),
      },
      silhouette: (
        layerId: layerId,
        startIndex: frameIndex,
        endIndexExclusive: frameIndex + count,
      ),
    );
  }

  /// A SOUND over an SE row's empty cell: the block it would start there,
  /// as long as the sound and no longer than the gap (「다음 블록까지」).
  ///
  /// ⛔Only the SPAN, and no preview row. A sound lands through
  /// `planSeTakePlacement` — the one planner for putting a sound on a row —
  /// and a preview that wrote the block itself would be the second way in
  /// that the landing's own comment forbids. Nothing moves for a sound, so
  /// there is nothing else to show.
  /// 🚨An SE row lives on the TRACK, not in the cut: [_layerById] answers
  /// null for one, which is why the first draft of this drew nothing at all
  /// (the mutant that removed its body survived — the hole and the bug were
  /// the same hole). The row comes from the track door and the cell is
  /// converted onto the track's axis, exactly as `landSound` does it.
  void showOnSeCell({
    required LayerId layerId,
    required int frameIndex,
    required String path,
  }) {
    final row = _seRowFor(layerId);
    final peaks = _peaksFor(path);
    if (row == null || peaks == null) {
      // No row, or no conform yet: nothing is drawn rather than a length
      // invented (the conform answers asynchronously and the hover cannot
      // wait for it).
      return clear();
    }
    final start = _seWindow().toGlobalFrame(frameIndex);
    final gaps = emptyGapsBetween(
      row,
      start,
      start + peaks.durationFrames(_frameRate()),
    );
    // ⛔The landing's own two rules, not a second reading of them: the gap
    // must begin AT the cell, and the block is as long as the gap answers
    // (「다음 블록까지」). `landSound` refuses and clips by exactly these.
    if (gaps.isEmpty || gaps.first.startIndex != start) {
      return clear();
    }
    _preview.value = MediaPlacementPreview(
      // Back on the CUT's axis by construction: the drop's own cell, plus a
      // length the track's axis measured. The row that paints this is the
      // cut-local display clone, and a global index would land elsewhere.
      silhouette: (
        layerId: layerId,
        startIndex: frameIndex,
        endIndexExclusive: frameIndex + gaps.first.length,
      ),
    );
  }

  /// The file stands in the gap [slot] of the LAYER AREA: draw the ROW it
  /// would make there (유저 2026-09-12, Q2: 「목업대로 — 실루엣 행을
  /// 끼운다」).
  ///
  /// What KIND of row, and how long its block, is the landing's own branch
  /// asked at hover time: one picture becomes an image row holding the cut
  /// (`planStillImageLayer`), and several become cels (`planSequenceLayer`).
  /// The count is the pool's, which is the count the bake writes — so the
  /// row drawn here is the row that appears.
  ///
  /// ⚠️Whether a row may go in that gap is NOT asked here: the rail's caret
  /// already asked it (`newRowInsertionForSlot`), and the caller only draws
  /// where that said yes.
  void showOnLayerSlot({required int slot, required String path}) {
    final count = _cellsFor(path) ?? 1;
    final cut = _cutFrameCount();
    _preview.value = MediaPlacementPreview(
      silhouetteSlot: slot,
      silhouetteRow: count == 1
          ? Layer(
              id: _previewRowId,
              name: mediaAssetDefaultName(path),
              kind: LayerKind.image,
              frames: [
                Frame(
                  id: const FrameId('placement-preview-0'),
                  duration: cut,
                  strokes: const [],
                ),
              ],
              timeline: SplayTreeMap<int, TimelineExposure>.of({
                0: TimelineExposure.drawing(
                  const FrameId('placement-preview-0'),
                  length: cut < 1 ? 1 : cut,
                ),
              }),
            )
          : _placedCells(0, count).copyWith(name: mediaAssetDefaultName(path)),
    );
  }

  /// The file left, or was let go: this drag's preview goes — and only
  /// this one, never a block drag's.
  void clear() {
    if (_preview.value is MediaPlacementPreview) {
      _preview.value = null;
    }
  }

  /// How many cells [path] would become — the pool's own count, which is
  /// the number the bake writes ([planSequenceLayer] registers
  /// `frameCount: sourceFiles.length`). A file with no count is one cell:
  /// a still is one picture.
  int? _cellsFor(String path) => _assetFor(path)?.frameCount ?? 1;

  /// [count] cells standing at [frameIndex] — a row that exists only to be
  /// planned with.
  ///
  /// 🚨★★★**ITS ID MUST NOT BE THE TARGET'S.** [planDrawingRangeMove] reads
  /// `source.id == target.id` as a SAME-ROW slide and answers null for a
  /// delta of zero — so a synthetic row wearing the target's id silently
  /// produced no preview at all (measured: every silhouette assertion came
  /// back null). A DIFFERENT id is not a trick to get past that: it is the
  /// shape the landing itself passes (`_landIntoRow` plans a freshly minted
  /// row ONTO the real one), and the cross-row path is the one that pushes
  /// what is in the way — which is the whole of 「밀림까지 실시간」.
  ///
  /// ⚠️The ids are placeholders and never reach the repository: the commit
  /// reads its own plan, never this channel.
  static const LayerId _previewRowId = LayerId('placement-preview');

  Layer _placedCells(int frameIndex, int count) => Layer(
    id: _previewRowId,
    name: '',
    frames: [
      for (var i = 0; i < count; i += 1)
        Frame(
          id: FrameId('placement-preview-$i'),
          duration: 1,
          strokes: const [],
        ),
    ],
    timeline: SplayTreeMap<int, TimelineExposure>.of({
      for (var i = 0; i < count; i += 1)
        frameIndex + i: TimelineExposure.drawing(
          FrameId('placement-preview-$i'),
          length: 1,
        ),
    }),
  );
}
