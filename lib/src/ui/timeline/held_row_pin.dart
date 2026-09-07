import '../../models/timeline_row_address.dart';

/// The row a drag gesture is HOLDING — move or select, layer row or fx
/// header — for the host that windows its rows. A host that builds every
/// row (the sheet) passes no pin at all.
///
/// A5 (2026-08-17): the window computation reads [held] to keep that one
/// row built while the rail scrolls past it: the recognizer lives in the
/// row's State, and an unmounted row used to release the grip mid-gesture
/// (드래그 풀림). A plain field, no notifier — the press finds its row
/// already built, and every window shift already rebuilds through the
/// grid's own scroll setState.
///
/// ⛔THE "RELEASE ONLY IF STILL MINE" GUARD IS THIS CLASS'S, and it has
/// ONE writer. It used to be written out at every site that could clear
/// the pin — the two row-drag wrappers and the range gestures' host — and
/// "add one more place that clears it" is the shape that lets one of them
/// clear a grip that belongs to somebody else.
///
/// ⚠️A LEAF FILE on purpose: both the row-drag wrapper and the range
/// gestures take the pin, and each of those already reaches the other's
/// file through the grid hooks — parking the class in either one closes
/// an import loop (`no_import_cycles_test`, round 8).
class HeldRowPin {
  TimelineRowAddress? _held;

  /// The row whose grip is currently taken, or null.
  TimelineRowAddress? get held => _held;

  void take(TimelineRowAddress row) {
    _held = row;
  }

  void release(TimelineRowAddress row) {
    if (_held == row) {
      _held = null;
    }
  }
}
