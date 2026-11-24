import 'package:flutter_test/flutter_test.dart';

/// 🚨★**THE LEDGER OF FILES WHOSE TESTS LEAVE SCREENS OF THE ENGINE** (card
/// the-prerender-scheduler-rests-a-tile-late-on-ci, 🗣️관제 2026-11-24: 「전
/// 파일에서 남기는 시험의 수 · 이름을 먼저 세어 카드에 적고, 많으면 장부(이유와
/// 함께, 총 개수 고정)로 시작해 줄여 간다. 한 번에 다 고치려 하지 말 것」).
///
/// Each test ends with every screen it made freed (test/flutter_test_config
/// .dart says why). 🔬The first count, 2026-11-24, every file: 163 files
/// leave some — 106 of a shot, 42 of a lay, 14 both — and one more, the
/// eraser's block file, of its view (red then for another reason, and
/// left out). Counted again once each test waited for the GPU to finish
/// before it was asked (the config says why), the same day: 42 of the 56
/// files that left a lay left none — 124 files, 14 of them leaving a lay.
/// ↩️Counted once more on master 7f1974785, the same day: the eraser's
/// file leaves none, and the brush switch's file leaves a live cel's — 125
/// files. A file here declares which it leaves
/// ([itsTestsLeaveScreensOfTheEngine]); a screen of another kind is red
/// in it as anywhere. The total is pinned
/// (test/architecture/a_file_leaves_screens_only_by_the_ledger_test.dart):
/// a file taken out lowers it, and one is put in only with its kind's
/// reason and who takes it out.
enum ScreensLeft {
  /// A shot's picture — a storyboard cell's, a media raster's
  /// (frame_shots.dart, `frameOnTheEngine`): it makes its screen and frees
  /// it after the compose's answer. A widget test ended first; its fake
  /// clock's zone runs no more, and the `finally` that frees it never
  /// runs. ✅What took one file out (the spilled sound's): wait for the
  /// panel's pictures before the test ends
  /// (test/helpers/until_the_panel_pictures_land.dart).
  ofAShot('frameOnTheEngine.showOn'),

  /// A picture the session's store laid (engine_frame_picture_store.dart,
  /// `_lay`): kept by a store whose session the test never ends. ↩️Or its
  /// lay was still on the GPU when the test was asked — till each test
  /// waited for the GPU first, which a lay hears in no one's zone.
  ofALay('EngineFramePictureStore._lay'),

  /// A sheet's live cel's screen (live_cel_screen.dart, `_show`, laid by
  /// `EngineStackScreen.compose`): the brush switch's file ends with it
  /// held. Why the view's dispose does not free it is not read yet — the
  /// brush's to fix (🗣️관제 2026-11-24: in the ledger with who takes it
  /// out): the commit that frees it takes the file's line out, lowers the
  /// total, and this kind with it where no file declares it.
  ofALiveCel('_LiveCelScreenState._show');

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
