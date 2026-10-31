import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/playback/frame_demand.dart' show FrameGhosts;
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/playback_rig.dart';
import 'package:anicel/src/ui/session/render_caches.dart';

/// A5 — ONE WARMING RESTART PER EDIT BURST, NOT ONE PER DAB.
///
/// Every brush invalidation used to call `_warmActiveCut()` directly, so a
/// stroke's stream of dab commits rebuilt the playhead-outward order,
/// bumped the scheduler's generation and reset its progress notifier once
/// per commit — pure churn, since warming cannot start until the idle
/// window has passed anyway. The debounce defers exactly ONE thing: the
/// restart. The cache invalidations stay synchronous, because a stale
/// composite must be unservable the instant the stroke lands.
/// The collaborator that owns the warmer — named so `tool/mutation_run.dart`
/// runs this file for it: the rig's own suite never schedules a warm, so the
/// idle window and the scheduler it hangs on had no observer here.
PlaybackRig playbackRigOf(EditorSessionManager session) => session.playbackRig;

/// And the collaborator that HOLDS the debounce this file is named after —
/// its own namer counts viewer bytes and never lets an edit burst settle.
RenderCaches renderCachesOf(EditorSessionManager session) =>
    session.renderCaches;

void main() {
  // The warm it restarts makes playback's rows, and a row asks the binding
  // for the quiet it takes its turn in ([QuietTurns]).
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvasSize = CanvasSize(width: 8, height: 8);

  test('a burst of edits restarts warming once — and a stale picture is '
      'unservable at once', () async {
    final cut = Cut(
      id: const CutId('cut'),
      name: '1',
      duration: 4,
      canvasSize: canvasSize,
      layers: [
        Layer(
          id: const LayerId('layer'),
          name: 'A',
          frames: [
            Frame(id: const FrameId('frame-1'), duration: 1, strokes: const []),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('frame-1'), length: 4),
          },
        ),
      ],
    );
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(id: const TrackId('track'), name: 'T', cuts: [cut]),
        ],
      ),
    );
    addTearDown(session.dispose);

    final activeCut = session.activeCutOrNull!;
    final frameKey = session.brushFrameKeyForCut(
      activeCut,
      const LayerId('layer'),
      const FrameId('frame-1'),
    );

    // Real content through the session's own store — a coordinator with
    // no hub wired, so nothing here counts as an edit burst yet.
    BrushFrameEditingCoordinator(
      initialFrameKey: frameKey,
      frameStore: renderCachesOf(session).brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 2, y: 2),
          color: 0xFF000000,
          size: 2,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );

    final pictures = session.playbackRig.framePictures;
    await pictures.make((
      cut: activeCut,
      frameIndex: 0,
      paintPaper: true,
      ghosts: FrameGhosts.none,
    ), shouldAbort: () => false);
    expect(pictures.has((
      cut: activeCut,
      frameIndex: 0,
      paintPaper: true,
      ghosts: FrameGhosts.none,
    )), isTrue);

    // Let any open-time warm restart land before counting.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    var restarts = 0;
    void countRestarts() {
      final value = playbackRigOf(session).prerenderScheduler.progress.value;
      if (value.cached == 0 && value.total > 0) {
        restarts += 1;
      }
    }

    session.playbackRig.prerenderScheduler.progress.addListener(countRestarts);
    addTearDown(
      () => session.playbackRig.prerenderScheduler.progress.removeListener(countRestarts),
    );

    // The burst: five dab commits' worth, synchronously — each an edit of
    // the cel's pixels, and its invalidation.
    for (var i = 0; i < 5; i += 1) {
      renderCachesOf(session).brushFrameStore.markCelEdited(frameKey);
      session.renderCaches.cacheInvalidationHub.invalidateBrushFrame(
        BrushFrameCacheInvalidation(frameKey: frameKey, wholeFrame: true),
      );
    }

    expect(
      pictures.has((
        cut: activeCut,
        frameIndex: 0,
        paintPaper: true,
        ghosts: FrameGhosts.none,
      )),
      isFalse,
      reason: 'only the RESTART is deferred — a stale picture must be '
          'unservable before the event loop turns: the edit asks another '
          'picture (one-picture-per-frame ②-2). ↩️The burst dropped the '
          'row images it invalidated',
    );
    expect(
      restarts,
      0,
      reason: 'the restart waits for the burst\'s trailing edge',
    );

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      restarts,
      1,
      reason: 'five invalidations, one queue rebuild — that is the whole '
          'point of the debounce',
    );
  });

  // 🗣️F-529 (유저 2026-11-01): 「어차피 화면 모든 프레임 바뀌니까 허용하고
  // 굽던거 버리고 다시굽는게 맞지않을까」.
  group('what the frames show moves', () {
    setUp(() => RenderCaches.walkFollowsHistory = true);
    tearDown(() => RenderCaches.walkFollowsHistory = false);

    EditorSessionManager aSession() {
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'P',
          createdAt: DateTime.utc(2026),
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'T',
              cuts: [
                Cut(
                  id: const CutId('cut'),
                  name: '1',
                  duration: 4,
                  canvasSize: canvasSize,
                  layers: [
                    Layer(
                      id: const LayerId('layer'),
                      name: 'A',
                      frames: [
                        Frame(
                          id: const FrameId('frame-1'),
                          duration: 1,
                          strokes: const [],
                        ),
                      ],
                      timeline: {
                        0: const TimelineExposure.drawing(
                          FrameId('frame-1'),
                          length: 4,
                        ),
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(session.dispose);
      return session;
    }

    /// Counts the walks [session] starts from here on.
    int Function() walks(EditorSessionManager session) {
      final progress = session.playbackRig.prerenderScheduler.progress;
      var started = 0;
      void count() {
        if (progress.value.cached == 0 && progress.value.total > 0) {
          started += 1;
        }
      }

      progress.addListener(count);
      addTearDown(() => progress.removeListener(count));
      return () => started;
    }

    Future<void> aTurn() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test('🚨a row\'s eye starts the walk over: a walk at rest stayed at rest '
        'with its bar emptied, and one on its way went on past the frames it '
        'had made', () async {
      final session = aSession();
      await aTurn();
      final started = walks(session);

      session.layerSwitches.toggleLayerVisibility(const LayerId('layer'));
      expect(started(), 0, reason: 'once the command is done');
      await aTurn();

      expect(started(), 1);
    });

    test('so does a row\'s opacity', () async {
      final session = aSession();
      await aTurn();
      final started = walks(session);

      session.opacityVerbs.setLayerOpacity(
        layerId: const LayerId('layer'),
        opacity: 0.5,
      );
      await aTurn();

      expect(started(), 1);
    });

    test('under a test\'s clock it stays out of it unless the test asks',
        () async {
      RenderCaches.walkFollowsHistory = false;
      final session = aSession();
      await aTurn();
      final started = walks(session);

      session.layerSwitches.toggleLayerVisibility(const LayerId('layer'));
      await aTurn();

      expect(started(), 0);
    });

    test('two changes in one turn start it over once', () async {
      final session = aSession();
      await aTurn();
      final started = walks(session);

      session.opacityVerbs.setLayerOpacity(
        layerId: const LayerId('layer'),
        opacity: 0.5,
      );
      session.layerSwitches.toggleLayerVisibility(const LayerId('layer'));
      await aTurn();

      expect(started(), 1);
    });

    test('a slider in flight only asks the walk to stand back: nothing is '
        'written until it lands', () async {
      final session = aSession();
      await aTurn();
      final started = walks(session);

      final scheduler = session.playbackRig.prerenderScheduler;
      final before = scheduler.lastEditActivity;
      // The wall clock's own step: told in the same one, nothing would show.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      session.opacityVerbs.previewLayerOpacity(const LayerId('layer'), 0.5);
      await aTurn();

      expect(started(), 0);
      expect(scheduler.lastEditActivity.isAfter(before), isTrue);

      session.opacityVerbs.commitLayerOpacity(const LayerId('layer'), 0.5);
      await aTurn();

      expect(started(), 1);
    });
  });
}
