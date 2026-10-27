/// THE in-between marks (中割) as DATA — what a cell carries, not a glyph it
/// prints: two marks, one in-between. 🗣️I-130 (유저 2026-10-25): 「지금의
/// 속이 찬 점을 마크2, 속이 빈 그냥 선으로 된 원을 마크1. 이 순서는 토에이
/// 디지털 타임시트, 클튜를 기반으로 확인했음 … 현재로서 두 마크가 다른
/// 기능한다거나 그런건없음. 일단은 모양이 다를뿐인 같은 중간나누기임」.
///
/// ↩️유저 2026-09-24 had named them the other way round — 「중간나누기
/// 마크1로서 작동했으면 … 마크2는 토에이 타임시트에 속이 빈 동그라미」 — and
/// until I-130 there was the one value, the filled ●. ↩️F-149 (유저
/// 2026-09-16: 「일단 이름 없는 기본상태를 속이 찬 동그라미로 통일적용. 추후
/// 두번째 중간나누기 마크(속이 빈)를 활용할지도 모르겠지만 당장은 제거」)
/// retired the hollow ○ the unnamed drawing printed; it is back as mark 1.
enum InbetweenMark {
  /// Mark 1 — the hollow ○, a line round it.
  one,

  /// Mark 2 — the filled ●.
  two;

  /// The mark written as TEXT — a file name, a menu, a notice. Surfaces that
  /// draw draw its shape instead. The one place either glyph is spelled.
  String get glyph => switch (this) {
    InbetweenMark.one => '○',
    InbetweenMark.two => '●',
  };
}

/// THE MARK A DRAWING WITH NO NAME WEARS until a hand picks the other
/// (Preferences ▸ Display, `AppFrameGridSettings.unnamedMark`): mark 2, the
/// filled ●. 🗣️F-489 (유저 2026-10-27): 「이름 없는 블록의 기본 마크1,2인지
/// 설정할수있게 … 업계일반적으론 마크2가 보통이라서 기본값은 마크2로 둠」.
/// ↩️Mark 1, the ○, and no choice, from F-469 (10-25 「이름없는 프레임의
/// 기본마크, 앞으로 마크1 사용」) — and the ● again before it (F-149).
const InbetweenMark defaultUnnamedDrawingMark = InbetweenMark.two;
