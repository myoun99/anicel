import 'dart:io';
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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart'
    show AnicelCelFileRef;
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/project_scratch_folder.dart';

/// 유저 2026-10-16 (frame-picture-indicator-Q1 b): 「a + 그 셀이 있는 타임라인
/// 칸에도 빨간 표시」 — for 「영영실패 … 아예 해동실패했을때 얘기잖아.
/// 디스크에 데이터가 없는상황」: a cel whose bytes the project's file does not
/// hold is red on the ruler's bar over the frames it shows, and its block is
/// red on the timeline.
///
/// The cel is kept as an opened project keeps one — a stretch of its file —
/// in a file that is not there, and read the way a run reads it.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const layerId = LayerId('layer');
  const frameId = FrameId('frame-a');

  /// One cel held across the cut's 24 frames, nothing after them.
  EditorSessionManager session() {
    final s = EditorSessionManager(
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
                duration: 24,
                canvasSize: canvasSize,
                layers: [
                  Layer(
                    id: layerId,
                    name: 'A',
                    frames: [
                      Frame(id: frameId, duration: 1, strokes: const []),
                    ],
                    timeline: {
                      0: const TimelineExposure.drawing(frameId, length: 24),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    return s;
  }

  BrushFrameKey celOf(EditorSessionManager s, [FrameId frame = frameId]) =>
      s.brushFrameKeyForCut(s.activeCutOrNull!, layerId, frame);

  /// [s]'s cel kept in a stretch of a file that is not there.
  Future<void> keepInAFileThatIsGone(EditorSessionManager s) async {
    final directory = await Directory.systemTemp.createTemp('qa-cel-gone');
    deleteAfterSessionEnds(directory);
    s.renderCaches.brushFrameStore.restoreFromFile({
      celOf(s): AnicelCelFileRef(
        filePath: '${directory.path}/gone.anicel',
        dataOffset: 0,
        length: 64,
        canvasSize: canvasSize,
        tileSize: 8,
        photoPaths: const [],
      ),
    });
  }

  /// The run's making of the cut's first frame — which reads the cel.
  Future<void> readTheCel(EditorSessionManager s) => expectLater(
    s.playbackRig.canvasPictures.make((
      cut: s.activeCutOrNull!,
      frameIndex: 0,
    ), shouldAbort: () => false),
    throwsA(anything),
    reason: '⛔CONTROL: the cel\'s bytes are not there to read',
  );

  testWidgets('🚨the ruler\'s bar is red over the frames that cel shows — the '
      'run does not wait for it', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      await keepInAFileThatIsGone(s);
      final budget = s.playbackRig.playbackCache;
      expect(
        budget.playbackReadyRuns(0, 30),
        [(startIndex: 24, endIndexExclusive: 30, unreadable: false)],
        reason: '⛔CONTROL: until something reads it, the hold waits for its '
            'picture like any other',
      );

      await readTheCel(s);

      expect(budget.playbackReadyRuns(0, 30), [
        (startIndex: 0, endIndexExclusive: 24, unreadable: true),
        (startIndex: 24, endIndexExclusive: 30, unreadable: false),
      ]);
    });
  });

  testWidgets('🚨and its block is red on the timeline — the rows told to look '
      'again', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      await keepInAFileThatIsGone(s);
      final stack = s.layerStack;
      final layer = s.layerById(layerId)!;
      expect(
        stack.celHasContentForLayer(layer, 0),
        isTrue,
        reason: '⛔the premise: a file cel says it is drawn by what it holds, '
            'so the grey says nothing of it',
      );
      expect(
        stack.celCannotBeReadForLayer(layer, 0),
        isFalse,
        reason: '⛔CONTROL: nothing has tried to read it yet',
      );
      final before = stack.celTintRevision.value;

      await readTheCel(s);

      expect(
        stack.celTintRevision.value,
        greaterThan(before),
        reason: 'the rows repaint when a cel is found unreadable — nothing '
            'else would tell them',
      );
      expect(
        [
          for (var frame = 0; frame < 30; frame += 1)
            if (stack.celCannotBeReadForLayer(layer, frame)) frame,
        ],
        [for (var frame = 0; frame < 24; frame += 1) frame],
        reason: 'the whole hold, and nothing past it',
      );
    });
  });

  testWidgets('🚨a drawing made elsewhere leaves it red — ↩️each new drawing '
      'read every unreadable cel again, and its red went out until it had', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = session();
      await keepInAFileThatIsGone(s);
      await readTheCel(s);
      final store = s.renderCaches.brushFrameStore;
      final generation = store.celContentRevision.value;

      // A cel nothing on the cut shows, drawn for the first time.
      store.storeBakedSurface(
        celOf(s, const FrameId('drawn-elsewhere')),
        BitmapSurface(
          canvasSize: canvasSize,
          tileSize: 8,
          tiles: {
            TileCoord(x: 0, y: 0): BitmapTile(
              size: 8,
              pixels: Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 0xFF),
            ),
          },
        ),
      );
      expect(
        store.celContentRevision.value,
        greaterThan(generation),
        reason: '⛔CONTROL: a cel crossed empty → drawn',
      );

      expect(
        s.layerStack.celCannotBeReadForLayer(s.layerById(layerId)!, 0),
        isTrue,
      );
      expect(s.playbackRig.playbackCache.playbackReadyRuns(0, 24), [
        (startIndex: 0, endIndexExclusive: 24, unreadable: true),
      ]);
    });
  });
}
