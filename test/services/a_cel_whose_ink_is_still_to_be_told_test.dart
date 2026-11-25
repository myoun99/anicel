// The first told compiles the compare kernel: tens of seconds on a machine
// this busy.
@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

import '../helpers/poll_until.dart';
import '../helpers/tiles_on_the_engine.dart';

/// 🚨A CEL WHOSE INK IS STILL TO BE TOLD (관제 2026-11-24, card
/// the-start-of-every-stroke-stalls-on-the-galaxy-tab ③-2 — 「모름 → 아는
/// 것으로 그리고, 답이 오면 고침」): a cel holding a tile pen-up handed over
/// is drawn, as the stroke showed it under the pen
/// ([BitmapSurface.showsSomethingNow]) — its block, its row's image, its
/// buttons —, and crosses once the GPU has told where the stroke left it
/// empty, as every crossing is told ([BrushFrameStore.celContentRevision]).
/// ㉡ What a file is told of it is the truth, waited for: saved before, it
/// opens as the same picture.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final side = gpuTileSide;
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );

  /// A stroke's tile of [value] on an empty cel, handed over as pen-up
  /// hands it: landed on nothing on its way ([EngineTileLedger.land],
  /// uncompared), its ink asked of the GPU ([EngineTileLedger.toldOf]) —
  /// the cel holding it, and when it is told.
  ({BitmapSurface cel, Future<void> told}) handedOnAnEmptyCel(
    GpuStroke stroke,
    int value,
  ) {
    final ledger = EngineTileLedger.instance;
    final [landed] = ledger.land(
      [(column: 0, row: 0, under: null)],
      by: tilesOf(value),
      ofTheHand: true,
    );
    final tile = landed.tile!;
    final told = ledger.toldOf(
      [(tile: tile, column: 0, row: 0)],
      by: stroke.toldOf,
      erases: false,
    );
    return (
      cel: BitmapSurface(
        canvasSize: CanvasSize(width: side, height: side),
        tileSize: side,
      ).putTiles([(coord: TileCoord(x: 0, y: 0), tile: tile)]),
      told: told,
    );
  }

  test('a first stroke on an empty cel: drawn at pen-up, as under the pen, '
      'and nothing moves once told', () async {
    final stroke = GpuStroke(appGpuEngine);
    addTearDown(stroke.free);
    final store = BrushFrameStore();
    final (:cel, :told) = handedOnAnEmptyCel(stroke, 200);
    final revision = store.celContentRevision.value;

    store.storeBakedSurface(key, cel);
    expect(
      cel.tiles.values.single.inkTold,
      isNotNull,
      reason: '⛔premise: its ink is still to be told',
    );
    expect(store.celHasRenderableContent(key), isTrue, reason: 'drawn');
    expect(store.celContentRevision.value, revision + 1, reason: 'crossed');

    await patiently(told);
    await Future<void>.delayed(Duration.zero);
    expect(store.celHasRenderableContent(key), isTrue, reason: 'told so');
    expect(
      store.celContentRevision.value,
      revision + 1,
      reason: 'and no second crossing',
    );
  });

  test('a stroke that leaves the cel empty: drawn till told, and crosses '
      'once it is — a crossing as every other', () async {
    final stroke = GpuStroke(appGpuEngine);
    addTearDown(stroke.free);
    final store = BrushFrameStore();
    final (:cel, :told) = handedOnAnEmptyCel(stroke, 0);
    store.storeBakedSurface(key, cel);
    expect(
      store.celHasRenderableContent(key),
      isTrue,
      reason: 'till told, drawn as under the pen',
    );
    final revision = store.celContentRevision.value;

    await patiently(told);
    expect(
      await pollUntil(() => store.celContentRevision.value != revision),
      isTrue,
      reason: 'it crosses once told',
    );
    expect(store.celHasRenderableContent(key), isFalse, reason: 'empty');
    expect(store.celContentRevision.value, revision + 1, reason: 'once');
    expect(store.celsLastCrossed, {key}, reason: 'naming its cel');
  });

  test('a cel moved on before its tile is told is asked as it moved', () async {
    final stroke = GpuStroke(appGpuEngine);
    addTearDown(stroke.free);
    final store = BrushFrameStore();
    final (:cel, :told) = handedOnAnEmptyCel(stroke, 0);
    store.storeBakedSurface(key, cel);
    // Undone before the GPU tells: the cel is empty again.
    store.storeBakedSurface(
      key,
      BitmapSurface(canvasSize: cel.canvasSize, tileSize: side),
    );
    final revision = store.celContentRevision.value;

    await patiently(told);
    await Future<void>.delayed(Duration.zero);
    expect(store.celHasRenderableContent(key), isFalse);
    expect(
      store.celContentRevision.value,
      revision,
      reason: 'what was told of a picture gone moves nothing',
    );
  });

  test('㉡ a file is told the truth of it, waited for: saved before the GPU '
      'tells, it opens as the same picture', () async {
    final stroke = GpuStroke(appGpuEngine);
    addTearDown(stroke.free);
    final inked = handedOnAnEmptyCel(stroke, 200);
    final blank = handedOnAnEmptyCel(stroke, 0);
    expect(
      [inked.cel.showsSomethingNow, blank.cel.showsSomethingNow],
      [true, true],
      reason: '⛔premise: not told, both drawn as under the pen',
    );

    final inkedBlob = AnicelCelBlob.ofSurface(key, inked.cel);
    final blankBlob = AnicelCelBlob.ofSurface(key, blank.cel);

    expect(
      [inkedBlob.showsSomething, blankBlob.showsSomething],
      [true, false],
      reason: 'its head says the truth',
    );
    expect(
      inkedBlob.toSurface().tileAt(TileCoord(x: 0, y: 0))!.pixels,
      inked.cel.tileAt(TileCoord(x: 0, y: 0))!.pixels,
      reason: 'and it opens as the same picture',
    );
    expect(blankBlob.toSurface().showsSomething, isFalse);
    await patiently(Future.wait([inked.told, blank.told]));
  });
}
