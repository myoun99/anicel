import 'dart:math' as math;

/// Where a run's playhead goes when its clock says [to]: forwards from
/// [from], round the end of a run of [total] frames, over every frame on the
/// way to the clock's — unless a frame on the way [waitsOn] its picture.
/// Then the run `stands` on the frame before that one, the last on the way
/// that is there, and `waitsFor` it. `passed` counts the frames gone over
/// without standing on them: what a run that fell behind its clock dropped.
///
/// 🚨A run behind its clock DROPS the frames on the way — time never
/// stretches for a busy frame — and stops before a frame whose picture is
/// not there: a tick that came late does not carry the playhead over a
/// picture that was never shown.
///
/// 🚨★★★WHERE A WAITING RUN STANDS IS ONE LAW, AND THIS IS WHERE IT IS
/// ANSWERED: on the last frame it has, never on the one it waits for (유저
/// 2026-10-15, F-365-Q1 「직전 프레임에 서서 기다린다(뷰어와 같은 법)」). A
/// playhead on a frame whose picture is not there shows a picture that is
/// not that frame's — white paper at a cut's head, or the cut before's last
/// — and 「정확하지 않은 그림을 보여주는건 해결이 아니라고생각하는데」. ↩️Each
/// surface kept its own: the media viewer parked before the page and the
/// canvas stood ON the frame, white at every cut's head on the iPad
/// (F-365). They parted in 3813e9e98, by nobody's word.
///
/// 🚨ONE WAY for every run that plays by a clock — the canvas's, and the
/// media viewer's (viewer-plays-by-the-one-playback-law ④, 유저 2026-10-08:
/// 「쓸수있는 로직 뷰어패널에서도 법 통일된거 재사용하게」). ↩️The viewer
/// turned a page a look, catching a clock that got ahead up at the
/// screen's rate — a rule of its own nobody asked for, and a picture behind
/// its sound for as long as it took.
///
/// Either clock only ever moves on — a step back is the lap wrapping — so
/// the way from [from] to [to] is forwards, round the end. 🚨Each clock
/// keeps that in one place: what is heard on the device
/// (`HeardOnTheDevice`), and the time a run's own ticker has reached
/// (`LookingTicker`). A reading that stepped back without wrapping walks
/// the whole lap, and where a frame waits for its picture it stands before
/// the first one not made — F-364, the playhead that jumped to the green
/// bar's edge.
///
/// 🚨COUNTED, not walked 「until it gets there」: a frame outside the run is
/// never got to, and that walk never ended — found by a mutant that took
/// the clamp off the device's reading and hung its test, which in the app
/// is a frozen window. However far the frame is, it is fewer steps ahead
/// than the run has frames.
({int stands, int passed, int? waitsFor}) playheadWay({
  required int from,
  required int to,
  required int total,
  required bool Function(int frame) waitsOn,
}) {
  final ahead = (to - from) % total;
  var stands = from;
  for (var step = 0; step < ahead; step += 1) {
    final next = (stands + 1) % total;
    if (waitsOn(next)) {
      return (stands: stands, passed: math.max(0, step - 1), waitsFor: next);
    }
    stands = next;
  }
  return (stands: stands, passed: math.max(0, ahead - 1), waitsFor: null);
}
