import '../../controllers/editing_session_state.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/media_asset.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';

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
    this.targetCutId,
    this.newLayers = const [],
    this.assetAdditions = const [],
    String? description,
  }) : _description = description ?? 'Import media';

  final ProjectRepository repository;
  final EditingSessionState editingSession;

  /// Where [newCuts] append (required when they exist).
  final TrackId? trackId;
  final List<Cut> newCuts;

  /// Where [newLayers] insert (required when they exist); they land on
  /// TOP of the stack (list end).
  final CutId? targetCutId;
  final List<Layer> newLayers;

  /// Pool registrations riding the same undo (reference-mode sources).
  final List<MediaAsset> assetAdditions;

  final String _description;

  CutId? _previousActiveCutId;
  List<MediaAsset>? _poolBefore;
  bool _hasExecuted = false;

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
      for (final cut in newCuts) {
        repository.insertCut(trackId: track, cut: cut);
      }
      editingSession.setActiveCutId(newCuts.first.id);
    }
    if (newLayers.isNotEmpty) {
      final cutId = targetCutId;
      if (cutId == null) {
        throw StateError('Importing layers needs a target cut id.');
      }
      for (final layer in newLayers) {
        repository.insertLayer(cutId: cutId, layer: layer);
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
    for (final layer in newLayers) {
      repository.deleteLayer(cutId: targetCutId!, layerId: layer.id);
    }
    for (final cut in newCuts) {
      repository.removeCut(cutId: cut.id);
    }
    repository.updateMediaAssets(poolBefore);
    editingSession.setActiveCutId(previousActiveCutId);
  }
}
