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
