import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
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
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/canvas/layer_image_draw.dart';
import 'package:anicel/src/ui/canvas/raster_picture.dart';
import 'package:anicel/src/ui/canvas/tiled_surface_compose.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

/// 🎯AN EXPORT'S ROWS ARE COMPOSED AS THEIR INK where every picture of its
/// run lays them down texel for texel (card
/// export-folders-and-rows-at-their-extent) — a row that draws exactly from
/// its ink is then rastered over its ink alone
/// (`a_row_drawn_from_its_ink_is_the_same_bytes` pins that the picture is
/// the same bytes). 🔬On the user's film the rows went from 2,859 to
/// 1,305 Mpx and the run from 151 to 132 s.
void main() {
  const canvasSize = CanvasSize(width: 64, height: 48);
  const cutId = CutId('cut');

  /// One tile of ink — the canvas's second column of tiles, first row.
  BitmapSurface inkInOneTile() {
    final pixels = Uint8List(16 * 16 * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = 200;
      pixels[i + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 16,
      tiles: {TileCoord(x: 1, y: 0): BitmapTile(size: 16, pixels: pixels)},
    );
  }

  /// A cut of one drawing shown at both its frames, through [camera].
  EditorSessionManager session({CutCamera? camera}) {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: canvasSize,
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: cutId,
                name: 'Cut',
                duration: 2,
                canvasSize: canvasSize,
                camera: camera,
                layers: [
                  Layer(
                    id: const LayerId('layer'),
                    name: 'A',
                    frames: [
                      Frame(id: const FrameId('f1'), duration: 2, strokes: []),
                    ],
                    timeline: const {
                      0: TimelineExposure.drawing(FrameId('f1'), length: 2),
                    },
                  ),
                  createCameraLayer(cutId: cutId),
                ],
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
    final cut = s.requireActiveCut;
    final key = s.brushFrameKeyForCut(
      cut,
      const LayerId('layer'),
      const FrameId('f1'),
    );
    final cel = AnicelCelEntry.fromSurface(key, inkInOneTile());
    s.renderCaches.brushFrameStore.restoreBaked({
      key: AnicelCelBlob.encode(cel),
    });
    return s;
  }

  (int, int) sizeOf(Rect rect) => (rect.width.round(), rect.height.round());
  late final ink = sizeOf(surfaceInkWorldRect(inkInOneTile()));
  late final whole = sizeOf(surfaceContentWorldRect(inkInOneTile()));

  /// The size of every row rastered, in order.
  late List<(int, int)> rastered;
  late int laidBack;
  setUp(() {
    rastered = [];
    debugOnWaitedSnapshot = (width, height) => rastered.add((width, height));
    laidBack = debugWholesLaidBack;
  });
  tearDown(() => debugOnWaitedSnapshot = null);

  test('LIVENESS: the ink is less than the canvas', () {
    expect(ink.$1 * ink.$2, lessThan(whole.$1 * whole.$2));
  });

  for (final mode in ExportSizeMode.values) {
    testWidgets('🎯a ${mode.name} video frame rasters its row over its ink, '
        'not over the canvas', (tester) async {
      await tester.runAsync(() async {
        final s = session();
        addTearDown(s.dispose);
        final renderer = ExportFrameRenderer(session: s);
        addTearDown(renderer.dispose);

        final cut = s.requireActiveCut;
        final image = await renderer.videoRun([
          ExportFrameTask(cut: cut, frameIndex: 0),
        ], mode).frame(0);
        image.dispose();

        expect(rastered, [ink]);
      });
    });
  }

  group('a camera-size picture sequence', () {
    /// Both frames of a sequence of the cut [camera] looks through, drawn
    /// in order.
    Future<void> drawBoth(CutCamera camera) async {
      final s = session(camera: camera);
      addTearDown(s.dispose);
      final renderer = ExportFrameRenderer(session: s);
      addTearDown(renderer.dispose);
      final cut = s.requireActiveCut;
      final run = renderer.stillRun([
        for (final index in [0, 1])
          ExportFrameTask(cut: cut, frameIndex: index),
      ], ExportSizeMode.camera);
      for (final index in [0, 1]) {
        (await run.frame(index)).dispose();
      }
    }

    testWidgets('🎯whose camera stands on whole pixels rasters its row over '
        'its ink, and draws that at every frame', (tester) async {
      await tester.runAsync(() async {
        await drawBoth(
          CutCamera(
            keyframes: {
              0: CameraPose(center: CanvasPoint(x: 32, y: 24)),
              1: CameraPose(center: CanvasPoint(x: 33, y: 24)),
            },
          ),
        );

        expect(rastered.toSet(), {ink});
        expect(debugWholesLaidBack, laidBack, reason: 'never laid back');
      });
    });

    testWidgets('🎯whose camera leaves whole pixels for a frame rasters its '
        'row whole — one composed as its ink would be laid back whole at '
        'that frame', (tester) async {
      await tester.runAsync(() async {
        await drawBoth(
          CutCamera(
            keyframes: {
              0: CameraPose(center: CanvasPoint(x: 32, y: 24)),
              1: CameraPose(center: CanvasPoint(x: 32.5, y: 24)),
            },
          ),
        );

        expect(rastered.toSet(), {whole});
        expect(debugWholesLaidBack, laidBack, reason: 'never laid back');
      });
    });
  });
}
