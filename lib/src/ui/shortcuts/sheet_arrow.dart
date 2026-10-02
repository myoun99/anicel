import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// A direction on the sheet — the way the direction keys and the canvas flip
/// both walk.
///
/// ↩️It carried its arrow KEY, and every reader asked 「is this an arrow?」 —
/// so the arrows were the only keys that turned with the sheet. Which keys
/// walk which way is the bindings' answer now ([SheetKeys], F-261).
enum SheetArrow {
  left(horizontal: true, forward: false),
  right(horizontal: true, forward: true),
  up(horizontal: false, forward: false),
  down(horizontal: false, forward: true);

  const SheetArrow({required this.horizontal, required this.forward});

  final bool horizontal;

  /// Right or down.
  final bool forward;

  /// The arrow along [horizontal] that points [forward].
  static SheetArrow along({required bool horizontal, required bool forward}) =>
      horizontal ? (forward ? right : left) : (forward ? down : up);
}

/// A move on the sheet (F-241): the way it walks as the timeline reads it,
/// and whether it is the one-frame step — Shift on the keys, the extra
/// finger on the flip.
typedef SheetMove = ({SheetArrow arrow, bool fine});

/// How the sheet in front of the user turns the arrows — answered where the
/// frame axis is asked (`FlipHudController`, F-28).
///
/// 🗣️F-241 (유저 2026-09-29): 「이전/다음 프레임, 이전/다음 블록, 위/아래
/// 레이어 이렇게 개편 … 위/아래 레이어는 x시트로 되있는 상태면 단축키가
/// 바뀌는데, 그런식으로 단축키 바뀐 상황에서 그에맞게 텍스트 내용도 변경」.
/// The moves are MEANINGS, and their keys are written as the timeline reads
/// them — the frames sideways, the rows down. On the X-sheet the frames run
/// down, so a pressed arrow is turned to the timeline's before it is matched,
/// and a bound arrow is shown turned the other way.
abstract interface class SheetArrowTurn {
  /// [pressed] as the timeline reads it.
  SheetArrow timelineArrowFor(SheetArrow pressed);

  /// The arrow that reads as [timeline] on this sheet.
  SheetArrow sheetArrowFor(SheetArrow timeline);
}

/// The sheet's DIRECTION KEYS — which key walks which way — read off the
/// bindings, never off a list of keys.
///
/// 🗣️F-261 (유저 2026-10-02): 「ws 위아래, ad 좌우(프레임)이동」 · 「그런
/// 인식못하는 문제같은거 근본 구조적으로 법 통일해줘」. A key bound bare to a
/// move that walks a way (the block and row moves, not their one-frame
/// steps) is that way's key: the arrows, the left hand's WASD and any key a
/// user records are one kind of key.
///
/// ★Keys turn as a SET. The n-th key of every way is one set — ← ↑ → ↓, then
/// A W D S — and only a set with a key in all four ways turns with the
/// sheet: a key pressed on the X-sheet is read as its set's key for the
/// turned way, so what a key does there, what the dialog shows it as and
/// what a key recorded there is kept as stay one answer. A key alone in its
/// place has no partner to turn into, so it presses its own move on every
/// sheet.
class SheetKeys {
  SheetKeys(Map<SheetArrow, List<LogicalKeyboardKey>> keysByArrow)
    : _keysByArrow = keysByArrow,
      _sets = SheetArrow.values
          .map((arrow) => keysByArrow[arrow]?.length ?? 0)
          .reduce((a, b) => a < b ? a : b);

  final Map<SheetArrow, List<LogicalKeyboardKey>> _keysByArrow;

  /// How many places hold a key in every way.
  final int _sets;

  /// Where [key] stands — its way and its set — or null when it is no
  /// direction key or stands in a set that does not turn.
  ({SheetArrow arrow, int set})? placeOf(LogicalKeyboardKey key) {
    for (final arrow in SheetArrow.values) {
      final at = (_keysByArrow[arrow] ?? const []).indexOf(key);
      if (at >= 0 && at < _sets) {
        return (arrow: arrow, set: at);
      }
    }
    return null;
  }

  /// [set]'s key for [arrow].
  LogicalKeyboardKey keyAt(SheetArrow arrow, int set) =>
      _keysByArrow[arrow]![set];

  /// The four keys of [set].
  List<LogicalKeyboardKey> setOf(int set) => [
    for (final arrow in SheetArrow.values) keyAt(arrow, set),
  ];
}
