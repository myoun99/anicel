import '../../models/bitmap_surface.dart';
import '../../services/commands/set_cut_layers_command.dart';
import '../../services/editing/layer_merge_plan.dart';
import '../../services/import/raster_cel_import.dart' show bakeCelSurface;
import 'layer_verbs.dart';
import 'render_caches.dart';
import 'row_selection.dart';
import 'session_roles.dart';

/// A press of MERGE as the session asks it and lands it (I-78): what it
/// makes of the selected rows ([planLayerMerge]), each picture laid on its
/// new cel, and the rows made the one row it planned.
///
/// The pictures are drawn by the press between the two: a frame of the cut
/// drawn is a picture of the screen, and that is the UI's
/// (`mergeLayerRows`), as a rasterize's is (`rasterizeReferenceRows`).
class LayerMerging {
  LayerMerging({
    required ProjectAccess project,
    required ChangeSink changes,
    required FrameIds frameIds,
    required RenderCaches renderCaches,
    required RowSelection rowSelection,
    required LayerVerbs layerVerbs,
  }) : _project = project,
       _changes = changes,
       _frameIds = frameIds,
       _renderCaches = renderCaches,
       _rowSelection = rowSelection,
       _layerVerbs = layerVerbs;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final RenderCaches _renderCaches;
  final RowSelection _rowSelection;
  final LayerVerbs _layerVerbs;

  static const String _step = 'Merge layers';

  /// Whether MERGE takes anything of the active cut's selected rows — its
  /// button's light, from the taking [planOfSelection] plans from.
  bool get mergesSelection => _takingOfSelection() != null;

  LayerMergeTaking? _takingOfSelection() => switch (_project.activeCutOrNull) {
    null => null,
    final cut => takeRowsToMerge(
      cut: cut,
      selected: {..._rowSelection.selectedLayerIds},
      isLinked: (row) => _layerVerbs.isLayerLinked(row.id),
    ),
  };

  /// What MERGE makes of the active cut's selected rows — null where it
  /// merges nothing.
  LayerMergePlan? planOfSelection() {
    final taking = _takingOfSelection();
    if (taking == null) {
      return null;
    }
    final store = _renderCaches.brushFrameStore;
    return planLayerMerge(
      taking,
      revisionOf: (layerId, frameId) => store.sourceRevisionOf(
        _project.brushFrameKeyForCut(taking.cut, layerId, frameId),
      ),
      mintFrameId: _frameIds.mintFrameId,
    );
  }


  /// [surface] laid as [picture]'s cel — as every door lays a cel it makes
  /// ([bakeCelSurface]), ahead of the row that shows it: the cel is new,
  /// so nothing shows it until the merge lands, and a merge undone leaves
  /// it to nobody.
  void layPicture(
    LayerMergePlan plan,
    LayerMergePicture picture,
    BitmapSurface surface,
  ) => bakeCelSurface(
    _renderCaches.brushFrameStore,
    _project.brushFrameKeyForCut(plan.cut, picture.rowId, picture.frameId),
    surface,
  );

  /// The rows [plan] takes made its one row, and the rows riding it with
  /// their new cels, as ONE write and ONE undo step ([SetCutLayersCommand])
  /// — standing on it after; or nothing, when its cut has changed since it
  /// was planned.
  bool land(LayerMergePlan plan) {
    final cut = plan.cut;
    if (_project.cutById(cut.id) != cut) {
      return false;
    }
    _project.historyManager.execute(
      SetCutLayersCommand(
        repository: _project.repository,
        cutId: cut.id,
        layers: plan.layers,
        description: _step,
      ),
    );
    _rowSelection.clearRowSelection();
    _changes.refreshAfterCutCommand(preferredActiveLayerId: plan.result.id);
    _changes.notifyChanged();
    return true;
  }
}
