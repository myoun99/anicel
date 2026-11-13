import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/native/app_gpu_engine.dart'
    show AppKernels, debugAppShaderFolder, debugTakeAppGpuEngineNoted;
import 'package:anicel/src/native/gpu_adapter_choice.dart';
import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/services/import/cel_picture.dart'
    show debugPictureSideLimit;
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart';
import 'package:anicel/src/services/persistence/open_project_file.dart';
import 'package:anicel/src/services/persistence/app_support_path.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/provider_documents.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/engine_screen_texture.dart';
import 'package:anicel/src/ui/playback/frame_wait_mark.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';

import '../tool/machine_cache.dart';
import 'helpers/a_shown_surface.dart';
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
  // The GPU engine opens on the first adapter: no Flutter names one here.
  // ⛔Nothing opens it now — a file that never asks for the engine opens no
  // device (app_gpu_engine.dart) — and nothing stands in for it: a test that
  // needs it and gets none fails. Named, not imported: it was to keep the
  // config from the engine, which it reaches all the same since Q24
  // (gpu_adapter_choice.dart says why, and why that is the law).
  debugGpuAdapterChoice = GpuAdapterChoice.first;
  // 🚨EVERY TEST RUN OF A MACHINE KEEPS ITS SHADERS IN ONE FOLDER OF THE
  // MACHINE'S — `<machine cache>/test_shaders`, beside the line's own
  // (tool/machine_cache.dart) — so what one run's engine compiled, the
  // next run's is handed: a file there is used only where all that was
  // asked of the compiler is the same, and is written beside its name and
  // renamed to it, so runs side by side share the folder
  // (rust/vendor/wgpu-hal, dxil_cache.rs).
  //
  // A run is a launch, and the container it stands in is new and its own
  // (`testContainerFolder`), so each run compiled every kernel it drew
  // with — on the test's thread, where a pumped clock has them compiled
  // (`AppKernels.debugCompileHere`). 🔬2026-11-13, main PC, eighteen suites
  // on the line (board two-tests-spend-the-wait-windows-minute-under-load):
  // the first drawing of a file stood 39–65 s in five kernels (a Drive
  // project opened in a tab) and 62–64 s in four (two rows merged) — 5–6 s
  // alone — behind a wait of sixty (`waitPatience`): red six times of ten,
  // and 38 and 24 red logs of lanes since 11-10, each the first test of
  // its file. With the folder, the same day and the line as full (nine
  // suites of the run beside nine of another's): the two windows stood
  // 5.9 s and 2.8 s where they had stood 60.8 s and 35.2 s with it empty,
  // and of 296 wait windows one stood past ten seconds, at 11.5, where
  // twenty had — a rasterize's apart, which waits for no kernel (board
  // the-attach-row-bake-test-waits-a-gpu-read-a-frame-under-load).
  // ⚠️What the folder does not change is Dart's own start in a new
  // process. 🔬By thread CPU (보드/인프라 and this lane, 2026-11-13, board
  // a-fresh-test-process-waits-long-for-its-first-frame-at-a-batch-start),
  // the brush library test alone, the folder the run's own and empty and
  // then the machine's and full: its first `pumpWidget` 6.6 s and 5.6 s,
  // 9.0 s and 8.2 s of CPU and none of it an engine thread's; its first
  // round 13.2 s and 1.7 s, 15.8 s and 0.2 s of CPU on the engine's
  // threads. Under eighteen suites the first frame stood 12–48 s, the
  // folder full as well.
  //
  // ⛔Not in the run's temp: the line empties it as each run ends
  // (tool/test_queue.dart, `RunTemp`). ⛔Never the app's own container
  // (`appSupportFilePath`): a test writes nothing among the user's files.
  // A machine that names no cache folder keeps each run's shaders in the
  // run's own container, as all did.
  final machine = machineCacheFolder(Platform.environment);
  debugAppShaderFolder = machine == null ? null : '$machine/test_shaders';
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
  FolderPicker.debugWaitClock = null;
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
  // 🚨SET rather than reset, as is the one after it. Carrying
  // a file secures its bytes in an isolate so a big movie stops freezing
  // the app — as a trimmed file's piece is cut, and a cel still in the file
  // is thawed ahead for playback; a `testWidgets` clock is fake, so awaiting
  // a real isolate is a hang and every voice-take and import widget test
  // stopped at「did not complete」. The same work runs either way and each
  // caller stays async either way, so the ORDER the entrances depend on is
  // unchanged.
  //
  // ⚠️Each worker's road therefore needs a test that turns this back OFF
  // (`debugWorkersRunHere = false` — the staging's, the cut's and the
  // thaw's each have theirs). Deleting one would leave the road production
  // takes there with no coverage at all.
  debugWorkersRunHere = true;
  // The fake clock once more: the side this device's engine hands a picture
  // back at is measured once, through the engine (`pictureSideLimit`), and
  // on a `testWidgets` clock the answer never comes back — not even one
  // already measured (🔬a throwaway probe, 2026-10-20: 16 ms with the real
  // clock lent, then fifty pumps and no answer). Every picture a widget
  // test imported waited behind it, its wait window up for good. So it is
  // named: what the test engine measures, 65536 — it cuts no picture a test
  // makes. A test that stands at another side puts this one back.
  debugPictureSideLimit = 1 << 16;
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
  // 🚨**AN ERROR THE DEVICE RAISED THAT NO JOB WAS REFUSED BY IS THE
  // TEST'S** (🗣️관제 2026-11-11: 「기록된 오류가 남아 있으면 시험이 끝날 때
  // 빨개지는 장치를 같이 둬라」). ↩️Till the device-loss lane such an error
  // ended the process where it was raised — wgpu's own handler panics —
  // and that was the alarm. The engine notes it now and fails the next job
  // that waits (rust/src/device.rs, `Refusals`), so a test on a way that
  // never waits would end green with it noted. Asked as each test ends,
  // and TAKEN: the test that raised it is the red one, and the next test's
  // first wait is not failed by it.
  //
  // ⚠️The first `tearDown` here, so the last one run — package:test runs
  // them in reverse — and what the two below let go of is asked for too.
  tearDown(() {
    expect(
      debugTakeAppGpuEngineNoted(),
      isNull,
      reason:
          'the GPU device raised an error that no job of this test was '
          'refused by: the way that raised it never waits for the device, '
          'and the app would go on as if it had worked',
    );
  });
  // 🚨**THE TIMELINE TILE STORE IS ONE PER PROCESS**, and a raster a test
  // queued drained inside the NEXT test — against the earlier test's
  // painter and resolvers, in the next test's zone (2026-09-26: a rows test
  // failed on a raster the test before it had queued). A test ends with
  // the store empty; the drain it scheduled then finds nothing.
  tearDown(TimelineGridTileStore.instance.clear);
  // `flutter test` registers no texture a frame grid's screen could be
  // shown by ([ScreenTexture.debugOnSurface]): where a file opens the GPU
  // engine, each grid's screen opens on a surface of its own, freed as the
  // test ends.
  debugOpenEngineScreen = _screenOnASurface;
  // Kernels compile on this isolate here, as they always did: a widget
  // test's pumped clock lends a compile on another isolate no real time to
  // finish in. The pins of the app's own route ask for it back.
  AppKernels.debugCompileHere = true;
  // The same clock once more: it opens no engine either, so a canvas a test
  // stands would mark its place for as long as the test settles
  // (`pumpAndSettle`) — the mark turns. The pins of the mark stand it.
  FrameWaitMark.debugStands = false;
  debugLayerOfScreen = screenDrawnAsAPicture;
  // A zoom's stop rasters what it stretched, on the engine a session's
  // pictures open: no test but the one that fires it by hand is about that,
  // and one left armed outlives the tree.
  TimelineGridTileStore.instance.debugZoomTimer = (_, _) => const _NoStop();
  tearDown(_freeScreenSurfaces);
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

/// A zoom's stop that does not come.
final class _NoStop implements Timer {
  const _NoStop();

  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

/// The surfaces the grids' screens opened on in this test.

Future<ScreenTexture> _screenOnASurface(
  GpuEngine engine,
  int width,
  int height,
) async {
  final surface = shownSurfaceOf(width, height);
  final id = shownScreens.length + 1;
  shownScreens[id] = surface;
  return ScreenTexture.debugOnSurface(surface, id: id);
}

void _freeScreenSurfaces() {
  for (final surface in shownScreens.values) {
    surface.free();
  }
  shownScreens.clear();
}
