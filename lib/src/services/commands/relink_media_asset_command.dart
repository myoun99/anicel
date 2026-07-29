import '../../models/cut.dart';
import '../../models/layer.dart';
import '../../models/project.dart';
import '../../models/track.dart';
import '../command.dart';
import '../project_repository.dart';

/// Points a media asset at a new file: rewrites the pool entry's path AND
/// every referencing clip across all tracks in ONE undo step — the Resolve
/// offline-media relink flow. The display name survives the move.
///
/// Undo restores the whole previous project reference (models are
/// immutable, so holding it is O(1)); untouched tracks/cuts/layers keep
/// their identity so downstream caches stay warm.
class RelinkMediaAssetCommand implements Command {
  RelinkMediaAssetCommand({
    required this.repository,
    required this.oldPath,
    required this.newPath,
  });

  final ProjectRepository repository;
  final String oldPath;
  final String newPath;

  Project? _previousProject;
  bool _hasExecuted = false;

  @override
  String get description => 'Relink media';

  @override
  void execute() {
    _previousProject ??= repository.requireProject();
    repository.updateProject(_relinked);
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previousProject = _previousProject;
    if (!_hasExecuted || previousProject == null) {
      throw StateError('Command has not been executed.');
    }
    repository.replaceProject(previousProject);
  }

  Layer _relinkedLayer(Layer layer, {required bool Function() markChanged}) {
    final referencesAsset = layer.mediaReference?.assetPath == oldPath;
    if (!referencesAsset &&
        !layer.audioClips.any((clip) => clip.filePath == oldPath)) {
      return layer;
    }
    markChanged();
    return layer.copyWith(
      audioClips: [
        for (final clip in layer.audioClips)
          clip.filePath == oldPath ? clip.copyWith(filePath: newPath) : clip,
      ],
      // The layer's MEDIA REFERENCE (§6-z23) rides the same relink walk.
      mediaReference: referencesAsset
          ? layer.mediaReference!.copyWith(assetPath: newPath)
          : layer.mediaReference,
    );
  }

  Project _relinked(Project project) {
    var tracksChanged = false;
    final tracks = <Track>[];
    for (final track in project.tracks) {
      var trackChanged = false;
      bool mark() => trackChanged = true;
      final seLayers = [
        for (final layer in track.seLayers)
          _relinkedLayer(layer, markChanged: mark),
      ];
      final cuts = <Cut>[];
      for (final cut in track.cuts) {
        var layersChanged = false;
        final layers = [
          for (final layer in cut.layers)
            _relinkedLayer(layer, markChanged: () => layersChanged = true),
        ];
        cuts.add(layersChanged ? cut.copyWith(layers: layers) : cut);
        trackChanged = trackChanged || layersChanged;
      }
      tracks.add(
        trackChanged ? track.copyWith(cuts: cuts, seLayers: seLayers) : track,
      );
      tracksChanged = tracksChanged || trackChanged;
    }
    return project.copyWith(
      mediaAssets: [
        for (final asset in project.mediaAssets)
          asset.path == oldPath ? asset.copyWith(path: newPath) : asset,
      ],
      tracks: tracksChanged ? tracks : project.tracks,
    );
  }
}
