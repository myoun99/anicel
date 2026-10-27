import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/draw_on_current_frame.dart';

/// 🚨THE GHOSTS A SCRUB CROSSES ARE MADE AHEAD, AS ITS FRAMES ARE (card
/// onion-scrub-rebuilds-the-ghost-each-step). The ghosts over a frame are a
/// picture of their own (`_ghostsOver`), and a picture is made ahead only
/// where the warmer's demand names it: named by none, every frame a scrub
/// crossed laid its ghosts on the spot — 🔬11520×7680 on a 3840² scene,
/// asked→back p50 131ms (10-28).
///
/// What the canvas stands on is what the warmer made: both stack the ghosts
/// through one function (`FramePictures.stackOf`), so here the ghosts of
/// every frame are asked of it, and found made.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const row = LayerId('row');

  // Three frames, each its own cel: every frame has a neighbour to ghost,
  // whichever side the pegs look.
  Cut threeCels() => Cut(
    id: const CutId('cut'),
    name: 'cut',
    duration: 3,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: row,
        name: 'A',
        frames: [
          for (var cel = 0; cel < 3; cel += 1)
            Frame(id: FrameId('f$cel'), duration: 1, strokes: const []),
        ],
        timeline: {
          for (var cel = 0; cel < 3; cel += 1)
            cel: TimelineExposure.drawing(FrameId('f$cel'), length: 1),
        },
      ),
    ],
  );

  EditorSessionManager inked() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(id: const TrackId('track'), name: 'T', cuts: [threeCels()]),
        ],
      ),
    );
    addTearDown(session.dispose);
    for (var cel = 0; cel < 3; cel += 1) {
      inkCel(
        session,
        session.brushFrameKeyForCut(
          session.requireActiveCut,
          row,
          FrameId('f$cel'),
        ),
        canvasSize: canvasSize,
        at: CanvasPoint(x: 2.0 + cel, y: 4),
        size: 3,
      );
    }
    return session;
  }

  DemandedPicture ghostsAt(EditorSessionManager session, int frame) => (
    cut: session.requireActiveCut,
    frameIndex: frame,
    paintPaper: false,
    ghosts: true,
  );

  /// Each row of a stack as a ghost reads: its cel, tint and opacity.
  List<(String, int?, double)> asGhosts(
    List<CompositeNode<CanvasStackRow>> nodes,
  ) => [
    for (final node in nodes)
      switch (node) {
        CompositeLeaf(payload: final CanvasLayerImageRequest ghost) => (
          ghost.frameKey.frameId.value,
          ghost.tint,
          ghost.opacity,
        ),
        _ => ('not a ghost: $node', null, -1),
      },
  ];

  Future<void> warmed(EditorSessionManager session) async {
    await Future<void>.delayed(Duration.zero);
    await session.playbackRig.prerenderScheduler.idle;
  }

  /// Every frame's ghosts stacked as the onion plans them, and made.
  void expectEveryFramesGhostsMade(EditorSessionManager session) {
    final pictures = session.playbackRig.framePictures;
    for (var frame = 0; frame < 3; frame += 1) {
      final ghosts = ghostsAt(session, frame);
      final planned = session.onionSkin.ghostsAt(
        session.requireActiveCut,
        frame,
      );
      expect(planned, isNotEmpty, reason: '⛔premise: frame $frame ghosts');
      expect(
        asGhosts(pictures.stackOf(ghosts)),
        [
          for (final ghost in planned)
            (ghost.frameKey.frameId.value, ghost.tint, ghost.opacity),
        ],
        reason: 'frame $frame: the ghosts are the onion\'s, not the frame',
      );
      expect(
        pictures.has(ghosts),
        isTrue,
        reason: 'frame $frame: its ghosts are made ahead of the scrub',
      );
    }
  }

  // A widget test, run for real: the pictures are images the engine makes.
  testWidgets('the onion turned on, every frame\'s ghosts are made ahead — '
      'stacked as the canvas stacks them', (tester) async {
    await tester.runAsync(() async {
      final session = inked();
      await warmed(session);

      session.onionSkin.toggleLayerOnionSkin(row);
      await warmed(session);

      expectEveryFramesGhostsMade(session);
    });
  });

  testWidgets('the pegs changed, the ghosts they plan are made ahead again', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = inked();
      session.onionSkin.toggleLayerOnionSkin(row);
      await warmed(session);
      final pictures = session.playbackRig.framePictures;
      final tinted = pictures.keyOf(ghostsAt(session, 1));

      session.onionSkin.settings.value = session.onionSkin.settings.value
          .copyWith(mode: OnionSkinMode.images);
      expect(
        pictures.keyOf(ghostsAt(session, 1)),
        isNot(tinted),
        reason: '⛔premise: untinted, the ghosts are another picture',
      );
      await warmed(session);

      expectEveryFramesGhostsMade(session);
    });
  });
}
