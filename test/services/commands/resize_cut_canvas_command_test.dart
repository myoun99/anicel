import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/commands/resize_cut_canvas_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

void main() {
  group('ResizeCutCanvasCommand', () {
    test('resizes only the target cut canvas', () {
      final repository = _repository();

      ResizeCutCanvasCommand(
        repository: repository,
        cutId: const CutId('cut-target'),
        canvasSize: const CanvasSize(width: 640, height: 480),
      ).execute();

      final cuts = repository.requireProject().tracks.single.cuts;
      expect(cuts.first.canvasSize, const CanvasSize(width: 640, height: 480));
      expect(cuts.first.id, const CutId('cut-target'));
      expect(cuts.first.layers, _targetCut.layers);
      expect(cuts.first.duration, _targetCut.duration);
      expect(cuts.last, _otherCut);
    });

    test('undo restores the previous canvas size', () {
      final repository = _repository();
      final historyManager = HistoryManager();

      historyManager.execute(
        ResizeCutCanvasCommand(
          repository: repository,
          cutId: const CutId('cut-target'),
          canvasSize: const CanvasSize(width: 640, height: 480),
        ),
      );
      historyManager.undo();

      expect(repository.requireProject().tracks.single.cuts.first, _targetCut);
    });

    test('redo applies the new canvas size again', () {
      final repository = _repository();
      final historyManager = HistoryManager();

      historyManager.execute(
        ResizeCutCanvasCommand(
          repository: repository,
          cutId: const CutId('cut-target'),
          canvasSize: const CanvasSize(width: 640, height: 480),
        ),
      );
      historyManager.undo();
      historyManager.redo();

      expect(
        repository.requireProject().tracks.single.cuts.first.canvasSize,
        const CanvasSize(width: 640, height: 480),
      );
    });

    test('throws when undo is called before execute', () {
      final command = ResizeCutCanvasCommand(
        repository: _repository(),
        cutId: const CutId('cut-target'),
        canvasSize: const CanvasSize(width: 640, height: 480),
      );

      expect(command.undo, throwsStateError);
    });

    test('throws when the target cut id is missing', () {
      final command = ResizeCutCanvasCommand(
        repository: _repository(),
        cutId: const CutId('missing'),
        canvasSize: const CanvasSize(width: 640, height: 480),
      );

      expect(command.execute, throwsStateError);
    });
  });

  group('anchored raster translation (R19: the baked truth blits)', () {
    // Target cut: 1920x1080. Resizing to 1720x880 shrinks by 200x200.
    const shrunkenSize = CanvasSize(width: 1720, height: 880);

    ResizeCutCanvasCommand command({
      required ProjectRepository repository,
      required BrushFrameStore store,
      required CanvasResizeAnchor anchor,
    }) {
      return ResizeCutCanvasCommand(
        repository: repository,
        cutId: const CutId('cut-target'),
        canvasSize: shrunkenSize,
        anchor: anchor,
        brushFrameStore: store,
      );
    }

    test('center anchor shifts pixels by half the size delta', () {
      final store = _storeWithInkAt(x: 500, y: 400);
      command(
        repository: _repository(),
        store: store,
        anchor: CanvasResizeAnchor.center,
      ).execute();

      expect(_inkAt(store, 400, 300), isNonZero);
      expect(_inkAt(store, 500, 400), anyOf(isNull, 0));
    });

    test('bottom-right anchor shifts pixels by the full size delta', () {
      final store = _storeWithInkAt(x: 500, y: 400);
      command(
        repository: _repository(),
        store: store,
        anchor: CanvasResizeAnchor.bottomRight,
      ).execute();

      expect(_inkAt(store, 300, 200), isNonZero);
    });

    test('top-left anchor leaves pixels untouched', () {
      final store = _storeWithInkAt(x: 500, y: 400);
      command(
        repository: _repository(),
        store: store,
        anchor: CanvasResizeAnchor.topLeft,
      ).execute();

      expect(_inkAt(store, 500, 400), isNonZero);
    });

    test('undo restores the baked surface BY REFERENCE; redo re-applies', () {
      final store = _storeWithInkAt(x: 500, y: 400);
      final original = store.bakedSurfaceOrNull(_frameKey())!;
      final repository = _repository();
      final historyManager = HistoryManager();

      historyManager.execute(
        command(
          repository: repository,
          store: store,
          anchor: CanvasResizeAnchor.center,
        ),
      );
      historyManager.undo();

      expect(
        identical(store.bakedSurfaceOrNull(_frameKey()), original),
        isTrue,
        reason: 'the reference snapshot restores byte-exactly for free',
      );
      expect(repository.requireProject().tracks.single.cuts.first, _targetCut);

      historyManager.redo();
      expect(_inkAt(store, 400, 300), isNonZero);
    });

    test('other cuts pixels are not translated', () {
      final store = BrushFrameStore();
      store.storeBakedSurface(
        _frameKey(cutId: 'cut-other'),
        _surfaceWithInkAt(x: 500, y: 400),
      );
      final before = store.bakedSurfaceOrNull(_frameKey(cutId: 'cut-other'));

      command(
        repository: _repository(),
        store: store,
        anchor: CanvasResizeAnchor.center,
      ).execute();

      expect(
        identical(
          store.bakedSurfaceOrNull(_frameKey(cutId: 'cut-other')),
          before,
        ),
        isTrue,
      );
    });
  });
}

BrushFrameKey _frameKey({String cutId = 'cut-target'}) => BrushFrameKey(
  projectId: const ProjectId('project-1'),
  trackId: const TrackId('track-1'),
  cutId: CutId(cutId),
  layerId: const LayerId('layer-1'),
  frameId: const FrameId('frame-1'),
);

/// A 1920x1080 baked surface with ONE opaque black pixel at ([x], [y]).
BitmapSurface _surfaceWithInkAt({required int x, required int y}) {
  const tileSize = 256;
  final coord = TileCoord(x: x ~/ tileSize, y: y ~/ tileSize);
  final pixels = Uint8List(tileSize * tileSize * 4);
  final offset = ((y % tileSize) * tileSize + (x % tileSize)) * 4;
  pixels[offset + 3] = 255;
  return BitmapSurface(
    canvasSize: const CanvasSize(width: 1920, height: 1080),
  ).putTile(BitmapTile(coord: coord, size: tileSize, pixels: pixels));
}

BrushFrameStore _storeWithInkAt({required int x, required int y}) {
  return BrushFrameStore()
    ..storeBakedSurface(_frameKey(), _surfaceWithInkAt(x: x, y: y));
}

int? _inkAt(BrushFrameStore store, int x, int y) {
  final surface = store.bakedSurfaceOrNull(_frameKey());
  if (surface == null) {
    return null;
  }
  return surfacePixelRgba(surface, x, y);
}

final _targetCut = Cut(
  id: const CutId('cut-target'),
  name: 'Target',
  layers: const [],
  duration: 24,
  canvasSize: const CanvasSize(width: 1920, height: 1080),
);

final _otherCut = Cut(
  id: const CutId('cut-other'),
  name: 'Other',
  layers: const [],
  duration: 24,
  canvasSize: const CanvasSize(width: 1280, height: 720),
);

ProjectRepository _repository() {
  return ProjectRepository(
    initialProject: Project(
      id: const ProjectId('project-1'),
      name: 'Project',
      tracks: [
        Track(
          id: const TrackId('track-1'),
          name: 'Video',
          cuts: [_targetCut, _otherCut],
        ),
      ],
      createdAt: DateTime.utc(2024),
    ),
  );
}
