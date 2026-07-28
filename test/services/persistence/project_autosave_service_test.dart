import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/project_autosave_service.dart';

/// PEN-12 #8: a NEVER-SAVED project autosaves nowhere — a dirty tick asks
/// the shell to prompt for a real file instead of piling sidecars into
/// hidden app-data folders.
void main() {
  test('a dirty NEVER-SAVED project prompts instead of writing', () async {
    final written = <String>[];
    var prompts = 0;
    var hasFile = false;
    final service = ProjectAutosaveService(
      isDirty: () => true,
      writeSnapshot: (path) async => written.add(path),
      autosavePath: () => '/projects/x.qap.autosave',
      needsProjectFile: () => !hasFile,
      onUnsavedProject: () => prompts += 1,
    );

    await service.tick();
    expect(written, isEmpty, reason: 'no silent app-data sidecars');
    expect(prompts, 1);

    // Saved (a real file exists): ticks snapshot the sidecar as ever.
    hasFile = true;
    await service.tick();
    expect(written, ['/projects/x.qap.autosave']);
    expect(prompts, 1);
  });

  test('SAVE-1: the default cadence is five minutes', () {
    final service = ProjectAutosaveService(
      isDirty: () => false,
      writeSnapshot: (_) async {},
      autosavePath: () => '/x',
    );
    expect(service.interval, const Duration(minutes: 5));
  });

  test('clean sessions neither write nor prompt', () async {
    final written = <String>[];
    var prompts = 0;
    final service = ProjectAutosaveService(
      isDirty: () => false,
      writeSnapshot: (path) async => written.add(path),
      autosavePath: () => '/projects/x.qap.autosave',
      needsProjectFile: () => true,
      onUnsavedProject: () => prompts += 1,
    );
    await service.tick();
    expect(written, isEmpty);
    expect(prompts, 0);
  });
}
