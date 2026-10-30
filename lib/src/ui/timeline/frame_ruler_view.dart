import 'package:flutter/foundation.dart' show listEquals;

/// How the frame rulers count — the timeline's, the X-sheet's and the
/// storyboard's, one choice for them all, picked at the grid's top-left
/// corner.
///
/// 🗣️I-81 (유저 2026-10-06): 「지금의 프레임/초+코마 스위칭에 세번째로
/// 페이지 상태? 로 넣는거 생각중. 기본 프레임뷰랑 똑같지만 페이지
/// 넘어가는것마다 프레임 번호 초기화하는느낌? p1 p2라는식으로 룰러에
/// 적는다던가」 — the page a ruler restarts at is its cut's X-sheet page
/// (I-81-Q1 「그 컷의 X시트 장을 따른다」), the storyboard's its conte book's
/// (I-81-Q3 「콘티용지패널의 페이지 기준」). ↩️A switch of two (frames ↔
/// seconds+frames, UI-R10 #27) until then.
enum FrameRulerView {
  /// Every frame's number counted from the cut's first.
  frames('frames'),

  /// The number counted 1..fps inside each second, and every length read
  /// as seconds+frames.
  secondsPlusFrames('seconds'),

  /// The frames view, the numbers restarting at each page the strip counts
  /// by ([TimelineRulerPages]) — `p1`, `p2` … beside the second at each
  /// page's head (I-81-Q4
  /// 「초 옆에 페이지 넘어가는곳마다 p1 p2라고 쓸뿐임」).
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

/// The pages a strip counts by under the page view: the frames each
/// begins on, the first on 0 and the rest in order, whatever their
/// lengths — ONE list for a sheet whose pages are all alike and a book
/// whose pages hold what their cells take.
final class TimelineRulerPages {
  /// Pages of [frames] each, as far as a strip runs: the X-sheet's, which
  /// prints on (I-81-Q1).
  const TimelineRulerPages.every(int this.frames)
    : assert(frames > 0),
      _heads = const [];

  /// Pages beginning on [heads]: a conte book's (I-81-Q3).
  const TimelineRulerPages.startingAt(this._heads) : frames = null;

  /// How long each page is where they are all alike.
  final int? frames;

  final List<int> _heads;

  /// The frames the pages of a strip ending on [end] begin on — never
  /// none.
  List<int> headsBefore(int end) => switch (frames) {
    final frames? => [
      for (var head = 0; head == 0 || head < end; head += frames) head,
    ],
    null => [
      for (final (page, head) in _heads.indexed)
        if (page == 0 || head < end) head,
    ],
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineRulerPages &&
          other.frames == frames &&
          listEquals(other._heads, _heads);

  @override
  int get hashCode => Object.hash(frames, Object.hashAll(_heads));
}
