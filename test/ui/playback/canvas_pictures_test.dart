import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/layer_pose_matrix.dart' show LayerPlacement;
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/canvas_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/draw_on_current_frame.dart';

/// playback-plays-the-screen-material ② (10-09): where the canvas shows a
/// cut, a frame's picture is the canvas's own — each row an image of its
/// cel at the level the canvas draws at — and the one maker makes THOSE.
/// 유저 F-296-Q6: 「중복소재 안만들고 싶은것」.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const tileSize = 4;
  // 8×8 RGBA: a cel inked into both corners is stored whole.
  const imageBytes = 8 * 8 * 4;

  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 4,
    canvasSize: canvasSize,
    layers: const [],
  );

  BrushFrameKey keyOf(String cel) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: cut.id,
    layerId: const LayerId('l'),
    frameId: FrameId(cel),
  );

  CanvasLayerImageRequest row(String cel) =>
      CanvasLayerImageRequest(frameKey: keyOf(cel), opacity: 1);

  /// A store whose [cels] are inked in two opposite corners — every tile —
  /// so each image is the whole canvas.
  BrushFrameStore storeOf(List<String> cels) {
    final store = BrushFrameStore();
    for (final cel in cels) {
      for (final corner in [CanvasPoint(x: 1, y: 1), CanvasPoint(x: 6, y: 6)]) {
        inkCelIn(
          store,
          keyOf(cel),
          canvasSize: canvasSize,
          at: corner,
          size: 2,
          tipShape: BrushTipShape.square,
          tileSize: tileSize,
        );
      }
    }
    return store;
  }

  /// Frames 0..1 show cel a, frames 2..3 cel b — and, in [both], frame 3
  /// shows a and b.
  CanvasPictures picturesOf(
    LayerFrameImageCache images, {
    PlaybackQuality quality = PlaybackQuality.full,
    bool both = false,
  }) => CanvasPictures(
    layerImages: images,
    rowsOf: (cut, frame) => [
      if (frame < 2 || (both && frame == 3)) row('a'),
      if (frame >= 2) row('b'),
    ],
    qualityAt: (_, _) => quality,
  );

  DemandedPicture at(int frame) => (cut: cut, frameIndex: frame);

  bool held(LayerFrameImageCache images, String cel, PlaybackQuality q) =>
      images.validImageOrNull(
        keyOf(cel),
        q,
        canvasSize: canvasSize,
        sourceEffects: const <ResolvedLayerEffect>[],
      ) !=
      null;

  testWidgets('a frame is there when every row of it is — made at the level '
      'the canvas draws at, and nothing else is made', (tester) async {
    await tester.runAsync(() async {
      final images = LayerFrameImageCache(frameStore: storeOf(['a', 'b']));
      addTearDown(images.dispose);
      final pictures = picturesOf(images, quality: PlaybackQuality.half);

      expect(pictures.has(at(0)), isFalse);
      expect(await pictures.make(at(0), shouldAbort: () => false), isTrue);

      expect(pictures.has(at(0)), isTrue);
      expect(pictures.has(at(1)), isTrue, reason: 'frame 1 shows the same cel');
      expect(pictures.has(at(2)), isFalse, reason: 'cel b is not made');
      expect(held(images, 'a', PlaybackQuality.half), isTrue);
      expect(
        held(images, 'a', PlaybackQuality.full),
        isFalse,
        reason: 'the canvas draws at half: a full image is a second picture',
      );
    });
  });

  testWidgets('each frame is made at its own level — a camera zooming through '
      'a cut draws its frames at more than one', (tester) async {
    await tester.runAsync(() async {
      final images = LayerFrameImageCache(frameStore: storeOf(['a', 'b']));
      addTearDown(images.dispose);
      // Frames 0..1 (cel a) drawn at full, 2..3 (cel b) at half.
      final pictures = CanvasPictures(
        layerImages: images,
        rowsOf: (cut, frame) => [if (frame < 2) row('a') else row('b')],
        qualityAt: (_, frame) =>
            frame < 2 ? PlaybackQuality.full : PlaybackQuality.half,
      );

      await pictures.make(at(0), shouldAbort: () => false);
      await pictures.make(at(2), shouldAbort: () => false);

      expect(held(images, 'a', PlaybackQuality.full), isTrue);
      expect(held(images, 'b', PlaybackQuality.half), isTrue);
      expect(
        [
          held(images, 'a', PlaybackQuality.half),
          held(images, 'b', PlaybackQuality.full),
        ],
        [false, false],
        reason: 'each cel at the level of the frames that show it, alone',
      );
      expect([pictures.has(at(1)), pictures.has(at(3))], [true, true]);
    });
  });

  testWidgets('a row with nothing in it is there by definition — the bar has '
      'always counted a frame that composes to nothing as made', (
    tester,
  ) async {
    final images = LayerFrameImageCache(frameStore: storeOf(['a']));
    addTearDown(images.dispose);
    final pictures = CanvasPictures(
      layerImages: images,
      rowsOf: (cut, frame) => [row('nothing-drawn')],
      qualityAt: (_, _) => PlaybackQuality.full,
    );
    expect(pictures.has(at(0)), isTrue);
    expect(pictures.bytesToMake(at(0)), 0);
  });

  testWidgets('what making a frame would add counts the rows not there — the '
      'canvas at the level each — and a walk weighs a held cel once', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final images = LayerFrameImageCache(frameStore: storeOf(['a', 'b']));
      addTearDown(images.dispose);
      final pictures = picturesOf(images, both: true);

      expect(pictures.bytesToMake(at(3)), 2 * imageBytes);
      await pictures.make(at(0), shouldAbort: () => false);
      expect(pictures.bytesToMake(at(3)), imageBytes, reason: 'a is made');

      await pictures.make(at(2), shouldAbort: () => false);
      final seen = <Object>{};
      expect(pictures.weighNew(at(0), seen), imageBytes);
      expect(pictures.weighNew(at(1), seen), 0, reason: 'the same cel');
      expect(pictures.weighNew(at(3), seen), imageBytes, reason: 'b is new');
    });
  });

  testWidgets('🚨one row\'s failure is one row\'s: its siblings are made past '
      'it, it is given up on, and the throw is handed on once', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final store = storeOf(['a', 'b']);
      final images = _ThrowsFor(keyOf('a'), frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(images, both: true);

      await expectLater(
        pictures.make(at(3), shouldAbort: () => false),
        throwsA(isA<StateError>()),
      );
      expect(held(images, 'b', PlaybackQuality.full), isTrue);
      expect(pictures.gaveUpOn(row('a')), isTrue);
      expect(pictures.has(at(3)), isFalse);
      expect(
        pictures.failed(at(3)),
        isTrue,
        reason: 'nothing of the frame is still to come',
      );

      // ⛔Not made again at the same content.
      await pictures.make(at(3), shouldAbort: () => false);
      expect(images.thrown, 1);
    });
  });

  testWidgets('a frame whose making stopped before its rows — the movie its '
      'cels show could not be read — gives up the rows still to come', (
    tester,
  ) async {
    final images = LayerFrameImageCache(frameStore: storeOf(['a', 'b']));
    addTearDown(images.dispose);
    final pictures = picturesOf(images, both: true);

    pictures.noteFailure(at(3));
    expect(pictures.gaveUpOn(row('a')), isTrue);
    expect(pictures.gaveUpOn(row('b')), isTrue);
    expect(pictures.failed(at(0)), isTrue, reason: 'frame 0 is a alone');
  });

  testWidgets('🚨a frame\'s failure gives up only its rows still to come — a '
      'row that was there is not given up on, so it is made again once it is '
      'let go', (tester) async {
    await tester.runAsync(() async {
      final images = LayerFrameImageCache(frameStore: storeOf(['a', 'b']));
      addTearDown(images.dispose);
      final pictures = picturesOf(images, both: true);
      await pictures.make(at(0), shouldAbort: () => false);
      expect(
        held(images, 'a', PlaybackQuality.full),
        isTrue,
        reason: '⛔premise',
      );

      pictures.noteFailure(at(3));

      expect(pictures.gaveUpOn(row('a')), isFalse, reason: 'a was there');
      expect(pictures.gaveUpOn(row('b')), isTrue);
    });
  });

  testWidgets('🚨an image of the ink alone is there only for a row its ink '
      'suffices — a posed row of the same cel wants the whole, and makes it',
      (tester) async {
    await tester.runAsync(() async {
      // Inked in one corner only: its ink is less than the canvas.
      final store = BrushFrameStore();
      inkCelIn(
        store,
        keyOf('a'),
        canvasSize: canvasSize,
        at: CanvasPoint(x: 1, y: 1),
        size: 2,
        tipShape: BrushTipShape.square,
        tileSize: tileSize,
      );
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      // Frame 0 shows the cel as it lies; frame 1 shows it moved.
      final pictures = CanvasPictures(
        layerImages: images,
        rowsOf: (cut, frame) => [
          if (frame == 0) row('a'),
          if (frame == 1)
            CanvasLayerImageRequest(
              frameKey: keyOf('a'),
              opacity: 1,
              placement: const LayerPlacement(1, 0, 0, 1, 1, 0),
            ),
        ],
        qualityAt: (_, _) => PlaybackQuality.full,
      );
      await pictures.make(at(0), shouldAbort: () => false);
      expect(pictures.has(at(0)), isTrue, reason: '⛔premise: the ink is held');

      expect(
        pictures.has(at(1)),
        isFalse,
        reason: 'the ink alone is not what a posed row draws',
      );
      await pictures.make(at(1), shouldAbort: () => false);
      expect(pictures.has(at(1)), isTrue);
    });
  });

  testWidgets('an interrupted making lands nothing and says so', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final images = LayerFrameImageCache(frameStore: storeOf(['a']));
      addTearDown(images.dispose);
      final pictures = picturesOf(images);

      expect(await pictures.make(at(0), shouldAbort: () => true), isFalse);
      expect(pictures.has(at(0)), isFalse);
      expect(pictures.gaveUpOn(row('a')), isFalse, reason: 'not a failure');
    });
  });

  test('the budget\'s order: each image is wanted at the soonest step that '
      'shows it, and an image no step shows is not wanted at all', () {
    final images = LayerFrameImageCache(frameStore: storeOf(['a', 'b']));
    addTearDown(images.dispose);
    final pictures = picturesOf(images, quality: PlaybackQuality.half);
    var playhead = 2;
    final demand = PlayingDemand(
      totalFrames: 4,
      loops: () => true,
      playhead: () => playhead,
      picturesOf: (frame) => [(cut: cut, frameIndex: frame)],
      playlistFrameOf: (cutId, frame) => frame,
    );

    final wanted = pictures.wantedAt(demand);
    expect(wanted((keyOf('b'), PlaybackQuality.half)), 0);
    expect(wanted((keyOf('a'), PlaybackQuality.half)), 2, reason: 'lapped');
    expect(
      wanted((keyOf('a'), PlaybackQuality.full)),
      isNull,
      reason: 'the canvas draws at half',
    );
    expect(wanted((keyOf('nobody'), PlaybackQuality.half)), isNull);
    expect(pictures.wantedAt(null)((keyOf('a'), PlaybackQuality.half)), isNull);

    playhead = 0;
    final again = pictures.wantedAt(demand);
    expect(again((keyOf('a'), PlaybackQuality.half)), 0);
    expect(again((keyOf('b'), PlaybackQuality.half)), 2);
  });
}

/// A layer image cache that cannot read [key]'s cel.
class _ThrowsFor extends LayerFrameImageCache {
  _ThrowsFor(this.key, {required super.frameStore});

  final BrushFrameKey key;
  int thrown = 0;

  @override
  Future<LayerFrameImage?> prepare({
    required BrushFrameKey key,
    required CanvasSize canvasSize,
    required PlaybackQuality quality,
    required List<ResolvedLayerEffect> sourceEffects,
    bool Function()? shouldAbort,
    bool inkSuffices = false,
  }) {
    if (key == this.key) {
      thrown += 1;
      throw StateError('the cel ${key.frameId.value} cannot be read');
    }
    return super.prepare(
      key: key,
      canvasSize: canvasSize,
      quality: quality,
      sourceEffects: sourceEffects,
      shouldAbort: shouldAbort,
      inkSuffices: inkSuffices,
    );
  }
}
