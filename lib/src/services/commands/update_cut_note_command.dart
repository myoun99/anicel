import '../../models/cut_id.dart';
import '../../models/cut_metadata.dart';
import '../command.dart';
import '../project_lookup.dart';
import '../project_repository.dart';

/// Writes the memo on one page of a cut's timesheet
/// ([CutMetadata.pageNotes]).
class UpdateCutNoteCommand implements Command {
  UpdateCutNoteCommand({
    required this.repository,
    required this.cutId,
    required this.page,
    required this.note,
  });

  final ProjectRepository repository;
  final CutId cutId;

  /// The page the memo is written on, 0-based.
  final int page;
  final String note;

  CutMetadata? _previousMetadata;
  bool _hasExecuted = false;

  @override
  String get description => 'Update cut note $cutId p$page';

  @override
  void execute() {
    _previousMetadata ??= requireCut(
      repository.requireProject(),
      cutId,
    ).metadata;
    repository.updateCutMetadata(
      cutId: cutId,
      metadata: _previousMetadata!.withPageNote(page, note),
    );
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previousMetadata = _previousMetadata;
    if (!_hasExecuted || previousMetadata == null) {
      throw StateError('Command has not been executed.');
    }

    repository.updateCutMetadata(cutId: cutId, metadata: previousMetadata);
  }
}
