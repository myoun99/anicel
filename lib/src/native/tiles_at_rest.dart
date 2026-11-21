import 'package:flutter/foundation.dart' show visibleForTesting;

/// 🚨WHO IS TOLD AS THE ENGINE'S TILES COME TO REST (🔢브러시/렌더링's,
/// 2026-11-21, on the card cel-originals-are-held-twice-in-ram-and-on-the-
/// gpu — no rule of the user's; theirs is Q3, 「놓는다」): a rest
/// (`EngineTileLedger.rest`) after tiles were stored there, a hand at work
/// putting it off — the rest the folds begin at
/// (`EngineTileLedger._foldFromHere`). A project's store then lets go of
/// the bytes it holds here of cels the engine holds
/// (`BrushFrameStore.letGoOfBytesTheEngineHolds`).
///
/// Each is told for as long as its holder lives, as a canvas says what it
/// stands on (`TilesStoodOn`): a list of these would hold every project
/// that was ever told.
final class TilesAtRest {
  TilesAtRest();

  /// The app's: what its ledger tells (`EngineTileLedger.instance`).
  static final TilesAtRest app = TilesAtRest();

  final Expando<void Function()> _toldOf = Expando('told at rest');

  /// Who is told now, each asked where it still lives.
  final List<WeakReference<Object>> _holders = [];

  /// [rested] is called at each rest from here on, for as long as
  /// [holder] lives — and nothing it was told by before.
  void tells(Object holder, void Function() rested) {
    forgets(holder);
    _toldOf[holder] = rested;
    _holders.add(WeakReference(holder));
  }

  /// [holder] is told of no rest any more.
  void forgets(Object holder) =>
      _holders.removeWhere((each) => identical(each.target, holder));

  /// Whether [holder] is told of the rests.
  @visibleForTesting
  bool debugTells(Object holder) =>
      _holders.any((each) => identical(each.target, holder));

  /// The engine's tiles have come to rest: everyone told hears it, in
  /// the order they asked.
  void rested() {
    _holders.removeWhere((each) => each.target == null);
    for (final each in [..._holders]) {
      final holder = each.target;
      if (holder != null) {
        _toldOf[holder]?.call();
      }
    }
  }
}
