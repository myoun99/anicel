import '../../models/bitmap_surface.dart';
import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart' show EffectId;
import '../../models/layer_id.dart';
import '../../models/layer_link_registry.dart' show LayerLinkRegistry;
import '../../services/commands/set_cut_layers_command.dart';
import '../../services/commands/set_cuts_layers_command.dart';
import '../../services/editing/fx_bake_plan.dart';
import '../../services/editing/layer_merge_plan.dart';
import '../../services/import/raster_cel_import.dart' show bakeCelSurface;
import '../../services/project_lookup.dart' show cutWritingRow;
import 'independent_clip_mint.dart' show copyBakedPictures;
import 'layer_verbs.dart';
import 'range_selections.dart';
import 'render_caches.dart';
import 'row_selection.dart';
import 'session_roles.dart';

/// A press of MERGE as the session asks it and lands it (I-78): what it
/// makes of the selected rows ([planLayerMerge]) or of the band's blocks
/// ([planBlockMerge]), each picture laid on its new cel, and the rows made
/// what it planned — and a press of an fx group's RASTERIZE (I-120,
/// [planFxBake]), whose pictures are baked and laid as a merge's are.
///
/// The pictures are drawn by the press between the two: a frame of the cut
/// drawn is a picture of the screen, and that is the UI's
/// (`mergeSelectionSubject`), as a rasterize's is (`rasterizeReferenceRows`).
class LayerMerging {
  LayerMerging({
    required ProjectAccess project,
    required ChangeSink changes,
    required FrameIds frameIds,
    required RenderCaches renderCaches,
    required RowSelection rowSelection,
    required RangeSelections rangeSelections,
    required LayerVerbs layerVerbs,
  }) : _project = project,
       _changes = changes,
       _frameIds = frameIds,
       _renderCaches = renderCaches,
       _rowSelection = rowSelection,
       _rangeSelections = rangeSelections,
       _layerVerbs = layerVerbs;

  final ProjectAccess _project;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final RenderCaches _renderCaches;
  final RowSelection _rowSelection;
  final RangeSelections _rangeSelections;
  final LayerVerbs _layerVerbs;

  /// Whether MERGE takes anything of the active cut's selected rows — the
  /// rows rung's light, from the taking [planOfSelection] plans from.
  bool get mergesSelection => _takingOfSelection() != null;

  /// Whether MERGE takes anything of the band's blocks — the frame axis's
  /// light, from the taking [planOfBand] plans from.
  bool get mergesBand => _takingOfBand() != null;

  bool _isLinked(Layer row) => _layerVerbs.isLayerLinked(row.id);

  LayerMergeTakings? _takingOfSelection() =>
      switch (_project.activeCutOrNull) {
        null => null,
        final cut => takeRowsToMergeAcross(
          project: _project.repository.requireProject(),
          cutId: cut.id,
          selected: {..._rowSelection.selectedLayerIds},
        ),
      };

  /// The blocks the band holds of the rows whose timing is their own, as
  /// the comma reads them ([RangeSelections.selectionBlockStartsByLayer]).
  BlockMergeTaking? _takingOfBand() => switch ((
    _project.activeCutOrNull,
    _rangeSelections.selectionBlockStartsByLayer(),
  )) {
    (final cut?, final starts?) => takeBlocksToMerge(
      cut: cut,
      blockStarts: starts,
      isLinked: _isLinked,
    ),
    _ => null,
  };

  /// What MERGE makes of the active cut's selected rows — null where it
  /// merges nothing.
  LayerMergePlan? planOfSelection() {
    final taking = _takingOfSelection();
    if (taking == null) {
      return null;
    }
    return planLayerMerge(
      taking,
      readsOf: _readsOf,
      mintFrameId: _frameIds.mintFrameId,
      reach: _project.repository.requireProject().pasteboardReach,
    );
  }

  /// How [cut]'s cels are read by a bake: what each holds, and where its
  /// ink lies.
  CelReads _readsOf(Cut cut) {
    final store = _renderCaches.brushFrameStore;
    return (
      revisionOf: (layerId, frameId) => store.sourceRevisionOf(
        _project.brushFrameKeyForCut(cut, layerId, frameId),
      ),
      inkOf: (row, cel) => _renderCaches.celContentBounds(cut, row, cel),
    );
  }

  /// Whether RASTERIZE in [rowId]'s group header for [effectId] — the
  /// transform's, where null — bakes anything: its light, from the taking
  /// [planOfFx] plans from (I-120 round ②).
  bool bakesFx(LayerId rowId, EffectId? effectId) =>
      _takingOfFx(rowId, effectId) != null;

