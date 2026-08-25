import 'package:file_selector/file_selector.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart'
    show FileSelectorPlatform, SaveDialogOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';

/// 🚨 F-14 AT THE CALL SITES, not just the helper.
///
/// `askingAgainWithoutHint` is pinned as a pure function elsewhere, but the
/// debug seams (`debugFolderPicker` and friends) sit ABOVE the desktop
/// branches — so a call site reverting to a bare `getDirectoryPath` inside
/// its old catch-all kept every seam test green while re-introducing the
/// user-reported failure verbatim: Windows, save toward a Drive folder,
/// "picker could not be opened", save refused.
///
/// These tests swap [FileSelectorPlatform.instance] instead — the layer
/// UNDER the call sites — with a platform whose dialogs refuse to start in
/// a hinted directory, exactly the observed Windows behaviour. The wiring
/// is only correct if every desktop dialog still opens.
void main() {
  late FileSelectorPlatform real;

  setUp(() {
    real = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _HintRefusingSelector();
    FolderPicker.debugOperatingSystem = 'windows';
  });
  tearDown(() {
    FileSelectorPlatform.instance = real;
    FolderPicker.debugOperatingSystem = null;
  });

  test('pick (folder) survives a hint the platform refuses', () async {
    final grant = await FolderPicker.pick(initialDirectory: 'C:/refused');
    expect(grant.status, FolderPickStatus.granted);
    expect(grant.path, '/picked/folder');
  });

  test('pickSaveDestination survives a hint the platform refuses', () async {
    final grant = await FolderPicker.pickSaveDestination(
      suggestedName: 'scene.anicel',
      initialDirectory: 'C:/refused',
    );
    expect(grant.status, FolderPickStatus.granted);
    expect(grant.path, '/picked/scene.anicel');
  });

  test('pickFiles survives a hint the platform refuses — the OPEN door, '
      'single and multiple alike', () async {
    final single = await FolderPicker.pickFiles(
      acceptedTypeGroups: const [],
      initialDirectory: 'C:/refused',
    );
    expect(single.single.status, FolderPickStatus.granted);
    expect(single.single.path, '/picked/a.anicel');

    final multiple = await FolderPicker.pickFiles(
      acceptedTypeGroups: const [],
      allowMultiple: true,
      initialDirectory: 'C:/refused',
    );
    expect(multiple.single.status, FolderPickStatus.granted);
  });

  test('and a refusal WITHOUT a hint is still a real refusal', () async {
    // The retry is "the same question with the optional half removed" —
    // it must not turn a genuinely broken dialog into an infinite ask.
    FileSelectorPlatform.instance = _AlwaysRefusingSelector();
    final grant = await FolderPicker.pick();
    expect(grant.status, FolderPickStatus.unavailable);
  });
}

/// The observed Windows behaviour behind F-14: a dialog pointed at a
/// directory it will not accept THROWS out of the call, and the same
/// dialog asked without the hint opens normally.
class _HintRefusingSelector extends FileSelectorPlatform {
  Never _refuse() => throw StateError('refused: hinted initialDirectory');

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    if (initialDirectory != null) _refuse();
    return XFile('/picked/a.anicel');
  }

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    if (initialDirectory != null) _refuse();
    return [XFile('/picked/a.anicel')];
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    if (options.initialDirectory != null) _refuse();
    return const FileSaveLocation('/picked/scene.anicel');
  }

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    if (initialDirectory != null) _refuse();
    return '/picked/folder';
  }
}

class _AlwaysRefusingSelector extends FileSelectorPlatform {
  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => throw StateError('this dialog is genuinely broken');
}
