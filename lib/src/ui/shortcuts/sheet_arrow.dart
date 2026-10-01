import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// An arrow on the sheet — a direction the arrow keys and the canvas flip
/// both walk.
enum SheetArrow {
  left(LogicalKeyboardKey.arrowLeft, horizontal: true, forward: false),
  right(LogicalKeyboardKey.arrowRight, horizontal: true, forward: true),
  up(LogicalKeyboardKey.arrowUp, horizontal: false, forward: false),
  down(LogicalKeyboardKey.arrowDown, horizontal: false, forward: true);

  const SheetArrow(this.key, {required this.horizontal, required this.forward});

  final LogicalKeyboardKey key;
  final bool horizontal;

  /// Right or down.
  final bool forward;

  /// The arrow [key] is, or null for any other key.
  static SheetArrow? of(LogicalKeyboardKey key) {
    for (final arrow in values) {
      if (arrow.key == key) {
        return arrow;
      }
    }
    return null;
  }

  /// The arrow along [horizontal] that points [forward].
  static SheetArrow along({required bool horizontal, required bool forward}) =>
      horizontal ? (forward ? right : left) : (forward ? down : up);
}

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
