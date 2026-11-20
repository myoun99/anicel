import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/bitmap_tile.dart';

/// 🚨THE SLOTS OF THE HOT CELS OF THE FRAME AN EDITOR STANDS ON ARE NOT A
/// FULL POOL'S TO LET GO (🔢브러시/렌더링's, 2026-11-20, said on the card
/// cel-originals-are-held-twice-in-ram-and-on-the-gpu — no rule of the
/// user's; theirs is Q3, 「놓는다」, of every other slot): what each canvas
/// that stands says it stands on, asked as a full pool makes its room
/// (`EngineTileLedger._shortAsRoomIsMade`) and never before.
///
/// A hot cel kept in the file is a shell where the engine holds it whole
/// (`BrushFrameStore._usedAsItsShell`): its tiles hold no bytes here, and
/// one whose slot went reads its cel's kept bytes again — the whole cel
/// decoded on the thread that asks (card cel-thaw-holds-the-ui-thread, 13
/// to 32 ms a cel). The doors that go before a read cool such a shell
/// first (`BrushFrameStore.coolWhereTheEngineLetGo`), but a stroke's step
/// is composed with no door before it — so a full pool leaves the hot
/// cels of the frame a pen may come down on their slots and makes its
/// room elsewhere, past its budget where there is none.
///
/// ⛔Not what the canvas last laid: a frame whose picture was made ahead
/// is shown with nothing laid (`FramePictureView`), and a step is patched
/// into that picture — the frame an editor steps to and draws on is one
/// its canvas never laid whole. So the canvas says where it stands, and
/// that is read when it is asked: nothing is kept of a frame as it is
/// shown, played through or stepped past.
///
/// Held by the canvas alone: one that is gone stands on nothing.
final class TilesStoodOn {
  TilesStoodOn();

  /// The app's: what its ledger asks (`EngineTileLedger.instance`).
  static final TilesStoodOn app = TilesStoodOn();

  /// What each canvas said it stands on, kept for as long as the canvas
  /// lives: a list of these would hold every project that ever stood.
  final Expando<Iterable<BitmapTile> Function()> _tilesOf = Expando(
    'tiles stood on',
  );

  /// The canvases that stand now, each asked where it still lives.
  final List<WeakReference<Object>> _standing = [];

  /// [canvas] stands on what [tiles] answers, whenever it is asked — and
  /// on nothing it said before.
  void standsOn(Object canvas, Iterable<BitmapTile> Function() tiles) {
    standDown(canvas);
    _tilesOf[canvas] = tiles;
    _standing.add(WeakReference(canvas));
  }

  /// [canvas] stands on no tile any more.
  void standDown(Object canvas) =>
      _standing.removeWhere((each) => identical(each.target, canvas));

  /// Whether [canvas] is asked what it stands on.
  @visibleForTesting
  bool debugStands(Object canvas) =>
      _standing.any((each) => identical(each.target, canvas));

  /// The key of every tile stood on now ([BitmapTile.pixelsKey]) — by
  /// identity, as `==` reads every pixel.
  Set<Object> keysNow() {
    final keys = Set<Object>.identity();
    for (final each in _standing) {
      final standing = each.target;
      if (standing == null) {
        continue;
      }
      for (final tile in _tilesOf[standing]!()) {
        keys.add(tile.pixelsKey);
      }
    }
    return keys;
  }
}
