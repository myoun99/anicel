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
import 'package:anicel/src/ui/playback/playback_cache_budget.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  // 8×8 RGBA = 256 bytes per full-quality image.
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

  // Ink in two opposite corners reaches every tile, so every tier of the
  // layer image is stored whole and the byte counts below are whole images.
  // A cel whose ink sits in one corner is stored as that corner
  // (`inkCropDrawsTheSame`) — what that costs is counted on its own.
  ({LayerFrameImageCache layers, CutFrameCompositeCache composites}) caches({
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
    return (
      layers: layers,
      composites: CutFrameCompositeCache(
        layerImages: layers,
        frameStore: store,
        frameKeyOf: frameKey,
      ),
    );
  }

  testWidgets(
    'layer images shrink into what the composites leave of the budget',
    (tester) async {
      await tester.runAsync(() async {
        final c = caches();
        await c.composites.prepareComposite(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.full,
        );
        // The composite build also cached the full-quality layer image.
        expect(c.layers.estimatedBytes, fullImageBytes);
        expect(c.composites.estimatedBytes, fullImageBytes);

        PlaybackCacheBudgetEnforcer(
          layerImages: c.layers,
          composites: c.composites,
          maxBytes: fullImageBytes,
        ).enforce(
          protect: const [
            PlaybackProtectedRange(
              cutId: CutId('cut'),
              startFrame: 0,
              endFrame: 3,
              quality: PlaybackQuality.full,
            ),
          ],
        );

        // Composites fit the budget exactly; nothing remains for the layer
        // image cache. With no reserve asked for, that is still the rule.
        expect(c.composites.estimatedBytes, fullImageBytes);
        expect(c.layers.estimatedBytes, 0);
        c.composites.dispose();
        c.layers.dispose();
      });
    },
  );

  testWidgets('a cel whose ink sits in one corner costs the budget that '
      'corner', (tester) async {
    await tester.runAsync(() async {
      final c = caches(ink: const [(1, 1)]);
      for (final quality in PlaybackQuality.values) {
        await c.composites.prepareComposite(
          cut: cut(),
          frameIndex: 0,
          quality: quality,
        );
      }
      // The ink is the 4×4 tile at the origin: 4×4 + 2×2 + 1×1 texels over
      // the three tiers, where the whole canvas is 8×8 + 4×4 + 2×2 — which
      // the composites, being the frame, still are.
      expect(c.layers.estimatedBytes, (16 + 4 + 1) * 4);
      expect(c.composites.estimatedBytes, (64 + 16 + 4) * 4);
      c.composites.dispose();
      c.layers.dispose();
    });
  });

  /// 🚨★★★ WHAT IS ON SCREEN RESERVES ITS OWN PIXELS FIRST.
  ///
  /// Measured by the user (2026-08-15): after #26 made a ruler scrub show
  /// the editing canvas, they raised playback quality to Full to see if the
  /// scrub stopped blanking — and it filled in SLOWER. The reason is here.
  /// Composites claim the budget first, and every warmed frame re-runs this;
  /// at Full they are 4× the bytes, so the remainder left to the layer-frame
  /// images goes to zero — and a target of zero evicts every entry, the one
  /// the editing canvas is drawing from included. The harder the warm
  /// worked, the emptier the scrub's own cache got.
  ///
  /// ⛔The pair is the test. A single case cannot tell "the reserve worked"
  /// from "there was room anyway", so both run the same numbers and differ
  /// only in the reserve.
  group('the editing canvas keeps its image when the budget is full', () {
    // 8×8 full + 4×4 half + 2×2 quarter = 256 + 64 + 16 = 336 bytes, in
    // BOTH caches (a composite build caches the layer image it used).
    const allTiers = 256 + 64 + 16;
    const budget = 512;

    List<PlaybackProtectedRange> protecting(List<PlaybackQuality> tiers) => [
      for (final quality in tiers)
        PlaybackProtectedRange(
          cutId: const CutId('cut'),
          startFrame: 0,
          endFrame: 3,
          quality: quality,
        ),
    ];

    Future<({int layers, int total})> afterEnforce(
      int reserve, {
      List<PlaybackQuality> protect = const [PlaybackQuality.full],
    }) async {
      final c = caches();
      for (final quality in PlaybackQuality.values) {
        await c.composites.prepareComposite(
          cut: cut(),
          frameIndex: 0,
          quality: quality,
        );
      }
      expect(c.layers.estimatedBytes, allTiers);
      expect(c.composites.estimatedBytes, allTiers);

      // The editing canvas reads its image every paint, so the full-tier
      // entry is the most recently used one — model that, or the LRU order
      // in this test is an artefact of which composite was built first.
      c.layers.validImageOrNull(
        frameKey(cut(), const LayerId('layer'), const FrameId('frame-a')),
        PlaybackQuality.full,
        canvasSize: canvasSize,
        sourceEffects: const [],
      );

      PlaybackCacheBudgetEnforcer(
        layerImages: c.layers,
        composites: c.composites,
        maxBytes: budget,
      ).enforce(reservedForDisplayBytes: reserve, protect: protecting(protect));
      final result = (
        layers: c.layers.estimatedBytes,
        total: c.layers.estimatedBytes + c.composites.estimatedBytes,
      );
      c.composites.dispose();
      c.layers.dispose();
      return result;
    }

    testWidgets('without a reserve the picture on screen is evicted', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // Composites keep all 336; 512 − 336 = 176 remains, which the
        // full-tier image (256) cannot fit in — so it goes, most-recently
        // used or not.
        expect((await afterEnforce(0)).layers, 0);
      });
    });

    testWidgets('a reserve takes its share off the composites first, and '
        'the picture survives', (tester) async {
      await tester.runAsync(() async {
        // The reserve comes out of the composites' claim (512 − 256), so
        // they shed the two unprotected tiers and the floor under the layer
        // trim is 256 — exactly the image the canvas is drawing.
        final result = await afterEnforce(fullImageBytes);
        expect(result.layers, fullImageBytes);
        // ⛔And the reserve is a SHARE of the budget, not an extra room on
        // the side. Handing the layer cache a floor without taking it off
        // the composites' claim lets the two of them hold 1.5× the number
        // this class exists to hold.
        expect(
          result.total,
          lessThanOrEqualTo(budget),
          reason: 'one combined budget — that is the whole job',
        );
      });
    });

    /// ⛔The floor is a SECOND mechanism, and this is the case that needs
    /// it. Above, the reserve worked by making the composites shed — so a
    /// build with no floor at all still passed. When every composite is
    /// protected there is nothing to shed, the remainder stays below the
    /// reserve, and only the floor keeps the canvas's image alive.
    testWidgets('the floor holds even when no composite can be shed', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const everyTier = PlaybackQuality.values;
        expect(
          (await afterEnforce(0, protect: everyTier)).layers,
          0,
          reason:
              '512 − 336 leaves 176, which the 256-byte image cannot '
              'fit in',
        );
        expect(
          (await afterEnforce(fullImageBytes, protect: everyTier)).layers,
          fullImageBytes,
          reason:
              'the remainder is still 176 — the floor is the only thing '
              'standing between the canvas and a blank frame',
        );
      });
    });
  });

  testWidgets('unprotected composites are evicted before protected ones', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final c = caches();
      final protectedImage = await c.composites.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.full,
      );
      await c.composites.prepareComposite(
        cut: cut(),
        frameIndex: 0,
        quality: PlaybackQuality.half,
      );

      PlaybackCacheBudgetEnforcer(
        layerImages: c.layers,
        composites: c.composites,
        maxBytes: fullImageBytes,
      ).enforce(
        protect: const [
          PlaybackProtectedRange(
            cutId: CutId('cut'),
            startFrame: 0,
            endFrame: 3,
            quality: PlaybackQuality.full,
          ),
        ],
      );

      expect(
        identical(
          c.composites.validCompositeOrNull(
            cut: cut(),
            frameIndex: 0,
            quality: PlaybackQuality.full,
          ),
          protectedImage,
        ),
        isTrue,
      );
      expect(
        c.composites.validCompositeOrNull(
          cut: cut(),
          frameIndex: 0,
          quality: PlaybackQuality.half,
        ),
        isNull,
      );
      c.composites.dispose();
      c.layers.dispose();
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
    PlaybackCacheBudgetEnforcer enforcerAt(int maxBytes) {
      final c = caches();
      addTearDown(() {
        c.composites.dispose();
        c.layers.dispose();
      });
      return PlaybackCacheBudgetEnforcer(
        layerImages: c.layers,
        composites: c.composites,
        maxBytes: maxBytes,
      );
    }

    test('the combined budget halves, and keeps halving', () {
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
