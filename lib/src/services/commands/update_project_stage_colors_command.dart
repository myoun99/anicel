import '../command.dart';
import '../project_repository.dart';

/// One stage-color change (R3b: the backdrop and/or the pasteboard) as one
/// undo step. Null leaves that plane untouched; undo restores exactly the
/// planes this command wrote.
class UpdateProjectStageColorsCommand implements Command {
  UpdateProjectStageColorsCommand({
    required this.repository,
    this.backdropArgb,
    this.pasteboardArgb,
  });

  final ProjectRepository repository;
  final int? backdropArgb;
  final int? pasteboardArgb;

  int? _previousBackdrop;
  int? _previousPasteboard;
  bool _hasExecuted = false;

  @override
  String get description => 'Change stage colors';

  @override
  void execute() {
    final project = repository.requireProject();
    if (backdropArgb != null) {
      _previousBackdrop ??= project.backdropArgb;
    }
    if (pasteboardArgb != null) {
      _previousPasteboard ??= project.pasteboardArgb;
    }
    repository.updateProjectStageColors(
      backdropArgb: backdropArgb,
      pasteboardArgb: pasteboardArgb,
    );
    _hasExecuted = true;
  }

  @override
  void undo() {
    if (!_hasExecuted) {
      throw StateError('Command has not been executed.');
    }
    repository.updateProjectStageColors(
      backdropArgb: _previousBackdrop,
      pasteboardArgb: _previousPasteboard,
    );
  }
}
