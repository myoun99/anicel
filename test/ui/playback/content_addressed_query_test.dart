import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
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
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

/// C2 — THE SIGNATURE IS THE ADDRESS; THE INDEX IS ONLY THE ACCELERATOR.
///
/// Held exposures share one signature and therefore one stored image, but
/// the query used to consult the per-frame index FIRST and return null
/// for any frame the warm loop had not visited — so the frames that were
/// already paid for read "cold", and the readiness bar lied by omission
/// across every held exposure and every covering-layer cut.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  const frameKey = BrushFrameKey(
    projectId: ProjectId('project'),
    trackId: TrackId('track'),
    cutId: CutId('cut'),
    layerId: LayerId('layer'),
    frameId: FrameId('frame-a'),
  );

  BrushDab dab({int sequence = 0, double x = 1, int color = 0xFF000000}) =>
      BrushDab(
        center: CanvasPoint(x: x, y: 1),
        color: color,
        size: 2,
        opacity: 1,
        flow: 1,
        hardness: 1,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: sequence,
      );

  Cut cut() => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    duration: 4,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: const LayerId('layer'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 4),
        },
      ),
    ],
  );

  ({CutFrameCompositeCache cache, BrushFrameEditingCoordinator coordinator})
  rig() {
    final store = BrushFrameStore();
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: frameKey,
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(
        userUndoLimit: 8,
        deferredBakeRatio: 0,
      ),
    )..commitSourceStroke(sourceDabs: [dab()]);
    final cache = CutFrameCompositeCache(
      layerImages: LayerFrameImageCache(frameStore: store),
      frameStore: store,
      frameKeyOf: (cut, layerId, frameId) => BrushFrameKey(
        projectId: const ProjectId('project'),
        trackId: const TrackId('track'),
        cutId: cut.id,
        layerId: layerId,
        frameId: frameId,
      ),
    );
    return (cache: cache, coordinator: coordinator);
  }

  testWidgets('a held exposure baked once answers every frame it holds',
      (tester) async {
    await tester.runAsync(() async {
      final r = rig();
      addTearDown(r.cache.dispose);

      await r.cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );

      for (var frame = 1; frame < 4; frame += 1) {
        expect(
          r.cache.validCompositeOrNull(
            cut: cut(),
            frameIndex: frame,
            quality: PlaybackQuality.full,
          ),
          isNotNull,
          reason: 'frame $frame shares frame 0\'s signature — the image is '
              'already bought, the query must find it by content',
        );
      }
    });
  });

  testWidgets('the adopting hit files the key — a pin on a queried frame '
      'actually protects it', (tester) async {
    await tester.runAsync(() async {
      final r = rig();
      addTearDown(r.cache.dispose);

      await r.cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
      // The query on frame 2 adopts (cut, 2, full) into the entry's keys.
      expect(
        r.cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 2,
          quality: PlaybackQuality.full,
        ),
        isNotNull,
      );

      r.cache.retainPin((const CutId('cut'), 2, PlaybackQuality.full));
      r.cache.enforceBudget(maxBytes: 0);
      expect(
        r.cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 2,
          quality: PlaybackQuality.full,
        ),
        isNotNull,
        reason: 'pins test the entry\'s filed keys — adoption is '
            'load-bearing, an unfiled frame is an unprotectable frame',
      );

      r.cache.releasePin((const CutId('cut'), 2, PlaybackQuality.full));
      r.cache.enforceBudget(maxBytes: 0);
      expect(
        r.cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 2,
          quality: PlaybackQuality.full,
        ),
        isNull,
        reason: 'released, the entry evicts as usual',
      );
    });
  });

  testWidgets('content addressing never serves yesterday\'s pixels — an '
      'edit moves the address and the query misses', (tester) async {
    await tester.runAsync(() async {
      final r = rig();
      addTearDown(r.cache.dispose);

      await r.cache.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
      r.coordinator.commitSourceStroke(
        sourceDabs: [dab(sequence: 1, x: 5, color: 0xFFFF0000)],
      );

      expect(
        r.cache.validCompositeOrNull(
          cut: cut(),
          frameIndex: 1,
          quality: PlaybackQuality.full,
        ),
        isNull,
        reason: 'the fresh signature carries the new revision, and no '
            'image lives at that address yet',
      );
    });
  });
}
