import '../editing/cut_duplicate_helpers.dart';
import '../editing/editing_session_state.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';
import 'cut_insertion.dart';

/// A cut copied in as a cut of its own — a duplicate of one the project
/// holds, or a paste of one a board holds (I-150).
///
/// [source] is the cut AS IT WAS HANDED IN: a paste's may have been cut
/// away, drawn over or never been this project's since its copy was taken.
///
/// ⛔It lands by THE ONE INSERTION ([CutInsertion]) — room out of the gaps
/// ahead before any push (유저 #19). ↩️It put the cut in with a bare insert,
/// so a duplicate pushed the cuts behind it with room to spare in front of
/// them.
class DuplicateCutCommand implements Command {
  DuplicateCutCommand({
    required this.repository,
    required this.editingSession,
    required this.source,
    required this.targetTrackId,
    required this.newCutId,
    required this.newName,
    required this.layerIdMap,
    required this.frameIdMap,
    this.index,
    this.leadingGapFrames = 0,
  });

  final ProjectRepository repository;
  final EditingSessionState editingSession;
  final Cut source;
  final TrackId targetTrackId;
  final CutId newCutId;
  final String newName;
  final Map<LayerId, LayerId> layerIdMap;
  final Map<FrameId, FrameId> frameIdMap;
  final int? index;

  /// The copy's walk-in into the gap it lands in — a paste's, where a new
  /// cut would land there ([CutLanding]).
  final int leadingGapFrames;

  CutId? _previousActiveCutId;
  bool _hasExecuted = false;

  @override
  String get description => 'Duplicate cut ${source.id}';

  late final CutInsertion _insertion = CutInsertion(
    trackId: targetTrackId,
    cut: duplicateCutAsIndependentCopy(
      source: source,
      newCutId: newCutId,
      newName: newName,
      layerIdMap: layerIdMap,
      frameIdMap: frameIdMap,
    ).copyWith(leadingGapFrames: leadingGapFrames),
    index: index,
  );

  @override
  void execute() {
    _previousActiveCutId = editingSession.activeCutId;
    _insertion.apply(repository);
    editingSession.setActiveCutId(newCutId);
    _hasExecuted = true;
  }

  /// Back to the cut stood in before — none, for a paste in a gap.
  @override
  void undo() {
    if (!_hasExecuted) {
      throw StateError('Command has not been executed.');
    }

    _insertion.revert(repository);
    editingSession.setActiveCutId(_previousActiveCutId);
  }
}
