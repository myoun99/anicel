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
  shuffledLap;

  /// Whether the dabs after one lap are left undrawn.
  bool get endsAfterOneLap => this == oneLap || this == shuffledLap;
}
