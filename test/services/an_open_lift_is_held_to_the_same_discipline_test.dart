import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/placed_tile.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**THE SAME BYTES WERE DISCIPLINED ON ONE SIDE OF A CONFIRM AND NOT
/// THE OTHER.** A confirmed transform's picture is budgeted the moment it
/// becomes a history entry; while the box was still open the pixels a tool
/// held sat in a plain Map in a widget's State, with no budget, no cap and
/// no way to get them back. A user who had not confirmed was held to LESS
/// discipline than one who had. 유저 확정 2026-09-08 (`undo-41-hole-scope`).
///
/// ↩️**That is the half of the 09-08 answer the 09-17 reversal KEPT.** The
/// other half — committing the erase the moment the box opens — is gone: a
/// move session writes nothing until it lands, so what it holds is no
/// longer a pre-lift SNAPSHOT of pixels that only it has, but the cel with
/// the hole, DERIVED from a picture that is still sitting right there.
///
/// 🎯**And that changes how the bytes come back, which is the whole of this
/// file.** A snapshot can only be given back by parking it to disk, because
/// losing it loses the user's pixels. A derivation is given back by
/// DROPPING it: the holder rebuilds it on the next paint. No isolate, no
/// encode, no file, and nothing that can refuse to come back.
///
/// ⛔**AND IT MUST NOT BE PARKED.** A parked surface is one the next paint
/// cannot draw — the blank frame 유저 forbade outright when they chose this
/// round: 「조작 전/중/후가 빈 프레임 존재안하고 눈에 보이는 결과가
/// 달라지지 않는건 절대조건」. The last case here is that, measured on the
/// 휘발성 room itself rather than on a flag.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = 8;
  const canvas = CanvasSize(width: 64, height: 64);

  PlacedTile tileOf(int x, int fill) {
    final coord = TileCoord(x: x, y: 0);
    return (
      coord: coord,
      tile: BitmapTile(
        size: size,
        pixels: Uint8List(BitmapTile.bytesFor(size))
          ..fillRange(0, BitmapTile.bytesFor(size), fill),
      ),
    );
  }

  BitmapSurface surfaceOf(Iterable<PlacedTile> tiles) => BitmapSurface(
    canvasSize: canvas,
    tileSize: size,
    tiles: {for (final t in tiles) t.coord: t.tile},
  );

  /// What an open move session holds: the cel with the hole, against the
  /// cel it was derived from. The erase rebuilt ONE tile and left the other
  /// alone, which is why the session owes one tile and not two.
  ({BitmapSurface holed, BitmapSurface cel}) session() {
    final untouched = tileOf(0, 11);
    final cel = surfaceOf([untouched, tileOf(1, 22)]);
    final holed = surfaceOf([untouched, tileOf(1, 0)]);
    return (holed: holed, cel: cel);
  }

  /// The store as a holder uses it: bytes on demand, and a reclaim that
  /// drops the derivation.
  ({BrushFrameStore store, bool Function() held}) holding(
    ({BitmapSurface holed, BitmapSurface cel}) open,
  ) {
    final store = BrushFrameStore();
    BitmapSurface? holed = open.holed;
    store.holdReclaimableView(
      1,
      bytes: () => holed?.bytesNotSharedWith(open.cel) ?? 0,
      reclaim: () => holed = null,
    );
    return (store: store, held: () => holed != null);
  }

  test('an open session reports its bytes — only the tiles it does not '
      'share with the cel', () {
    final open = session();
    final store = BrushFrameStore();
    expect(store.reclaimableViewBytes, 0, reason: 'nothing open yet');

    final view = holding(open);
    expect(
      view.store.reclaimableViewBytes,
      BitmapTile.bytesFor(size),
      reason: 'only the tile the erase rebuilt — the rest is the cel\'s own',
    );
  });

  test('a memory warning takes them back, and the holder is told so it can '
      'rebuild', () {
    final view = holding(session());
    expect(view.held(), isTrue);

    view.store.respondToMemoryPressure();

    // ⛔This is the whole round: before it, the store had no idea these
    // bytes existed and a warning left every one of them in RAM.
    expect(view.store.reclaimableViewBytes, 0);
    expect(
      view.held(),
      isFalse,
      reason: 'the holder let go — the next paint derives it again',
    );
  });

  test('releasing takes it back from the store — a session that ended must '
      'not go on being weighed for nobody', () {
    final view = holding(session());
    expect(view.store.reclaimableViewBytes, greaterThan(0));

    view.store.releaseReclaimableView(1);

    expect(view.store.reclaimableViewBytes, 0);
    expect(
      view.held(),
      isTrue,
      reason: 'releasing is the tool saying「mine now」, not a reclaim',
    );
  });

  test('🚨and a warning writes NO file — a picture the next paint needs '
      'must never go to disk', () {
    final view = holding(session());
    final before = _volatilePaths();

    view.store.respondToMemoryPressure();

    // ⛔THE ROOM IS THE ASSERTION, not a flag. Parking a derivation would
    // look like a success from every angle the old pass measured — the
    // bytes fall, the flag flips, the surface reads back — while the next
    // paint waits on a decode for a picture it could have rebuilt from the
    // cel sitting beside it.
    expect(_volatilePaths().difference(before), isEmpty);
  });
}

/// What is in the run's 휘발성 room right now.
Set<String> _volatilePaths() {
  final room = Directory(SessionScratch.volatileFolder());
  if (!room.existsSync()) {
    return const {};
  }
  return room.listSync().whereType<File>().map((file) => file.path).toSet();
}
