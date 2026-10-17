import '../../models/attached_layer_resolve.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_mark.dart';
import '../../models/timeline_coverage.dart' show coveringDrawingBlockAt;
import 'active_cut_controllers.dart';
import 'active_cut_edits.dart';
import 'range_selections.dart';
import 'session_roles.dart';

/// The LAYER MARKS — the mark a layer carries, the frames a selection can
/// mark, and toggling a mark at the current frame — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Dry-run before cutting: the rest reads none of it.
class LayerMarks {
  LayerMarks({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required ActiveCutEdits activeCut,
    required RangeSelections rangeSelections,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _controllers = controllers,
       _activeCut = activeCut,
       _rangeSelections = rangeSelections;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final ActiveCutEdits _activeCut;
  final RangeSelections _rangeSelections;

  /// Sets [layerId]'s organizational color mark. One undo step.
  void setLayerMark(LayerId layerId, LayerMark mark) =>
      _activeCut.onCutOfRowQuietly(
        layerId,
        (cutId) => _project.cutCommandCoordinator.setLayerMark(
          cutId: cutId,
          layerId: layerId,
          mark: mark,
        ),
      );

  /// 🚨결정 9 / R8-c (유저 확정 2026-08-22) — **THE MARK LEARNED THE BAND.**
  ///
  /// > 「지우기 눌렀다고해서 **현재 행만 지우는게아니라 선택된 모든게
  /// > 지워지는걸** 말하는거임. **복사든 뭐든 마찬가지**」
  ///
  /// The swept frames of the swept rows, or empty when no band is up. This
  /// is the rung the ● did not have: it used to END the ladder at a live
  /// band ([_selection.bandNamesRowsThisPressWouldMiss]) because dotting the active row
  /// while the highlight sat elsewhere would edit something nobody swept.
  /// Refusing was the honest answer for a verb that could only reach one
  /// row; now that it can reach the band, serving it is.
  ///
  /// ⚠️SYNCED attach and non-drawing rows are filtered HERE rather than in
  /// the controller, for the same reason the delete collector does it: the
  /// button and the dispatch have to read one answer, and three downstream
  /// copies of a filter is how they stop agreeing.
  Map<LayerId, List<int>> _markableFramesForSelection() =>
      _selection.bandRowsForSelection(
        _markable,
        (ids, selection) =>
            _controllers.timelineController.markableFramesInBand(
              layerIds: ids,
              startIndex: selection.startIndex,
              endIndexExclusive: selection.endIndexExclusive,
            ),
      );

  /// Whether [layer] carries cell marks of its own.
  ///
  /// ⛔ONE PREDICATE FOR THE BAND AND THE PLAYHEAD. SYNCED attach rows
  /// carry no cell marks (the base's sheet row does); free attach rows
  /// mark like normal (UI-R21 #3). ⚠️Unlike the exposure verb's, a
  /// SINGLE-CEL row IS markable: a mark is a flag on the cell, not a
  /// change to the covering block.
  static bool _markable(Layer layer) =>
      layer.kind.holdsDrawings && !isSyncedAttachedLayer(layer);

  bool get canToggleMarkForSelection =>
      _markableFramesForSelection().isNotEmpty;

  bool get canToggleMarkAtCurrentFrame => _selection.bandOrActiveRow(
    canToggleMarkForSelection,
    _markable,
    (layer) => _controllers.timelineController.canToggleMarkAt(
      layer: layer,
      frameIndex: _controllers.timelineController.currentFrameIndex,
    ),
  );

  void toggleMarkAtCurrentFrame() {
    final banded = _markableFramesForSelection();
    if (banded.isNotEmpty) {
      // SET the whole band one way, never toggle each frame: a mixed band
      // would invert under the hand and hand back the complement of what
      // was there. All marked → clear; anything unmarked → mark them all.
      _controllers.timelineController.setMarksForFrames(
        banded,
        marked: !_controllers.timelineController.bandFramesAreAllMarked(banded),
      );
      _changes.notifyChanged();
      return;
    }
    final layer = _selection.activeLayer;
    if (layer == null || !canToggleMarkAtCurrentFrame) {
      return;
    }

    _controllers.timelineController.toggleMarkForLayer(layerId: layer.id);
    _changes.notifyChanged();
  }

  /// 🗣️I-58 (유저 2026-10-01): 「중간나누기 마크 자동추가. 대상은 중간나누기
  /// 마크가 적용가능한 행의 선택된블록들or현재 인덱스 블록, 각자 현재 블록
  /// 안에서 블록이 끝날때까지, n코마마다 중간나누기 마크 추가 … 3적고
  /// 확인누르면 현재 블록에서 헤더부터 시작해서 3코마마다 점 찍음. 즉
  /// 1--------- 이렇게있으면, 1--.--.--.」
  ///
  /// The cells [every] koma apart from the head of each block the press
  /// takes, to the block's end, per row. It climbs the ● ladder
  /// ([canToggleMarkAtCurrentFrame]) in blocks rather than cells: the
  /// band's blocks on the rows that take marks — the blocks the comma
  /// press takes there ([RangeSelections.selectionBlockStarts]) — else the
  /// block under the playhead on the active row. A ghost is no block of
  /// its own.
  Map<LayerId, List<int>> _framesEvery(int every) {
    final banded = _selection.bandRowsForSelection(
      _markable,
      (ids, band) => _withFrames({
        for (final id in ids)
          if (_project.rangeLayerById(id) case final layer?)
            id: [
              for (final start in _rangeSelections.selectionBlockStarts(
                layer,
                band.startIndex,
                band.endIndexExclusive,
              ))
                ..._everyFromTheHead(layer, start, every),
            ],
      }),
    );
    if (banded.isNotEmpty || _selection.bandNamesRowsThisPressWouldMiss) {
      return banded;
    }
    final layer = _selection.activeLayer;
    if (layer == null || !_markable(layer)) {
      return const {};
    }
    final block = coveringDrawingBlockAt(
      layer.timeline,
      _controllers.timelineController.currentFrameIndex,
    );
    if (block == null || block.entry.ghost) {
      return const {};
    }
    return _withFrames({
      layer.id: [..._everyFromTheHead(layer, block.startIndex, every)],
    });
  }

  /// The cells [every] koma apart from the head of [layer]'s block at
  /// [start], to its end — held cells all, where a mark stands
  /// ([TimelineController.canToggleMarkAt]).
  static Iterable<int> _everyFromTheHead(
    Layer layer,
    int start,
    int every,
  ) sync* {
    final end = start + (layer.timeline[start]?.length ?? 1);
    for (var frame = start + every; frame < end; frame += every) {
      yield frame;
    }
  }

  static Map<LayerId, List<int>> _withFrames(
    Map<LayerId, List<int>> byLayer,
  ) => {
    for (final MapEntry(key: id, value: frames) in byLayer.entries)
      if (frames.isNotEmpty) id: frames,
  };

  /// Lit while a block the press takes has a cell past its head — what a
  /// press of 1 would dot.
  bool get canMarkEvery => _framesEvery(1).isNotEmpty;

  /// Dots the blocks [_framesEvery] names, keeping every mark they carry —
  /// 「추가」. One undo step.
  void markEvery(int every) {
    if (every < 1) {
      return;
    }
    final frames = _framesEvery(every);
    if (frames.isEmpty) {
      return;
    }
    _controllers.timelineController.setMarksForFrames(frames, marked: true);
    _changes.notifyChanged();
  }

  bool hasMarkForLayer(Layer layer, int frameIndex) {
    if (!layer.kind.holdsDrawings) {
      return false;
    }
    return _controllers.timelineController.hasMarkAt(
      layer: layer,
      frameIndex: frameIndex,
    );
  }
}
