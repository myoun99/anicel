import '../editing/editing_session_state.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/media_asset.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';
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
      for (var index = 0; index < newLayers.length; index += 1) {
        repository.insertLayer(
          cutId: cutId,
          layer: newLayers[index],
          index: at == null ? null : at + index,
        );
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
    for (final insertion in (_cutInsertions ?? const <CutInsertion>[]).reversed) {
      insertion.revert(repository);
    }
    repository.updateMediaAssets(poolBefore);
    editingSession.setActiveCutId(previousActiveCutId);
  }
}
