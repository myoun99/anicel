import 'package:anicel/src/models/brush_frame_key.dart';
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
import 'package:anicel/src/native/app_gpu_engine.dart'
    show letTheGoneAppGpuEngineGo;
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/the_apps_engine_let_go.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — and what the device took of a
/// cel is told as every other emptying is, as the app lets it go
/// (`BrushFrameStore.recordWhatWentWithTheDevice`).
///
/// ⚠️Each test loses the app's engine: the tests after it find the next.
void main() {
  const canvas = CanvasSize(width: 256, height: 256);

  /// A session of one cut whose row shows cel `a`, then cel `b` — both
  /// inked, nothing of either copied here yet: the engine holds the only
  /// copy of each.
  EditorSessionManager twoInkedCels() {
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
                duration: 4,
                canvasSize: canvas,
                layers: [
                  Layer(
                    id: const LayerId('layer'),
                    name: 'A',
                    frames: [
                      Frame(
                        id: const FrameId('a'),
                        duration: 1,
                        strokes: const [],
                      ),
                      Frame(
                        id: const FrameId('b'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: {
                      0: const TimelineExposure.drawing(
                        FrameId('a'),
                        length: 2,
                      ),
                      2: const TimelineExposure.drawing(
                        FrameId('b'),
                        length: 2,
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
    for (final cel in ['a', 'b']) {
      inkCel(
        s,
        celOf(s, cel),
        canvasSize: canvas,
        at: CanvasPoint(x: 128, y: 128),
        size: 40,
      );
    }
    return s;
  }

  testWidgets('a cel that held nothing but what the device took is told '
      'crossed to empty as the app lets the device go', (tester) async {
    await tester.runAsync(() async {
      final s = twoInkedCels();
      addTearDown(s.dispose);
      final cels = s.renderCaches.brushFrameStore;
      final both = {celOf(s, 'a'), celOf(s, 'b')};
      expect(
        both.map(cels.celHasRenderableContent),
        [true, true],
        reason: '⛔premise: both drawn',
      );
      final told = cels.celContentRevision.value;

      theAppsEngineLostAndLetGo();

      expect(cels.celContentRevision.value, told + 1);
      expect(cels.celsLastCrossed, both);
      expect(both.map(cels.celHasRenderableContent), [false, false]);
    });
  });

  testWidgets('every cel store of the session is told — each sheet\'s ink '
      'as the drawings\'', (tester) async {
    await tester.runAsync(() async {
      final s = twoInkedCels();
      addTearDown(s.dispose);
      final sheets = s.renderCaches.sheetInkStores;
      final cel = celOf(s, 'a');
      for (final sheet in sheets) {
        inkCelIn(
          sheet,
          cel,
          canvasSize: canvas,
          at: CanvasPoint(x: 128, y: 128),
          size: 40,
        );
      }
      final told = [
        for (final sheet in sheets) sheet.celContentRevision.value,
      ];

      theAppsEngineLostAndLetGo();

      expect(
        [for (final sheet in sheets) sheet.celContentRevision.value],
        [for (final was in told) was + 1],
      );
      expect(
        sheets.map((sheet) => sheet.celHasRenderableContent(cel)),
        everyElement(isFalse),
      );
    });
  });

  testWidgets("a frame's key follows: kept over a row whose cel the device "
      'took, it draws no row once the app lets the device go', (tester) async {
    await tester.runAsync(() async {
      final s = twoInkedCels();
      addTearDown(s.dispose);
      final frames = s.playbackRig.framePictures;
      final second = (
        cut: s.activeCutOrNull!,
        frameIndex: 2,
        paintPaper: true,
        ghosts: FrameGhosts.none,
      );
      expect(
        frames.keyOf(second).signature.nodes,
        isNotEmpty,
        reason: '⛔premise: kept over its row',
      );

      theAppsEngineLostAndLetGo();

      expect(frames.keyOf(second).signature.nodes, isEmpty);
    });
  });

  testWidgets('every cel is recorded, not only one the device still holds '
      'the only copy of: one read between the loss and the letting go was '
      'told no crossing', (tester) async {
    await tester.runAsync(() async {
      final s = twoInkedCels();
      addTearDown(s.dispose);
      final cels = s.renderCaches.brushFrameStore;
      final b = celOf(s, 'b');
      final told = cels.celContentRevision.value;

      theAppsEngineLost();
      final tiles = cels.bakedSurfaceOrNull(b)!.tiles;
      for (final tile in tiles.values) {
        expect(tile.pixels.every((byte) => byte == 0), isTrue);
      }
      expect(
        tiles.values.where((tile) => tile.isOnlyOnEngine),
        isEmpty,
        reason: '⛔premise: read as the picture each landed on',
      );
      expect(cels.celContentRevision.value, told, reason: '⛔premise');

      letTheGoneAppGpuEngineGo();

      expect(cels.celsLastCrossed, contains(b));
      expect(cels.celHasRenderableContent(b), isFalse);
    });
  });
}

/// [s]'s cel [frame] of the row `layer`.
BrushFrameKey celOf(EditorSessionManager s, String frame) =>
    s.brushFrameKeyForCut(
      s.requireActiveCut,
      const LayerId('layer'),
      FrameId(frame),
    );
