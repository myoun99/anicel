import '../../models/attached_layer_resolve.dart';
import '../../models/frame.dart' show InbetweenMark;
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

  /// The press of [mark]'s button (I-130: ○ is mark 1, ● mark 2) — on the
  /// band's cells, else the active row's cell under the playhead.
  void toggleMarkAtCurrentFrame(InbetweenMark mark) {
    final banded = _markableFramesForSelection();
    if (banded.isNotEmpty) {
      _toggleMarksOf(banded, mark);
      return;
    }
    final layer = _selection.activeLayer;
    if (layer == null || !canToggleMarkAtCurrentFrame) {
      return;
    }

    _controllers.timelineController.toggleMarkForLayer(
      layerId: layer.id,
      mark: mark,
    );
    _changes.notifyChanged();
  }

  /// A mark's law over many cells — what a press of [mark] that toggles
  /// [frames] does to them, as ONE undo step. SET them one way, never toggle
  /// each: a mix would invert under the hand and hand back the complement
  /// of what was there. All wearing [mark] → clear; anything else → [mark]
  /// on them all.
  void _toggleMarksOf(Map<LayerId, List<int>> frames, InbetweenMark mark) {
    final timeline = _controllers.timelineController;
    timeline.setMarksForFrames(
      frames,
      mark: timeline.bandFramesAreAllMarked(frames, mark) ? null : mark,
    );
    _changes.notifyChanged();
  }

  /// 🗣️I-58 (유저 2026-10-01): 「중간나누기 마크 자동추가. 대상은 중간나누기
  /// 마크가 적용가능한 행의 선택된블록들or현재 인덱스 블록, 각자 현재 블록
  /// 안에서 블록이 끝날때까지, n코마마다 중간나누기 마크 추가 … 3적고
  /// 확인누르면 현재 블록에서 헤더부터 시작해서 3코마마다 점 찍음. 즉
  /// 1--------- 이렇게있으면, 1--.--.--.」
  ///
  /// 🗣️F-402 (유저 2026-10-19): 「선택된대상 블록이 있을때의 동작은 지금과
  /// 같음. 다만 선택된게 없는 상황에서, 지금 헤드부터 시작해서 마크
  /// 추가하는데, 그게아니라 현재 인덱스부터 시작해서 마크를 추가함. 참고로
  /// 현재 인덱스에도 마크찍도록. 즉 마크를 중간부터 일정하게 찍고싶을때 쓰는
  /// 동작」.
  ///
  /// The cells [every] koma apart, to the block's end, per row: in each
  /// block the band takes, from its head; with no band, in the block under
  /// the playhead, from the playhead's cell. It climbs the ● ladder
  /// ([canToggleMarkAtCurrentFrame]) in blocks rather than cells: the
  /// band's blocks on the rows that take marks — the blocks the comma
  /// press takes there ([RangeSelections.selectionBlockStarts]) — else the
  /// block under the playhead on the active row. A ghost is no block of
  /// its own. ↩️With no band it counted from the block's head too (I-58).
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
                ..._everyFrom(layer, start, from: start, every: every),
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
    final here = _controllers.timelineController.currentFrameIndex;
    final block = coveringDrawingBlockAt(layer.timeline, here);
    if (block == null || block.entry.ghost) {
      return const {};
    }
    return _withFrames({
      layer.id: [
        ..._everyFrom(layer, block.startIndex, from: here, every: every),
      ],
    });
  }

  /// The cells [every] koma apart from [from], to the end of [layer]'s
  /// block at [start] — held cells all, where a mark stands
  /// ([TimelineController.canToggleMarkAt]): the head, the drawing itself,
  /// is passed by when the count starts on it (F-402: 「현재 인덱스가
  /// 헤드면 자연스럽게 무시」).
  static Iterable<int> _everyFrom(
    Layer layer,
    int start, {
    required int from,
    required int every,
  }) sync* {
    final end = start + (layer.timeline[start]?.length ?? 1);
    for (var frame = from; frame < end; frame += every) {
      if (frame != start) {
        yield frame;
      }
    }
  }

  static Map<LayerId, List<int>> _withFrames(
    Map<LayerId, List<int>> byLayer,
  ) => {
    for (final MapEntry(key: id, value: frames) in byLayer.entries)
      if (frames.isNotEmpty) id: frames,
  };

  /// Lit while the press names a cell to dot — what a press of 1 would.
  bool get canMarkEvery => _framesEvery(1).isNotEmpty;

  /// Toggles the cells [_framesEvery] names by the ●'s law over many
  /// ([_toggleMarksOf]). One undo step.
  ///
  /// 🗣️F-402 (유저 2026-10-19): 「중간나누기 마크는 토글이기 때문에 마크가
  /// 존재하는 곳은 토글규칙에 따라서 마크 삭제」. ↩️It only added, keeping
  /// every mark the cells carried (I-58 「추가」).
  ///
  /// It lays [mark], the one its window picked: 🗣️I-130-Q2 (유저 2026-10-25
  /// 「창에서 마크를 고른다」). ↩️It laid the ● alone, the one mark there was.
  void markEvery(int every, InbetweenMark mark) {
    if (every < 1) {
      return;
    }
    final frames = _framesEvery(every);
    if (frames.isEmpty) {
      return;
    }
    _toggleMarksOf(frames, mark);
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
