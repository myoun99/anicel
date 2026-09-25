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
    this.carriedAs,
    this.description = 'Relink media',
  });

  final ProjectRepository repository;
  final String oldPath;
  final String newPath;

  /// The carry the asset is after the relink, when it is a new one — or
  /// null to keep the one it has ([MediaAsset.carriedAs]).
  ///
  /// 🚨A relink by HAND is a new carry: the person picked a file and said
  /// 「this asset is THAT one」, and nothing proved it holds the same bytes.
  /// Kept, the carry's one name would have meant two sets of bytes — the
  /// old file's copy an undo needs, and the picked file's (audit 09-25).
  /// The batch relink proves the identity first, so it keeps the carry,
  /// and the name goes with it.
  final String? carriedAs;

  Project? _previousProject;
  bool _hasExecuted = false;

  @override
  final String description;

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
          if (clip.filePath == oldPath)
            clip.copyWith(filePath: newPath)
          else
            clip,
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
          if (asset.path != oldPath)
            asset
          else
            // 🚨copyWith keeps what it is NOT given, so a relink moves the
            // path and leaves whatever source tracking the asset already
            // had. ⛔It does not write any: a relink says 「the same file
            // is over here now」, and where a copy came from is the copy's
            // business — see [MediaAsset.sourcePath].
            asset.copyWith(path: newPath, carriedAs: carriedAs),
      ],
      tracks: tracksChanged ? tracks : project.tracks,
    );
  }
}
