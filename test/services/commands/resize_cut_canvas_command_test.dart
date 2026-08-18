import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
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

    test('D5: the command COMPLETES the raster adoption — every cel '
        'carries the NEW canvas size for every anchor, with no widget '
        'half involved', () {
      for (final anchor in [
        CanvasResizeAnchor.topLeft,
        CanvasResizeAnchor.center,
        CanvasResizeAnchor.bottomRight,
      ]) {
        final store = _storeWithInkAt(x: 500, y: 400);
        command(
          repository: _repository(),
          store: store,
          anchor: anchor,
        ).execute();
        expect(
          store.bakedSurfaceOrNull(_frameKey())!.canvasSize,
          shrunkenSize,
          reason: 'anchor $anchor: the old split left the crop to the '
              'WIDGET (didUpdateWidget), so any state that skipped it — '
              '겸용 canonical keys, a null selection, an unmounted host — '
              'left the cel at the old size, displaying as EMPTY and '
              'turning permanent on the first stroke (the D5 loss)',
        );
      }
    });

    test('D3: the undo payload reports its weight — the reference '
        'snapshot pins the pre-resize tiles, and the history byte-trim '
        'must see them', () {
      final store = _storeWithInkAt(x: 500, y: 400);
      final resize = command(
        repository: _repository(),
        store: store,
        anchor: CanvasResizeAnchor.center,
      );
      resize.execute();
      expect(
        resize.estimatedRetainedBytes,
        256 * 256 * 4,
        reason: 'one retained tile of RGBA — uncounted, a large cut\'s '
            'resize pinned its whole baked set invisibly',
      );
    });

    test('D3: a top-left GROW retains ~nothing — the live surface shares '
        'every snapshot tile; phantom full-count bytes were evicting '
        'real undo history', () {
      final store = _storeWithInkAt(x: 500, y: 400);
      final resize = ResizeCutCanvasCommand(
        repository: _repository(),
        cutId: const CutId('cut-target'),
        canvasSize: const CanvasSize(width: 2120, height: 1280),
        anchor: CanvasResizeAnchor.topLeft,
        brushFrameStore: store,
      );
      resize.execute();
      expect(resize.estimatedRetainedBytes, 0);
    });

    test('D5: the model follows the picture — camera keyframes, guides '
        'and layer transform keys move by the content offset; undo '
        'restores them exactly', () {
      final repository = _repositoryWithModelContent();
      final store = _storeWithInkAt(x: 500, y: 400);
      final historyManager = HistoryManager();
      final before = repository.requireProject();

      // Center anchor, 1920x1080 → 1720x880: offset (-100, -100).
      historyManager.execute(
        command(
          repository: repository,
          store: store,
          anchor: CanvasResizeAnchor.center,
        ),
      );

      final cut = repository.requireProject().tracks.single.cuts.first;
      final pose = cut.camera.keyframeAt(0)!;
      expect(pose.center.x, 860);
      expect(pose.center.y, 440);
      expect(pose.zoom, 2.0, reason: 'a resize is a crop, never a scale');
      final axis = (cut.guides.guides.single.shape as SymmetryShape).axis;
      expect(axis.origin.x, 200);
      expect(axis.origin.y, 100);
      final track = cut.layers.single.transformTrack;
      expect(track.position.keyAt(0)!.value.x, 300);
      expect(track.position.keyAt(0)!.value.y, 150);
      expect(
        track.anchorPoint.isEmpty,
        isTrue,
        reason: 'null anchors stay null — they re-read as the NEW canvas '
            'centre, which is exactly right for the centre anchor',
      );

      historyManager.undo();
      expect(repository.requireProject(), before);
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

/// The D5 model-follow fixture: the target cut carries a camera
/// keyframe, a symmetry guide and a layer with a position key (anchor
/// deliberately unkeyed — the null-anchor law is part of the pin).
ProjectRepository _repositoryWithModelContent() {
  final cut = _targetCut.copyWith(
    camera: CutCamera(
      keyframes: {
        0: CameraPose(center: CanvasPoint(x: 960, y: 540), zoom: 2.0),
      },
    ),
    guides: CutGuides(
      guides: [
        DrawingGuide(
          id: const GuideId('guide-1'),
          name: 'Axis',
          shape: SymmetryShape(
            axis: GuideAxis(
              origin: CanvasPoint(x: 300, y: 200),
              angleDegrees: 0,
            ),
          ),
        ),
      ],
    ),
    layers: [
      Layer(
        id: const LayerId('layer-1'),
        name: 'A',
        frames: const [],
        timeline: const {},
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack(
            keys: {0: PropertyKey(CanvasPoint(x: 400, y: 250))},
          ),
        ),
      ),
    ],
  );
  return ProjectRepository(
    initialProject: Project(
      id: const ProjectId('project-1'),
      name: 'Project',
      tracks: [
        Track(id: const TrackId('track-1'), name: 'Video', cuts: [cut]),
      ],
      createdAt: DateTime.utc(2024),
    ),
  );
}
