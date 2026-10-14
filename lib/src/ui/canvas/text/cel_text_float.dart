import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

import '../landing_preview.dart';
import '../selection_float_overlay.dart';

/// THE TEXT IN HAND AS THE CANVAS FLOATS IT (F-344): its pixels over the
/// hole its lifting left in its cel, as far as a hand has carried them, and
/// the cel's texts above it over those, as they stand.
///
/// 🗣️유저 2026-10-12: 「텍스트도구, 잡고 이동할때나 변형할때나 너무 느림.
/// 변형로직같은거 참고/재사용하면서 라이브 빠르게 움직이도록 구조개편」. Each of
/// the two IS a lifted selection's float — its pure move — so the hole is
/// made once, when the text is taken in hand, and a move of the hand moves
/// these pixels and nothing else. No plate is cut again, and no tile is
/// stamped or pictured again.
///
/// 🚨WHAT IS SEEN IS WHAT LANDS. A text moved by whole pixels lands as its
/// plate moved (`CelTextSession.showMoved`), which is [held]'s pixels at
/// its offset. The texts above it are over it on the cel, so they are over
/// it here too.
///
/// ⚠️BUT NOT WHERE IT LIES OVER INK, in two ways, both measured
/// (`a_carried_text_shows_what_it_lands_as_test`): its partly clear pixels
/// are blended here where the landing stamps them — one apart at most, the
/// cost of the transform tool's float too — and on a row with a colour key
/// each of the two is keyed by itself, where the landing keys the text
/// with the ink under it. Which of those the hand should see is the user's
/// (F-344-Q1).
@immutable
class CelTextFloat implements LandingPreview {
  const CelTextFloat({required this.held, required this.above});

  /// The text in hand: the pixels of its plate where it was set — through
  /// its row's keys, as its cel shows them — carried as far as a hand has
  /// carried them.
  final SelectionFloatPaint held;

  /// The texts of the cel above the one in hand, where they stand — none
  /// for a text that is new, which goes on top.
  final SelectionFloatPaint? above;

  @override
  Rect get drawnWorldRect {
    final under = held.drawnWorldRect;
    final over = above?.drawnWorldRect ?? Rect.zero;
    if (over.isEmpty) {
      return under.isEmpty ? Rect.zero : under;
    }
    return under.isEmpty ? over : under.expandToInclude(over);
  }

  @override
  void paintInto(Canvas canvas) {
    held.paintInto(canvas);
    above?.paintInto(canvas);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CelTextFloat && other.held == held && other.above == above;

  @override
  int get hashCode => Object.hash(held, above);
}
