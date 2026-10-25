import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_cache_budget.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/draw_on_current_frame.dart';

/// 「허용치 = 레이어 그림 수요 순서」(playback-plays-the-screen-material,
/// 10-09): what every screen shows is what the budget keeps — by when each
/// is wanted, the latest let go first. Since a frame became one picture
/// (one-picture-per-frame ②-2) that is the frames' pictures.
/// ↩️The row images were every screen's pictures, kept by the demand, until
/// then; ↩️the composites the film was shown from gave way before any of
/// them, until they went (2026-10-10); ↩️the canvas's row images held what
/// the pictures left of the line, and gave way first, until no screen drew
/// a row's image (②-5b-1).
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 3,
    canvasSize: canvasSize,
    layers: const [],
  );

  BrushFrameKey cel(String name) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: cut.id,
    layerId: const LayerId('l'),
    frameId: FrameId(name),
  );

  const names = ['a', 'b', 'c'];

  /// Frames 0, 1 and 2 show cels a, b and c — each inked into both
  /// corners, so each frame's picture is the whole canvas.
  FramePictures picturesOfTheFrames() {
    final store = BrushFrameStore();
    for (final name in names) {
      for (final corner in [CanvasPoint(x: 1, y: 1), CanvasPoint(x: 6, y: 6)]) {
        inkCelIn(
          store,
          cel(name),
          canvasSize: canvasSize,
          at: corner,
          size: 2,
          tipShape: BrushTipShape.square,
          tileSize: 4,
        );
      }
    }
    final layers = LayerFrameImageCache(frameStore: store);
    addTearDown(layers.dispose);
    final pictureStore = FramePictureStore<FramePictureKey>();
    addTearDown(pictureStore.dispose);
    return FramePictures(
      store: pictureStore,
      layerImages: layers,
      stackOf: (picture) => [
        CompositeLeaf(
          CanvasLayerImageRequest(
            frameKey: cel(names[picture.frameIndex]),
            opacity: 1,
          ),
        ),
      ],
      pageOf: (picture) => (
        canvasSize: picture.cut.canvasSize,
        pasteboardReach: PasteboardReach.none,
        paintPaper: picture.paintPaper,
        paperBackground: ProjectBackground.defaultBackground,
      ),
    );
  }

  FramePictureKey keyOf(FramePictures pictures, String name) => pictures
      .keyOf((cut: cut, frameIndex: names.indexOf(name), paintPaper: true));

  Future<void> makePictures(FramePictures pictures) async {
    for (final frame in [0, 1, 2]) {
      await pictures.make((
        cut: cut,
        frameIndex: frame,
        paintPaper: true,
      ), shouldAbort: () => false);
    }
  }

  List<bool> heldPictures(FramePictures pictures) => [
    for (final name in names)
      pictures.store.peek(keyOf(pictures, name)) != null,
  ];

  /// b under the playhead, a two steps on, c five.
  FramePictureWantedAt wantedAtOf(FramePictures pictures) =>
      (key) => {
        keyOf(pictures, 'b'): 0,
        keyOf(pictures, 'a'): 2,
        keyOf(pictures, 'c'): 5,
      }[key];

  testWidgets('the frames\' pictures go latest-wanted first, and the one '
      'under the playhead stays whatever the cap', (tester) async {
    await tester.runAsync(() async {
      final pictures = picturesOfTheFrames();
      await makePictures(pictures);
      final picture = pictures.store.bytesOf(keyOf(pictures, 'a'))!;
      final wantedAt = wantedAtOf(pictures);
      PlaybackCacheBudgetEnforcer budget(int maxBytes) =>
          PlaybackCacheBudgetEnforcer(
            pictures: pictures.store,
            maxBytes: maxBytes,
          );

      budget(3 * picture).enforce(wantedAt: wantedAt);
      expect(
        heldPictures(pictures),
        [true, true, true],
        reason: 'LIVENESS: room for all',
      );

      budget(2 * picture).enforce(wantedAt: wantedAt);
      expect(heldPictures(pictures), [true, true, false]);

      budget(picture).enforce(wantedAt: wantedAt);
      expect(heldPictures(pictures), [false, true, false]);

      budget(0).enforce(wantedAt: wantedAt);
      expect(
        heldPictures(pictures),
        [false, true, false],
        reason: 'b is the playhead\'s',
      );
    });
  });

  /// 🗣️F-289-Q21 (유저 2026-10-07): 「붙든다 — 재생 줄의 허용치 안에서」 — an
  /// export run borrows this line for the rows it keeps, playback resting
  /// while it goes. What it holds comes off the pictures' share.
  testWidgets('🎯what is lent comes off the pictures — the same budget with '
      'nothing lent keeps them all', (tester) async {
    await tester.runAsync(() async {
      for (final lent in [0, 1]) {
        final pictures = picturesOfTheFrames();
        await makePictures(pictures);
        final picture = pictures.store.bytesOf(keyOf(pictures, 'a'))!;
        PlaybackCacheBudgetEnforcer(
          pictures: pictures.store,
          maxBytes: 3 * picture,
        ).enforce(wantedAt: wantedAtOf(pictures), lentBytes: lent * picture);
        expect(
          heldPictures(pictures),
          lent == 0 ? [true, true, true] : [true, true, false],
          reason: 'lent: $lent pictures',
        );
      }
    });
  });

  testWidgets('🚨room is made out of a picture wanted LATER — never out of '
      'one wanted sooner', (tester) async {
    await tester.runAsync(() async {
      final pictures = picturesOfTheFrames();
      await makePictures(pictures);
      final picture = pictures.store.bytesOf(keyOf(pictures, 'a'))!;
      final wantedAt = wantedAtOf(pictures);
      final budget = PlaybackCacheBudgetEnforcer(
        pictures: pictures.store,
        maxBytes: 4 * picture,
      );

      expect(
        budget.makeRoomFor(
          bytes: picture,
          step: 1,
          within: 3 * picture,
          wantedAt: wantedAt,
        ),
        isTrue,
      );
      expect(
        heldPictures(pictures),
        [true, true, false],
        reason: 'c is wanted after step 1',
      );

      expect(
        budget.makeRoomFor(
          bytes: picture,
          step: 3,
          within: picture,
          wantedAt: wantedAt,
        ),
        isFalse,
        reason: 'a and b are wanted sooner than step 3',
      );
      expect(heldPictures(pictures), [true, true, false]);
    });
  });

  testWidgets('what may be lent is the line less the pictures a screen '
      'shows', (tester) async {
    await tester.runAsync(() async {
      final pictures = picturesOfTheFrames();
      await makePictures(pictures);
      final budget = PlaybackCacheBudgetEnforcer(
        pictures: pictures.store,
        maxBytes: 4096,
      );
      expect(budget.lendableBytes(), 4096, reason: 'all of it gives way');

      final shown = keyOf(pictures, 'b');
      pictures.store.retainPin(shown);
      addTearDown(() => pictures.store.releasePin(shown));
      final picture = pictures.store.bytesOf(shown)!;
      expect(budget.lendableBytes(), 4096 - picture);
    });
  });

  test('the pictures may hold the line, less what is lent', () {
    final budget = PlaybackCacheBudgetEnforcer(
      pictures: picturesOfTheFrames().store,
      maxBytes: 1000,
    );
    expect(budget.room(), 1000);
    expect(budget.room(lentBytes: 300), 700);
    expect(budget.room(lentBytes: 3000), 0);
  });
}
