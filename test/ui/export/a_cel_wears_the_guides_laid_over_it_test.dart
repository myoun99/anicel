import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
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
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

/// **I-105** — the cut's guides laid over a cel are written into its file
/// as 래스터라이즈 bakes them: the perspective guides the canvas shows
/// (I-105-Q1), each the faint line the canvas draws at rest, on the paper
/// alone (I-105-Q2) — at the CAM's sizes, a pixel of the file for each
/// pixel of the screen (I-89-Q20).
void main() {
  const canvas = CanvasSize(width: 640, height: 640);
  const camera = CanvasSize(width: 320, height: 180);
  const cutId = CutId('cut');
  const layerId = LayerId('a');
  const ink = ui.Color(0xFF1E5AC8);
  final drawing = Frame(
    id: const FrameId('f1'),
    duration: 1,
    strokes: const [],
  );

  /// A perspective guide of one point at (500, 50), off its eye level,
  /// which runs flat along y = 200: no ray of the point lies along it.
  DrawingGuide perspective(String id, {bool visible = true}) => DrawingGuide(
    id: GuideId(id),
    name: id,
    visible: visible,
    shape: PerspectiveShape(
      vanishingPoints: [VanishingPointAt(CanvasPoint(x: 500, y: 50))],
      eyeLevel: GuideAxis(origin: CanvasPoint(x: 320, y: 200), angleDegrees: 0),
      constrainToEyeLevel: false,
    ),
  );
  final shown = perspective('shown');
  final hidden = perspective('hidden', visible: false);
  final symmetry = DrawingGuide(
    id: const GuideId('symmetry'),
    name: 'symmetry',
    shape: SymmetryShape(
      axis: GuideAxis(origin: CanvasPoint(x: 320, y: 320), angleDegrees: 90),
    ),
  );

  /// A cut wearing [guides], its camera keyed by [keys], its one drawing a
  /// black pixel in the paper's corner — a cel with no artwork has nothing
  /// to lay anything over.
  EditorSessionManager sessionOf(
    List<DrawingGuide> guides, {
    Map<int, CameraPose>? keys,
  }) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: camera,
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: cutId,
                name: 'CUT',
                duration: 4,
                canvasSize: canvas,
                camera: keys == null ? null : CutCamera(keyframes: keys),
                guides: CutGuides(guides: guides),
                layers: [
                  Layer(
                    id: layerId,
                    name: 'A',
                    frames: [drawing],
                    timeline: {
                      0: TimelineExposure.drawing(drawing.id, length: 4),
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
    addTearDown(session.dispose);
    const tile = 256;
    final pixels = Uint8List(tile * tile * 4)..[3] = 255;
    final cut = session.requireActiveCut;
    session.renderCaches.brushFrameStore.storeRebuiltDisplayCache(
      key: session.brushFrameKeyForCut(cut, layerId, drawing.id),
      previewSurface: BitmapSurface(canvasSize: canvas, tileSize: tile)
          .putTiles([
            (
              coord: TileCoord(x: 0, y: 0),
              tile: BitmapTile(size: tile, pixels: pixels),
            ),
          ]),
    );
    return session;
  }

  /// The cel of [session]'s cut as [mode] writes it on a clear ground, the
  /// guides laid over it or not — and the camera's work, where [camera]:
  /// its straight RGBA, and how wide it is.
  Future<({Uint8List rgba, int width})> celOf(
    EditorSessionManager session, {
    required bool laid,
    bool camera = false,
    ExportSizeMode mode = ExportSizeMode.canvas,
  }) async {
    final cut = session.requireActiveCut;
    final layer = cut.layers.firstWhere((layer) => layer.id == layerId);
    final image =
        await ExportFrameRenderer(
          session: session,
          background: const ui.Color(0x00000000),
        ).renderCelGroup(
          ExportCelGroupTask(
            cut: cut,
            baseLayer: layer,
            members: [layer],
            memberFrames: [drawing],
            baseFrame: drawing,
            celName: '1',
            fileName: 'A1.png',
            cameraLaid: camera,
            guidesLaid: laid,
          ),
          mode,
          guideColor: ink,
        );
    final bytes = await image!.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final width = image.width;
    image.dispose();
    return (rgba: bytes!.buffer.asUint8List(), width: width);
  }

  /// The ink down column [x] of [cel] from row [top] to row [bottom]: its
  /// alphas summed, an opaque pixel 1.
  double inkDown(
    ({Uint8List rgba, int width}) cel,
    int x, {
    required int top,
    required int bottom,
  }) {
    var sum = 0;
    for (var y = top; y <= bottom; y += 1) {
      sum += cel.rgba[(y * cel.width + x) * 4 + 3];
    }
    return sum / 255;
  }

  testWidgets('laid, the cel wears what 래스터라이즈 bakes — the perspective '
      'guide the canvas shows, its faint line, on the paper: not the hidden '
      'one, not the symmetry; not laid, the artwork alone', (tester) async {
    await tester.runAsync(() async {
      final session = sessionOf([shown, hidden, symmetry]);
      final baked = await guideLinesOnPaper(
        shown,
        canvasSize: canvas,
        color: ink,
      );
      final lines = baked!.image.rgba;
      expect(
        [for (var at = 3; at < lines.length; at += 4) lines[at]],
        contains(greaterThan(0)),
        reason: 'fixture: the guide bakes lines',
      );

      final laid = await celOf(session, laid: true);
      // The artwork's pixel aside, the file is the bake.
      var differing = 0;
      for (var at = 4; at < lines.length; at += 1) {
        if (laid.rgba[at] != lines[at]) {
          differing += 1;
        }
      }
      expect(differing, 0, reason: 'bytes off the bake');

      final bare = await celOf(session, laid: false);
      expect(bare.rgba.sublist(0, 4), [0, 0, 0, 255], reason: 'the artwork');
      expect(bare.rgba.skip(4), everyElement(0));
    });
    await tester.pumpAndSettle();
  });

  testWidgets('through a zoomed camera the line keeps the canvas\'s weight '
      'in the file\'s pixels: the eye level holds one pixel of its ink '
      'across, not two', (tester) async {
    await tester.runAsync(() async {
      // The file is the frame, a canvas pixel two of its: the eye level
      // runs along its middle, and its column 280 is the canvas's x = 320,
      // which no ray of the point crosses there.
      final session = sessionOf([
        shown,
      ], keys: {0: CameraPose(center: CanvasPoint(x: 260, y: 200), zoom: 2)});
      final cel = await celOf(session, laid: true, mode: ExportSizeMode.camera);
      expect(cel.width, camera.width);
      expect(inkDown(cel, 280, top: 80, bottom: 100), closeTo(0.28, 0.05));
    });
    await tester.pumpAndSettle();
  });

  testWidgets('the lines stop at the paper\'s edge, where the camera\'s '
      'frame runs past it', (tester) async {
    await tester.runAsync(() async {
      // The frame, 320 wide about x = 100, runs 60 pixels past the paper's
      // left edge: its columns 0 – 59 are off the paper.
      final session = sessionOf([
        shown,
      ], keys: {0: CameraPose(center: CanvasPoint(x: 100, y: 200))});
      final cel = await celOf(session, laid: true, mode: ExportSizeMode.camera);
      expect(
        inkDown(cel, 200, top: 80, bottom: 100),
        greaterThan(0.2),
        reason: 'fixture: the eye level crosses the paper',
      );
      for (final x in [0, 30, 59]) {
        expect(
          inkDown(cel, x, top: 0, bottom: camera.height - 1),
          0,
          reason: 'column $x is off the paper',
        );
      }
    });
    await tester.pumpAndSettle();
  });

  // ⚠️My call, not the user's: the guides lie under the camera's work — the
  // camera's marks are what is said of the drawing, the guides what it was
  // drawn over.
  testWidgets('laid with the camera\'s work, the guides lie under it: where '
      'a mark covers a pixel whole, the guide\'s line does not show through '
      'it', (tester) async {
    await tester.runAsync(() async {
      // The first key's cross sits on the eye level. It stands half a
      // pixel across, as do its frame's upright edges: there a line 1.6 or
      // 1.8 wide covers a column whole, where on a pixel's edge it covers
      // none.
      final session = sessionOf(
        [shown],
        keys: {
          0: CameraPose(center: CanvasPoint(x: 200.5, y: 200)),
          3: CameraPose(center: CanvasPoint(x: 440, y: 440)),
        },
      );
      final marks = await celOf(session, laid: false, camera: true);
      final lines = await celOf(session, laid: true);
      final both = await celOf(session, laid: true, camera: true);
      // A pixel a mark covers whole, which the guide inks too.
      int? at;
      for (var pixel = 1; pixel * 4 < marks.rgba.length; pixel += 1) {
        if (marks.rgba[pixel * 4 + 3] == 255 &&
            lines.rgba[pixel * 4 + 3] > 0) {
          at = pixel * 4;
          break;
        }
      }
      expect(at, isNotNull, reason: 'fixture: a mark covers the guide\'s ink');
      expect(both.rgba.sublist(at!, at + 4), marks.rgba.sublist(at, at + 4));
    });
    await tester.pumpAndSettle();
  });
}
