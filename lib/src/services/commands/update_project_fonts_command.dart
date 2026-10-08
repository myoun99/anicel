import '../../models/project_font_file.dart';
import '../command.dart';
import '../project_repository.dart';

/// The font files registered with the project become [fonts], in one undo
/// step — a font registered, or one a person took out (R9-rest).
///
/// The list is the unit, as the media pool's is
/// (`UpdateMediaAssetsCommand`): whoever asks says what the list is to be.
class UpdateProjectFontsCommand implements Command {
  UpdateProjectFontsCommand({
    required this.repository,
    required this.fonts,
    this.description = 'Change project fonts',
  });

  final ProjectRepository repository;
  final List<ProjectFontFile> fonts;

  @override
  final String description;

  List<ProjectFontFile>? _previousFonts;
  bool _hasExecuted = false;

  @override
  void execute() {
    _previousFonts ??= repository.requireProject().fonts;
    repository.updateFonts(fonts);
    _hasExecuted = true;
  }

  @override
  void undo() {
    final previous = _previousFonts;
    if (!_hasExecuted || previous == null) {
      throw StateError('Command has not been executed.');
    }
    repository.updateFonts(previous);
  }
}
