/// What a run does at a frame whose picture is not made yet.
///
/// 유저 2026-10-08: 「클튜처럼 재생전굽기랑 실시간재생 옵션 두는거 좋은데
/// (… 안구워진곳에 닿으면 그 자리에서 만들어서 보여주기때문에 그 자리에서
/// 멈췃다가 구워지면 이어서 재생되고 그런거). 추가로 지금방식인 안구워져있으면
/// 건너뛰기방식? 다빈치방식? 도 세개 두면 좋을거같긴하고」 · 「좋아 통일할거
/// 통일하면서 권장대로가자. 기본값 모든그림.」
///
/// 🚨ONE MECHANISM, THREE SETTINGS. In every mode the warmer makes the
/// pictures ahead of the playhead, in the order the run plays them and as
/// far as the allowance holds. What a mode sets is how long the CLOCK stands
/// when the playhead reaches a frame that is not there: not at all, until
/// that picture is, or until everything ahead of it is. A cut played alone
/// and the film played through are the same run under each.
enum PlaybackMode {
  /// The clock never stands: the run keeps its time, and its sound, and a
  /// picture that is not there in time is not shown — what playback did
  /// until now, and DaVinci Resolve's default.
  skipFrames,

  /// The clock stands on the frame until its picture is there, and then
  /// goes on: the playhead never passes a picture that was not shown. THE
  /// DEFAULT (「기본값 모든그림」) — what bothered was 「재생했는데 재생바는
  /// 지나가고있는데 그림이 없어서 비어있다」.
  everyPicture,

  /// The clock stands until what lies ahead is there — every frame the run
  /// will play, or as much of it as the allowance holds — before it starts,
  /// and again whenever the playhead reaches a frame that is not (유저:
  /// 「클튜처럼 재생전굽기」). A film is not baked whole: 1500 cuts are
  /// hundreds of gigabytes of pictures, so what fills is the window.
  renderFirst,
}

/// What a project that has never said plays as.
const PlaybackMode defaultPlaybackMode = PlaybackMode.everyPicture;
