import 'package:flutter/widgets.dart';

import 'memo_token.dart';

/// What a windowed host keeps of the rows it built while only its WINDOW
/// moves (card frame-panels-build-in-one-frame ③, 2026-10-29): a move
/// builds the rows that arrive and hands each row that stayed back as the
/// very widget it was, so nothing under it builds again.
///
/// A PASS is one build of everything above the window — the host's own
/// build, a drag preview's — and the host names it ([lay]). A lay in
/// another pass hands a row back while what the row is built from holds
/// ([row]'s facts, [keptWhileSame]) — the very widget again, so an edit
/// builds the rows it changed and no other. A row the window left is let
/// go of at the next lay.
///
/// ↩️Every move built every row the window held again, the rows that
/// stayed among them — 175–236 elements a move on the timeline, 49–106 on
/// the storyboard — and with every lane of S5_BA cut 352 open, the
/// storyboard's fast scroll went from build p90 0.9 to 9.1 ms once its rows
/// were windowed (②).
///
/// ↩️A lay in another pass kept nothing until card
/// an-eye-toggle-holds-the-ui-thread (11-19): the rows' memos handed every
/// row's insides back, and the wrapper each stood in was built again
/// around them — 🔬84 of the 249 widgets an eye toggle rebuilt on S5_BA
/// cut 352, a row's name and berth on each side for every row the window
/// held. The storyboard rail kept its labels across passes in a keep of
/// its own (`_KeptRailRows`) — the same keep, which this one is now.
///
/// ONE keep for every windowed host: the timeline's rail and cells, the
/// storyboard's rail, its strips and its labels — and what a lay builds
/// beside its rows off the pass alone, the storyboard's section zones (④)
/// and a lane graph ([ofThePass]).
final class WindowMoveKeep {
  Object? _pass;
  bool _fresh = true;
  Map<Object, Kept<Object?>> _held = {};
  Map<Object, Kept<Object?>> _before = {};

  /// Starts laying the rows of [pass] — whether it is another pass than
  /// the last lay's, whose rows are kept only while their facts hold.
  bool lay(Object pass) {
    _fresh = pass != _pass;
    _pass = pass;
    _before = _held;
    _held = {};
    return _fresh;
  }

  /// [key]'s row as [build] makes it from [facts] — what it is built from.
  /// In the pass the last lay laid, the row that lay kept, its facts never
  /// asked; in another, the row kept while [facts] are what it was built
  /// from; else [build]'s, kept.
  Widget row<F>(
    Object key,
    F Function() facts,
    Widget Function(F facts) build,
  ) {
    if (_before.remove(key) case final kept?) {
      _held[key] = kept;
      if (!_fresh) return kept.built;
    }
    final now = facts();
    return keptWhileSame<Object, Object?>(_held, key, now, () => build(now));
  }

  /// [build]'s widget for [key], built from the pass alone: kept while
  /// only the window moves, built again in another pass.
  Widget ofThePass(Object key, Widget Function() build) =>
      row(key, () => _pass, (_) => build());

  /// Lets go now of every row the last lay left out, which the next lay
  /// would — for a host whose moves lay rows in no lay of their own (the
  /// storyboard rail's labels), so a row the window left and brought back
  /// is built again, not handed back from a pass before (I-57 ㉣).
  void letGo() => _before = {};
}
