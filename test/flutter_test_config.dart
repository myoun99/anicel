import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/open_project_file.dart';
import 'package:anicel/src/services/persistence/media_staging_store.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/ui/session/trimmed_pieces.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/provider_documents.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';

import 'helpers/native_engine_path.dart';
import 'helpers/temp_dir.dart';

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
  // 🚨★★★**THE ENGINE THE PARITY PINS NEED, POINTED AT FROM ONE PLACE.**
  //
  // 「Where is the engine」 had two answers and they disagreed.
  // `nativeEngineLibraryPathOrNull` looks under `build/native_standalone`,
  // so the suites that use it ran; `openQaEngineLibrary` — which is what
  // PRODUCTION calls, and therefore what `QaCelCompressor.instance` calls —
  // tries `QA_ENGINE_PATH` and then the bare library name beside the
  // executable, and `flutter test` has neither. So every suite gated on the
  // compressor skipped SILENTLY with the DLL sitting right there: 27 pins
  // over the zstd block frames, the carried conform and the staged blob
  // (2026-09-08).
  //
  // ⛔The env var cannot be set from Dart, and that is the whole reason
  // this seam exists. Setting it here makes the two answers one.
  //
  // ⚠️`??=`, so `QA_ENGINE_PATH` still wins: CI sets it, and a run that
  // wants to measure the NO-engine world can too.
  debugQaEngineLibraryPathOverride ??= nativeEngineLibraryPathOrNull();
  // 🚨★★★**THE RUN'S TEMP IS ITS OWN, AND IT IS EMPTY WHEN THE RUN ENDS**
  // (2026-10-08). FIRST, before anything below asks for a temp path: from
  // here on `Directory.systemTemp` answers a folder of this file's own —
  // see `giveTheRunItsOwnTemp` — and the last `tearDownAll` at the bottom
  // asks what is still in it.
  final temp = giveTheRunItsOwnTemp();
  AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  // The program/notation languages live app-wide too (AppText), so a file
  // that flips them cannot leak into the next one. Tests that flip them
  // WITHIN a file reset per-test themselves.
  AppText.settings.value = const AppLanguageSettings();
  // The app documents home resolves through the channel override, pointed
  // at a sandbox in the run's temp so no test ever writes into the REAL
  // user Documents. 🪦It said 「and with it the Recordings take shelf」 until
  // the shelf was deleted (2026-09-08); what is left here is the PICKER's
  // starting hint, and a sandbox is still what keeps a test from creating
  // `Documents/Anicel` on the developer's machine.
  // Tests that override the path themselves must tearDown-restore the
  // previous value, never null (null falls back to the real home).
  //
  // ⚠️A PATH, made by whatever first asks the home to exist
  // (`ensuredAppDocumentsDirectory`). ↩️It was a folder made here and
  // deleted in a `finally` after `testMain` — which returns once the tests
  // are DECLARED, before one of them has run — so every file that went on
  // to ask for the home made it again, and left it (2026-10-08).
  final documents = '${temp.path.replaceAll('\\', '/')}/qa_test_docs';
  AppStorage.channelDocumentsPath = documents;
  // PICK-2: the folder-picker seam is a static, so a file that installs one
  // and forgets to remove it would hand its fake to every file after it.
  // Cleared here rather than trusted to each suite's tearDown.
  FolderPicker.debugFolderPicker = null;
  FolderPicker.debugFilePicker = null;
  // PICK-6: export is the one picker with a side effect on disk (it MOVES
  // the file), so a leaked seam here does more than return a wrong path.
  FolderPicker.debugFileExporter = null;
  FolderPicker.debugFilesExporter = null;
  FolderPicker.debugSaveDestinationPicker = null;
  FolderPicker.debugOperatingSystem = null;
  FolderPicker.debugBookmarkResolver = null;
  // The native file coordinator does not exist under `flutter test`, and
  // since 2026-09-13 every save on a platform that has one goes through
  // it — so a test that fakes an Apple OS needs a stand-in or every whole
  // write it makes fails at the swap. These doubles do what the native
  // side does on one volume (a move) and say yes to the rest. A test that
  // wants to watch, refuse or stage installs its own; one that wants「no
  // coordinator」fakes a platform without one.
  FolderPicker.debugCoordinatedReplacer =
      ({required String sourcePath, required String destinationPath}) async {
        File(sourcePath).renameSync(destinationPath);
        return true;
      };
  FolderPicker.debugCoordinatedReader = null;
  FolderPicker.debugDownloadRequester = null;
  FolderPicker.debugArrival = null;
  FolderPicker.debugCoordinatedInPlaceReader = (_) async => true;
  FolderPicker.debugCoordinatedToucher = (_) async => true;
  // PICK-7: the provider seam and the documents a run has been handed — a
  // working copy left registered would make another suite's file hand
  // itself back to a document that was never there.
  ProviderDocuments.debugReset();
  // Back to the PRODUCTION default, not to false — a reset that quietly
  // put every test on the other shape would hide the one that ships.
  anicelAlwaysZip64 = true;
  // A lowered limit forces the ZIP64 per-entry shape onto small fixtures;
  // leaked, it would sentinel every entry in every other suite's archives.
  anicelZip64FieldLimit = anicelZip64FieldLimitShipped;
  // A watcher left installed would hear — and hold on to — every later
  // suite's saves.
  anicelDebugWriteWatcher = null;
  // Same hazard, same fix: the flow's platform seam decides whether a pick
  // has to clear Android's storage grant first.
  debugOperatingSystemOverride = null;
  // PICK-6: once-per-session, so a file that leaves it true silences the
  // notice for every file after it.
  debugDriveNoticeShown = false;
  AppStorage.debugAllFilesAccessOverride = null;
  // 🚨SET rather than reset, and it is the only one here that is. Carrying
  // a file secures its bytes in an isolate so a big movie stops freezing
  // the app; a `testWidgets` clock is fake, so awaiting a real isolate is a
  // hang and every voice-take and import widget test stopped at「did not
  // complete」. The same work runs either way and `stageCarriedBytes` stays async
  // either way, so the ORDER the entrances depend on is unchanged.
  //
  // ⚠️The isolate road therefore needs one test that turns this back OFF —
  // `media_staging_store_test` has it. Deleting that test would leave the
  // road production takes with no coverage at all.
  MediaStagingStore.debugStageInline = true;
  // The same fake-clock reason: cutting a trimmed file's piece runs in a
  // worker in the app, and a widget test cannot await one.
  TrimmedPieces.debugCutInline = true;
  // 🚨★★★**ONE PROCESS HOLDS ONE PROJECT FILE OPEN, AND A TEST CORPUS
  // MAKES A NEW PROJECT PER TEST.** A file-backed cel reads through
  // [OpenProjectFile], which keeps the `.anicel` open for the next read;
  // on Windows that also stops the folder holding it from being deleted.
  // In the app that IS the feature — the project cannot be pulled out
  // from under the session drawing into it — and the release point is the
  // whole-store swap that opening the next project performs. A test drops
  // its store on the floor instead, and Dart has no destructor.
  //
  // 🚨**REGISTERED AS AN `addTearDown` FROM A `setUp`, AND THE ORDERING IS
  // THE WHOLE POINT.** package:test runs every `addTearDown` callback
  // before any `tearDown`. Written as a plain `tearDown` here this is the
  // OUTERMOST one, so it ran dead last — after each suite's own
  // `tearDown(() => deleteTempQuietly(directory))`, which is the
  // exact line it exists to unblock (five suites failed that way with
  // errno 32). Registered from `setUp` it lands in the earlier phase and
  // gets there first.
  //
  // ⛔**What it still cannot reach**: a suite that registers its delete
  // with `addTearDown` INSIDE the test. Those run in reverse registration
  // order, so a later registration runs earlier, and ours — registered in
  // `setUp`, before the body — is last again. That shape needs the release
  // in the same callback: `deleteAfterSessionEnds` in
  // `test/helpers/project_scratch_folder.dart`.
  setUp(() => addTearDown(OpenProjectFile.instance.releaseAll));
  // 🚨**THE TIMELINE TILE STORE IS ONE PER PROCESS**, and a raster a test
  // queued drained inside the NEXT test — against the earlier test's
  // painter and resolvers, in the next test's zone (2026-09-26: a rows test
  // failed on a raster the test before it had queued). A test ends with
  // the store empty; the drain it scheduled then finds nothing.
  tearDown(TimelineGridTileStore.instance.clear);
  // 🚨★★★**THE RUN ENDS THE WAY THE APP'S RUN ENDS, AND THEN IT IS ASKED
  // WHAT IT LEFT** (2026-10-08). Registered BEFORE the file declares a
  // single test, so it is the root group's LAST `tearDownAll` — package:test
  // runs them in reverse — and every cleanup a file wrote has run by then.
  //
  // First the run lets go the way the app does on a normal exit: the
  // project file, then this run's room in the container
  // (`SessionScratch.deleteThisRunsFolder` — its lock file is held open for
  // the whole run, and Windows will not delete a folder with an open file
  // in it). Then the two stand-ins this run made for the user's own folders
  // go: the Documents home above, and the container
  // (`testContainerFolder`). Whatever is still in the run's temp after that
  // was left behind by a test or by the code it drove, and the file is red
  // for it — after the folder is removed anyway, so a red run does not
  // leave it on the machine either.
  tearDownAll(() async {
    OpenProjectFile.instance.releaseAll();
    SessionScratch.deleteThisRunsFolder();
    deleteTempQuietly(Directory(documents));
    deleteTempQuietly(Directory(testContainerFolder()));
    final left = await whatTheRunLeftIn(temp);
    deleteTempQuietly(temp);
    expect(
      left,
      isEmpty,
      reason:
          'whatever this file — or the code its tests drive — makes under '
          'Directory.systemTemp has to be gone when its tests are: delete '
          'it with deleteTempQuietly or deleteAfterSessionEnds, and let go '
          'of what still holds it first',
    );
  });
  await testMain();
}
