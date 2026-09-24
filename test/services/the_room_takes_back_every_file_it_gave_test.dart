import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/scratch_file.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/services/undo_surface_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/project_scratch_folder.dart';

/// 🚨★★★**THE SPILL MUST NOT LEAVE FILES BEHIND.** The cold tier exists so
/// an over-budget undo entry MOVES instead of dying; a room that grows for
/// as long as the session does is the shape of the problem it was built to
/// solve ([ParkableCommand.dropPayload]'s own words). Two windows let it
/// grow anyway, and both are widest exactly when the room is busiest.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = 8;
  const canvas = CanvasSize(width: 64, height: 64);
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  BitmapSurface surfaceOf(int fill) {
    final coord = TileCoord(x: 0, y: 0);
    return BitmapSurface(
      canvasSize: canvas,
      tileSize: size,
      tiles: {
        coord: BitmapTile(
          size: size,
          pixels: Uint8List(BitmapTile.bytesFor(size))
            ..fillRange(0, BitmapTile.bytesFor(size), fill),
        ),
      },
    );
  }

  /// 🚨THE ENTRY LEFT THE STACK MID-ENCODE. `park()` spans an isolate hop,
  /// and the stack sheds and trims SYNCHRONOUSLY from `_push` while that
  /// await sits on the event loop — so a `drop()` lands inside the window
  /// where there is no path to give back yet. It used to read
  /// `_parkedPath`, find null, and return having done nothing; the park
  /// then wrote a file that nothing would ever read or remove.
  test('🚨dropping DURING a park still gives the file back', () async {
    final snapshot = UndoSurfaceSnapshot(
      key: key,
      snapshot: surfaceOf(7),
      sharedWith: null,
    );
    final before = _volatilePaths();

    final parking = snapshot.park();
    // Inside the isolate hop, which is where the stack's own droppers run.
    snapshot.drop();
    expect(await parking, isTrue);

    expect(
      _volatilePaths().difference(before),
      isEmpty,
      reason: 'the room is exactly as it was before a park nobody wanted',
    );
    expect(snapshot.isParked, isFalse);
    expect(
      snapshot.residentBytes,
      0,
      reason: 'and the bytes are not still in RAM either',
    );
  });

  test('a park nobody dropped keeps its file, so the case above is not '
      'just "parking never writes"', () async {
    final snapshot = UndoSurfaceSnapshot(
      key: key,
      snapshot: surfaceOf(9),
      sharedWith: null,
    );
    final before = _volatilePaths();

    expect(await snapshot.park(), isTrue);

    expect(_volatilePaths().difference(before), hasLength(1));
  });

  /// 🚨A REFUSED WRITE IS THE DISK-FULL CASE, and it is the one that has
  /// already put bytes in the neighbour. Leaving them there takes space on
  /// the volume that just said it had none — and the caller retries on the
  /// next edit with a fresh name, so it was one orphan per stroke.
  test('🚨a refused write takes its own .part with it', () {
    final room = Directory(SessionScratch.volatileFolder())
      ..createSync(recursive: true);
    // A directory where the file wants to be: the rename cannot land, and
    // the bytes have already been written to the neighbour by then.
    final path = '${room.path}/refused-write.undo';
    Directory(path).createSync(recursive: true);
    deleteAfterSessionEnds(Directory(path));

    expect(ScratchFile.write(path, Uint8List(64)), isNull);

    expect(
      File('$path.part').existsSync(),
      isFalse,
      reason: 'the neighbour must not outlive the refusal',
    );
  });
}

Set<String> _volatilePaths() {
  final room = Directory(SessionScratch.volatileFolder());
  if (!room.existsSync()) {
    return const {};
  }
  return room.listSync().whereType<File>().map((file) => file.path).toSet();
}
