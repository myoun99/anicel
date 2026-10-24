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
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cels_kept_in_a_file.dart';

/// 🚨Whatever lands on a cel while a save runs is the NEXT save's to write
/// (card a-resize-during-a-save-can-lose-the-resize, found 2026-10-21: a
/// canvas resized while Ctrl+S ran came back at its old size once it
/// cooled, and the next save skipped it).
///
/// A save takes its snapshot when it begins and adopts what it wrote when
/// it ends ([BrushFrameStore.adoptSavedFile]); a cel changed in between
/// holds bytes the file does not. Each change below lands in between, and
/// the cel must come out of the adoption unsaved and changed — not clean,
/// on a ref to the bytes from before. (A stroke landing then is pinned in
/// `brush_frame_store_tiering_test.dart`, a wall moving then in
/// `a_pasteboard_that_moves_takes_every_picture_with_it_test.dart`.)
void main() {
  const canvas = CanvasSize(width: 16, height: 16);
  const grown = CanvasSize(width: 32, height: 32);
  const cutId = CutId('c');

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: cutId,
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  BitmapSurface ink() => BitmapSurface(
    canvasSize: canvas,
    tileSize: 8,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: 8,
        pixels: Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 7),
      ),
    },
  );

  BitmapSurface nothing() => BitmapSurface(canvasSize: canvas, tileSize: 8);

  /// A save around [during]: its snapshot first, its adoption last, with a
  /// ref for every cel the snapshot held — or [written] when the save wrote
  /// something else.
  void saveAround(
    BrushFrameStore store,
    void Function() during, {
    Map<BrushFrameKey, AnicelCelFileRef>? written,
  }) {
    final snapshot = store.bakedSnapshotForSave();
    during();
    store.adoptSavedFile(
      written ??
          {
            for (final cel in {
              ...snapshot.hot.keys,
              ...snapshot.cold.keys,
              ...snapshot.fileRefs.keys,
            })
              cel: const AnicelCelFileRef(
                filePath: 'written-by-the-save.anicel',
                dataOffset: 0,
                length: 1,
                canvasSize: canvas,
                tileSize: 8,
                photoPaths: [],
                showsSomething: true,
              ),
          },
      dirtyTicksAtSnapshot: snapshot.dirtyTicks,
    );
  }

  void expectLeftForTheNextSave(
    BrushFrameStore store,
    BrushFrameKey cel, {
    required CanvasSize size,
  }) {
    expect(
      store.dirtyCelKeysSinceSave,
      contains(cel),
      reason: 'the next save writes it',
    );
    expect(
      store.isCelFileBacked(cel),
      isFalse,
      reason: 'the file holds the bytes from before the change: a ref to '
          'them lets cooling drop the change for free',
    );
    expect(store.bakedSurfaceOrNull(cel)?.canvasSize, size);
  }

  group('a cel the save wrote, changed while it ran, is left unsaved', () {
    test('resized while drawn (the card: draw, Ctrl+S, resize)', () {
      final store = BrushFrameStore();
      final cel = key('drawn');
      store.storeBakedSurface(cel, ink());
      saveAround(store, () => store.resizeBakedSurfaces(grown, cutId: cutId));
      expectLeftForTheNextSave(store, cel, size: grown);
    });

    test('resized while parked', () async {
      final store = BrushFrameStore()..hotCelByteBudget = 0;
      final cel = key('parked');
      store.storeBakedSurface(cel, ink());
      // The cel drawn last never cools.
      store.storeBakedSurface(key('drawn-after'), ink());
      await store.drainCooling();
      expect(store.isCelCold(cel), isTrue, reason: 'premise: parked');
      saveAround(store, () => store.resizeBakedSurfaces(grown, cutId: cutId));
      expectLeftForTheNextSave(store, cel, size: grown);
    });

    test('resized while kept in the file', () {
      final store = BrushFrameStore();
      final cel = key('kept');
      keepInAFile(store, {cel: ink()});
      saveAround(store, () => store.resizeBakedSurfaces(grown, cutId: cutId));
      expectLeftForTheNextSave(store, cel, size: grown);
    });

    test('resized from an anchor, its picture moved', () {
      final store = BrushFrameStore();
      final cel = key('anchored');
      store.storeBakedSurface(cel, ink());
      saveAround(
        store,
        () => store.adoptCutCanvasSize(
          cutId: cutId,
          canvasSize: grown,
          dx: 8,
        ),
      );
      expectLeftForTheNextSave(store, cel, size: grown);
    });

    test('erased', () {
      final store = BrushFrameStore();
      final cel = key('erased');
      store.storeBakedSurface(cel, ink());
      saveAround(store, () => store.storeBakedSurface(cel, nothing()));
      expect(store.dirtyCelKeysSinceSave, contains(cel));
      expect(store.isCelFileBacked(cel), isFalse);
      expect(store.bakedSurfaceOrNull(cel), isNull);
    });
  });

  test('a cel moved to another frame while the save ran stands only where '
      'it went — the save\'s ref to where it was stands no copy there', () {
    final store = BrushFrameStore();
    final from = key('from');
    final to = key('to');
    store.storeBakedSurface(from, ink());
    saveAround(store, () => store.rekeyFrames([(from, to)]));
    expect(store.isCelFileBacked(from), isFalse);
    expect(store.bakedSurfaceOrNull(from), isNull);
    expect(store.dirtyCelKeysSinceSave, containsAll([from, to]));
    expect(store.bakedSurfaceOrNull(to)?.canvasSize, canvas);
  });

  test('a cel an undo moved back while the save ran, onto the frame the '
      'save wrote as empty, is left for the next save to write there', () {
    final store = BrushFrameStore();
    final there = key('there');
    final back = key('back');
    store.storeBakedSurface(back, ink());
    saveAround(store, () {});
    store.rekeyFrames([(back, there)]);
    saveAround(store, () => store.rekeyFrames([(there, back)]));
    expect(store.dirtyCelKeysSinceSave, contains(back));
    expect(store.bakedSurfaceOrNull(back)?.canvasSize, canvas);
  });

  test('a cel the save wrote as erased, brought back by an undo while it '
      'ran, is left unsaved', () {
    final store = BrushFrameStore();
    final cel = key('undone');
    store.storeBakedSurface(cel, ink());
    saveAround(store, () {});
    final before = store.bakedSurfacesForCut(cutId);
    store.storeBakedSurface(cel, nothing());
    saveAround(
      store,
      () => store.restoreBakedForCut(cutId, before),
      written: const {},
    );
    expectLeftForTheNextSave(store, cel, size: canvas);
  });
}
