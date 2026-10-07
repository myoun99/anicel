import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    show FileSaveLocation, FileSelectorPlatform, SaveDialogOptions, XTypeGroup;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';

/// WHICH PLATFORMS HAVE A SAVE WINDOW THAT ANSWERS WITH A PATH — the fact a
/// file's place hangs on: where there is one, a file is asked its place
/// before it is made (F-221, 유저 2026-10-06: 「맥도 그럼 윈도랑
/// 통일할수있으면 통일」).
///
/// Its own question, apart from whether a platform's grants are scoped:
/// macOS answers yes to both.
void main() {
  late FileSelectorPlatform real;
  late _RecordingSelector window;

  setUp(() {
    real = FileSelectorPlatform.instance;
    window = _RecordingSelector();
    FileSelectorPlatform.instance = window;
  });
  tearDown(() {
    FileSelectorPlatform.instance = real;
    FolderPicker.debugOperatingSystem = null;
  });

  test('the desktops have one — macOS among them; iOS and Android do not', () {
    for (final os in const ['windows', 'linux', 'macos']) {
      expect(FolderPicker.aSaveWindowAnswersAPathOn(os), isTrue, reason: os);
    }
    for (final os in const ['ios', 'android', 'fuchsia']) {
      expect(FolderPicker.aSaveWindowAnswersAPathOn(os), isFalse, reason: os);
    }
  });

  test('it is NOT the scoped question turned round: macOS has the window '
      'AND scoped grants', () {
    expect(FolderPicker.aSaveWindowAnswersAPathOn('macos'), isTrue);
    expect(FolderPicker.scopedForPlatform('macos'), isTrue);
  });

  test('🎯on macOS the save window is ASKED — the name written in it, where '
      'it opens — and its answer comes back as the file\'s path', () async {
    FolderPicker.debugOperatingSystem = 'macos';

    final grant = await FolderPicker.pickSaveDestination(
      suggestedName: 'Project.png',
      initialDirectory: '/Users/me/Renders',
    );

    expect(window.asked, ['Project.png in /Users/me/Renders']);
    expect(grant.status, FolderPickStatus.granted);
    expect(grant.path, '/picked/shot.png');
    expect(grant.kind, GrantKind.file);
  });

  test('where there is none, asking for it is a mistake said out loud — the '
      'file is made first and placed there', () async {
    for (final os in const ['ios', 'android']) {
      FolderPicker.debugOperatingSystem = os;

      await expectLater(
        FolderPicker.pickSaveDestination(suggestedName: 'Project.png'),
        throwsStateError,
        reason: os,
      );
    }
    expect(window.asked, isEmpty);
  });
}

/// The save window, writing down what it was asked.
class _RecordingSelector extends FileSelectorPlatform {
  final List<String> asked = [];

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    asked.add('${options.suggestedName} in ${options.initialDirectory}');
    return const FileSaveLocation('/picked/shot.png');
  }
}
