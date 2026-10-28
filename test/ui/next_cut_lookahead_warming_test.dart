
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_cache_invalidation.dart';
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
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../helpers/draw_on_current_frame.dart';

/// #31 — 스토리보드는 액티브 컷만 굽는다, 남은 절반 (유저 확정: 스토리보드
/// 프로 따라서). The session's warm restart carries the NEXT cut in
/// storyboard order behind the active one, so entering that cut plays from
/// cache — without the user ever having activated it.
///
/// ⚠️What it makes is what a run of the cut shows — the canvas's own
/// pictures since playback-plays-the-screen-material — so it is the
/// timeline's bar, on entering, that is green; the storyboard's counts the
/// film's composites (`storyboard_ready_runs_test`).
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  Cut cutNamed(String id, String layerId, String frameId) => Cut(
    id: CutId(id),
    name: id,
    duration: 2,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: LayerId(layerId),
        name: layerId,
        frames: [
          Frame(id: FrameId(frameId), duration: 1, strokes: const []),
        ],
        timeline: {0: TimelineExposure.drawing(FrameId(frameId), length: 1)},
      ),
    ],
  );

  // A widget test, run for real: the canvas's pictures are images the
  // engine makes, which a bare `test` never gets.
  testWidgets('a warm restart on the FIRST cut makes the SECOND cut\'s '
      'pictures without it ever being activated', (tester) async {
    await tester.runAsync(() async {
      final first = cutNamed('cut-1', 'layer-1', 'frame-1');
      final second = cutNamed('cut-2', 'layer-2', 'frame-2');
      final session = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'P',
          createdAt: DateTime.utc(2026),
          tracks: [
            Track(id: const TrackId('track'), name: 'T', cuts: [first, second]),
          ],
        ),
      );
      addTearDown(session.dispose);
      expect(
        session.activeCutOrNull!.id,
        const CutId('cut-1'),
        reason: 'fixture',
      );

      // Content for both cuts, on the cel's own tiles. ↩️A hand-made 4px
      // tile stood in for a cel: a composite could be made of it, a layer
      // image cannot, and the warm gave it up.
      final firstKey = session.brushFrameKeyForCut(
        session.activeCutOrNull!,
        const LayerId('layer-1'),
        const FrameId('frame-1'),
      );
      for (final key in [
        firstKey,
        session.brushFrameKeyForCut(
          second,
          const LayerId('layer-2'),
          const FrameId('frame-2'),
        ),
      ]) {
        inkCel(
          session,
          key,
          canvasSize: canvasSize,
          at: CanvasPoint(x: 4, y: 4),
          size: 4,
        );
      }

      // One edit-burst invalidation: the debounced restart rebuilds the warm
      // order — which must now carry cut-2 behind cut-1.
      session.renderCaches.cacheInvalidationHub.invalidateBrushFrame(
        BrushFrameCacheInvalidation(frameKey: firstKey, wholeFrame: true),
      );
      // Debounce trailing edge, then the run itself.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await session.playbackRig.prerenderScheduler.idle;

      // What a run of the cut would show, as the screen counts it — the
      // canvas's own pictures since playback-plays-the-screen-material.
      bool made(Cut cut) =>
          session.playbackRig.framePictures.has((cut: cut, frameIndex: 0, paintPaper: true));
      expect(made(first), isTrue, reason: 'the active cut warms first');
      expect(
        made(second),
        isTrue,
        reason: '#31: the next cut in storyboard order warms behind the '
            'active one — moving there must not be the thing that starts '
            'the bake',
      );
    });
  });
}
