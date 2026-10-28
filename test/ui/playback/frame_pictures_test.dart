import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_pictures.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/quiet_turns.dart';

import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/poll_until.dart';

/// one-picture-per-frame ②-2 (D7-2-Q3=a, 유저 10-24 「쓸데없는 소재를 만들고
/// 싶지 않은 것」): what the warmer makes ahead of a screen is the frame the
/// screen shows — one picture, kept under the key of the tree it stacks —
/// and nothing else.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const tileSize = 4;

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

  CompositeNode<CanvasStackRow> row(String cel) =>
      CompositeLeaf(CanvasLayerImageRequest(frameKey: keyOf(cel), opacity: 1));

  /// A store whose [cels] are inked in the top left corner — and, with
  /// [bothCorners], the bottom right too, every tile. [store] holds what it
  /// held besides.
  BrushFrameStore storeOf(
    List<String> cels, {
    BrushFrameStore? store,
    bool bothCorners = true,
  }) {
    store ??= BrushFrameStore();
    for (final cel in cels) {
      for (final corner in [
        CanvasPoint(x: 1, y: 1),
        if (bothCorners) CanvasPoint(x: 6, y: 6),
      ]) {
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

  /// A store keeping [cel] as an opened project keeps one — a stretch of a
  /// file — and that file since gone: its bytes cannot be read.
  BrushFrameStore storeWithGone(String cel) {
    final store = BrushFrameStore();
    keepInAFileThatIsGone(store, {
      keyOf(cel): storeOf([cel]).bakedSurfaceOrNull(keyOf(cel))!,
    });
    return store;
  }

  /// Frames 0..1 show cel a, frames 2..3 cel b — and, in [both], frame 3
  /// shows a under b. [blank] shows a cel with nothing in it at every frame.
  FramePictures picturesOf(
    LayerFrameImageCache images, {
    bool both = false,
    String? blank,
    CanvasSize? drawnAt,
    QuietTurns? quietTurns,
    void Function()? onWalk,
  }) {
    final store = FramePictureStore<FramePictureKey>();
    addTearDown(store.dispose);
    return FramePictures(
      store: store,
      layerImages: images,
      stackOf: (picture) {
        onWalk?.call();
        return [
          if (blank != null) row(blank),
          if (picture.frameIndex < 2 || (both && picture.frameIndex == 3))
            row('a'),
          if (picture.frameIndex >= 2) row('b'),
        ];
      },
      pageOf: (picture) => (
        canvasSize: drawnAt ?? picture.cut.canvasSize,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: picture.paintPaper,
        paperBackground: ProjectBackground.defaultBackground,
      ),
      quietTurns: quietTurns,
    );
  }

  DemandedPicture at(int frame, {bool paintPaper = true}) =>
      (cut: cut, frameIndex: frame, paintPaper: paintPaper, ghosts: FrameGhosts.none);

  testWidgets('a frame is there once its picture is made — one picture for '
      'every frame that stacks the same, and nothing else is made', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final images = LayerFrameImageCache(frameStore: storeOf(['a', 'b']));
      addTearDown(images.dispose);
      final pictures = picturesOf(images);

      expect(pictures.has(at(0)), isFalse);
      expect(await pictures.make(at(0), shouldAbort: () => false), isTrue);

      expect(pictures.has(at(0)), isTrue);
      expect(pictures.has(at(1)), isTrue, reason: 'frame 1 stacks the same');
      expect(pictures.keyOf(at(1)), pictures.keyOf(at(0)));
      expect(pictures.has(at(2)), isFalse, reason: 'cel b is another frame');
      expect(
        pictures.store.peek(pictures.keyOf(at(0))),
        isNotNull,
        reason: 'the frame is its picture',
      );
      expect(
        pictures.has(at(0, paintPaper: false)),
        isFalse,
        reason: 'a screen that does not paint the paper shows another '
            'picture',
      );
    });
  });

  testWidgets('a screen stacking the frame asks the warmer\'s own key', (
    tester,
  ) async {
    final images = LayerFrameImageCache(frameStore: storeOf(['a', 'b']));
    addTearDown(images.dispose);
    final pictures = picturesOf(images, both: true);
    for (final frame in [0, 2, 3]) {
      expect(
        pictures.keyOfStack(pictures.stackOf(at(frame)), at(frame)),
        pictures.keyOf(at(frame)),
      );
    }
    expect(pictures.keyOf(at(3)), isNot(pictures.keyOf(at(2))));
  });

  testWidgets('a cel with nothing in it is no part of the picture — and a '
      'frame of nothing is there by definition, on its paper or not: its '
      'page is drawn as it stands', (tester) async {
    final images = LayerFrameImageCache(frameStore: storeOf(['a']));
    addTearDown(images.dispose);
    final pictures = picturesOf(images, blank: 'nothing-drawn');
    final plain = FramePictures(
      store: pictures.store,
      layerImages: images,
      stackOf: (picture) => [row('a')],
      pageOf: pictures.pageOf,
    );
    expect(pictures.keyOf(at(0)), plain.keyOf(at(0)));

    final nothing = FramePictures(
      store: pictures.store,
      layerImages: images,
      stackOf: (picture) => [row('nothing-drawn'), row('nothing-either')],
      pageOf: pictures.pageOf,
    );
    for (final paintPaper in [false, true]) {
      final frame = at(0, paintPaper: paintPaper);
      expect(
        nothing.drawsOnlyItsPage(nothing.keyOf(frame)),
        isTrue,
        reason: 'paper $paintPaper',
      );
      expect(nothing.has(frame), isTrue, reason: 'paper $paintPaper');
      expect(nothing.partsToMake(frame), isEmpty, reason: 'paper $paintPaper');
    }
    expect(
      pictures.drawsOnlyItsPage(pictures.keyOf(at(0))),
      isFalse,
      reason: '⛔premise: a frame with a row in it is a picture to make',
    );
  });

  /// A cel donated with no drawing state — a layer's cels forked by an
  /// unlink, an independent clip's copies — had its pixels and no picture
  /// while the drawing state was asked beside the content (2026-10-10).
  /// ↩️Pinned on the row images, until a frame's one picture was all a
  /// screen drew (one-picture-per-frame ②-5b-1).
  testWidgets('🚨a cel donated without a drawing state is in the picture — '
      'the content alone says whether a cel has one', (tester) async {
    await tester.runAsync(() async {
      final store = BrushFrameStore()
        ..storeBakedSurface(
          keyOf('a'),
          storeOf(['a']).bakedSurfaceOrNull(keyOf('a'))!,
        );
      expect(
        store.frameOrNull(keyOf('a')),
        isNull,
        reason: '⛔premise: the donation alone, no drawing state',
      );
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(images);
      final frame = at(0, paintPaper: false);

      expect(await pictures.make(frame, shouldAbort: () => false), isTrue);

      final image = pictures.store.peek(pictures.keyOf(frame))!.image;
      final pixels = (await image.toByteData())!;
      expect(
        pixels.getUint8((1 * image.width + 1) * 4 + 3),
        0xFF,
        reason: 'its ink',
      );
    });
  });

  testWidgets('🚨one cel\'s failure is one cel\'s: the frame is laid without '
      'it, its throw handed on, and it is not read again', (tester) async {
    await tester.runAsync(() async {
      // a's file gone; b drawn.
      final store = storeOf(['b'], store: storeWithGone('a'));
      final images = _CountsReadings(keyOf('a'), frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(images, both: true);

      await expectLater(
        pictures.make(at(3), shouldAbort: () => false),
        throwsA(anything),
      );
      expect(images.unreadable.has(keyOf('a')), isTrue);
      expect(pictures.has(at(3)), isTrue, reason: 'b is in it');
      expect(
        pictures.standingOf(at(3)),
        (state: PictureState.there, cannotRead: true),
        reason: 'it is there, and the bar reads red',
      );
      expect(
        pictures.keyOf(at(3)),
        pictures.keyOf(at(2)),
        reason: 'the picture is of what it draws: b alone',
      );

      pictures.noteFailure(at(3));
      expect(
        pictures.standingOf(at(3)).state,
        PictureState.there,
        reason: '⛔the walk notes the throw it was handed: a frame that is '
            'there is no failure',
      );
      pictures.partsToMake(at(3));
      pictures.bytesToMake(at(3));
      await pictures.readIn(at(3));
      expect(images.read, 1, reason: '⛔not read again at the same content');
    });
  });

  testWidgets('🚨a cel recorded at another canvas size is drawn without, and '
      'looked at afresh once the store\'s content moves — a resize heals it '
      'with no revision of its own', (tester) async {
    await tester.runAsync(() async {
      final store = storeOf(['a']);
      final images = LayerFrameImageCache(frameStore: store);
      addTearDown(images.dispose);
      final pictures = picturesOf(
        images,
        drawnAt: const CanvasSize(width: 16, height: 16),
      );
      final key = pictures.keyOf(at(0));

      expect(await pictures.make(at(0), shouldAbort: () => false), isTrue);
      expect(pictures.has(at(0)), isTrue, reason: 'the paper alone');
      expect(pictures.keyOf(at(0)), isNot(key), reason: 'a is no part of it');
      expect(images.unreadable.has(keyOf('a')), isFalse, reason: 'a miss');
      final generation = store.celContentRevision.value;

      storeOf(['c'], store: store);
      expect(
        store.celContentRevision.value,
        greaterThan(generation),
        reason: '⛔CONTROL: a cel crossed empty → drawn, which moves the '
            'store\'s content as a resize\'s heal does',
      );

      expect(pictures.keyOf(at(0)), key, reason: 'a is asked for again');
      expect(pictures.has(at(0)), isFalse);
      expect(pictures.partsToMake(at(0)), {key});
    });
  });

  testWidgets('🚨but a cel that could not be read stays given up on — '
      '「영영실패」: a drawing made elsewhere does not read it again', (
    tester,
  ) async {
    final store = storeOf(['a']);
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    final pictures = picturesOf(images);
    final withA = pictures.keyOf(at(0));
    // How the cache keeps a cel whose reading threw.
    images.unreadable.note(keyOf('a'));
    final withoutA = pictures.keyOf(at(0));
    expect(withoutA, isNot(withA), reason: '⛔CONTROL');

    storeOf(['c'], store: store);

    expect(pictures.keyOf(at(0)), withoutA);
  });

  testWidgets('a frame whose making threw past its cels is not waited for, '
      'nor made again at that content — and a new content is a new frame', (
    tester,
  ) async {
    final store = storeOf(['a', 'b']);
    final images = LayerFrameImageCache(frameStore: store);
    addTearDown(images.dispose);
    final pictures = picturesOf(images);

    pictures.noteFailure(at(0));
    expect(pictures.standingOf(at(0)).state, PictureState.gaveUp);
    expect(
      pictures.standingOf(at(1)).state,
      PictureState.gaveUp,
      reason: 'the same frame',
    );
    expect(pictures.partsToMake(at(0)), isEmpty);
    expect(pictures.gaveUpAt(pictures.keyOf(at(0))), isTrue);
    expect(
      pictures.gaveUpAt(pictures.keyOf(at(2))),
      isFalse,
      reason: 'still to come is not given up on',
    );
    expect(pictures.standingOf(at(2)).state, PictureState.toCome);

    // Ink where a has none: its content moves.
    inkCelIn(
      store,
      keyOf('a'),
      canvasSize: canvasSize,
      at: CanvasPoint(x: 5, y: 1),
      size: 2,
      tipShape: BrushTipShape.square,
      tileSize: tileSize,
    );
    expect(
      pictures.standingOf(at(0)).state,
      PictureState.toCome,
      reason: 'a was drawn on',
    );
    expect(pictures.partsToMake(at(0)), {pictures.keyOf(at(0))});
  });

  // 🪶Card frame-panels-build-in-one-frame (2026-10-28): the storyboard's
  // bar asks this of every span of the film each time the panel is shown
  // again — asked as there, then failed, then red, it walked a frame's
  // stack two or three times.
  testWidgets('where a frame stands, and its red, are read off ONE walk of '
      'its stack — there, given up on or still to come', (tester) async {
    await tester.runAsync(() async {
      final images = LayerFrameImageCache(frameStore: storeOf(['a', 'b']));
      addTearDown(images.dispose);
      var walks = 0;
      final pictures = picturesOf(images, onWalk: () => walks += 1);
      expect(await pictures.make(at(2), shouldAbort: () => false), isTrue);
      pictures.noteFailure(at(0));

      for (final (picture, state) in [
        (at(2), PictureState.there),
        (at(0), PictureState.gaveUp),
        (at(2, paintPaper: false), PictureState.toCome),
      ]) {
        walks = 0;
        expect(
          pictures.standingOf(picture),
          (state: state, cannotRead: false),
        );
        expect(walks, 1, reason: '$state');
      }
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
      expect(
        pictures.standingOf(at(0)).state,
        PictureState.toCome,
        reason: 'not a failure',
      );
    });
  });

  test('the budget\'s order: each picture is wanted at the soonest step that '
      'shows it, and a picture no step shows is not wanted at all', () {
    final images = LayerFrameImageCache(frameStore: storeOf(['a', 'b']));
    addTearDown(images.dispose);
    final pictures = picturesOf(images);
    var playhead = 2;
    final demand = PlayingDemand(
      totalFrames: 4,
      loops: () => true,
      playhead: () => playhead,
      picturesOf: (frame) => [at(frame)],
      playlistFrameOf: (cutId, frame) => frame,
    );
    final a = pictures.keyOf(at(0));
    final b = pictures.keyOf(at(2));

    final wanted = pictures.wantedAt(demand);
    expect(wanted(b), 0);
    expect(wanted(a), 2, reason: 'lapped');
    expect(
      wanted(pictures.keyOf(at(0, paintPaper: false))),
      isNull,
      reason: 'no step shows a without its paper',
    );
    expect(pictures.wantedAt(null)(a), isNull);

    playhead = 0;
    final again = pictures.wantedAt(demand);
    expect(again(a), 0);
    expect(again(b), 2);
  });

  group('🚨a frame takes its turn in the quiet between a run\'s held frames '
      'before it is rastered', () {
    ({int fromMicros, int untilMicros})? quiet;
    late Completer<void> moved;

    /// Frame 0 shows cel a, taking its turns in [quiet].
    FramePictures inTheQuiet(LayerFrameImageCache images) {
      quiet = (fromMicros: 0, untilMicros: 0);
      moved = Completer<void>();
      return picturesOf(
        images,
        quietTurns: QuietTurns(
          clock: QuietClock(
            quiet: () => quiet,
            now: () => 0,
            wait: (_) async {},
            moved: () => moved.future,
          ),
        ),
      );
    }

    testWidgets('a frame the quiet has no room for is made once the quiet '
        'moves', (tester) async {
      await tester.runAsync(() async {
        final images = LayerFrameImageCache(frameStore: storeOf(['a']));
        addTearDown(images.dispose);
        final pictures = inTheQuiet(images);

        var made = false;
        final making = pictures
            .make(at(0), shouldAbort: () => false)
            .then((landed) => made = landed);
        await pumpEventQueue();
        expect(made, isFalse, reason: 'its turn has not come');
        expect(pictures.has(at(0)), isFalse);

        // The run stood: nothing is held, and there is no quiet to keep.
        quiet = null;
        moved.complete();
        await making;

        expect(made, isTrue);
        expect(pictures.has(at(0)), isTrue);
      });
    });

    testWidgets('🚨a frame the run shows next is made at once, whatever the '
        'quiet', (tester) async {
      await tester.runAsync(() async {
        final images = LayerFrameImageCache(frameStore: storeOf(['a']));
        addTearDown(images.dispose);
        final pictures = inTheQuiet(images);

        expect(
          await pictures.make(at(0), shouldAbort: () => false, due: () => true),
          isTrue,
        );
        expect(pictures.has(at(0)), isTrue);
      });
    });

    testWidgets('a frame stood down while it waits for its turn lands '
        'nothing', (tester) async {
      await tester.runAsync(() async {
        final images = LayerFrameImageCache(frameStore: storeOf(['a']));
        addTearDown(images.dispose);
        final pictures = inTheQuiet(images);
        var stoodDown = false;
        final making = pictures.make(at(0), shouldAbort: () => stoodDown);
        await pumpEventQueue();

        stoodDown = true;
        moved.complete();

        expect(await making, isFalse);
        expect(pictures.has(at(0)), isFalse);
        expect(
          pictures.standingOf(at(0)).state,
          PictureState.toCome,
          reason: 'not a failure',
        );
      });
    });

    testWidgets('🚨a frame that lands says how long a frame takes: the next '
        'one that would land past the quiet waits for the quiet after it', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final images = LayerFrameImageCache(frameStore: storeOf(['a', 'b']));
        addTearDown(images.dispose);
        // Each look at the clock is a millisecond on, and each quiet ends
        // 2.5ms after it is asked for: room for a frame that takes nothing,
        // none for one that took a look's millisecond.
        var now = 0;
        final moved = Completer<void>();
        final pictures = picturesOf(
          images,
          quietTurns: QuietTurns(
            clock: QuietClock(
              quiet: () => (fromMicros: 0, untilMicros: now + 2500),
              now: () => now += 1000,
              wait: (_) async {},
              moved: () => moved.future,
            ),
          ),
        );
        expect(await pictures.make(at(0), shouldAbort: () => false), isTrue);

        var made = false;
        final making = pictures
            .make(at(2), shouldAbort: () => false)
            .then((landed) => made = landed);
        await pumpEventQueue();
        expect(made, isFalse, reason: 'the frame before it took longer');

        // Each quiet too short for it asks a frame for less.
        moved.complete();
        expect(await making, isTrue);
        expect(pictures.has(at(2)), isTrue);
      });
    });

    testWidgets('🚨while frames are held, a frame is made once the GPU is '
        'done with it — what walks the frames goes on from there', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final images = LayerFrameImageCache(frameStore: storeOf(['a']));
        addTearDown(images.dispose);
        final gpu = Completer<void>();
        final pictures = picturesOf(
          images,
          quietTurns: QuietTurns(
            clock: QuietClock(
              quiet: () => (fromMicros: 0, untilMicros: 1000000),
              now: () => 0,
              wait: (_) async {},
              moved: () => Completer<void>().future,
              held: () => true,
              gpuDone: () => gpu.future,
            ),
          ),
        );

        var made = false;
        final making = pictures
            .make(at(0), shouldAbort: () => false)
            .then((landed) => made = landed);
        await pollUntil(() => pictures.has(at(0)));
        await pumpEventQueue();
        expect(pictures.has(at(0)), isTrue);
        expect(made, isFalse, reason: 'laid, but the GPU is not done with it');

        gpu.complete();
        expect(await making, isTrue);
      });
    });

    testWidgets('🚨a frame found to draw its page alone takes no turn: it is '
        'there by definition, with no quiet at all', (tester) async {
      await tester.runAsync(() async {
        final images = LayerFrameImageCache(frameStore: storeOf(['a']));
        addTearDown(images.dispose);
        // a is recorded at another canvas size: the store says it is drawn,
        // and its drawing finds nothing of it — the frame is its page.
        var turnsAsked = 0;
        final pictures = picturesOf(
          images,
          drawnAt: const CanvasSize(width: 16, height: 16),
          quietTurns: QuietTurns(
            clock: QuietClock(
              quiet: () {
                turnsAsked += 1;
                return (fromMicros: 0, untilMicros: 0);
              },
              now: () => 0,
              wait: (_) async {},
              moved: () => Completer<void>().future,
            ),
          ),
        );
        expect(
          pictures.has(at(0)),
          isFalse,
          reason: '⛔CONTROL: a is drawn by the store\'s word until looked at',
        );

        var made = false;
        unawaited(
          pictures
              .make(at(0), shouldAbort: () => false)
              .then((landed) => made = landed),
        );
        await pumpEventQueue();

        expect(made, isTrue, reason: 'no quiet was waited for');
        expect(turnsAsked, 0);
        expect(pictures.has(at(0)), isTrue, reason: 'its page alone');
      });
    });
  });
}

/// A layer image cache that counts the readings of [key]'s stored pixels.
///
/// ⚠️IT READS THEM AS ANY CACHE DOES: what a cel that could not be read is
/// remembered by is the cache's record ([LayerFrameImageCache.unreadable]),
/// kept by its reading — a stand-in for the reading would stand in for the
/// record as well.
class _CountsReadings extends LayerFrameImageCache {
  _CountsReadings(this.key, {required super.frameStore});

  final BrushFrameKey key;
  int read = 0;

  @override
  BitmapSurface? storedSurfaceOrNull(
    BrushFrameKey key, {
    required CanvasSize canvasSize,
  }) {
    if (key == this.key) {
      read += 1;
    }
    return super.storedSurfaceOrNull(key, canvasSize: canvasSize);
  }
}
