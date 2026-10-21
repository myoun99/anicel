import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cels_kept_in_a_file.dart';

/// 🔬Card `a-canvas-resize-rewrites-kept-cels-on-the-ui-thread`: what a
/// resize works out ahead is what its step will take — the same cuts, the
/// same move — and where the step is no step, nothing is worked out.
void main() {
  ({
    CutCommandCoordinator coordinator,
    BrushFrameStore store,
    CutId cut,
    CanvasSize size,
    BrushFrameKey kept,
  })
  fixture() {
    final project = createDefaultProject();
    final cut = project.tracks.first.cuts.first;
    final store = BrushFrameStore();
    final kept = BrushFrameKey(
      projectId: const ProjectId('p'),
      trackId: const TrackId('t'),
      cutId: cut.id,
      layerId: const LayerId('l'),
      frameId: const FrameId('kept'),
    );
    // Tiles of 8: the moves below are of no whole tile.
    keepInAFile(store, {
      kept: BitmapSurface(canvasSize: cut.canvasSize, tileSize: 8).putTiles([
        (
          coord: TileCoord(x: 1, y: 1),
          tile: BitmapTile(
            size: 8,
            pixels: Uint8List(256)..fillRange(0, 256, 50),
          ),
        ),
      ]),
    });
    return (
      coordinator: CutCommandCoordinator(
        repository: ProjectRepository(initialProject: project),
        editingSession: EditingSessionState(activeCutId: cut.id),
        historyManager: HistoryManager(),
        brushFrameStore: store,
      ),
      store: store,
      cut: cut.id,
      size: cut.canvasSize,
      kept: kept,
    );
  }

  test('a place that is no step works nothing out', () async {
    final f = fixture();
    await f.coordinator.placeCutCanvasAhead(
      cutId: f.cut,
      canvasSize: f.size,
      contentOffset: (dx: 0.4, dy: -0.4),
    );
    expect(
      f.store.hotBakedSurfaceOrNull(f.kept),
      isNull,
      reason: 'not even thawed: the step will not be taken',
    );
  });

  test('a place works out the move its step takes', () async {
    final f = fixture();
    await f.coordinator.placeCutCanvasAhead(
      cutId: f.cut,
      canvasSize: f.size,
      contentOffset: (dx: 9.6, dy: 0),
    );
    expect(f.store.movedAheadOf(f.kept), isNotNull);
    f.coordinator.placeCutCanvas(
      cutId: f.cut,
      canvasSize: f.size,
      contentOffset: (dx: 9.6, dy: 0),
    );
    expect(f.store.celsMovedHere, 0);
  });

  // Linked cuts show ONE physical cel, kept under one of them: a resize of
  // the other moves it all the same, and so does what is worked out ahead.
  test('a resize of a 겸용 cut works out the cels it shares', () async {
    const track = TrackId('track');
    const cutWithCels = CutId('cut-1');
    const linked = CutId('cut-2');
    const size = CanvasSize(width: 40, height: 24);
    Cut cut(CutId id, LayerId layer) => Cut(
      id: id,
      name: id.value,
      layers: [Layer(id: layer, name: 'A', frames: const [])],
      duration: 12,
      canvasSize: size,
    );
    final project = Project(
      id: const ProjectId('p'),
      name: 'p',
      tracks: [
        Track(
          id: track,
          name: 'Video',
          cuts: [
            cut(cutWithCels, const LayerId('l1')),
            cut(linked, const LayerId('l2')),
          ],
        ),
      ],
      createdAt: DateTime(2020),
      linkRegistry: LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'g',
            members: [
              LayerLinkMember(
                trackId: track,
                cutId: cutWithCels,
                layerId: const LayerId('l1'),
              ),
              LayerLinkMember(
                trackId: track,
                cutId: linked,
                layerId: const LayerId('l2'),
              ),
            ],
          ),
        ],
      ),
    );
    final repository = ProjectRepository(initialProject: project);
    final store = BrushFrameStore()
      ..setLinkResolver(
        (key) =>
            repository.currentProject?.linkRegistry.canonicalCelKey(key) ??
            key,
      );
    final kept = BrushFrameKey(
      projectId: const ProjectId('p'),
      trackId: track,
      cutId: cutWithCels,
      layerId: const LayerId('l1'),
      frameId: const FrameId('kept'),
    );
    keepInAFile(store, {
      kept: BitmapSurface(canvasSize: size, tileSize: 8).putTiles([
        (
          coord: TileCoord(x: 1, y: 1),
          tile: BitmapTile(
            size: 8,
            pixels: Uint8List(256)..fillRange(0, 256, 50),
          ),
        ),
      ]),
    });
    final coordinator = CutCommandCoordinator(
      repository: repository,
      editingSession: EditingSessionState(activeCutId: linked),
      historyManager: HistoryManager(),
      brushFrameStore: store,
    );
    await coordinator.placeCutCanvasAhead(
      cutId: linked,
      canvasSize: size,
      contentOffset: (dx: 3, dy: 0),
    );
    expect(store.movedAheadOf(kept), isNotNull);
    coordinator.placeCutCanvas(
      cutId: linked,
      canvasSize: size,
      contentOffset: (dx: 3, dy: 0),
    );
    expect(store.celsMovedHere, 0);
  });

  test('a resize works out its anchor\'s move', () async {
    final f = fixture();
    final size = CanvasSize(width: f.size.width - 20, height: f.size.height);
    await f.coordinator.resizeCutCanvasAhead(
      cutId: f.cut,
      canvasSize: size,
      anchor: CanvasResizeAnchor.center,
    );
    expect(f.store.movedAheadOf(f.kept), isNotNull);
    f.coordinator.resizeCutCanvas(
      cutId: f.cut,
      canvasSize: size,
      anchor: CanvasResizeAnchor.center,
    );
    expect(f.store.celsMovedHere, 0);
    expect(f.store.bakedSurfaceOrNull(f.kept)!.canvasSize, size);
  });
}
