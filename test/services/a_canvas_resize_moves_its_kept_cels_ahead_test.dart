import 'dart:typed_data';

import 'package:anicel/src/core/on_a_worker.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/cels_parked_cold.dart';

/// 🔬Card `a-canvas-resize-rewrites-kept-cels-on-the-ui-thread` (F-432's
/// sequel, S5_BA saved and opened again — 127 cels of 2436×1524): a resize
/// thawed every kept cel of the cut on the UI thread, 1.9 s, and moved each
/// picture there, 2.4 s more for any anchor but the top left. Both are
/// worked out ahead now, on the machine's workers, while the wait window is
/// up ([BrushFrameStore.moveCutCelsAhead]) — and a move worked out ahead is
/// the very move the resize makes.
///
/// The paper is 16 × 8 in tiles of 4, its pasteboard a quarter past it; the
/// resize takes it to 14 × 6 about its centre — the picture one pixel up and
/// one to the left, a move of no whole tile.
void main() {
  const canvas = CanvasSize(width: 16, height: 8);
  const resized = CanvasSize(width: 14, height: 6);
  const tileSize = 4;
  const reach = PasteboardReach.quarter;
  const dx = -1;
  const dy = -1;

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );
  final drawnCel = key('drawn');
  final otherCel = key('other');

  /// Every pixel of its own bytes, so a pixel landing one off reads wrong.
  BitmapTile tile(int salt) => BitmapTile(
    size: tileSize,
    pixels: Uint8List.fromList([
      for (var i = 0; i < tileSize * tileSize * 4; i += 1) (i * 7 + salt) | 1,
    ]),
  );

  /// Ink inside the paper, on the pasteboard, a text's letters, and a file's
  /// picture laid past the wall.
  BitmapSurface drawn({int salt = 0}) => BitmapSurface(
    canvasSize: canvas,
    tileSize: tileSize,
    laidBounds: DirtyRegion(
      left: -6,
      top: -1,
      rightExclusive: 5,
      bottomExclusive: 3,
    ),
    texts: [
      CelText(
        id: 1,
        content: CelTextContent(
          spans: const [CelTextSpan(text: 'a', style: TextLetterStyle())],
          anchor: CanvasPoint(x: 2, y: 3),
        ),
        plate: {TileCoord(x: 1, y: 0): tile(90 + salt)},
      ),
    ],
  ).putTiles([
    (coord: TileCoord(x: 0, y: 0), tile: tile(10 + salt)),
    (coord: TileCoord(x: 1, y: 1), tile: tile(20 + salt)),
    (coord: TileCoord(x: 3, y: 0), tile: tile(30 + salt)),
    (coord: TileCoord(x: -1, y: 0), tile: tile(40 + salt)),
    (coord: TileCoord(x: -2, y: 0), tile: tile(50 + salt)),
  ]);

  void expectSamePicture(BitmapSurface? actual, BitmapSurface expected) {
    expect(actual, isNotNull);
    expect(actual!.canvasSize, expected.canvasSize);
    expect(actual.pasteboardReach, expected.pasteboardReach);
    expect(actual.laidBounds, expected.laidBounds);
    void samePixels(
      Map<TileCoord, BitmapTile> tiles,
      Map<TileCoord, BitmapTile> expected,
    ) {
      expect(tiles.keys.toSet(), expected.keys.toSet());
      for (final MapEntry(key: coord, :value) in expected.entries) {
        expect(tiles[coord]!.pixels, value.pixels, reason: '$coord');
      }
    }

    samePixels(actual.tiles, expected.tiles);
    expect(actual.texts.length, expected.texts.length);
    for (final (index, text) in expected.texts.indexed) {
      expect(actual.texts[index].content, text.content);
      samePixels(actual.texts[index].plate, text.plate);
    }
  }

  void resize(BrushFrameStore store, {int dx = dx, int dy = dy}) =>
      store.adoptCutCanvasSize(
        cutId: const CutId('c'),
        canvasSize: resized,
        dx: dx.toDouble(),
        dy: dy.toDouble(),
      );

  Future<void> moveAhead(
    BrushFrameStore store, {
    int dx = dx,
    int dy = dy,
    void Function(double done)? report,
  }) => store.moveCutCelsAhead(const [
    CutId('c'),
  ], (canvasSize: resized, dx: dx, dy: dy), report: report);

  for (final (tier, keep) in <(String, _KeepAll)>[
    ('parked cold', parkCold),
    ('kept in a file', keepInAFile),
  ]) {
    group(tier, () {
      BrushFrameStore kept() {
        final store = BrushFrameStore();
        keep(store, {
          drawnCel: drawn(),
          otherCel: drawn(salt: 3),
        }, pasteboardReach: reach);
        return store;
      }

      test('what is worked out is the move the resize makes', () async {
        final here = kept();
        final ahead = kept();
        await moveAhead(ahead);
        resize(here);
        resize(ahead);
        expect(here.celsMovedHere, 2, reason: 'premise: moved on the UI thread');
        expect(ahead.celsMovedHere, 0, reason: 'every move was worked out');
        for (final cel in [drawnCel, otherCel]) {
          expectSamePicture(
            ahead.bakedSurfaceOrNull(cel),
            here.bakedSurfaceOrNull(cel)!,
          );
        }
        expect(ahead.dirtyCelKeysSinceSave, here.dirtyCelKeysSinceSave);
      });

      test('the resize takes the very picture worked out, and lets go of '
          'it', () async {
        final store = kept();
        await moveAhead(store);
        final worked = store.movedAheadOf(drawnCel);
        expect(worked, isNotNull);
        // Thawed ahead as a read here thaws it: the picture the undo keeps.
        expectSamePicture(
          store.hotBakedSurfaceOrNull(drawnCel),
          kept().bakedSurfaceOrNull(drawnCel)!,
        );
        resize(store);
        expect(identical(store.hotBakedSurfaceOrNull(drawnCel), worked), isTrue);
        expect(store.movedAheadOf(otherCel), isNull);
      });
    });
  }

  test('on a worker of its own, the road production takes, counted for the '
      'window', () async {
    debugWorkersRunHere = false;
    addTearDown(() => debugWorkersRunHere = true);
    final store = BrushFrameStore();
    keepInAFile(store, {
      drawnCel: drawn(),
      otherCel: drawn(salt: 3),
    }, pasteboardReach: reach);
    final reports = <double>[];
    await moveAhead(store, report: reports.add);
    expect(reports, [0.5, 1.0]);
    final here = BrushFrameStore();
    keepInAFile(here, {drawnCel: drawn()}, pasteboardReach: reach);
    resize(store);
    resize(here);
    expect(store.celsMovedHere, 0);
    expectSamePicture(
      store.bakedSurfaceOrNull(drawnCel),
      here.bakedSurfaceOrNull(drawnCel)!,
    );
  });

  test('ink the wall cut away on the thaw stays away, whatever the move '
      'carries inside the new wall', () async {
    // Wholly past the quarter wall of the paper (x -8..-5, the wall at -4),
    // and a grow of six about the centre carries it three to the right —
    // to where the wider paper's wall reaches.
    const grown = CanvasSize(width: 22, height: 8);
    BitmapSurface pastTheWall() => BitmapSurface(
      canvasSize: canvas,
      tileSize: tileSize,
    ).putTiles([(coord: TileCoord(x: -2, y: 0), tile: tile(60))]);
    final here = BrushFrameStore();
    final ahead = BrushFrameStore();
    for (final store in [here, ahead]) {
      keepInAFile(store, {drawnCel: pastTheWall()}, pasteboardReach: reach);
    }
    await ahead.moveCutCelsAhead(const [
      CutId('c'),
    ], (canvasSize: grown, dx: 3, dy: 0));
    for (final store in [here, ahead]) {
      store.adoptCutCanvasSize(
        cutId: const CutId('c'),
        canvasSize: grown,
        dx: 3,
        dy: 0,
      );
    }
    expect(ahead.celsMovedHere, 0);
    expectSamePicture(
      ahead.bakedSurfaceOrNull(drawnCel),
      here.bakedSurfaceOrNull(drawnCel)!,
    );
  });

  test('a cel drawn on since is moved as it stands now', () async {
    final store = BrushFrameStore();
    keepInAFile(store, {drawnCel: drawn()}, pasteboardReach: reach);
    await moveAhead(store);
    final worked = store.movedAheadOf(drawnCel);
    store.storeBakedSurface(drawnCel, drawn(salt: 5));
    resize(store);
    expect(store.celsMovedHere, 1);
    final here = BrushFrameStore();
    keepInAFile(here, {drawnCel: drawn(salt: 5)}, pasteboardReach: reach);
    resize(here);
    final moved = store.bakedSurfaceOrNull(drawnCel);
    expect(identical(moved, worked), isFalse);
    expectSamePicture(moved, here.bakedSurfaceOrNull(drawnCel)!);
  });

  test('worked out for another move: not taken, and not left behind', () async {
    final store = BrushFrameStore();
    keepInAFile(store, {drawnCel: drawn()}, pasteboardReach: reach);
    await moveAhead(store, dx: -2);
    resize(store);
    expect(store.celsMovedHere, 1);
    expect(store.movedAheadOf(drawnCel), isNull);
    final here = BrushFrameStore();
    keepInAFile(here, {drawnCel: drawn()}, pasteboardReach: reach);
    resize(here);
    expectSamePicture(
      store.bakedSurfaceOrNull(drawnCel),
      here.bakedSurfaceOrNull(drawnCel)!,
    );
  });

  test('a hot cel is moved where it is: its pixels are not bytes a worker '
      'is handed', () async {
    final store = BrushFrameStore()..storeBakedSurface(drawnCel, drawn());
    await moveAhead(store);
    expect(store.movedAheadOf(drawnCel), isNull);
    resize(store);
    expect(store.celsMovedHere, 1);
  });

  test('a move of whole tiles is made where the tiles are: the very tiles '
      'renamed, shared with the undo', () async {
    final store = BrushFrameStore();
    keepInAFile(store, {drawnCel: drawn()}, pasteboardReach: reach);
    await moveAhead(store, dx: -tileSize, dy: 0);
    expect(store.movedAheadOf(drawnCel), isNull);
    final was = store.hotBakedSurfaceOrNull(drawnCel);
    expect(was, isNotNull, reason: 'thawed ahead all the same');
    resize(store, dx: -tileSize, dy: 0);
    expect(store.celsMovedHere, 1);
    expect(
      identical(
        store.bakedSurfaceOrNull(drawnCel)!.tileAt(TileCoord(x: 0, y: 1)),
        was!.tileAt(TileCoord(x: 1, y: 1)),
      ),
      isTrue,
    );
  });

  test('nothing to move: the thaw alone', () async {
    final store = BrushFrameStore();
    keepInAFile(store, {drawnCel: drawn()}, pasteboardReach: reach);
    final reports = <double>[];
    await moveAhead(store, dx: 0, dy: 0, report: reports.add);
    expect(reports, [1.0]);
    expect(store.hotBakedSurfaceOrNull(drawnCel), isNotNull);
    expect(store.movedAheadOf(drawnCel), isNull);
  });

  test('worked out again, the last round is the one held', () async {
    final store = BrushFrameStore();
    keepInAFile(store, {drawnCel: drawn()}, pasteboardReach: reach);
    await moveAhead(store, dx: -2);
    await moveAhead(store);
    expect(store.movedAheadOf(drawnCel), isNull, reason: 'hot by then');
    resize(store);
    expect(store.celsMovedHere, 1);
  });

  test('a store laid in anew lets what was worked out go', () async {
    final store = BrushFrameStore();
    keepInAFile(store, {drawnCel: drawn()}, pasteboardReach: reach);
    await moveAhead(store);
    expect(store.movedAheadOf(drawnCel), isNotNull);
    parkCold(store, const {});
    expect(store.movedAheadOf(drawnCel), isNull);
  });
}

typedef _KeepAll =
    Map<BrushFrameKey, Object> Function(
      BrushFrameStore store,
      Map<BrushFrameKey, BitmapSurface> cels, {
      PasteboardReach pasteboardReach,
    });
