import '../../models/attached_layer_resolve.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_mark.dart';
import '../../services/commands/update_layer_mark_command.dart';
import 'active_cut_edits.dart';
import 'row_sweep.dart';
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
    required TimelineAccess timeline,
    required ActiveCutEdits activeCut,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _activeCut = activeCut;

  final ActiveCutEdits _activeCut;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;

  /// Sets [layerId]'s organizational color mark. One undo step.
  void setLayerMark(LayerId layerId, LayerMark mark) =>
      _activeCut.onActiveCutQuietly(
        (cutId) => _project.cutCommandCoordinator.setLayerMark(
          cutId: cutId,
          layerId: layerId,
          mark: mark,
        ),
      );

  /// Clears every layer mark of the active cut (track-owned SE rows
  /// included, like the sheet sweep) — one undo.
  void clearAllLayerMarks() {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return;
    }
    final cutId = cut.id;
    final swept = sweepRows(
      history: _project.historyManager,
      rows: [...cut.layers, ..._selection.activeTrack.seLayers],
      description: 'Clear all layer marks',
      commandFor: (layer) => layer.mark == LayerMark.none
          ? null
          : UpdateLayerMarkCommand(
              repository: _project.repository,
              cutId: cutId,
              layerId: layer.id,
              mark: LayerMark.none,
            ),
    );
    if (swept) {
      _changes.notifyChanged();
    }
  }

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
        (ids, selection) => _timeline.timelineController.markableFramesInBand(
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
    (layer) => _timeline.timelineController.canToggleMarkAt(
      layer: layer,
      frameIndex: _timeline.timelineController.currentFrameIndex,
    ),
  );

  void toggleMarkAtCurrentFrame() {
    final banded = _markableFramesForSelection();
    if (banded.isNotEmpty) {
      // SET the whole band one way, never toggle each frame: a mixed band
      // would invert under the hand and hand back the complement of what
      // was there. All marked → clear; anything unmarked → mark them all.
      _timeline.timelineController.setMarksForFrames(
        banded,
        marked: !_timeline.timelineController.bandFramesAreAllMarked(banded),
      );
      _changes.notifyChanged();
      return;
    }
    final layer = _selection.activeLayer;
    if (layer == null || !canToggleMarkAtCurrentFrame) {
      return;
    }

    _timeline.timelineController.toggleMarkForLayer(layerId: layer.id);
    _changes.notifyChanged();
  }

  bool hasMarkForLayer(Layer layer, int frameIndex) {
    if (!layer.kind.holdsDrawings) {
      return false;
    }
    return _timeline.timelineController.hasMarkAt(
      layer: layer,
      frameIndex: frameIndex,
    );
  }
}
