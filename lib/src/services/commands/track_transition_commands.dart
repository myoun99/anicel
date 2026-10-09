import '../../models/layer.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';
import 'cameras_follow_their_ends.dart';

/// Replaces a track's TRANSITION row wholesale (one undo step).
///
/// The row is a fixture — never added, never removed — so every edit to it
/// is a replacement of its span map, exactly the shape
/// `UpdateLayerInstructionsCommand` has for a cut's direction row. Keeping
/// the whole layer as the unit means an undo restores the spans and the
/// row's own flags together, and there is no partial state to reason about.
///
/// An O.L taken away, or made shorter, draws its cuts for fewer frames and
/// brings in the camera keys on the frames that went
/// (I-73-camera-row-Q7) — put back on the way back
/// ([CamerasFollowTheirEnds]).
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

  late final CamerasFollowTheirEnds _cameras = CamerasFollowTheirEnds(
    repository,
  );

  @override
  String get description => _debugLabel ?? 'Edit transition';

  @override
  void execute() => _cameras.around(
    () => repository.updateTrackTransitionLayer(
      trackId: trackId,
      transitionLayer: after,
    ),
  );

  @override
  void undo() => _cameras.back(
    () => repository.updateTrackTransitionLayer(
      trackId: trackId,
      transitionLayer: before,
    ),
  );
}
