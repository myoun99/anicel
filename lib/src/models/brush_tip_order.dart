/// Which of a brush's tip images each dab of a stroke takes — Clip Studio's
/// 繰り返し方法, all six of it (F-176-Q3 a: 「클튜 여섯 전부 + 끌어서
/// 순서」).
///
/// A dab takes the next turn, every dab — each of a spray's — and the turns
/// start over at every press (Clip Studio: 획마다 처음부터). With one tip
/// only the two laps differ from the others: they draw it once.
enum BrushTipOrder {
  /// 繰り返し — 0, 1, 2, 0, 1, 2, …
  repeat,

  /// 折り返し — 0, 1, 2, 1, 0, 1, …: back the way it came, the end tips
  /// once each.
  pingPong,

  /// 繰り返さない — 0, 1, 2, 2, 2, …: the last tip, once the others ran.
  holdLast,

  /// ランダム — any tip, thrown afresh each dab.
  random,

  /// 一巡のみ — 0, 1, 2, then nothing: the dabs after the lap are not drawn.
  oneLap,

  /// ランダムに一巡 — every tip once, in a shuffled order, then nothing.
  shuffledLap,

  /// ペンの傾き — the pen's lean picks the turn: held upright the first,
  /// laid flat the last, the turns cut evenly between. A pen that reports no
  /// lean is upright.
  ///
  /// ⚠️NOT ONE OF CLIP STUDIO'S SIX — its tips only take turns. Choosing an
  /// image by a pen input is GIMP's and Krita's (an image pipe's 傾き
  /// selection). 🗣️F-451 (유저 2026-10-23): 「세웠을땐 사각형이 아니라 진짜
  /// 연필처럼 … 둥글다던가」, while laid flat the lead's side stays square —
  /// one footprint cannot be both, and squashing one only stretches it.
  lean;

  /// Whether the dabs after one lap are left undrawn.
  bool get endsAfterOneLap => this == oneLap || this == shuffledLap;
}
