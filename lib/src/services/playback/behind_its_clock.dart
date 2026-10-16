/// Whether a run is BEHIND its clock at a look of it — the app was longer
/// than a frame — and shows the next picture all the same: it goes on one
/// frame however far its clock is ahead, and its clock is put back to that
/// frame, the sound with it (`playheadWay`'s `everyPicture`). Its mode says
/// whether it does ([showsEveryPicture]: `PlaybackWait`).
///
/// 🚨THE FIRST LOOK AFTER A START IS NEVER LATENESS (F-364-Q1 b). The
/// device starts AT that look (`FirstLookStart`) and a clock of the run's
/// own counts from it, so no tick the app was long in is in it — only how
/// far the sound is heard ahead of the picture by then: a frame is shown
/// refreshes after its tick, and the user's correction is on top
/// (`HeardOnTheDevice`). Two frames ahead, a run that showed every picture
/// by that look would put its clock back, find it two frames ahead at the
/// next first look, and put it back again — a frame a look, the sound
/// started afresh at every one. (Why the sound is ahead at a start at all:
/// board a-start-is-heard-ahead-of-its-first-picture.)
///
/// 🚨ONE LAW for both runs that show every picture — the canvas's and the
/// media viewer's (유저 2026-10-16, F-364-every-picture-even-when-late-Q1 a:
/// 「재생 전 굽기도 안 건너뛴다(뷰어도)」; viewer-plays-by-the-one-playback-
/// law, 2026-10-08: 「쓸수있는 로직 뷰어패널에서도 법 통일된거 재사용하게」).
/// Each starts it with its clock and looks through it. ↩️The canvas's
/// controller kept the flag itself, when it alone showed every picture.
final class BehindItsClock {
  BehindItsClock(this.showsEveryPicture);

  /// Whether the run's mode shows every picture — asked at each look that
  /// can be lateness, so a mode picked under a run holds from its next one.
  final bool Function() showsEveryPicture;

  bool _looked = false;

  /// The clock starts — the run begins, goes on from a wait, or is put back
  /// to the frame it went on onto: its next look is its start.
  void clockStarts() => _looked = false;

  /// The clock looks — once at every look, whatever it says: whether the
  /// run shows every picture at this one. Never at the first since the
  /// clock started ([clockStarts]).
  bool look() {
    final everyPicture = _looked && showsEveryPicture();
    _looked = true;
    return everyPicture;
  }
}
