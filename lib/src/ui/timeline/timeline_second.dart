/// The frames one second takes on the time axis: the project's counting
/// rate — or 24 for a nonsense rate (zero or less) rather than dividing by
/// zero.
///
/// ⛔ONE answer for every mark of the second. The ruler wrote this fallback
/// out five times, and the grid's second lines kept an answer of their own
/// (a nonsense rate ruled no second at all) — the ruler marked seconds the
/// grid did not rule.
int timelineSecondFrames(int framesPerSecond) =>
    framesPerSecond > 0 ? framesPerSecond : 24;

/// Whether a second begins at [frameIndex] — where the ruler writes its
/// mark and the grid rules its second line.
bool timelineOnSecondBoundary(int frameIndex, int framesPerSecond) =>
    frameIndex % timelineSecondFrames(framesPerSecond) == 0;

/// The SECONDS a second's marks step by as the view widens — the ruler's
/// seconds and the grid's second lines both (I-22, 유저 09-12 「여기까지
/// 오면 초수도 생략해야할텐데 1초, 3초 ,5초 뭐 이런식으로? 1초 5초 10초 …
/// 이런부분은 프로툴 참고하는 방향으로 판단맡김」): a pro editor's ruler
/// steps — whole seconds 1, 2, 5, 10, 15, 30, then minutes 1, 2, 5, 10 —
/// and past ten minutes it doubles on.
const List<int> timelineSecondStrideLadder = [
  1,
  2,
  5,
  10,
  15,
  30,
  60,
  120,
  300,
  600,
];

/// The densest rung of [timelineSecondStrideLadder] (doubling on past its
/// top) whose span, at [secondExtent] a second, holds a mark of
/// [markExtent] — the frame ladder's question, asked in seconds.
int timelineSecondsHolding(double markExtent, double secondExtent) {
  assert(markExtent.isFinite && secondExtent > 0);
  for (final seconds in timelineSecondStrideLadder) {
    if (markExtent <= seconds * secondExtent) {
      return seconds;
    }
  }
  var seconds = timelineSecondStrideLadder.last;
  while (markExtent > seconds * secondExtent) {
    seconds *= 2;
  }
  return seconds;
}