  FxBakeTaking? _takingOfFx(
    LayerId rowId,
    EffectId? effectId, [
    BakedFrames? band,
  ]) {
    final project = _project.repository.requireProject();
    final cutId = cutWritingRow(
      project,
      rowId,
      standing: _project.activeCutOrNull?.id,
    );
    return cutId == null
        ? null
        : takeFxToBake(
            project: project,
            cutId: cutId,
            rowId: rowId,
            effectId: effectId,
          )?.over(band);
  }

  /// What RASTERIZE scoped to [band] — over every frame, where none does —
  /// makes of [rowId]'s fx [effectId]: null where it bakes nothing.
  FxBakePlan? planOfFx(
    LayerId rowId,
    EffectId? effectId, {
    BakedFrames? band,
  }) => switch (_takingOfFx(rowId, effectId, band)) {
    null => null,
    final taking => planFxBake(
      taking,
      readsOf: _readsOf,
      mintFrameId: _frameIds.mintFrameId,
    ),
  };

  /// The row [plan] bakes made what it planned in every cut it is used in,
  /// in ONE undo step, and the pictures it copies copied to their new cels
  /// ([FxBakePlan.copies]) — or nothing, when one of its cuts has changed
  /// since it was planned.
  bool landFx(FxBakePlan plan) {
    if (!_landsAcross(
      [(cut: plan.cut, layers: plan.layers), ...plan.others],
      _project.repository.requireProject().linkRegistry,
      'Rasterize fx',
    )) {
      return false;
    }
    for (final (:cut, :row, :minted) in plan.copies) {
      copyBakedPictures(
        project: _project,
        store: _renderCaches.brushFrameStore,
        minted: minted,
        from: (cut: cut, row: row),
        to: (cut: cut, row: row),
      );
    }
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
    return true;
  }

  /// What MERGE makes of the band's blocks — null where it merges none.
  BlockMergePlan? planOfBand() => switch (_takingOfBand()) {
    null => null,
    final taking => planBlockMerge(
      taking,
      mintFrameId: _frameIds.mintFrameId,
    ),
  };

  /// [surface] laid as [cut]'s cel [frameId] of [rowId] — as every door
  /// lays a cel it makes ([bakeCelSurface]), ahead of the row that shows
  /// it: the cel is new, so nothing shows it until the merge lands, and a
  /// merge undone leaves it to nobody.
  void layPicture(
    Cut cut,
    LayerId rowId,
    FrameId frameId,
    BitmapSurface surface,
  ) => bakeCelSurface(
    _renderCaches.brushFrameStore,
    _project.brushFrameKeyForCut(cut, rowId, frameId),
    surface,
  );

  /// The rows [plan] takes made its one row in every cut it reaches, and
  /// the rows riding it with their new cels — standing on it after; or
  /// nothing, when one of its cuts has changed since it was planned.
  ///
  /// Every cut and the link table as ONE write and ONE undo step
  /// ([SetCutsLayersCommand]).
  bool land(LayerMergePlan plan) {
    if (!_landsAcross(
      [(cut: plan.cut, layers: plan.layers), ...plan.others],
      plan.links,
      'Merge layers',
    )) {
      return false;
    }
    _rowSelection.clearRowSelection();
    _changes.refreshAfterCutCommand(preferredActiveLayerId: plan.result.id);
    _changes.notifyChanged();
    return true;
  }

  /// Each row's blocks [plan] takes made one — the band let go, as every
  /// cut command lets it go ([ChangeSink.refreshAfterCutCommand]); or
  /// nothing, when its cut has changed since it was planned.
  bool landBlocks(BlockMergePlan plan) {
    if (!_lands(plan.cut, plan.layers, 'Merge blocks')) {
      return false;
    }
    _changes.refreshAfterCutCommand();
    _changes.notifyChanged();
    return true;
  }

  /// Each of [cuts] written its rows after, and the link table [links], as
  /// ONE write and ONE undo step ([SetCutsLayersCommand]) — none when a cut
  /// is no longer what it was.
  bool _landsAcross(
    List<({Cut cut, List<Layer> layers})> cuts,
    LayerLinkRegistry links,
    String step,
  ) {
    if (cuts.any((each) => _project.cutById(each.cut.id) != each.cut)) {
      return false;
    }
    _project.historyManager.execute(
      SetCutsLayersCommand(
        repository: _project.repository,
        layers: {for (final each in cuts) each.cut.id: each.layers},
        links: links,
        description: step,
      ),
    );
    return true;
  }

  /// [cut]'s rows written [layers] as ONE write and ONE undo step
  /// ([SetCutLayersCommand]) — none when the cut is no longer [cut].
  bool _lands(Cut cut, List<Layer> layers, String step) {
    if (_project.cutById(cut.id) != cut) {
      return false;
    }
    _project.historyManager.execute(
      SetCutLayersCommand(
        repository: _project.repository,
        cutId: cut.id,
        layers: layers,
        description: step,
      ),
    );
    return true;
  }
}
