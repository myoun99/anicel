import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/swap_layer_reference_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// I-47 (유저 2026-09-25 · Q1 2026-09-27 「창 없이 바로 바꾼다 (언두 하나)」):
/// a reference row shows another file, and ONE undo step carries both what
/// it points at and the picture its cel holds.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cel = CanvasSize(width: 256, height: 256);
  const rowId = LayerId('bg');
  const celId = FrameId('bg-cel');
  late ProjectRepository repository;
  late CutId cutId;
  late BrushFrameKey key;
  late BrushFrameStore store;

  BitmapSurface solid(int value) => BitmapSurface(
    canvasSize: cel,
    tileSize: 128,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: 128,
        pixels: BitmapTile.blank(size: 128).pixels
          ..fillRange(0, BitmapTile.bytesFor(128), value),
      ),
    },
  );

  /// The first byte of the picture the cel holds.
  int shown() =>
      store.bakedSurfaceOrNull(key)!.tiles[TileCoord(x: 0, y: 0)]!.pixels[0];

  MediaReference? pointsAt() => requireLayer(
    repository.requireProject(),
    cutId: cutId,
    layerId: rowId,
  ).mediaReference;

  void seed(String shows) {
    final project = createDefaultProject();
    final track = project.tracks.first;
    final cut = track.cuts.first;
    cutId = cut.id;
    final row = Layer(
      id: rowId,
      name: 'BG',
      kind: LayerKind.image,
      frames: [Frame(id: celId, duration: 1, strokes: const [])],
      timeline: {0: const TimelineExposure.drawing(celId, length: 4)},
      mediaReference: MediaReference(assetPath: shows),
    );
    repository = ProjectRepository(
      initialProject: project.copyWith(
        tracks: [
          track.copyWith(
            cuts: [
              cut.copyWith(layers: [...cut.layers, row]),
            ],
          ),
        ],
      ),
    );
    key = BrushFrameKey(
      projectId: project.id,
      trackId: track.id,
      cutId: cut.id,
      layerId: rowId,
      frameId: celId,
    );
    store = BrushFrameStore()..storeBakedSurface(key, solid(0x11));
  }

  SwapLayerReferenceCommand swapTo(
    String path, {
    Map<BrushFrameKey, BitmapSurface> pictures = const {},
  }) => SwapLayerReferenceCommand(
    repository: repository,
    cutId: cutId,
    layerId: rowId,
    reference: MediaReference(assetPath: path),
    store: store,
    pictures: pictures,
  );

  group('a still', () {
    setUp(() => seed('/work/bg_v1.png'));

    test('🎯the new picture goes into the SAME cel and the row points at the '
        'new file — one undo brings both back, a redo both again', () {
      final history = HistoryManager();
      addTearDown(history.dispose);

      history.execute(swapTo('/work/bg_v2.png', pictures: {key: solid(0x22)}));

      expect(shown(), 0x22);
      expect(pointsAt()?.assetPath, '/work/bg_v2.png');
      expect(
        requireLayer(
          repository.requireProject(),
          cutId: cutId,
          layerId: rowId,
        ).frames.single.id,
        celId,
        reason: 'the same cel — a new one would sweep a linked sibling\'s '
            'exposures of this one away',
      );

      history.undo();
      expect(shown(), 0x11);
      expect(pointsAt()?.assetPath, '/work/bg_v1.png');

      history.redo();
      expect(shown(), 0x22);
      expect(pointsAt()?.assetPath, '/work/bg_v2.png');
    });

    test('what it holds is billed, parks to the room and back, and the '
        'room is given back when the step leaves', () async {
      final history = HistoryManager();
      addTearDown(history.dispose);
      final swap = swapTo('/work/bg_v2.png', pictures: {key: solid(0x22)});
      history.execute(swap);
      final room = Directory(SessionScratch.volatileFolder());
      int filesInRoom() => room.existsSync() ? room.listSync().length : 0;
      final before = filesInRoom();

      expect(swap.estimatedRetainedBytes(undone: false), greaterThan(0));
      expect(await swap.parkPayload(), isTrue);
      expect(swap.estimatedRetainedBytes(undone: false), 0);
      expect(filesInRoom(), greaterThan(before));

      history.undo();
      expect(shown(), 0x11, reason: 'a parked swap still undoes');

      swap.dropPayload();
      expect(filesInRoom(), before);
    });

    test('the tiles it holds alone are those of the picture the cel is NOT '
        'showing', () {
      final history = HistoryManager();
      addTearDown(history.dispose);
      final swap = swapTo('/work/bg_v2.png', pictures: {key: solid(0x22)});
      history.execute(swap);
      final held = <int>[];

      swap.visitHeldTiles((_, tile) => held.add(tile.pixels[0]), undone: false);
      history.undo();
      swap.visitHeldTiles((_, tile) => held.add(tile.pixels[0]), undone: true);

      expect(held, [0x11, 0x22]);
    });

    test('its undo is read ahead the way it runs, the undo adopts what was '
        'read, and a read-ahead given back holds nothing', () async {
      final history = HistoryManager();
      addTearDown(history.dispose);
      final swap = swapTo('/work/bg_v2.png', pictures: {key: solid(0x22)});
      history.execute(swap);
      expect(await swap.parkPayload(), isTrue);

      var ahead = history.readAhead(undo: true, wants: (_) => true);
      expect(ahead[key]!.next.tiles[TileCoord(x: 0, y: 0)]!.pixels[0], 0x11);
      expect(swap.estimatedRetainedBytes(undone: false), greaterThan(0));
      swap.dropReadAhead();
      expect(swap.estimatedRetainedBytes(undone: false), 0);

      ahead = history.readAhead(undo: true, wants: (_) => true);
      history.undo();
      expect(identical(store.bakedSurfaceOrNull(key), ahead[key]!.next),
          isTrue);
    });
  });

  group('a movie', () {
    setUp(() => seed('/work/take1.mp4'));

    test('hands over no pictures — the reference is all that moves, and all '
        'that comes back', () {
      final history = HistoryManager();
      addTearDown(history.dispose);
      final swap = swapTo('/work/take2.mp4');

      history.execute(swap);
      expect(pointsAt()?.assetPath, '/work/take2.mp4');
      expect(shown(), 0x11, reason: 'no cel of it was touched');
      expect(swap.estimatedRetainedBytes(undone: false), 0);

      history.undo();
      expect(pointsAt()?.assetPath, '/work/take1.mp4');
      history.redo();
      expect(pointsAt()?.assetPath, '/work/take2.mp4');
    });

    test('keeps how far into the file the row starts', () {
      final history = HistoryManager();
      addTearDown(history.dispose);
      repository.updateLayer(
        layerId: rowId,
        update: (layer) => layer.copyWith(
          mediaReference: MediaReference(
            assetPath: '/work/take1.mp4',
            frameOffset: 12,
          ),
        ),
      );

      history.execute(
        SwapLayerReferenceCommand(
          repository: repository,
          cutId: cutId,
          layerId: rowId,
          reference: pointsAt()!.copyWith(assetPath: '/work/take2.mp4'),
          store: store,
        ),
      );
      history.undo();

      expect(
        pointsAt(),
        MediaReference(assetPath: '/work/take1.mp4', frameOffset: 12),
      );
    });
  });
}
