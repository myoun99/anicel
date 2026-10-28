import '../../models/bitmap_surface.dart';
import '../../models/cut.dart';
import '../../models/layer.dart';
import '../../services/commands/delete_layer_command.dart';
import '../../services/commands/set_layer_placement_command.dart';
import '../../services/commands/update_layer_timeline_command.dart';
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
  /// button's light, from the taking [planOfSelection] plans by.
  bool get mergesSelection => switch (_project.activeCutOrNull) {
    null => false,
    final cut => layerMergeTakesAny(
      cut: cut,
      selected: {..._rowSelection.selectedLayerIds},
      isLinked: _isLinked,
    ),
  };

  bool _isLinked(Layer row) => _layerVerbs.isLayerLinked(row.id);

  /// What MERGE makes of the active cut's selected rows, with the cut it
  /// was asked of — null where it merges nothing.
  ({Cut cut, LayerMergePlan plan})? planOfSelection() {
    final cut = _project.activeCutOrNull;
    if (cut == null) {
      return null;
    }
    final store = _renderCaches.brushFrameStore;
    final plan = planLayerMerge(
      cut: cut,
      selected: {..._rowSelection.selectedLayerIds},
      revisionOf: (layerId, frameId) => store.sourceRevisionOf(
        _project.brushFrameKeyForCut(cut, layerId, frameId),
      ),
      mintFrameId: _frameIds.mintFrameId,
      isLinked: _isLinked,
    );
    return plan == null ? null : (cut: cut, plan: plan);
  }

  /// [surface] laid as [picture]'s cel of [plan]'s row in [cut] — as every
  /// door lays a cel it makes ([bakeCelSurface]), ahead of the row that
  /// shows it: the cel is new, so nothing shows it until the merge lands,
  /// and a merge undone leaves it to nobody.
  void layPicture(
    Cut cut,
    LayerMergePlan plan,
    LayerMergePicture picture,
    BitmapSurface surface,
  ) => bakeCelSurface(
    _renderCaches.brushFrameStore,
    _project.brushFrameKeyForCut(cut, plan.result.id, picture.frameId),
    surface,
  );

  /// The rows [plan] takes made its one row, as ONE undo step, standing on
  /// it — or nothing, when [cut] has changed since it was planned.
  ///
  /// A row a taken folder held and the merge did not take is placed first
  /// ([LayerMergePlan.regrouped]), so no row is left in a folder that goes.
  bool land(Cut cut, LayerMergePlan plan) {
    if (_project.cutById(cut.id) != cut) {
      return false;
    }
    final history = _project.historyManager;
    final repository = _project.repository;
    history.runAsOneStep(_step, () {
      if (plan.regrouped.isNotEmpty) {
        history.execute(
          SetLayerPlacementCommand(
            repository: repository,
            cutId: cut.id,
            order: [for (final row in cut.layers) row.id],
            folderIds: plan.regrouped,
            description: _step,
          ),
        );
      }
      for (final layerId in plan.removed) {
        history.execute(
          DeleteLayerCommand(
            repository: repository,
            cutId: cut.id,
            layerId: layerId,
          ),
        );
      }
      history.execute(
        UpdateLayerTimelineCommand(
          repository: repository,
          before: cut.layers.byId(plan.result.id)!,
          after: plan.result,
        ),
      );
    });
    _rowSelection.clearRowSelection();
    _changes.refreshAfterCutCommand(preferredActiveLayerId: plan.result.id);
    _changes.notifyChanged();
    return true;
  }
}
