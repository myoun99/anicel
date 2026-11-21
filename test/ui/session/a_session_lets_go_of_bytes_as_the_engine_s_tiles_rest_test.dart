import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show coveringDrawingBlockAt;
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/native/tiles_at_rest.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/import/raster_cel_import.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/tiles_on_the_engine.dart';

/// 🚨A PROJECT'S STORE HEARS OF THE ENGINE'S RESTS, AND WHICH CELS ITS
/// CANVAS STANDS ON (card cel-originals-are-held-twice-in-ram-and-on-the-
/// gpu — 유저 2026-11-21 on Q4 「최대한 사본안만드는게 중요」 and on Q6
/// 「사본이나 ram에있는걸 최대한 없애고싶어서」): at a rest
/// (`TilesAtRest`) its kept cels let go of the bytes the engine holds, and
/// the cels an import lands are parked behind — every one but the frame's
/// its canvas stands on, read where the playhead is then; and a project
/// closed hears no more.
///
/// What the store does with each word is its own
/// (a_hot_cel_that_is_kept_lets_its_bytes_go_at_a_rest_test.dart,
/// an_imported_cel_is_parked_behind_test.dart), and when a rest is the
/// ledger's (the_ledger_folds_its_tiles_once_the_hand_rests_test.dart).
void main() {
  final origin = TileCoord(x: 0, y: 0);

  /// A project whose row holds a cel at 0 and one at 3, a frame long
  /// each; standing on the one at 0.
  ({EditorSessionManager session, BrushFrameKey at0, BrushFrameKey at3})
  twoCels() {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    session.createDrawingAtCurrentFrame();
    final row = session.activeLayer!.id;
    session.selectFrameIndex(3);
    session.createDrawingAtCurrentFrame();
    session.selectFrameIndex(0);
    BrushFrameKey keyAt(int frame) {
      final cut = session.requireActiveCut;
      return session.brushFrameKeyForCut(
        cut,
        row,
        coveringDrawingBlockAt(cut.layers.byId(row)!.timeline, frame)!.frameId,
      );
    }

    return (session: session, at0: keyAt(0), at3: keyAt(3));
  }

  /// A cel of the project's cut, one tile drawn on.
  BitmapSurface drawn(EditorSessionManager session) => BitmapSurface(
    canvasSize: session.requireActiveCut.canvasSize,
    tileSize: gpuTileSide,
    tiles: {origin: aTileOfItsOwn()},
  );

  bool bytesHere(BrushFrameStore store, BrushFrameKey key) =>
      store.hotBakedSurfaceOrNull(key)!.tiles[origin]!.hasItsBytesHere;

  test('🚨at a rest of the engine\'s tiles a project\'s kept cels let go '
      'of their bytes here — but the frame\'s its canvas stands on, till '
      'it has moved on', () {
    final (:session, :at0, :at3) = twoCels();
    addTearDown(session.dispose);
    final store = session.renderCaches.brushFrameStore;
    keepInAFile(store, {at0: drawn(session), at3: drawn(session)});
    // Used and shown: their bytes here, and their tiles on the engine.
    for (final key in [at0, at3]) {
      final used = store.bakedSurfaceOrNull(key)!;
      EngineTileLedger.instance.held(
        (hold) => hold.slotsOf(EngineTileLedger.landedCel, [
          ...used.tiles.values,
        ]),
      );
    }
    expect(
      [bytesHere(store, at0), bytesHere(store, at3)],
      [true, true],
      reason: '⛔premise: thawed, their bytes here',
    );

    TilesAtRest.app.rested();

    expect([bytesHere(store, at0), bytesHere(store, at3)], [true, false]);

    session.selectFrameIndex(3);
    TilesAtRest.app.rested();

    expect([bytesHere(store, at0), bytesHere(store, at3)], [false, false]);
  });

  test('🚨the cels an import lands are parked behind — but the frame\'s '
      'its canvas stands on, read where it stands then', () async {
    final (:session, :at0, :at3) = twoCels();
    addTearDown(session.dispose);
    final store = session.renderCaches.brushFrameStore;
    session.selectFrameIndex(3);

    landImportedCel(store, at0, drawn(session));
    landImportedCel(store, at3, drawn(session));
    await store.drainTiering();

    expect(store.hotBakedSurfaceOrNull(at3), isNotNull);
    expect(store.isCelParked(at3), isFalse);
    expect(store.hotBakedSurfaceOrNull(at0), isNull);
    expect(store.isCelCold(at0), isTrue);
  });

  test('🚨a project closed is told of no rest', () {
    final (:session, at0: _, at3: _) = twoCels();
    final canvas = session.editingCanvas;
    expect(TilesAtRest.app.debugTells(canvas), isTrue, reason: '⛔premise');

    session.dispose();

    // ⛔Not left to its emptied store to do nothing: every rest would
    // call a closed project's store, for as long as the app runs.
    expect(TilesAtRest.app.debugTells(canvas), isFalse);
  });
}
