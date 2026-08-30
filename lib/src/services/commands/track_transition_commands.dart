import '../../models/layer.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';

/// Replaces a track's TRANSITION row wholesale (one undo step).
///
/// The row is a fixture — never added, never removed — so every edit to it
/// is a replacement of its span map, exactly the shape
/// `UpdateLayerInstructionsCommand` has for a cut's direction row. Keeping
/// the whole layer as the unit means an undo restores the spans and the
/// row's own flags together, and there is no partial state to reason about.
class UpdateTrackTransitionLayerCommand implements Command {
  UpdateTrackTransitionLayerCommand({
    required this.repository,
    required this.trackId,
    required this.before,
    required this.after,
    String? debugLabel,
  }) : _debugLabel = debugLabel;

  final ProjectRepository repository;
  final TrackId trackId;
  final Layer before;
  final Layer after;

  /// 🚨A DEBUG LINE, NOT A LABEL — the Command.description getter is read
  /// by no UI in this repo. ⛔It must NOT be translated: a diagnostic that
  /// changes with the reading language is a diagnostic nobody can grep.
  final String? _debugLabel;

  @override
  String get description => _debugLabel ?? 'Edit transition';

  @override
  void execute() {
    repository.updateTrackTransitionLayer(
      trackId: trackId,
      transitionLayer: after,
    );
  }

  @override
  void undo() {
    repository.updateTrackTransitionLayer(
      trackId: trackId,
      transitionLayer: before,
    );
  }
}
