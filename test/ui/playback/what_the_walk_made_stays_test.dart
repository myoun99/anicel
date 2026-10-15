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
import 'package:anicel/src/models/playback_mode.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/rgba_image_bytes.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

/// 🚨WHAT THE WALK MADE, THE BUDGET KEEPS (F-365, 유저 2026-10-15, iPad ·
/// AMMI OP: 「재생전 렌더링은 3번컷 처음부분에서 막혀서 그이후로 재생해도
/// 재생안되고」 — gone with the allowance raised from 2500 to 5000).
///
/// The warmer asks for room before it makes a picture, by what the picture
/// is estimated to weigh — a canvas's worth a row — and the budget trimmed
/// after it landed by what it did weigh. A row inked out onto the
/// pasteboard weighs more than its canvas: the trim let go of the picture
/// just made — the one wanted latest — the walk found it missing, the room
/// let it in again by its estimate, and so on for good. A walk that never
/// rests is a run that renders first standing for good.
void main() {
  const canvasSize = CanvasSize(width: 6, height: 6);

  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 2,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: LayerId('$id-layer'),
        name: 'A',
        frames: [
          Frame(id: FrameId('$id-cel'), duration: 2, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('$id-cel'), length: 2),
        },
      ),
    ],
  );

  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('walk'),
        name: 'Walk',
        createdAt: DateTime.utc(2026, 10, 15),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [cut('cut-1'), cut('cut-2'), cut('cut-3')],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    return s;
  }

  BrushFrameKey celOf(EditorSessionManager s, Cut cut) => s.brushFrameKeyForCut(
    cut,
    LayerId('${cut.id.value}-layer'),
    FrameId('${cut.id.value}-cel'),
  );

  /// A dab past every edge of [cut]'s canvas: its ink, and so its picture,
  /// is bigger than the canvas a row's room is asked by.
  void draw(EditorSessionManager s, Cut cut) {
    BrushFrameEditingCoordinator(
      initialFrameKey: celOf(s, cut),
      frameStore: s.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: 4,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 3, y: 3),
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

  testWidgets('🚨a picture bigger than the room it was made in stays: the '
      'walk comes to rest, and a run that renders first goes on', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = session();
      final rig = s.playbackRig;
      final images = s.renderCaches.layerFrameImageCache;
      final cuts = [
        for (final id in ['cut-1', 'cut-2', 'cut-3']) s.cutById(CutId(id))!,
      ];
      for (final cut in cuts) {
        draw(s, cut);
      }
      await rig.prerenderScheduler.idle;
      // Nothing made but the first cut's picture, the one the run is put on.
      rig.prerenderScheduler.cancel();
      images.enforceBudget(maxBytes: 0);
      await rig.canvasPictures.make((
        cut: cuts.first,
        frameIndex: 0,
      ), shouldAbort: () => false);
      final first = images.validImageOrNull(
        celOf(s, cuts.first),
        PlaybackQuality.full,
        canvasSize: canvasSize,
        sourceEffects: const [],
      )!;
      final made = estimatedImageBytes(first.image.width, first.image.height);
      final estimated = rig.canvasPictures.bytesToMake((
        cut: cuts[1],
        frameIndex: 0,
      ));
      expect(
        made,
        greaterThan(estimated),
        reason: 'premise: ink past the canvas weighs more than the canvas',
      );
      // Room for the second picture by its estimate, none by its weight.
      final line = made + estimated + (made - estimated) ~/ 2;
      rig.playbackCache.playbackCacheByteBudget = line;
      expect(images.estimatedBytes, made, reason: 'premise');

      var landed = 0;
      rig.prerenderScheduler.landings.addListener(() => landed += 1);
      rig.setPlaybackMode(PlaybackMode.renderFirst);
      rig.playback.play(scope: PlaybackScope.allCuts, startGlobalFrame: 0);
      expect(rig.playbackCache.playbackCacheByteBudget, line, reason: 'seam');

      final rested = await Future.any([
        rig.prerenderScheduler.idle.then((_) => true),
        Future<bool>.delayed(const Duration(seconds: 3), () => false),
      ]);
      expect(
        rested,
        isTrue,
        reason: 'the walk comes to rest — $landed pictures landed',
      );
      expect(
        landed,
        lessThanOrEqualTo(2),
        reason: 'the second cut\'s picture and the third\'s, each once',
      );
      expect(
        images.validImageOrNull(
          celOf(s, cuts[1]),
          PlaybackQuality.full,
          canvasSize: canvasSize,
          sourceEffects: const [],
        ),
        isNotNull,
        reason: 'what the walk made, the budget keeps',
      );
      expect(
        rig.playback.isWaiting,
        isFalse,
        reason: 'a run that renders first goes on once the walk rests',
      );
    });
  });
}
