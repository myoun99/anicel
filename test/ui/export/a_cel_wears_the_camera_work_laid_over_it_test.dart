import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/camera_work_marks.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/no_guides_laid.dart';

/// **CAM (I-89-Q18)** — the camera's work laid over a cel is written into
/// its file as the canvas draws it off the camera's row: every key's frame
/// with its cross at its centre, the first in IN's green and the last in
/// OUT's red, at the canvas's sizes a pixel of the file each.
void main() {
  const canvas = CanvasSize(width: 640, height: 640);
  const camera = CanvasSize(width: 320, height: 180);
  const cutId = CutId('cut');
  const layerId = LayerId('a');
  final drawing = Frame(id: const FrameId('f1'), duration: 1, strokes: const []);

  /// A cut whose camera moves from [from] on frame 0 to [to] on frame 3.
  EditorSessionManager sessionOf(CameraPose from, CameraPose to) {
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
                camera: CutCamera(keyframes: {0: from, 3: to}),
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
    // One black pixel in the corner: a cel with no artwork has nothing to
    // lay anything over.
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

  /// The cel of [session]'s cut, the camera's work laid over it or not.
  ExportCelGroupTask taskOf(
    EditorSessionManager session, {
    required bool laid,
  }) {
    final cut = session.requireActiveCut;
    final layer = cut.layers.firstWhere((layer) => layer.id == layerId);
    return ExportCelGroupTask(
      cut: cut,
      baseLayer: layer,
      members: [layer],
      memberFrames: [drawing],
      baseFrame: drawing,
      celName: '1',
      fileName: 'A1.png',
      cameraLaid: laid,
    );
  }

  /// The cel of [session]'s cut, the camera's work laid over it or not, as
  /// [mode] writes it: its pixels, and how wide it is.
  Future<({ByteData bytes, int width})> celOf(
    EditorSessionManager session, {
    required bool laid,
    ExportSizeMode mode = ExportSizeMode.canvas,
  }) async {
    final image = await ExportFrameRenderer(session: session).renderCelGroup(
      taskOf(session, laid: laid),
      mode,
      guideColor: noGuidesLaid,
    );
    final bytes = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    image.dispose();
    return (bytes: bytes!, width: width);
  }

  /// The colour at ([x], [y]) of [cel], as `0xRRGGBB`.
  int rgbAt(({ByteData bytes, int width}) cel, int x, int y) {
    final at = (y * cel.width + x) * 4;
    return cel.bytes.getUint8(at) << 16 |
        cel.bytes.getUint8(at + 1) << 8 |
        cel.bytes.getUint8(at + 2);
  }

  /// How much of [argb]'s ink covers the pixel [rgb] over the white ground
  /// — 1 wholly — or null where [rgb] is no blend of the two.
  double? inkOver(int rgb, int argb) {
    final covers = [
      for (final shift in [16, 8, 0])
        (0xFF - (rgb >> shift & 0xFF)) / (0xFF - (argb >> shift & 0xFF)),
    ];
    final least = covers.reduce(math.min);
    final most = covers.reduce(math.max);
    return most - least > 0.15 ? null : (least + most) / 2;
  }

  /// A pixel mostly [argb]'s ink over the white ground.
  Matcher inks(int argb) => predicate<int>(
    (rgb) => (inkOver(rgb, argb) ?? 0) > 0.5,
    'mostly 0x${argb.toRadixString(16)} over white',
  );

  testWidgets('laid, each key wears its frame, and its cross at the frame\'s '
      'centre, in its colour — the first IN\'s green, the last OUT\'s red; '
      'not laid, the cel is the artwork alone', (tester) async {
    await tester.runAsync(() async {
      final session = sessionOf(
        CameraPose(center: CanvasPoint(x: 200, y: 200)),
        CameraPose(center: CanvasPoint(x: 440, y: 440)),
      );
      // Off each other, off the trails and off the labels in the frames'
      // top-left corners: the first key's cross, the top side of its frame
      // (320 × 180 about it), and the last key's cross.
      const first = (x: 203, y: 200);
      const side = (x: 280, y: 110);
      const last = (x: 443, y: 440);
      final laid = await celOf(session, laid: true);
      expect(rgbAt(laid, first.x, first.y), inks(cameraInArgb));
      expect(rgbAt(laid, side.x, side.y), inks(cameraInArgb));
      expect(rgbAt(laid, last.x, last.y), inks(cameraOutArgb));

      final bare = await celOf(session, laid: false);
      for (final (:x, :y) in [first, side, last]) {
        expect(rgbAt(bare, x, y), 0xFFFFFF, reason: 'the ground at ($x, $y)');
      }
    });
    await tester.pumpAndSettle();
  });

  testWidgets('through a zoomed camera the marks keep the canvas\'s sizes '
      'in the file\'s pixels: a cross reaches five of them either way', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Frame 0's camera at twice the zoom: the file is its frame, a canvas
      // pixel two of the file's.
      final session = sessionOf(
        CameraPose(center: CanvasPoint(x: 200, y: 200), zoom: 2),
        CameraPose(center: CanvasPoint(x: 440, y: 440), zoom: 2),
      );
      final cel = await celOf(session, laid: true, mode: ExportSizeMode.camera);
      expect(cel.width, camera.width);
      const centre = (x: 160, y: 90);
      expect(rgbAt(cel, centre.x + 3, centre.y), inks(cameraInArgb));
      expect(
        rgbAt(cel, centre.x + 7, centre.y),
        0xFFFFFF,
        reason: 'five pixels of the file, not five of the canvas (ten here)',
      );
    });
    await tester.pumpAndSettle();
  });

  // 🗣️I-117: a cel's Photoshop file keeps the rows it is made of apart.
  testWidgets('in a Photoshop file the camera\'s work is a row of its own '
      'over the artwork\'s, named as the CAM pill is and laid whole: its '
      'marks on nothing', (tester) async {
    await tester.runAsync(() async {
      final session = sessionOf(
        CameraPose(center: CanvasPoint(x: 200, y: 200)),
        CameraPose(center: CanvasPoint(x: 440, y: 440)),
      );
      final rows = ExportFrameRenderer(session: session).celGroupRows(
        taskOf(session, laid: true),
        ExportSizeMode.canvas,
        guideColor: noGuidesLaid,
      );

      expect(
        [for (final row in rows) row.name],
        [AppText.strings.exBackground, 'A', AppText.strings.tlKindCamera],
      );
      expect(
        (rows.last.opacity, rows.last.blendMode),
        (1.0, LayerBlendMode.normal),
        reason: 'as the cel\'s picture lays it over its artwork',
      );
      final image = await rows.last.draw();
      final marks = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      final width = image.width;
      image.dispose();
      int alphaAt(int x, int y) => marks.getUint8((y * width + x) * 4 + 3);
      expect(alphaAt(203, 200), greaterThan(0), reason: 'the first cross');
      expect(alphaAt(0, 0), 0, reason: 'not the artwork, nor the ground');
    });
    await tester.pumpAndSettle();
  });
}
