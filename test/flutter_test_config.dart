import 'dart:async';
import 'dart:io';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';
import 'package:anicel/src/ui/input/app_input_settings.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// Corpus-wide input baseline (UI-R22F #1).
///
/// The PRODUCT default is touch-scrolls-ON (finger pans scroll the
/// timeline; the edit gestures release touch). The test corpus, though,
/// was written under the R17-⑥ touch-as-pen contract — `tester.drag`
/// and `startGesture` default to [PointerDeviceKind.touch] — so every
/// file starts from OFF here and suites that assert the ON behavior
/// (touch scrolling, touch released by edit gestures) opt in explicitly.
///
/// Tests that flip the value themselves must tearDown-reset to THIS
/// baseline (`AppInputSettings.testCorpusBaseline`), not to the
/// product default `AppInputSettings()`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  // The program/notation languages live app-wide too (AppText), so a file
  // that flips them cannot leak into the next one. Tests that flip them
  // WITHIN a file reset per-test themselves.
  AppText.settings.value = const AppLanguageSettings();
  // REC1-B2: the app documents home — and with it the Recordings take
  // shelf — resolves through the channel override, pointed at a per-run
  // temp sandbox so no test ever writes into the REAL user Documents.
  // Tests that override the path themselves must tearDown-restore the
  // previous value, never null (null falls back to the real home).
  final sandbox = Directory.systemTemp.createTempSync('qa_test_docs_');
  AppStorage.channelDocumentsPath = sandbox.path.replaceAll('\\', '/');
  // PICK-2: the folder-picker seam is a static, so a file that installs one
  // and forgets to remove it would hand its fake to every file after it.
  // Cleared here rather than trusted to each suite's tearDown.
  FolderPicker.debugFolderPicker = null;
  FolderPicker.debugFilePicker = null;
  FolderPicker.debugOperatingSystem = null;
  FolderPicker.debugBookmarkResolver = null;
  // Same hazard, same fix: the flow's platform seam decides whether a pick
  // has to clear Android's storage grant first.
  debugOperatingSystemOverride = null;
  AppStorage.debugAllFilesAccessOverride = null;
  try {
    await testMain();
  } finally {
    try {
      sandbox.deleteSync(recursive: true);
    } on Object {
      // A leaked handle on Windows must not fail the suite.
    }
  }
}
