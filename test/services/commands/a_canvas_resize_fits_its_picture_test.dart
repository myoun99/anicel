import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_picture_place.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart' show MediaFitMode;
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/commands/resize_cut_canvas_command.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/surface_rgba_in_place.dart';

/// 🗣️I-180: a canvas resize can fit the picture to the new canvas as an
/// import fits one — 비율 유지 늘림 · 비율 무시 늘림 — in the middle
/// (Q5 a), a drawing's cels laid anew by the canvas's own sampler (Q1 a)
/// and a reference's file kept 1:1, moved by whole pixels (F-374-Q1). Born,
/// the default, is the resize there always was.
///
/// The paper is 512 × 256 in the engine's tiles; a 4 × 4 square of ink
/// stands at (100, 60).
void main() {
  const canvas = CanvasSize(width: 512, height: 256);
  const side = defaultCelTileSize;
  const ink = 0xC80A0AFF;
  const drawnRow = LayerId('drawn');
  const referenceRow = LayerId('ref');
  const cutId = CutId('cut');

  BrushFrameKey cel(LayerId row) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: cutId,
    layerId: row,
    frameId: const FrameId('f'),
  );

  BitmapSurface inked() {
    final pixels = Uint8List(side * side * 4);
    for (var y = 60; y < 64; y += 1) {
      for (var x = 100; x < 104; x += 1) {
        final at = (y * side + x) * 4;
        pixels
          ..[at] = 0xC8
          ..[at + 1] = 0x0A
          ..[at + 2] = 0x0A
          ..[at + 3] = 0xFF;
      }
    }
    return BitmapSurface(canvasSize: canvas).putTiles([
      (
        coord: TileCoord(x: 0, y: 0),
        tile: BitmapTile(size: side, pixels: pixels),
      ),
    ]);
  }

  final reference = MediaReference(
    assetPath: 'a.png',
    pose: TransformPose(center: CanvasPoint(x: 256, y: 128)),
    pictureSize: canvas,
  );

  ProjectRepository repository() => ProjectRepository(
    initialProject: Project(
      id: const ProjectId('p'),
      name: 'P',
      tracks: [
        Track(
          id: const TrackId('t'),
          name: 'V',
          cuts: [
            Cut(
              id: cutId,
              name: 'C',
              layers: [
                Layer(
                  id: drawnRow,
                  name: 'D',
                  frames: const [],
                  timeline: const {},
                ),
                Layer(
                  id: referenceRow,
                  name: 'R',
                  frames: const [],
                  timeline: const {},
                  mediaReference: reference,
                ),
              ],
              duration: 24,
              canvasSize: canvas,
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    ),
  );

  ({
    ProjectRepository repository,
    BrushFrameStore store,
    ResizeCutCanvasCommand command,
  })
  fixture(CanvasSize to, MediaFitMode fit, {LayerId row = drawnRow}) {
    final repo = repository();
    final store = BrushFrameStore()..storeBakedSurface(cel(row), inked());
    return (
      repository: repo,
      store: store,
      command: ResizeCutCanvasCommand(
        repository: repo,
        cutId: cutId,
        canvasSize: to,
        place: PictureFittedBy(fit),
        brushFrameStore: store,
      ),
    );
  }

  Future<void> resize(ResizeCutCanvasCommand command) async {
    await command.workAhead(undo: false)!((_) {});
    command.execute();
  }

  int? at(BrushFrameStore store, int x, int y, {LayerId row = drawnRow}) =>
      surfaceRgbaInPlace(store.bakedSurfaceOrNull(cel(row))!, x, y);

  test('비율 무시 늘림 lays the drawing anew at twice its size, every pixel '
      'the one its centre lands on', () async {
    final (:store, :command, repository: _) = fixture(
      const CanvasSize(width: 1024, height: 512),
      MediaFitMode.stretch,
    );
    await resize(command);
    expect(at(store, 200, 120), ink);
    expect(at(store, 207, 127), ink);
    expect(at(store, 199, 120), 0);
    expect(at(store, 208, 127), 0);
    expect(at(store, 207, 128), 0);
    expect(
      store.bakedSurfaceOrNull(cel(drawnRow))!.canvasSize,
      const CanvasSize(width: 1024, height: 512),
    );
  });

  test('a photo on a fitted cel goes by the same map — its centre and its '
      'size', () async {
    final repo = repository();
    final store = BrushFrameStore()
      ..storeBakedSurface(
        cel(drawnRow),
        inked().withPhotos([
          CelPhoto(
            id: 1,
            reference: MediaReference(
              assetPath: 'p.png',
              pose: TransformPose(
                center: CanvasPoint(x: 50, y: 40),
                scaleX: 0.5,
                scaleY: 0.5,
              ),
              pictureSize: const CanvasSize(width: 20, height: 10),
            ),
          ),
        ]),
      );
    await resize(
      ResizeCutCanvasCommand(
        repository: repo,
        cutId: cutId,
        canvasSize: const CanvasSize(width: 1024, height: 512),
        place: const PictureFittedBy(MediaFitMode.stretch),
        brushFrameStore: store,
      ),
    );
    final pose = store
        .bakedSurfaceOrNull(cel(drawnRow))!
        .photos
        .single
        .reference
        .pose;
    expect(pose.center, CanvasPoint(x: 100, y: 80));
    expect((pose.scaleX, pose.scaleY), (1.0, 1.0));
  });

  test('비율 무시 늘림 scales each axis by its own factor', () async {
    final (:store, :command, repository: _) = fixture(
      const CanvasSize(width: 1024, height: 256),
      MediaFitMode.stretch,
    );
    await resize(command);
    expect(at(store, 200, 60), ink);
    expect(at(store, 207, 63), ink);
    expect(at(store, 207, 64), 0);
    expect(at(store, 208, 63), 0);
  });

  test('비율 유지 늘림 stands the picture in the middle of the new canvas, '
      'whatever its anchor', () async {
    final (:store, :command, repository: _) = fixture(
      const CanvasSize(width: 512, height: 512),
      MediaFitMode.contain,
    );
    await resize(command);
    expect(at(store, 100, 188), ink);
    expect(at(store, 103, 191), ink);
    expect(at(store, 100, 60), 0);
  });

  test('a reference\'s file stays laid 1:1, moved by whole pixels where the '
      'fit carries its centre, and its pose takes the scale', () async {
    final (:store, :command, :repository) = fixture(
      const CanvasSize(width: 1024, height: 512),
      MediaFitMode.stretch,
      row: referenceRow,
    );
    await resize(command);
    expect(at(store, 356, 188, row: referenceRow), ink);
    expect(at(store, 359, 191, row: referenceRow), ink);
    expect(at(store, 360, 191, row: referenceRow), 0);
    final moved = repository
        .requireProject()
        .tracks
        .single
        .cuts
        .single
        .layers
        .last
        .mediaReference!;
    expect(moved.laid, TransformPose(center: CanvasPoint(x: 512, y: 256)));
    expect(
      moved.pose,
      TransformPose(
        center: CanvasPoint(x: 512, y: 256),
        scaleX: 2,
        scaleY: 2,
      ),
    );
  });

  test('🚨a fit not laid ahead writes nothing and says so', () {
    final (:store, :command, :repository) = fixture(
      const CanvasSize(width: 1024, height: 512),
      MediaFitMode.stretch,
    );
    final before = repository.requireProject();
    final picture = store.bakedSurfaceOrNull(cel(drawnRow));
    expect(command.execute, throwsStateError);
    expect(identical(repository.requireProject(), before), isTrue);
    expect(identical(store.bakedSurfaceOrNull(cel(drawnRow)), picture), isTrue);
  });

  test('undo puts the picture back, and a redo laid ahead again fits it '
      'again', () async {
    final (:store, :command, repository: _) = fixture(
      const CanvasSize(width: 1024, height: 512),
      MediaFitMode.stretch,
    );
    final picture = store.bakedSurfaceOrNull(cel(drawnRow));
    await resize(command);
    command.undo();
    expect(store.bakedSurfaceOrNull(cel(drawnRow)), picture);
    await resize(command);
    expect(at(store, 200, 120), ink);
    expect(at(store, 208, 127), 0);
  });

  test('born — the default — is the resize there always was: the picture '
      'moved by its anchor, nothing in it changed', () async {
    final repo = repository();
    final store = BrushFrameStore()..storeBakedSurface(cel(drawnRow), inked());
    await resize(
      ResizeCutCanvasCommand(
        repository: repo,
        cutId: cutId,
        canvasSize: const CanvasSize(width: 1024, height: 512),
        place: const PictureMovedBy((dx: 256, dy: 128)),
        brushFrameStore: store,
      ),
    );
    expect(at(store, 356, 188), ink);
    expect(at(store, 359, 191), ink);
    expect(at(store, 360, 191), 0);
  });

  test('a fit to the canvas it is on takes no step, whatever offset the '
      'edges dragged say (I-180-Q6 a)', () {
    final project = createDefaultProject();
    final cut = project.tracks.first.cuts.first;
    final history = HistoryManager();
    final coordinator = CutCommandCoordinator(
      repository: ProjectRepository(initialProject: project),
      editingSession: EditingSessionState(activeCutId: cut.id),
      historyManager: history,
      brushFrameStore: BrushFrameStore(),
    );
    const dragged = PictureMovedBy((dx: 50, dy: 0));
    coordinator.placeCutCanvas(
      cutId: cut.id,
      canvasSize: cut.canvasSize,
      place: CanvasPicturePlace.under(MediaFitMode.stretch, dragged),
    );
    expect(history.undoCount, 0);
    coordinator.placeCutCanvas(
      cutId: cut.id,
      canvasSize: cut.canvasSize,
      place: CanvasPicturePlace.under(MediaFitMode.born, dragged),
    );
    expect(history.undoCount, 1, reason: 'born moves it where it is dragged');
  });
}
