import '../editing/default_cut_helpers.dart';
import '../editing/editing_session_state.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_id.dart';
import '../../models/layer_id.dart';
import '../../models/track_id.dart';
import '../command.dart';
import '../project_repository.dart';
import 'cut_insertion.dart';

class CreateCutCommand implements Command {
  CreateCutCommand({
    required this.repository,
    required this.editingSession,
    required this.trackId,
    required CutId cutId,
    required LayerId layerId,
    required String name,
    this.index,
    // #18 — a gap landing walks INTO the gap: the distance from the
    // gap's start becomes the new cut's own leading gap, and a range
    // landing names its own duration. Both ride the SAME absorption
    // arithmetic below (#19): the footprint is leadingGap + duration
    // either way.
    int leadingGapFrames = 0,
    int? duration,
    CanvasSize canvasSize = defaultCutCanvasSize,
  }) : cut = _plannedCut(
         cutId: cutId,
         name: name,
         layerId: layerId,
         canvasSize: canvasSize,
         leadingGapFrames: leadingGapFrames,
         duration: duration,
       );

  static Cut _plannedCut({
    required CutId cutId,
    required String name,
    required LayerId layerId,
    required CanvasSize canvasSize,
    required int leadingGapFrames,
    required int? duration,
  }) {
    final base = createDefaultCut(
      cutId: cutId,
      name: name,
      layerId: layerId,
      canvasSize: canvasSize,
    );
    if (leadingGapFrames == 0 && duration == null) {
      return base;
    }
    return base.copyWith(
      leadingGapFrames: leadingGapFrames,
      duration: duration ?? base.duration,
    );
  }

  final ProjectRepository repository;
  final EditingSessionState editingSession;
  final TrackId trackId;
  final int? index;
  final Cut cut;

  CutId? _previousActiveCutId;
  bool _hasExecuted = false;

  /// Where [cut] goes and the room it takes — the #19 arithmetic, shared
  /// with an import's new cuts.
  late final CutInsertion _insertion = CutInsertion(
    trackId: trackId,
    cut: cut,
    index: index,
  );

  @override
  String get description => 'Create cut ${cut.name}';

  @override
  void execute() {
    _previousActiveCutId = editingSession.activeCutId;
    // 🚨★★ 유저 #19 (2026-08-15): the room this cut needs comes out of its
    // follower's leading gap first, and only what the gap cannot cover is a
    // push — [CutInsertion], where the user's words and the arithmetic live.
    _insertion.apply(repository);
    editingSession.setActiveCutId(cut.id);
    _hasExecuted = true;
  }

  @override
  void undo() {
    // ⛔Executed-ness is the ONLY guard: a null previous active cut is a
    // legitimate recorded state, not a not-run marker — creation from a
    // GAP PARKING (no cut is active there, #18) and the project's very
    // first cut both start from null, and treating null as "never ran"
    // made their undo throw.
    if (!_hasExecuted) {
      throw StateError('Command has not been executed.');
    }
    final previousActiveCutId = _previousActiveCutId;

    // ⛔The gap goes back BEFORE the active cut does, and it goes back to the
    // recorded number rather than gap+footprint: the follower may have had
    // less room than this cut took, and adding the footprint back would
    // invent frames that were never there ([CutInsertion.revert] keeps it).
    _insertion.revert(repository);
    editingSession.setActiveCutId(previousActiveCutId);
  }
}
