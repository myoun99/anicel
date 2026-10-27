import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_mode.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

import '../../helpers/cels_kept_in_a_file.dart';

/// 🚨WHAT THE WALK MADE, THE BUDGET KEEPS (F-365, 유저 2026-10-15, iPad ·
/// AMMI OP: 「재생전 렌더링은 3번컷 처음부분에서 막혀서 그이후로 재생해도
/// 재생안되고」 — gone with the allowance raised from 2500 to 5000).
///
/// The warmer asks for room before it makes a picture, by what the picture
/// is weighed as — a row whose cel is not read yet, as its canvas: a
/// picture asked for ahead (playback-picture-weight-estimates) — and the
/// budget trimmed after it landed by what it did weigh. A row inked out
/// onto the pasteboard weighs more than its canvas: the trim let go of the
/// picture just made — the one wanted latest — the walk found it missing,
/// made it again, and so on for good. A walk that never rests is a run that
/// renders first standing for good.
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

  /// [cuts]' cels kept as an opened project keeps them — in its file, not
  /// read yet — each inked past every edge of its canvas: its picture is
  /// bigger than the canvas a row is weighed as before it is read.
  void keepInkedPastEveryEdge(EditorSessionManager s, List<Cut> cuts) {
    BitmapTile inked() => BitmapTile(
      size: 4,
      pixels: Uint8List.fromList([
        for (var i = 0; i < 4 * 4; i += 1) ...[0, 0, 0, 255],
      ]),
    );
    keepInAFile(s.renderCaches.brushFrameStore, {
      for (final cut in cuts)
        celOf(s, cut): BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 4,
          tiles: {
            for (var y = -1; y <= 1; y += 1)
              for (var x = -1; x <= 1; x += 1) TileCoord(x: x, y: y): inked(),
          },
        ),
    });
  }

  testWidgets('🚨a picture bigger than the room it was made in stays: the '
      'walk comes to rest, and a run that renders first goes on', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = session();
      final rig = s.playbackRig;
      final pictures = s.renderCaches.framePictureStore;
      final cuts = [
        for (final id in ['cut-1', 'cut-2', 'cut-3']) s.cutById(CutId(id))!,
      ];
      DemandedPicture headOf(Cut cut) =>
          (cut: cut, frameIndex: 0, paintPaper: true, ghosts: false);
      keepInkedPastEveryEdge(s, cuts);
      await rig.prerenderScheduler.idle;
      // Nothing made but the first cut's picture, the one the run is put on.
      rig.prerenderScheduler.cancel();
      pictures.enforceBudget(maxBytes: 0, wantedAt: (_) => null);
      await rig.framePictures.make(
        headOf(cuts.first),
        shouldAbort: () => false,
      );
      final made = pictures.bytesOf(rig.framePictures.keyOf(headOf(cuts[0])))!;
      final estimated = rig.framePictures.bytesToMake(headOf(cuts[2]));
      expect(
        made,
        greaterThan(estimated),
        reason: 'premise: a cel not read yet is weighed as its canvas, and '
            'its ink past the canvas weighs more',
      );
      // Room for the second picture by its weight — the walk reads it first
      // — and for the third, asked for ahead, by its estimate: none for the
      // third by its weight.
      final line = 2 * made + estimated + (made - estimated) ~/ 2;
      rig.playbackCache.playbackCacheByteBudget = line;
      expect(pictures.estimatedBytes, made, reason: 'premise');

      // The walk comes to rest — or, making and letting go of the same
      // pictures, lands more of them than there are to make: whichever is
      // seen first is the answer, and no wall clock is asked.
      final settled = Completer<bool>();
      var landed = 0;
      rig.prerenderScheduler.landings.addListener(() {
        landed += 1;
        if (landed > 4 && !settled.isCompleted) {
          settled.complete(false);
        }
      });
      rig.setPlaybackMode(PlaybackMode.renderFirst);
      rig.playback.play(scope: PlaybackScope.allCuts, startGlobalFrame: 0);
      expect(rig.playbackCache.playbackCacheByteBudget, line, reason: 'seam');

      unawaited(
        rig.prerenderScheduler.idle.then((_) {
          if (!settled.isCompleted) {
            settled.complete(true);
          }
        }),
      );
      final rested = await settled.future;
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
        rig.framePictures.has(headOf(cuts[1])),
        isTrue,
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
