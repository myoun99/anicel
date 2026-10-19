/// How thick a scrollbar is — its lane, and the thumb that fills it.
///
/// 🚨F-409 (유저 2026-10-19): 「실제 인식되는 범위보다 스크롤바가 작은데 이런거
/// 개선. 조작 가능한 만큼 위젯의 모양새가 위치하도록」 — the thumb is as thick
/// as the lane the pointer can grab it in (`AppScrollbar`), so a lane width
/// is the bar's width. And the two words are theirs: 「지금의 일반적으로 쓰이는
/// 타임라인패널등의 스크롤바를 얇은 스크롤바로서 명명하고, 방금 말한 프레임영역은
/// 두꺼운 스크롤바로서 명명. 그러고 환경설정창은 다 두꺼운 스크롤바 사용」.
///
/// ↩️Three lane steps (16 · 14 · 12) under a 4px thumb, which drew them all
/// the same; the 14 (the floor's panbar capsules) and the 12 (the bars laid
/// over a panel while it overflows) were mine, and are the thin bar now.
///
/// Deliberately free of any widget import: the grid metrics that subtract
/// a lane from a viewport are calculation-only files, and they must be
/// able to say WHICH lane without pulling Flutter in behind them.
abstract final class AppScrollbarLane {
  /// Every bar but the two the thick one is for.
  static const double thin = 16;

  /// The frame area's vertical bar, and every bar in the preferences
  /// window — 「지금보다 살짝 더 두꺼운」.
  static const double thick = 20;
}

/// How short a scrollbar thumb is allowed to get.
///
/// 🚨★★★THE LANE HAD A VOCABULARY AND THE THUMB DID NOT, so the number was
/// written out wherever it was needed: `32` three times, as three private
/// constants in `layer_rail_window.dart`,
/// `timeline_horizontal_scrollbar_rail.dart` and
/// `timeline_vertical_scrollbar_rail.dart`. Three copies of one law agree
/// until the day somebody changes one.
///
/// It is load-bearing beyond the scrollbar itself: `editor_workspace.dart`
/// sizes the x-sheet's floor around it — 「a 31px window — under the
/// scrollbar's own 32px thumb minimum, so nothing scrolls and nothing is
/// readable」 — and `timeline_panel.dart` and `storyboard_panel.dart` reason
/// from it too. A layout that computes against a number the scrollbar no
/// longer uses is a layout that is wrong and still compiles.
///
/// ⚠️Free of widget imports for the same reason as [AppScrollbarLane]: the
/// grid metrics that reason about it are calculation-only files.
abstract final class AppScrollbarThumb {
  /// CLAUDE.md: 「레인 16px, **썸 최소 32px**」.
  ///
  /// ⛔ONE MINIMUM FOR THE WHOLE APP — 유저 (ARCH-audit-Q1, 2026-09-01)
  /// chose 「32 하나로 통일」 over three named steps. The panbar carried
  /// its own 24 and `AppScrollbar` defaulted to 28, and neither number
  /// could say who asked for it: `git log -S` finds the commits and the
  /// messages say nothing.
  static const double minimum = 32;
}

/// An extent a scrollbar can reason about: anything not finite, and
/// anything at or below zero, IS zero. A NaN track extent otherwise walks
/// straight into the thumb arithmetic and comes out as a NaN thumb.
double finiteNonNegativeExtent(double value) {
  if (!value.isFinite || value <= 0) {
    return 0;
  }
  return value;
}

/// How far a viewport can travel over its content — never negative, so
/// content that fits reads as "nothing to scroll" rather than as a
/// backwards range.
double scrollRangeFor({
  required double contentExtent,
  required double viewportExtent,
}) => (contentExtent - viewportExtent).clamp(0.0, double.infinity).toDouble();
