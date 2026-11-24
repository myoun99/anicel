import 'package:flutter_test/flutter_test.dart';

/// 🚨★**THE LEDGER OF FILES WHOSE TESTS LEAVE SCREENS OF THE ENGINE** (card
/// the-prerender-scheduler-rests-a-tile-late-on-ci, 🗣️관제 2026-11-24: 「전
/// 파일에서 남기는 시험의 수 · 이름을 먼저 세어 카드에 적고, 많으면 장부(이유와
/// 함께, 총 개수 고정)로 시작해 줄여 간다. 한 번에 다 고치려 하지 말 것」).
///
/// Each test ends with every screen it made freed (test/flutter_test_config
/// .dart says why). 🔬The first count, 2026-11-24, every file: 163 files
/// leave some — 106 of a shot, 42 of a lay, 14 both — and one more, the
/// eraser's block file, of its view (red already, for another reason: it
/// is not in the ledger). A file here declares which it leaves
/// ([itsTestsLeaveScreensOfTheEngine]); a screen of another kind is red
/// in it as anywhere. The total is pinned
/// (test/architecture/a_file_leaves_screens_only_by_the_ledger_test.dart):
/// a file taken out lowers it, and none is put in.
enum ScreensLeft {
  /// A shot's picture — a storyboard cell's, a media raster's
  /// (frame_shots.dart, `frameOnTheEngine`): it makes its screen and frees
  /// it after the compose's answer. A widget test ended first; its fake
  /// clock's zone runs no more, and the `finally` that frees it never
  /// runs. ✅What took one file out (the spilled sound's): wait for the
  /// panel's pictures before the test ends
  /// (test/helpers/until_the_panel_pictures_land.dart).
  ofAShot('frameOnTheEngine.showOn'),

  /// A picture the session's store laid or was laying
  /// (engine_frame_picture_store.dart, `_lay`): kept by a store whose
  /// session the test never ends, or its lay's answer came after the
  /// test's zone stopped.
  ofALay('EngineFramePictureStore._lay');

  const ScreensLeft(this.madeIn);

  /// The frame of where a screen of this kind was made.
  final String madeIn;
}

Set<ScreensLeft> _leftHere = const {};

/// What the file running now declared its tests leave.
Set<ScreensLeft> get screensThisFileLeaves => _leftHere;

/// Declares that the tests of the file this is called in leave screens of
/// [kinds]: the first line of its `main`.
void itsTestsLeaveScreensOfTheEngine(Set<ScreensLeft> kinds) {
  setUpAll(() => _leftHere = kinds);
  tearDownAll(() => _leftHere = const {});
}
