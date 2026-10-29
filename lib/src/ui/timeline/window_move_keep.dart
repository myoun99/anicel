import 'package:flutter/widgets.dart';

/// What a windowed host keeps of the rows it built while only its WINDOW
/// moves (card frame-panels-build-in-one-frame ③, 2026-10-29): a move
/// builds the rows that arrive and hands each row that stayed back as the
/// very widget it was, so nothing under it builds again.
///
/// A PASS is one build of everything above the window — the host's own
/// build, a drag preview's — and the host names it ([lay]); a lay in
/// another pass keeps nothing. A row the window left is let go of at the
/// next lay.
///
/// ↩️Every move built every row the window held again, the rows that
/// stayed among them — 175–236 elements a move on the timeline, 49–106 on
/// the storyboard — and with every lane of S5_BA cut 352 open, the
/// storyboard's fast scroll went from build p90 0.9 to 9.1 ms once its rows
/// were windowed (②).
///
/// ONE keep for every windowed host: the timeline's rail and cells, the
/// storyboard's rail and strips — and what a lay builds beside its rows off
/// the pass alone, the storyboard's section zones (④).
final class WindowMoveKeep {
  Object? _pass;
  Map<Object, Widget> _held = {};
  Map<Object, Widget> _before = {};

  /// Starts laying the rows of [pass] — whether it is another pass than
  /// the last lay's, which keeps nothing.
  bool lay(Object pass) {
    final fresh = pass != _pass;
    _pass = pass;
    _before = fresh ? {} : _held;
    _held = {};
    return fresh;
  }

  /// The row kept for [key] in this pass, else [build]'s, kept.
  Widget row(Object key, Widget Function() build) =>
      _held[key] = _before.remove(key) ?? build();
}
