import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/rgba_image_bytes.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';

import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/poll_until.dart';

/// Card playback-picture-weight-estimates (F-365 ③): the warmer asks the
/// playback line for room before it makes a picture, and it weighed a row as
/// the canvas — 🔬a cut's head asked 1.5–2× what it weighed, and one inked
/// onto the pasteboard less (10-15, PC, a copy of the user's project). A
/// picture is weighed by the plan its image is made by, once what its
/// making reads first is read. ↩️A row's image was weighed so too, a cel's
/// shape by a row's kind at every level, until no row image was made
/// (one-picture-per-frame ②-5b-1).
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  // The canvas as its picture lies ([pictureExtentOf]).
  final canvasPicture = pictureExtentOf(canvasSize.canvasRect);
  final canvasBytes = estimatedImageBytes(
    canvasPicture.width.round(),
    canvasPicture.height.round(),
  );

  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 1,
    canvasSize: canvasSize,
    layers: const [],
  );
  final key = BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: cut.id,
    layerId: const LayerId('l'),
    frameId: const FrameId('a'),
  );
  final picture = (cut: cut, frameIndex: 0, paintPaper: true, ghosts: false);

  BitmapTile red() => BitmapTile(
    size: 4,
    pixels: Uint8List.fromList([
      for (var i = 0; i < 4 * 4; i += 1) ...[255, 0, 0, 255],
    ]),
  );

  BitmapSurface inkedAt(List<TileCoord> tiles) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: 4,
    tiles: {for (final at in tiles) at: red()},
  );

  BitmapSurface inACorner() => inkedAt([TileCoord(x: 0, y: 0)]);
  BitmapSurface onThePasteboard() =>
      inkedAt([TileCoord(x: -1, y: -1), TileCoord(x: 2, y: 2)]);

  CanvasLayerImageRequest asItLies() =>
      CanvasLayerImageRequest(frameKey: key, opacity: 1);

  FramePictures picturesOf(
    LayerFrameImageCache images, {
    List<CompositeNode<CanvasStackRow>> Function(int frame)? rowsAt,
  }) {
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    return FramePictures(
      store: store,
      layerImages: images,
      stackOf: (picture) =>
          rowsAt?.call(picture.frameIndex) ?? [CompositeLeaf(asItLies())],
      pageOf: (picture) => (
        canvasSize: picture.cut.canvasSize,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: picture.paintPaper,
        paperBackground: ProjectBackground.defaultBackground,
      ),
    );
  }

  testWidgets('🚨a cel still in the file is weighed as the canvas, reading '
      'nothing, until what its making reads first is read — then as the '
      'picture it is made as', (tester) async {
    await tester.runAsync(() async {
      final store = BrushFrameStore();
      keepInAFile(store, {key: onThePasteboard()});
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(images);

      expect(pictures.bytesToMake(picture), canvasBytes);
      expect(
        store.hotBakedSurfaceOrNull(key),
        isNull,
        reason: 'weighing read nothing',
      );

      await pictures.readIn(picture);
      final weight = pictures.bytesToMake(picture);
      expect(await pictures.make(picture, shouldAbort: () => false), isTrue);

      expect(weight, pictures.weighNew(picture, {}));
      expect(
        weight,
        greaterThan(canvasBytes),
        reason: '⛔premise: ink past the canvas',
      );
    });
  });

  testWidgets('🚨a cel that will not read is weighed as the canvas: reading it '
      'in throws nothing, and reads nothing on this thread — its making says '
      'why', (tester) async {
    await tester.runAsync(() async {
      final store = BrushFrameStore();
      final kept = keepInAFile(store, {key: onThePasteboard()});
      File(kept[key]!.filePath).deleteSync();
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(images);

      await pictures.readIn(picture);

      expect(pictures.bytesToMake(picture), canvasBytes);
    });
  });

  testWidgets('🚨reading a picture in reads the cels not in hand, and no cel '
      'another frame has read already', (tester) async {
    await tester.runAsync(() async {
      final other = BrushFrameKey(
        projectId: key.projectId,
        trackId: key.trackId,
        cutId: key.cutId,
        layerId: const LayerId('m'),
        frameId: const FrameId('b'),
      );
      final store = BrushFrameStore();
      keepInAFile(store, {key: inACorner(), other: inACorner()});
      final images = _ReadsRecorded(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(
        images,
        rowsAt: (frame) => [
          CompositeLeaf(asItLies()),
          if (frame == 1)
            CompositeLeaf(CanvasLayerImageRequest(frameKey: other, opacity: 1)),
        ],
      );
      await pictures.readIn(picture);
      expect(await pictures.make(picture, shouldAbort: () => false), isTrue);
      images.read.clear();

      await pictures.readIn((
        cut: cut,
        frameIndex: 1,
        paintPaper: true,
        ghosts: false,
      ));

      expect(images.read, [other]);
    });
  });

  testWidgets('🚨a walk reading its picture in asks the room for nothing once '
      'it has been replaced', (tester) async {
    await tester.runAsync(() async {
      final store = BrushFrameStore();
      keepInAFile(store, {key: inACorner()});
      final images = _ReadInHeld(frameStore: store);
      addTearDown(images.dispose);
      final room = _Asked();
      final scheduler = PlaybackPrerenderScheduler(
        pictures: picturesOf(images),
        resolveCut: (_) => cut,
        room: room,
        idleDelay: Duration.zero,
      );
      addTearDown(scheduler.dispose);

      scheduler.follow(
        PlayingDemand(
          totalFrames: 1,
          loops: () => false,
          playhead: () => 0,
          picturesOf: (frame) => [(
            cut: cut,
            frameIndex: frame,
            paintPaper: true,
            ghosts: false,
          )],
          playlistFrameOf: (_, frame) => frame,
        ),
      );
      await images.asked.future;
      scheduler.cancel();
      images.held.complete();
      await images.reading;
      await pumpEventQueue();

      expect(room.asked, isEmpty);
    });
  });

  testWidgets('🚨the walk asks the room for what its picture will be made as '
      '— its cel read first, not weighed as the canvas', (tester) async {
    await tester.runAsync(() async {
      final store = BrushFrameStore();
      keepInAFile(store, {key: onThePasteboard()});
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(images);
      final room = _Asked();
      final scheduler = PlaybackPrerenderScheduler(
        pictures: pictures,
        resolveCut: (_) => cut,
        room: room,
        idleDelay: Duration.zero,
      );
      addTearDown(scheduler.dispose);

      scheduler.follow(
        PlayingDemand(
          totalFrames: 1,
          loops: () => false,
          playhead: () => 0,
          picturesOf: (frame) => [(
            cut: cut,
            frameIndex: frame,
            paintPaper: true,
            ghosts: false,
          )],
          playlistFrameOf: (_, frame) => frame,
        ),
      );
      await patiently(scheduler.idle);

      expect(pictures.has(picture), isTrue, reason: '⛔premise: it was made');
      final weight = pictures.weighNew(picture, {});
      expect(weight, greaterThan(canvasBytes), reason: '⛔premise');
      expect(room.asked.first, weight);
    });
  });
}

/// An image cache whose reading in waits for [held], saying when it is
/// asked.
class _ReadInHeld extends LayerFrameImageCache {
  _ReadInHeld({required super.frameStore});

  final Completer<void> asked = Completer();
  final Completer<void> held = Completer();
  late Future<void> reading;

  @override
  Future<void> readIn(BrushFrameKey key, {required CanvasSize canvasSize}) {
    if (!asked.isCompleted) {
      asked.complete();
    }
    return reading = held.future.then(
      (_) => super.readIn(key, canvasSize: canvasSize),
    );
  }
}

/// An image cache saying which cels it was asked to read in.
class _ReadsRecorded extends LayerFrameImageCache {
  _ReadsRecorded({required super.frameStore});

  final List<BrushFrameKey> read = [];

  @override
  Future<void> readIn(BrushFrameKey key, {required CanvasSize canvasSize}) {
    read.add(key);
    return super.readIn(key, canvasSize: canvasSize);
  }
}

/// A room with space for everything, saying what it was asked for.
class _Asked implements PictureRoom {
  final List<int> asked = [];

  @override
  int get bytes => 1 << 30;

  @override
  bool makeRoomFor({required int bytes, required int step}) {
    asked.add(bytes);
    return true;
  }
}
