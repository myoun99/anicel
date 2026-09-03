// A STAGE-COLOR EDIT UNDOES ONLY THE FIELDS IT SET.
//
// No test named this command file (audit 2026-09-04); the settings dialog
// reached it through the session. These pins drive it directly: a
// backdrop-only command restores the backdrop and leaves a pasteboard
// changed in between alone, all three fields round-trip together, and
// undo before execute is refused.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/commands/update_project_stage_colors_command.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  late ProjectRepository repository;

  setUp(() {
    repository = ProjectRepository(initialProject: createDefaultProject());
  });

  test('a backdrop-only edit undoes the backdrop and nothing else', () {
    final project = repository.requireProject();
    final backdropBefore = project.backdropArgb;
    final backdrop = UpdateProjectStageColorsCommand(
      repository: repository,
      backdropArgb: 0xFF112233,
    );
    backdrop.execute();
    expect(repository.requireProject().backdropArgb, 0xFF112233);

    // The pasteboard changes meanwhile; the backdrop's undo must not
    // carry it back.
    UpdateProjectStageColorsCommand(
      repository: repository,
      pasteboardArgb: 0xFF445566,
    ).execute();
    backdrop.undo();
    expect(repository.requireProject().backdropArgb, backdropBefore);
    expect(repository.requireProject().pasteboardArgb, 0xFF445566);
  });

  test('all three fields round-trip together', () {
    final before = repository.requireProject();
    final command = UpdateProjectStageColorsCommand(
      repository: repository,
      backdropArgb: 0xFF010203,
      pasteboardArgb: 0xFF040506,
      pasteboardMargin: 42,
    );
    command.execute();
    final after = repository.requireProject();
    expect(after.backdropArgb, 0xFF010203);
    expect(after.pasteboardArgb, 0xFF040506);
    expect(after.pasteboardMargin, 42);
    command.undo();
    final restored = repository.requireProject();
    expect(restored.backdropArgb, before.backdropArgb);
    expect(restored.pasteboardArgb, before.pasteboardArgb);
    expect(restored.pasteboardMargin, before.pasteboardMargin);
    command.execute();
    expect(repository.requireProject().pasteboardMargin, 42);
  });

  test('undo before execute is refused', () {
    expect(
      UpdateProjectStageColorsCommand(
        repository: repository,
        backdropArgb: 0xFF000000,
      ).undo,
      throwsStateError,
    );
  });
}
