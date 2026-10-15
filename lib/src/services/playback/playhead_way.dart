import 'dart:math' as math;

/// Where a run's playhead goes when its clock says [to]: forwards from
/// [from], round the end of a run of [total] frames, over every frame on the
/// way to the clock's — unless a frame on the way [waitsOn] its picture, and
/// then to THAT frame. `passed` counts the frames gone over without standing
/// on them: what a run that fell behind its clock dropped.
///
/// 🚨A run behind its clock DROPS the frames on the way — time never
/// stretches for a busy frame — and stops at a frame whose picture is not
/// there: a tick that came late does not carry the playhead over a picture
/// that was never shown. Where the run then stands is the surface's own
/// law: the canvas stands ON that frame, and the media viewer before it.
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
/// the whole lap, and where a frame waits for its picture it stands on the
/// first one not made — F-364, the playhead that jumped to the green bar's
/// edge.
///
/// 🚨COUNTED, not walked 「until it gets there」: a frame outside the run is
/// never got to, and that walk never ended — found by a mutant that took
/// the clamp off the device's reading and hung its test, which in the app
/// is a frozen window. However far the frame is, it is fewer steps ahead
/// than the run has frames.
({int landing, int passed, bool waits}) playheadWay({
  required int from,
  required int to,
  required int total,
  required bool Function(int frame) waitsOn,
}) {
  final ahead = (to - from) % total;
  var landing = from;
  var passed = -1;
  var waits = false;
  for (var step = 0; step < ahead && !waits; step += 1) {
    landing = (landing + 1) % total;
    passed += 1;
    waits = waitsOn(landing);
  }
  return (landing: landing, passed: math.max(0, passed), waits: waits);
}
