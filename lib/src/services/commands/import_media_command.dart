import '../editing/editing_session_state.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/media_asset.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';
import 'add_layer_command.dart';
import 'cut_command_input_planner.dart' show AddLayerCommandInputPlan;
import 'cut_insertion.dart';

/// ONE import lands as ONE undo step: prebuilt cuts insert into the
/// track, prebuilt layers insert into an existing cut, and the media pool
/// gains the batch's registrations — together. The cel PIXELS are baked
/// into the brush-frame store outside this command (store bytes are
/// keyed, not command state — undoing the structure strands them
/// harmlessly and redo finds them again, exactly like drawn cels).
class ImportMediaCommand implements Command {
  ImportMediaCommand({
    required this.repository,
    required this.editingSession,
    this.trackId,
    this.newCuts = const [],
    this.newCutIndex,
    this.targetCutId,
    this.newLayers = const [],
    this.layerPlans = const [],
    this.layerInsertionIndex,
    this.assetAdditions = const [],
    String? description,
  }) : _description = description ?? 'Import media';

  final ProjectRepository repository;
  final EditingSessionState editingSession;

  /// Where [newCuts] go (required when they exist).
  final TrackId? trackId;
  final List<Cut> newCuts;

  /// The track slot the first of [newCuts] takes, the rest following it in
  /// order — where a drop put a new cut. Null is after the track's last cut,
  /// which is where every import landed before a drop could name the place.
  final int? newCutIndex;

  /// Where [newLayers] insert (required when they exist); they land on
  /// TOP of the stack (list end) unless [layerInsertionIndex] names a slot.
  final CutId? targetCutId;
  final List<Layer> newLayers;

  /// [newLayers]' copies in [targetCutId]'s 겸용 siblings, one plan per row
  /// ([planAddLayersCommandInput]) — none for a cut that has none. Each row
  /// goes in as an added row does ([AddLayerCommand]), copies and all
  /// (F-398).
  final List<AddLayerCommandInputPlan> layerPlans;

  /// The cut-list slot the first of [newLayers] takes, the rest following
  /// it in order — a canvas drop's "directly above the active layer". Null
  /// is the top.
  final int? layerInsertionIndex;

  /// Pool registrations riding the same undo (reference-mode sources).
  final List<MediaAsset> assetAdditions;

  final String _description;

  CutId? _previousActiveCutId;
  List<MediaAsset>? _poolBefore;
  bool _hasExecuted = false;

  /// The new cuts' insertions, made once so a redo takes exactly the room
  /// the first run took ([CutInsertion]).
  List<CutInsertion>? _cutInsertions;

  /// The new rows' adds, made once for the same reason.
  List<AddLayerCommand>? _layerAdds;

  @override
  String get description => _description;

  @override
  void execute() {
    final project = repository.requireProject();
    _previousActiveCutId = editingSession.activeCutId;
    _poolBefore ??= project.mediaAssets;

    if (assetAdditions.isNotEmpty) {
      final known = {for (final asset in project.mediaAssets) asset.path};
      repository.updateMediaAssets([
        ...project.mediaAssets,
        for (final asset in assetAdditions)
          if (known.add(asset.path)) asset,
      ]);
    }
    if (newCuts.isNotEmpty) {
      final track = trackId;
      if (track == null) {
        throw StateError('Importing cuts needs a track id.');
      }
      final first = newCutIndex;
      final insertions = _cutInsertions ??= [
        for (var at = 0; at < newCuts.length; at += 1)
          CutInsertion(
            trackId: track,
            cut: newCuts[at],
            index: first == null ? null : first + at,
          ),
      ];
      for (final insertion in insertions) {
        insertion.apply(repository);
      }
      editingSession.setActiveCutId(newCuts.first.id);
    }
    if (newLayers.isNotEmpty) {
      final cutId = targetCutId;
      if (cutId == null) {
        throw StateError('Importing layers needs a target cut id.');
      }
      final at = layerInsertionIndex;
      final adds = _layerAdds ??= [
        for (var index = 0; index < newLayers.length; index += 1)
          AddLayerCommand(
            repository: repository,
            cutId: cutId,
            layer: newLayers[index],
            insertionIndex: at == null ? null : at + index,
            mirrors: index < layerPlans.length
                ? layerPlans[index].mirrors
                : const [],
            linkGroupId: index < layerPlans.length
                ? layerPlans[index].linkGroupId
                : null,
          ),
      ];
      for (final add in adds) {
        add.execute();
      }
    }
    _hasExecuted = true;
  }

  @override
  void undo() {
    final poolBefore = _poolBefore;
    final previousActiveCutId = _previousActiveCutId;
    if (!_hasExecuted || poolBefore == null) {
      throw StateError('Command has not been executed.');
    }
    for (final add in (_layerAdds ?? const <AddLayerCommand>[]).reversed) {
      add.undo();
    }
    for (final insertion in (_cutInsertions ?? const <CutInsertion>[]).reversed) {
      insertion.revert(repository);
    }
    repository.updateMediaAssets(poolBefore);
    editingSession.setActiveCutId(previousActiveCutId);
  }
}
