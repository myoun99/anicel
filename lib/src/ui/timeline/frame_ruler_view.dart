/// How the frame rulers count — the timeline's, the X-sheet's and the
/// storyboard's, one choice for them all, picked at the grid's top-left
/// corner.
///
/// 🗣️I-81 (유저 2026-10-06): 「지금의 프레임/초+코마 스위칭에 세번째로
/// 페이지 상태? 로 넣는거 생각중. 기본 프레임뷰랑 똑같지만 페이지
/// 넘어가는것마다 프레임 번호 초기화하는느낌? p1 p2라는식으로 룰러에
/// 적는다던가」 — the page a ruler restarts at is its cut's X-sheet page
/// (I-81-Q1 「그 컷의 X시트 장을 따른다」). ↩️A switch of two (frames ↔
/// seconds+frames, UI-R10 #27) until then.
enum FrameRulerView {
  /// Every frame's number counted from the cut's first.
  frames('frames'),

  /// The number counted 1..fps inside each second, and every length read
  /// as seconds+frames.
  secondsPlusFrames('seconds'),

  /// The frames view, the numbers restarting at each page of the cut's
  /// X-sheet — `p1`, `p2` … on the seconds line.
  pages('pages');

  const FrameRulerView(this.jsonValue);

  /// The stored key.
  final String jsonValue;

  /// Whether a LENGTH reads as seconds+frames — the blocks' and the cuts'
  /// totals; the page view reads them as the frames view does (「기본
  /// 프레임뷰랑 똑같지만」).
  bool get seconds => this == secondsPlusFrames;

  static FrameRulerView fromJson(Object? json) {
    for (final view in values) {
      if (json == view.jsonValue) {
        return view;
      }
    }
    return frames;
  }
}
