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
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/playback/cut_frame_composite_cache.dart';
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
  //
  // The cut holds TWO pictures: the drawing on frame 0, and the nothing
  // every frame after it composes to (one image, whichever of them asks).
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
        );
        // The composite build also cached the layer image it drew.
        expect(c.layers.estimatedBytes, fullImageBytes);
        expect(c.composites.estimatedBytes, fullImageBytes);

        PlaybackCacheBudgetEnforcer(
          layerImages: c.layers,
          composites: c.composites,
          maxBytes: fullImageBytes,
        ).enforce();

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
      await c.composites.prepareComposite(cut: cut(), frameIndex: 0);
      // The ink is the 4×4 tile at the origin, where the whole canvas is
      // 8×8 — which the composite, being the frame, still is.
      expect(c.layers.estimatedBytes, 16 * 4);
      expect(c.composites.estimatedBytes, 64 * 4);
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
  /// at Full they were 4× the bytes of the Half they had been, so the
  /// remainder left to the layer-frame images went to zero — and a target of
  /// zero evicts every entry, the one the editing canvas is drawing from
  /// included. The harder the warm worked, the emptier the scrub's own cache
  /// got. (Full is the only size a cut's picture has since 2026-10-08.)
  ///
  /// ⛔The pair is the test. A single case cannot tell "the reserve worked"
  /// from "there was room anyway", so both run the same numbers and differ
  /// only in the reserve.
  group('the editing canvas keeps its image when the budget is full', () {
    // The cut's two pictures — 2 × 256 = 512 bytes of composites — and the
    // drawing's layer image at every level of the display's pyramid:
    // 8×8 + 4×4 + 2×2 = 256 + 64 + 16 = 336 bytes.
    const bothPictures = 2 * fullImageBytes;
    const allLevels = 256 + 64 + 16;
    const budget = 512;

    // [bothOnScreen]: a screen shows the cut's two pictures — the one
    // thing a full budget does not let go of.
    Future<({int layers, int total})> afterEnforce(
      int reserve, {
      bool bothOnScreen = false,
    }) async {
      final c = caches();
      for (final frameIndex in [0, 1]) {
        await c.composites.prepareComposite(cut: cut(), frameIndex: frameIndex);
      }
      for (final level in [PlaybackQuality.half, PlaybackQuality.quarter]) {
        await c.layers.prepare(
          key: frameKey(
            cut(),
            const LayerId('layer'),
            const FrameId('frame-a'),
          ),
          canvasSize: canvasSize,
          quality: level,
          sourceEffects: const [],
        );
      }
      expect(c.layers.estimatedBytes, allLevels);
      expect(c.composites.estimatedBytes, bothPictures);

      // The editing canvas reads its image every paint, so the full-size
      // entry is the most recently used one — model that, or the LRU order
      // in this test is an artefact of which level was built first.
      c.layers.validImageOrNull(
        frameKey(cut(), const LayerId('layer'), const FrameId('frame-a')),
        PlaybackQuality.full,
        canvasSize: canvasSize,
        sourceEffects: const [],
      );

      final enforcer = PlaybackCacheBudgetEnforcer(
        layerImages: c.layers,
        composites: c.composites,
        maxBytes: budget,
      );
      if (bothOnScreen) {
        c.composites
          ..retainPin((const CutId('cut'), 0))
          ..retainPin((const CutId('cut'), 1));
      }
      enforcer.enforce(reservedForDisplayBytes: reserve);
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
        // Composites keep all 512, which is the budget; nothing remains,
        // so the full-size image goes, most-recently used or not.
        expect((await afterEnforce(0)).layers, 0);
      });
    });

    testWidgets('a reserve takes its share off the composites first, and '
        'the picture survives', (tester) async {
      await tester.runAsync(() async {
        // The reserve comes out of the composites' claim (512 − 256), so
        // they shed a picture and the floor under the layer trim is 256 —
        // exactly the image the canvas is drawing.
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
    /// build with no floor at all still passed. When a screen shows every
    /// composite there is nothing to shed, the remainder stays below the
    /// reserve, and only the floor keeps the canvas's image alive.
    testWidgets('the floor holds even when no composite can be shed', (
      tester,
    ) async {
      await tester.runAsync(() async {
        expect(
          (await afterEnforce(0, bothOnScreen: true)).layers,
          0,
          reason: '512 − 512 leaves nothing for the 256-byte image',
        );
        expect(
          (await afterEnforce(fullImageBytes, bothOnScreen: true)).layers,
          fullImageBytes,
          reason:
              'the remainder is still nothing — the floor is the only thing '
              'standing between the canvas and a blank frame',
        );
      });
    });
  });

  /// 유저 2026-10-08 (「4 허용치도 해결」) · 「저장」 10-08 (「천장은 지키는
  /// 범위에도 걸린다」): a full budget keeps what is wanted SOONEST. ↩️It
  /// kept a named range whole, whatever the cap said.
  testWidgets('a full budget lets go of the composite wanted latest — not '
      'the one used longest ago', (tester) async {
    await tester.runAsync(() async {
      // The playhead on frame 0, then on frame 1: the picture under it is
      // the one that stays, whichever was made first.
      for (final playhead in [0, 1]) {
        final c = caches();
        await c.composites.prepareComposite(cut: cut(), frameIndex: 0);
        await c.composites.prepareComposite(cut: cut(), frameIndex: 1);

        PlaybackCacheBudgetEnforcer(
          layerImages: c.layers,
          composites: c.composites,
          maxBytes: fullImageBytes,
        ).enforce(
          demand: StandingDemand(
            cutId: const CutId('cut'),
            frameCount: 4,
            around: playhead,
            resolveCut: (_) => cut(),
          ),
        );

        expect(
          [
            for (final frameIndex in [0, 1])
              c.composites.validCompositeOrNull(
                    cut: cut(),
                    frameIndex: frameIndex,
                  ) !=
                  null,
          ],
          [playhead == 0, playhead == 1],
          reason: 'the playhead on frame $playhead',
        );
        c.composites.dispose();
        c.layers.dispose();
      }
    });
  });

  testWidgets('the trim leaves the picture under the playhead, whatever '
      'the cap', (tester) async {
    await tester.runAsync(() async {
      final c = caches();
      await c.composites.prepareComposite(cut: cut(), frameIndex: 0);
      await c.composites.prepareComposite(cut: cut(), frameIndex: 1);

      PlaybackCacheBudgetEnforcer(
        layerImages: c.layers,
        composites: c.composites,
        maxBytes: 0,
      ).enforce(
        demand: StandingDemand(
          cutId: const CutId('cut'),
          frameCount: 4,
          around: 1,
          resolveCut: (_) => cut(),
        ),
      );

      expect(
        [
          for (final frameIndex in [0, 1])
            c.composites.validCompositeOrNull(
                  cut: cut(),
                  frameIndex: frameIndex,
                ) !=
                null,
        ],
        [false, true],
        reason: 'the playhead stands on frame 1',
      );
      c.composites.dispose();
      c.layers.dispose();
    });
  });

  group('the room the warmer asks before it makes a picture', () {
    Future<
      ({
        LayerFrameImageCache layers,
        CutFrameCompositeCache composites,
        PlaybackCacheBudgetEnforcer enforcer,
      })
    >
    bothHeld({required int maxBytes, int madeLast = 1}) async {
      final c = caches();
      addTearDown(() {
        c.composites.dispose();
        c.layers.dispose();
      });
      for (final frameIndex in [1 - madeLast, madeLast]) {
        await c.composites.prepareComposite(cut: cut(), frameIndex: frameIndex);
      }
      return (
        layers: c.layers,
        composites: c.composites,
        enforcer: PlaybackCacheBudgetEnforcer(
          layerImages: c.layers,
          composites: c.composites,
          maxBytes: maxBytes,
        ),
      );
    }

    // The playhead on frame 0: frame 1's picture is wanted a step later.
    StandingDemand fromFrameZero() => StandingDemand(
      cutId: const CutId('cut'),
      frameCount: 4,
      around: 0,
      resolveCut: (_) => cut(),
    );

    bool held(CutFrameCompositeCache composites, int frameIndex) =>
        composites.validCompositeOrNull(cut: cut(), frameIndex: frameIndex) !=
        null;

    testWidgets('🚨room is made out of a composite wanted LATER, never out '
        'of one wanted sooner', (tester) async {
      await tester.runAsync(() async {
        final c = await bothHeld(maxBytes: 2 * fullImageBytes);

        expect(
          c.enforcer.makeRoomFor(
            bytes: fullImageBytes,
            step: 5,
            demand: fromFrameZero(),
          ),
          isFalse,
          reason: 'both are wanted sooner than step 5: what is held is the '
              'window, and there is no room in it',
        );
        expect([held(c.composites, 0), held(c.composites, 1)], [true, true]);

        expect(
          c.enforcer.makeRoomFor(
            bytes: fullImageBytes,
            step: 0,
            demand: fromFrameZero(),
          ),
          isTrue,
        );
        expect(
          [held(c.composites, 0), held(c.composites, 1)],
          [true, false],
          reason: 'the one wanted a step later went, and only that one',
        );
      });
    });

    testWidgets('a composite a screen shows is no room at all', (tester) async {
      await tester.runAsync(() async {
        final c = await bothHeld(maxBytes: 2 * fullImageBytes);
        c.composites
          ..retainPin((const CutId('cut'), 0))
          ..retainPin((const CutId('cut'), 1));

        expect(
          c.enforcer.makeRoomFor(
            bytes: fullImageBytes,
            step: 0,
            demand: fromFrameZero(),
          ),
          isFalse,
        );
        expect([held(c.composites, 0), held(c.composites, 1)], [true, true]);
      });
    });

    testWidgets('the layer images the last picture was made of keep their '
        'room while pictures are being made — and only then', (tester) async {
      await tester.runAsync(() async {
        // Frame 0 — the drawing, one 256-byte layer image — made last.
        final c = await bothHeld(maxBytes: 4 * fullImageBytes, madeLast: 0);
        expect(c.composites.lastComposeLayerBytes, fullImageBytes);

        expect(c.enforcer.roomForComposites(), 3 * fullImageBytes);
        expect(
          c.enforcer.roomForComposites(lentBytes: fullImageBytes),
          2 * fullImageBytes,
          reason: 'what is lent comes off as well',
        );
        expect(
          c.enforcer.roomForComposites(
            reservedForDisplayBytes: 3 * fullImageBytes,
          ),
          2 * fullImageBytes,
          reason: 'the layer images\' share is half the line and no more',
        );

        // The frame after the drawing shows nothing, and is made of no
        // layer image: made last, it asks no room for any.
        final after = await bothHeld(maxBytes: 4 * fullImageBytes);
        expect(after.composites.lastComposeLayerBytes, 0);
        expect(after.enforcer.roomForComposites(), 4 * fullImageBytes);
      });
    });

    testWidgets('a window nobody is adding to keeps the whole line: the '
        'enforcer takes no share for layer images nobody will use', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final c = await bothHeld(maxBytes: 2 * fullImageBytes, madeLast: 0);
        expect(c.enforcer.roomForComposites(), fullImageBytes);

        c.enforcer.enforce(demand: fromFrameZero());

        expect([held(c.composites, 0), held(c.composites, 1)], [true, true]);
        expect(c.layers.estimatedBytes, 0);
      });
    });
  });

  /// 🗣️F-289-Q21 (유저 2026-10-07): 「붙든다 — 재생 줄의 허용치 안에서」 — an
  /// export run borrows this line for the rows it keeps, playback resting
  /// while it goes. What it holds comes off the caches' share, and it may
  /// hold no more than they will give back.
  group('a run borrows the line, and the caches give way to it', () {
    // The cut's two pictures and the layer image they were made of.
    const everything = 3 * fullImageBytes;

    Future<({LayerFrameImageCache layers, CutFrameCompositeCache composites})>
    filled() async {
      final c = caches();
      addTearDown(() {
        c.composites.dispose();
        c.layers.dispose();
      });
      for (final frameIndex in [0, 1]) {
        await c.composites.prepareComposite(cut: cut(), frameIndex: frameIndex);
      }
      expect(
        c.layers.estimatedBytes + c.composites.estimatedBytes,
        everything,
      );
      return c;
    }

    testWidgets('🎯what is lent comes off the caches — the same budget with '
        'nothing lent keeps them whole', (tester) async {
      await tester.runAsync(() async {
        for (final lent in [0, 600]) {
          final c = await filled();
          PlaybackCacheBudgetEnforcer(
            layerImages: c.layers,
            composites: c.composites,
            maxBytes: 1024,
          ).enforce(lentBytes: lent);
          final held = c.layers.estimatedBytes + c.composites.estimatedBytes;
          if (lent == 0) {
            expect(held, everything, reason: 'LIVENESS: room for all');
          } else {
            expect(held, lessThanOrEqualTo(1024 - lent));
          }
        }
      });
    });

    testWidgets('🚨what may be lent is the line less what the caches never '
        'give back — the pictures a screen shows, and nothing else', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final c = await filled();
        final enforcer = PlaybackCacheBudgetEnforcer(
          layerImages: c.layers,
          composites: c.composites,
          maxBytes: 1024,
        );
        expect(enforcer.lendableBytes(), 1024, reason: 'all of it gives way');

        c.composites.retainPin((const CutId('cut'), 0));
        expect(
          enforcer.lendableBytes(),
          1024 - fullImageBytes,
          reason: 'less the composite a screen shows',
        );

        c.layers.retainPin(
          frameKey(cut(), const LayerId('layer'), const FrameId('frame-a')),
          PlaybackQuality.full,
        );
        expect(
          enforcer.lendableBytes(),
          1024 - 2 * fullImageBytes,
          reason: 'and the layer image on screen',
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
