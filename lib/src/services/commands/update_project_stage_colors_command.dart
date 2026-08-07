import '../command.dart';
import '../project_repository.dart';

/// One stage change (R3b: the backdrop, the pasteboard, and how far the
/// pasteboard shows) as one undo step. Null leaves that plane untouched;
/// undo restores exactly the planes this command wrote.
class UpdateProjectStageColorsCommand implements Command {
  UpdateProjectStageColorsCommand({
    required this.repository,
    this.backdropArgb,
    this.pasteboardArgb,
    this.pasteboardMargin,
  });

  final ProjectRepository repository;
  final int? backdropArgb;
  final int? pasteboardArgb;
  final double? pasteboardMargin;

  int? _previousBackdrop;
  int? _previousPasteboard;
  double? _previousMargin;
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
    if (pasteboardMargin != null) {
      _previousMargin ??= project.pasteboardMargin;
    }
    repository.updateProjectStageColors(
      backdropArgb: backdropArgb,
      pasteboardArgb: pasteboardArgb,
      pasteboardMargin: pasteboardMargin,
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
      pasteboardMargin: _previousMargin,
    );
  }
}
