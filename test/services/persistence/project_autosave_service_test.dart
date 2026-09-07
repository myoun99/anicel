import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/project_autosave_service.dart';

/// The autosave service decides WHETHER; the shell decides WHEN.
///
/// PEN-12 #8: a NEVER-SAVED project has nowhere to write — a dirty pass asks
/// the shell to prompt for a real file instead of piling files into hidden
/// app-data folders for a document with no identity yet.
void main() {
  test('a dirty NEVER-SAVED project prompts instead of writing', () async {
    final written = <String>[];
    var prompts = 0;
    var hasFile = false;
    final service = ProjectAutosaveService(
      isDirty: () => true,
      saveProject: (path) async => written.add(path),
      projectPath: () => '/projects/x.anicel',
      needsProjectFile: () => !hasFile,
      onUnsavedProject: () => prompts += 1,
    );

    await service.saveNow();
    expect(written, isEmpty, reason: 'no silent writes into app-data');
    expect(prompts, 1);

    // Saved (a real file exists): the tick saves the PROJECT FILE.
    hasFile = true;
    await service.saveNow();
    expect(written, ['/projects/x.anicel']);
    expect(prompts, 1);
  });

  test('clean sessions neither write nor prompt', () async {
    final written = <String>[];
    var prompts = 0;
    final service = ProjectAutosaveService(
      isDirty: () => false,
      saveProject: (path) async => written.add(path),
      projectPath: () => '/projects/x.anicel',
      needsProjectFile: () => true,
      onUnsavedProject: () => prompts += 1,
    );
    await service.saveNow();
    expect(written, isEmpty);
    expect(prompts, 0);
  });

  test('a burst of triggers writes ONCE', () async {
    // One trip to the home screen sends inactive, then hidden, then
    // paused, and the shell wires all three because no platform promises
    // which it will send. Without collapsing them, leaving the app would
    // rewrite the same snapshot three times — the last two over a file the
    // first is still writing.
    var inFlight = 0;
    var peak = 0;
    final service = ProjectAutosaveService(
      isDirty: () => true,
      saveProject: (_) async {
        inFlight += 1;
        peak = inFlight > peak ? inFlight : peak;
        await Future<void>.delayed(Duration.zero);
        inFlight -= 1;
      },
      projectPath: () => '/projects/x.anicel',
    );

    await Future.wait([service.saveNow(), service.saveNow(), service.saveNow()]);

    expect(peak, 1);
  });
}
