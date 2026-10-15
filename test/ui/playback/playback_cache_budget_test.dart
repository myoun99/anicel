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
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/playback_cache_budget.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  // 8×8 RGBA = 256 bytes per canvas-sized image.
  const fullImageBytes = 8 * 8 * 4;

  BrushFrameKey frameKey(Cut cut, LayerId layerId, FrameId frameId) =>
      BrushFrameKey(
        projectId: const ProjectId('project'),
        trackId: const TrackId('track'),
        cutId: cut.id,
        layerId: layerId,
        frameId: frameId,
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
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 1),
        },
      ),
    ],
  );

  // Ink in two opposite corners reaches every tile, so the layer image is
  // stored whole and the byte counts below are whole images. A cel whose ink
  // sits in one corner is stored as that corner (`inkCropDrawsTheSame`) —
  // what that costs is counted on its own.
  LayerFrameImageCache layerImages({
    List<(double, double)> ink = const [(1, 1), (6, 6)],
  }) {
    final store = BrushFrameStore();
    BrushFrameEditingCoordinator(
      initialFrameKey: frameKey(
        cut(),
        const LayerId('layer'),
        const FrameId('frame-a'),
      ),
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        for (final (sequence, (x, y)) in ink.indexed)
          BrushDab(
            center: CanvasPoint(x: x, y: y),
            color: 0xFF000000,
            size: 2,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.round,
            pressure: 1,
            sequence: sequence,
          ),
      ],
    );
    final layers = LayerFrameImageCache(frameStore: store);
    addTearDown(layers.dispose);
    return layers;
  }

  /// The drawing's image at [quality], stored as its ink where the ink
  /// alone draws the same.
  Future<void> make(LayerFrameImageCache layers, PlaybackQuality quality) =>
      layers.prepare(
        key: frameKey(cut(), const LayerId('layer'), const FrameId('frame-a')),
        canvasSize: canvasSize,
        quality: quality,
        sourceEffects: const [],
        inkSuffices: true,
      );

  testWidgets('a cel whose ink sits in one corner costs the budget that '
      'corner', (tester) async {
    await tester.runAsync(() async {
      final layers = layerImages(ink: const [(1, 1)]);
      await make(layers, PlaybackQuality.full);
      // The ink is the 4×4 tile at the origin, where the whole canvas is
      // 8×8.
      expect(layers.estimatedBytes, 16 * 4);
    });
  });

  /// 🗣️F-289-Q21 (유저 2026-10-07): 「붙든다 — 재생 줄의 허용치 안에서」 — an
  /// export run borrows this line for the rows it keeps, playback resting
  /// while it goes. What it holds comes off the caches' share, and it may
  /// hold no more than they will give back.
  group('a run borrows the line, and the cache gives way to it', () {
    // The drawing at every level of the display's pyramid:
    // 8×8 + 4×4 + 2×2 = 256 + 64 + 16 = 336 bytes.
    const everything = fullImageBytes * (1 + 4 + 16) ~/ 16;

    Future<LayerFrameImageCache> filled() async {
      final layers = layerImages();
      for (final quality in PlaybackQuality.values) {
        await make(layers, quality);
      }
      expect(layers.estimatedBytes, everything);
      return layers;
    }

    testWidgets('🎯what is lent comes off the cache — the same budget with '
        'nothing lent keeps it whole', (tester) async {
      await tester.runAsync(() async {
        for (final lent in [0, 200]) {
          final layers = await filled();
          PlaybackCacheBudgetEnforcer(
            layerImages: layers,
            maxBytes: 400,
          ).enforce(wantedAt: (_) => null, lentBytes: lent);
          if (lent == 0) {
            expect(
              layers.estimatedBytes,
              everything,
              reason: 'LIVENESS: room for all',
            );
          } else {
            expect(layers.estimatedBytes, lessThanOrEqualTo(400 - lent));
          }
        }
      });
    });

    testWidgets('🚨what may be lent is the line less what the cache never '
        'gives back — the pictures a screen shows, and nothing else', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final layers = await filled();
        final enforcer = PlaybackCacheBudgetEnforcer(
          layerImages: layers,
          maxBytes: 1024,
        );
        expect(enforcer.lendableBytes(), 1024, reason: 'all of it gives way');

        layers.retainPin(
          frameKey(cut(), const LayerId('layer'), const FrameId('frame-a')),
          PlaybackQuality.full,
        );
        expect(
          enforcer.lendableBytes(),
          1024 - fullImageBytes,
          reason: 'less the layer image on screen',
        );
      });
    });
  });

  /// 🚨★★★**THE LARGEST CACHE IN THE APP USED TO BE THE DEAF ONE.**
  ///
  /// `EditorSessionManager.respondToMemoryPressure` always ended by calling
  /// [PlaybackCacheBudgetEnforcer.enforce], and its comment said the
  /// playback caches "re-run their budget against the shrunken world" —
  /// but nothing shrank their world. 600MB went in and 600MB came out,
  /// beside a cel store that had just halved itself.
  group('memory pressure', () {
    PlaybackCacheBudgetEnforcer enforcerAt(int maxBytes) =>
        PlaybackCacheBudgetEnforcer(
          layerImages: layerImages(),
          maxBytes: maxBytes,
        );

    test('the budget halves, and keeps halving', () {
      final enforcer = enforcerAt(playbackCacheBudgetBytes);
      expect(enforcer.maxBytes, playbackCacheBudgetBytes);
      expect(enforcer.respondToMemoryPressure(), isTrue);
      expect(enforcer.maxBytes, playbackCacheBudgetBytes ~/ 2);
      expect(enforcer.respondToMemoryPressure(), isTrue);
      expect(enforcer.maxBytes, playbackCacheBudgetBytes ~/ 4);
    });

    test('it stops at four frames and stays there', () {
      final enforcer = enforcerAt(playbackCacheBudgetUnderPressureBytes * 2);
      expect(enforcer.respondToMemoryPressure(), isTrue);
      expect(enforcer.maxBytes, playbackCacheBudgetUnderPressureBytes);
      // iOS sends the warning again as things get worse; a budget that
      // kept halving would walk to zero and rebuild every scrubbed frame.
      expect(enforcer.respondToMemoryPressure(), isFalse);
      expect(enforcer.maxBytes, playbackCacheBudgetUnderPressureBytes);
    });

    test('a caller already tighter than the floor is left alone', () {
      final enforcer = enforcerAt(1024);
      expect(enforcer.respondToMemoryPressure(), isFalse);
      expect(enforcer.maxBytes, 1024);
    });
  });
}
