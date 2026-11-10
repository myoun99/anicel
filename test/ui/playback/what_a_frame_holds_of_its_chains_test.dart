import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
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
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/diagnostics/memory_census.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';

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

  /// Laid for a screen to show, [keepsNodes] where a canvas stands on it.
  Future<void> shown(
    EditorSessionManager s,
    DemandedPicture picture, {
    bool keepsNodes = true,
  }) {
    final pictures = s.playbackRig.framePictures;
    return pictures.makeShown(
      pictures.stackOf(picture),
      picture,
      shouldAbort: () => false,
      keepsNodes: keepsNodes,
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
      await shown(still, drawn(still), keepsNodes: false);
      final held = still.playbackRig.framePictures;
      expect(held.aheadNodes.heldBytes, greaterThan(0), reason: 'nothing live');
      expect(held.heldNodes.heldBytes, 0);
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
      int censused() => collectMemoryCensus([s]).items
          .firstWhere((item) => item.id == 'framePictures')
          .bytes;
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
