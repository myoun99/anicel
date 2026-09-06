/// The hit-lane widths a surface reserves around a scrollbar thumb.
///
/// The thumb itself is one thickness everywhere (see `AppScrollbar`); what
/// differs between surfaces is how much room the pointer gets to grab it.
/// Three named steps, so a lane width is a decision with a name instead of
/// a literal repeated per call site.
///
/// Deliberately free of any widget import: the grid metrics that subtract
/// a lane from a viewport are calculation-only files, and they must be
/// able to say WHICH lane without pulling Flutter in behind them.
abstract final class AppScrollbarLane {
  /// Timeline rails — the lanes a finger sweeps along most often, and the
  /// only ones that are always visible in their own reserved column.
  static const double wide = 16;

  /// Canvas panbars.
  static const double medium = 14;

  /// The tool rail and the panel docks, where width is the scarce axis.
  /// These lanes are laid OVER content and only while it overflows, so
  /// this number is pointer reach rather than layout.
  static const double narrow = 12;
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
