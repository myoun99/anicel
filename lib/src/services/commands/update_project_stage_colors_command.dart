import '../command.dart';
import '../project_repository.dart';

/// One stage change (R3b: the backdrop and the pasteboard; F-114: whether
/// each is there at all) as one undo step. Null leaves that field untouched;
/// undo restores exactly the fields this command wrote.
class UpdateProjectStageColorsCommand implements Command {
  UpdateProjectStageColorsCommand({
    required this.repository,
    this.backdropArgb,
    this.backdropNone,
    this.pasteboardArgb,
    this.pasteboardNone,
  });

  final ProjectRepository repository;
  final int? backdropArgb;
  final bool? backdropNone;
  final int? pasteboardArgb;
  final bool? pasteboardNone;

  int? _previousBackdrop;
  bool? _previousBackdropNone;
  int? _previousPasteboard;
  bool? _previousPasteboardNone;
  bool _hasExecuted = false;

  @override
  String get description => 'Change stage colors';

  @override
  void execute() {
    final project = repository.requireProject();
    if (backdropArgb != null) {
      _previousBackdrop ??= project.backdropArgb;
    }
    if (backdropNone != null) {
      _previousBackdropNone ??= project.backdropNone;
    }
    if (pasteboardArgb != null) {
      _previousPasteboard ??= project.pasteboardArgb;
    }
    if (pasteboardNone != null) {
      _previousPasteboardNone ??= project.pasteboardNone;
    }
    repository.updateProjectStageColors(
      backdropArgb: backdropArgb,
      backdropNone: backdropNone,
      pasteboardArgb: pasteboardArgb,
      pasteboardNone: pasteboardNone,
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
      backdropNone: _previousBackdropNone,
      pasteboardArgb: _previousPasteboard,
      pasteboardNone: _previousPasteboardNone,
    );
  }
}
