import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_cache_budget.dart';

import '../../helpers/draw_on_current_frame.dart';

/// playback-plays-the-screen-material (10-09, 「허용치 = 레이어 그림 수요
/// 순서」): the canvas's own images are every screen's pictures, and they
/// are what the budget keeps — by when each is wanted, the latest let go
/// first. ↩️The composites the film was shown from gave way before any of
/// them, until they went (2026-10-10).
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  // 8×8 RGBA: a cel inked into both corners is stored whole.
  const image = 8 * 8 * 4;

  BrushFrameKey keyOf(Cut cut, LayerId layerId, FrameId frameId) =>
      BrushFrameKey(
        projectId: const ProjectId('p'),
        trackId: const TrackId('t'),
        cutId: cut.id,
        layerId: layerId,
        frameId: frameId,
      );

  /// One row, cels a, b and c on frames 0, 1 and 2.
  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 3,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: const LayerId('l'),
        name: 'A',
        frames: [
          for (final cel in ['a', 'b', 'c'])
            Frame(id: FrameId(cel), duration: 1, strokes: const []),
        ],
        timeline: {
          for (final (frame, cel) in ['a', 'b', 'c'].indexed)
            frame: TimelineExposure.drawing(FrameId(cel), length: 1),
        },
      ),
    ],
  );

  BrushFrameKey cel(String name) =>
      keyOf(cut, const LayerId('l'), FrameId(name));

  (BrushFrameKey, PlaybackQuality) slot(String name) =>
      (cel(name), PlaybackQuality.full);

  ({LayerFrameImageCache layers}) caches() {
    final store = BrushFrameStore();
    for (final name in ['a', 'b', 'c']) {
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
    return (layers: layers);
  }

  Future<void> make(LayerFrameImageCache layers, List<String> names) async {
    for (final name in names) {
      await layers.prepare(
        key: cel(name),
        canvasSize: canvasSize,
        quality: PlaybackQuality.full,
        sourceEffects: const [],
      );
    }
  }

  bool held(LayerFrameImageCache layers, String name) =>
      layers.validImageOrNull(
        cel(name),
        PlaybackQuality.full,
        canvasSize: canvasSize,
        sourceEffects: const [],
      ) !=
      null;

  /// b under the playhead, a two steps on, c five.
  int? wantedAt((BrushFrameKey, PlaybackQuality) asked) =>
      {slot('b'): 0, slot('a'): 2, slot('c'): 5}[asked];

  testWidgets('the canvas\'s images go latest-wanted first, and the rows under '
      'the playhead stay whatever the cap', (tester) async {
    await tester.runAsync(() async {
      final c = caches();
      await make(c.layers, ['a', 'b', 'c']);
      PlaybackCacheBudgetEnforcer budget(int maxBytes) =>
          PlaybackCacheBudgetEnforcer(
            layerImages: c.layers,
            maxBytes: maxBytes,
          );

      budget(2 * image).enforce(wantedAt: wantedAt);
      expect([held(c.layers, 'a'), held(c.layers, 'b'), held(c.layers, 'c')], [
        true,
        true,
        false,
      ]);

      budget(image).enforce(wantedAt: wantedAt);
      expect([held(c.layers, 'a'), held(c.layers, 'b')], [false, true]);

      budget(0).enforce(wantedAt: wantedAt);
      expect(held(c.layers, 'b'), isTrue, reason: 'b is the playhead\'s');
    });
  });

  testWidgets('🚨room is made out of an image wanted LATER, never out of one '
      'wanted sooner', (tester) async {
    await tester.runAsync(() async {
      final c = caches();
      await make(c.layers, ['a', 'b', 'c']);
      final budget = PlaybackCacheBudgetEnforcer(
        layerImages: c.layers,
        maxBytes: 2 * image,
      );

      expect(
        budget.makeRoomFor(
          bytes: image,
          step: 1,
          within: 2 * image,
          wantedAt: wantedAt,
        ),
        isTrue,
      );
      expect([held(c.layers, 'a'), held(c.layers, 'b'), held(c.layers, 'c')], [
        false,
        true,
        false,
      ]);

      expect(
        budget.makeRoomFor(
          bytes: image,
          step: 1,
          within: image,
          wantedAt: wantedAt,
        ),
        isFalse,
        reason: 'only b is left, and b is wanted sooner',
      );
      expect(held(c.layers, 'b'), isTrue);
    });
  });

  test('the canvas\'s images may hold the line, less what is lent', () {
    final c = caches();
    final budget = PlaybackCacheBudgetEnforcer(
      layerImages: c.layers,
      maxBytes: 1000,
    );
    expect(budget.room(), 1000);
    expect(budget.room(lentBytes: 300), 700);
    expect(budget.room(lentBytes: 3000), 0);
  });
}
