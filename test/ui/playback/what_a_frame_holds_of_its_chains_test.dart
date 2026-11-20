import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show Color, GlobalKey, Row, Size, SizedBox, Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart' show EnginePictures;
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/a_fill_on_a_session.dart';
import '../../helpers/settle_async.dart';

/// 🚨★WHAT A FRAME'S CHAINS PUT IS HELD WHERE ITS SCREEN STANDS
/// (`FramePictures.heldNodes` · `aheadNodes`; card
/// paint-walk-redoes-the-same-work-each-step): laid for the canvas that
/// stands on it a blurred folder is held for its strokes' steps; laid ahead
/// of a screen, or for one that draws nothing live, for the frames after it
/// — apart, each in its own room on the playback line (🗣️유저 2026-10-27,
/// Q3 = c: 「위 폴더는 하나씩, 메모리 몫 안에서 전부」; 🔬S5_BA cut 353 on the
/// Surface, 29.9–30.8 s → 8.0–8.5 s with the folder held). What a held chain
/// lays is the engine's to answer
/// (`the_engine_holds_what_a_chain_put_test`).
void main() {
  opensTheEnginesScreens();
  const canvasSize = CanvasSize(width: 32, height: 24);

  /// The row of cel `a-0` held for two frames, or [turning] to `a-1` at
  /// the second.
  Layer row(String id, {LayerId? folder, bool turning = false}) => Layer(
    id: LayerId(id),
    name: id,
    folderId: folder,
    frames: [
      for (final cel in turning ? const ['0', '1'] : const ['0'])
        Frame(id: FrameId('$id-$cel'), duration: 1, strokes: const []),
    ],
    timeline: turning
        ? {
            0: TimelineExposure.drawing(FrameId('$id-0'), length: 1),
            1: TimelineExposure.drawing(FrameId('$id-1'), length: 1),
          }
        : {0: TimelineExposure.drawing(FrameId('$id-0'), length: 2)},
  );

  EditorSessionManager session({bool turning = false}) {
    const folder = LayerId('folder');
    return EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('held'),
        name: 'Held',
        createdAt: DateTime.utc(2026, 10, 27),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: 'cut',
                duration: 2,
                canvasSize: canvasSize,
                layers: [
                  row('a', folder: folder, turning: turning),
                  createFolderLayer(id: folder, name: 'F').copyWith(
                    effects: [
                      LayerEffect(
                        id: const EffectId('blur'),
                        kind: EffectKind.blur,
                        parameters: {
                          'blurriness': EffectParameter(value: 3),
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// [s] with the cels of its row drawn, each its own, and the frame [at].
  DemandedPicture drawn(EditorSessionManager s, {int at = 0}) {
    final cut = s.requireActiveCut;
    for (final (index, frame) in cut.layers.first.frames.indexed) {
      BrushFrameEditingCoordinator(
        initialFrameKey: s.brushFrameKeyForCut(
          cut,
          const LayerId('a'),
          frame.id,
        ),
        frameStore: s.renderCaches.brushFrameStore,
        sessionStore: BrushFrameEditSessionStore(canvasSize: canvasSize),
        historyPolicy: const BrushHistoryPolicy(),
      ).commitSourceStroke(
        sourceDabs: [
          BrushDab(
            center: CanvasPoint(x: 8.0 + 8 * index, y: 12),
            color: 0xFF000000,
            size: 10,
            opacity: 1,
            flow: 1,
            hardness: 1,
            tipShape: BrushTipShape.square,
            pressure: 1,
            sequence: 0,
          ),
        ],
      );
    }
    return (
      cut: s.requireActiveCut,
      frameIndex: at,
      paintPaper: true,
      ghosts: FrameGhosts.none,
    );
  }

  /// Laid for a screen to show — for [s]'s canvas, standing on it to
  /// draw, where it [drawsLive].
  Future<void> shown(
    EditorSessionManager s,
    DemandedPicture picture, {
    bool drawsLive = true,
  }) {
    final pictures = s.playbackRig.framePictures;
    return pictures.makeShown(
      pictures.stackOf(picture),
      picture,
      shouldAbort: () => false,
      canvas: drawsLive ? s : null,
    );
  }

  testWidgets('laid for the canvas that stands on it the chains are held '
      'for its steps; laid ahead, or for a screen that draws nothing live, '
      'for the frames after it', (tester) async {
    await tester.runAsync(() async {
      final standing = session();
      addTearDown(standing.dispose);
      await shown(standing, drawn(standing));
      final stood = standing.playbackRig.framePictures;
      expect(stood.heldNodes.heldBytes, greaterThan(0), reason: 'for its pen');
      expect(stood.aheadNodes.heldBytes, 0);

      final ahead = session();
      addTearDown(ahead.dispose);
      final made = ahead.playbackRig.framePictures;
      await made.make(drawn(ahead), shouldAbort: () => false);
      expect(made.aheadNodes.heldBytes, greaterThan(0), reason: 'for the next');
      expect(made.heldNodes.heldBytes, 0);

      final still = session();
      addTearDown(still.dispose);
      await shown(still, drawn(still), drawsLive: false);
      final held = still.playbackRig.framePictures;
      expect(held.aheadNodes.heldBytes, greaterThan(0), reason: 'nothing live');
      expect(held.heldNodes.heldBytes, 0);
    });
  });

  /// Frame [frame] of [s]'s cut, drawn ([drawn]) — on its paper.
  DemandedPicture frameAt(EditorSessionManager s, int frame) => (
    cut: s.requireActiveCut,
    frameIndex: frame,
    paintPaper: true,
    ghosts: FrameGhosts.none,
  );

  /// What a canvas holds, stood on [frames] of a cut whose cel turns, in
  /// turn.
  Future<int> heldOn(List<int> frames) async {
    final s = session(turning: true);
    addTearDown(s.dispose);
    drawn(s);
    for (final frame in frames) {
      await shown(s, frameAt(s, frame));
    }
    return s.playbackRig.framePictures.heldNodes.heldBytes;
  }

  // 🗣️유저 2026-10-27, Q3 = c: 「다른 프레임으로 가면 놓는다」
  // (`EngineChainHolds.settleOnce`).
  testWidgets('🚨the canvas gone on to another frame holds that one\'s '
      'folder alone', (tester) async {
    await tester.runAsync(() async {
      final alone = await heldOn([1]);
      expect(alone, greaterThan(0), reason: '⛔premise: held');
      expect(await heldOn([0, 1]), alone);
    });
  });

  // The canvas a view is to what is held (`FramePictureView.standsAs`):
  // the conte's pictures stand on frames of their own beside the canvas,
  // on its holds (브러시/렌더링 2026-11-20).
  testWidgets('🚨views drawing live on frames of their own each hold their '
      'own, and one gone lets go of its own', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final alone = (await tester.runAsync(
      () async => [await heldOn([0]), await heldOn([1])],
    ))!;
    final s = session(turning: true);
    addTearDown(s.dispose);
    drawn(s);
    final pictures = s.playbackRig.framePictures;
    final run = (
      landings: s.playbackRig.prerenderScheduler.landings,
      pictures: pictures,
    );
    Widget viewOn(int frame) => SizedBox(
      width: canvasSize.width.toDouble(),
      height: canvasSize.height.toDouble(),
      child: standingOn(
        run,
        picture: frameAt(s, frame),
        nodes: pictures.stackOf(frameAt(s, frame)),
        viewport: CanvasViewport(),
        live: (
          activeSurfacePainter: BitmapSurfacePainter(
            surface: BitmapSurface(canvasSize: canvasSize, tileSize: 16),
            showTransparentBackground: false,
            lineage: 'a view on frame $frame',
          ),
          floatOverlay: null,
          liftedRows: const {},
        ),
      ),
    );
    final screen = GlobalKey();
    Widget views({required bool both}) => onAScreen(
      screen,
      size: Size(2.0 * canvasSize.width, canvasSize.height.toDouble()),
      under: const Color(0xFF000000),
      view: Row(children: [viewOn(0), if (both) viewOn(1)]),
    );

    await tester.pumpWidget(views(both: true));
    expect(
      await settleAsync(
        tester,
        () => pictures.heldNodes.heldBytes == alone[0] + alone[1],
      ),
      isTrue,
      reason: 'each its own',
    );
    await tester.pumpWidget(views(both: false));
    expect(
      await settleAsync(
        tester,
        () => pictures.heldNodes.heldBytes == alone[0],
      ),
      isTrue,
      reason: 'the one gone, its own let go of',
    );
    await tester.pumpWidget(const SizedBox());
  });

  // What a fill reads is the frame's rows planned as a screen's are
  // (`fillPictureOf`), its chains' puts held among the canvas's (mutants
  // FD05 · FD20 lived on every fill's pins, 2026-11-12: with no hold a
  // press runs each chain again, and shows the same).
  testWidgets('a fill pressed on the frame holds its chains where the '
      'canvas that stands on it does: what the first press put, and one '
      'hold with the canvas\'s', (tester) async {
    await tester.runAsync(() async {
      final pressed = session();
      addTearDown(pressed.dispose);
      drawn(pressed);
      expect(
        fillPressedOn(pressed, CanvasPoint(x: 30, y: 2)),
        isNotNull,
        reason: '⛔premise: it read a picture',
      );
      final first = pressed.playbackRig.framePictures;
      final held = first.heldNodes.heldBytes;
      expect(held, greaterThan(0));
      expect(first.aheadNodes.heldBytes, 0);

      final stood = session();
      addTearDown(stood.dispose);
      await shown(stood, drawn(stood));
      final both = stood.playbackRig.framePictures;
      expect(both.heldNodes.heldBytes, held, reason: '⛔premise: the same put');
      fillPressedOn(stood, CanvasPoint(x: 30, y: 2));
      expect(both.heldNodes.heldBytes, held);
    });
  });

  testWidgets('a folder the next frame shows the same is held once', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final pictures = s.playbackRig.framePictures;
      final first = drawn(s);
      await pictures.make(first, shouldAbort: () => false);
      final once = pictures.aheadNodes.heldBytes;
      expect(once, greaterThan(0), reason: '⛔premise: held');

      final next = (
        cut: first.cut,
        frameIndex: 1,
        paintPaper: false,
        ghosts: FrameGhosts.none,
      );
      await pictures.make(next, shouldAbort: () => false);
      expect(pictures.aheadNodes.heldBytes, once);
    });
  });

  testWidgets('⚖️the chains laid ahead take what the line has free beside '
      'the pictures: past it the one used longest ago goes', (tester) async {
    await tester.runAsync(() async {
      /// What is held and what the pictures weigh, the two frames of cels
      /// of their own laid ahead on a line of [budget].
      Future<({int ahead, int pictures})> on(int? budget) async {
        final s = session(turning: true);
        addTearDown(s.dispose);
        if (budget != null) {
          s.playbackRig.playbackCache.debugSetPlaybackCacheBudgetBytes(budget);
        }
        final pictures = s.playbackRig.framePictures;
        final first = drawn(s);
        await pictures.make(first, shouldAbort: () => false);
        await pictures.make(
          (
            cut: first.cut,
            frameIndex: 1,
            paintPaper: true,
            ghosts: FrameGhosts.none,
          ),
          shouldAbort: () => false,
        );
        return (
          ahead: pictures.aheadNodes.heldBytes,
          pictures: s.renderCaches.framePictureStore.estimatedBytes,
        );
      }

      final wide = await on(null);
      expect(wide.ahead, greaterThan(0), reason: '⛔premise');

      final narrow = await on(wide.pictures + wide.ahead - 1);
      expect(narrow.pictures, wide.pictures, reason: '⛔premise');
      expect(narrow.ahead, lessThan(wide.ahead));
      expect(narrow.ahead, greaterThan(0), reason: 'the last stays');
    });
  });

  testWidgets('🚨what is held comes off the playback line, is counted with '
      'the frames\' pictures, and goes at a memory warning and with the '
      'session', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      final pictures = s.playbackRig.framePictures;
      final line = s.playbackRig.playbackCache;
      final picture = drawn(s);
      final budget = line.playbackCacheByteBudget;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // The row less what no picture holds: a picture goes into a slot the
      // engine keeps made (engine-pictures-keep-to-pool-pages), and one
      // that stood idle the row counted before it.
      int censused() =>
          collectMemoryCensus([s]).items
              .firstWhere((item) => item.id == 'framePictures')
              .bytes -
          EnginePictures.idlePictureBytes;
      final before = censused();
      debugDefaultTargetPlatformOverride = null;

      await shown(s, picture);
      final held = pictures.heldNodes.heldBytes;
      expect(held, greaterThan(0), reason: '⛔premise: the folder is held');

      expect(line.bytes, budget - held);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(
        censused() - before,
        held + s.renderCaches.framePictureStore.estimatedBytes,
      );
      debugDefaultTargetPlatformOverride = null;

      line.respondToMemoryPressure();
      expect(pictures.heldBytes, 0);

      await shown(s, (
        cut: picture.cut,
        frameIndex: 0,
        paintPaper: false,
        ghosts: FrameGhosts.none,
      ));
      expect(pictures.heldBytes, greaterThan(0), reason: '⛔premise');
      s.dispose();
      expect(pictures.heldBytes, 0);
    });
  });
}
