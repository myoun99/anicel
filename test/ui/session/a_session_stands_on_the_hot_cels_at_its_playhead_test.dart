import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show coveringDrawingBlockAt;
import 'package:anicel/src/native/tiles_stood_on.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/an_empty_drawing_row.dart';

/// 🚨THE HOT CELS OF THE FRAME A PROJECT'S CANVAS STANDS ON ARE WHAT IT
/// STANDS ON (card cel-originals-are-held-twice-in-ram-and-on-the-gpu,
/// 2026-11-20 — `TilesStoodOn` has why): each row's cel as the cut exposes
/// it at the playhead, where that cel is hot — read where the playhead is
/// when it is asked, whatever showed the frame, and no more once the
/// project is closed.
///
/// What a full pool does with the answer is the ledger's
/// (a_full_pool_leaves_the_tiles_stood_on_their_slots_test.dart).
void main() {
  // The app's own list: other projects of this isolate may stand in it, so
  // each tile is asked for by name.
  bool stoodOn(BitmapTile tile) =>
      TilesStoodOn.app.keysNow().contains(tile.pixelsKey);

  FrameId celAt(EditorSessionManager session, LayerId layerId, int frame) =>
      coveringDrawingBlockAt(
        session.requireActiveCut.layers.byId(layerId)!.timeline,
        frame,
      )!.frameId;

  /// The one tile of the cel of [layerId] at [frame], made hot.
  BitmapTile hotAt(EditorSessionManager session, LayerId layerId, int frame) {
    final cut = session.requireActiveCut;
    final tile = BitmapTile(size: 8, pixels: Uint8List(8 * 8 * 4)..[3] = 255);
    session.renderCaches.brushFrameStore.storeBakedSurface(
      session.brushFrameKeyForCut(cut, layerId, celAt(session, layerId, frame)),
      BitmapSurface(
        canvasSize: cut.canvasSize,
        tileSize: 8,
        tiles: {TileCoord(x: 0, y: 0): tile},
      ),
    );
    return tile;
  }

  /// A project whose row A holds cels at 0 and 3 (a frame long each) and
  /// whose row B, above it, holds one at 3 — every one hot; standing on A
  /// at 0.
  ({
    EditorSessionManager session,
    BitmapTile a0,
    BitmapTile a3,
    BitmapTile b3,
  })
  threeHotCels() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    session.createDrawingAtCurrentFrame();
    final a = session.activeLayer!.id;
    session.selectFrameIndex(3);
    session.createDrawingAtCurrentFrame();
    addAnEmptyDrawingRow(session);
    final b = session.activeLayer!.id;
    session.createDrawingAtCurrentFrame();
    session.selectLayer(a);
    final cels = (
      session: session,
      a0: hotAt(session, a, 0),
      a3: hotAt(session, a, 3),
      b3: hotAt(session, b, 3),
    );
    session.selectFrameIndex(0);
    return cels;
  }

  test('🚨a project stands on the hot cels its frame shows — every row\'s, '
      'and no other frame\'s', () {
    final (:session, :a0, :a3, :b3) = threeHotCels();
    addTearDown(session.dispose);

    expect([stoodOn(a0), stoodOn(a3), stoodOn(b3)], [true, false, false]);
  });

  test('🚨gone to another frame it stands on that one\'s, with no word to '
      'anyone — and on none where the frame shows no cel', () {
    final (:session, :a0, :a3, :b3) = threeHotCels();
    addTearDown(session.dispose);

    session.selectFrameIndex(3);
    expect([stoodOn(a0), stoodOn(a3), stoodOn(b3)], [false, true, true]);

    session.selectFrameIndex(1);
    expect([stoodOn(a0), stoodOn(a3), stoodOn(b3)], [false, false, false]);
  });

  test('a cel that is hot no more is stood on no more', () {
    final (:session, :a0, a3: _, b3: _) = threeHotCels();
    addTearDown(session.dispose);
    expect(stoodOn(a0), isTrue, reason: '⛔premise');

    final again = hotAt(session, session.activeLayer!.id, 0);

    expect([stoodOn(a0), stoodOn(again)], [false, true]);
  });

  test('🚨a project closed stands on nothing', () {
    final (:session, :a0, a3: _, b3: _) = threeHotCels();
    expect(stoodOn(a0), isTrue, reason: '⛔premise');

    session.dispose();

    expect(stoodOn(a0), isFalse);
  });
}
