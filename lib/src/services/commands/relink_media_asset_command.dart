import '../../models/project.dart';
import '../command.dart';
import '../media/media_moves.dart';
import '../project_repository.dart';

/// Points a media asset at a new file: rewrites the pool entry's path AND
/// every reference to it — clips, rows, the work's pictures
/// ([projectWithMediaMoved]) — in ONE undo step, the Resolve offline-media
/// relink flow. The display name survives the move.
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

  /// The walk every move of a file takes ([projectWithMediaMoved]), and the
  /// carry a relink by hand gives the asset ([carriedAs]).
  Project _relinked(Project project) {
    final moved = projectWithMediaMoved(project, {oldPath: newPath});
    final carriedAs = this.carriedAs;
    if (carriedAs == null) {
      return moved;
    }
    return moved.copyWith(
      mediaAssets: [
        for (final asset in moved.mediaAssets)
          if (asset.path == newPath)
            asset.copyWith(carriedAs: carriedAs)
          else
            asset,
      ],
    );
  }
}
