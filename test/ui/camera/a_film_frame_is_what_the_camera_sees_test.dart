import 'dart:typed_data';

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
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

import '../../helpers/cels_parked_cold.dart';

/// A FILM'S FRAME IS WHAT THE CAMERA SEES: the frame's one picture on the
/// engine, shown through the cut's camera onto the file's pixels — the whole
/// road an export takes (`renderVideoFrame`, `frameOnTheEngine`).
///
/// ↩️Asked of `CameraFrameRenderService`, which composited a shot's rows
/// again on Flutter, until exports went on the engine and it had no caller.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canvas = CanvasSize(width: 8, height: 8);
  const cutId = CutId('cut');
  const layerId = LayerId('a');
  const red = [255, 0, 0, 255];
  const white = [255, 255, 255, 255];
  final backdrop = [
    (defaultProjectBackdropArgb >> 16) & 0xFF,
    (defaultProjectBackdropArgb >> 8) & 0xFF,
    defaultProjectBackdropArgb & 0xFF,
    255,
  ];
  final drawing = Frame(id: const FrameId('f1'), duration: 1, strokes: const []);
  final atRest = CameraPose(center: CanvasPoint(x: 4, y: 4));

  /// The cel whose only ink is [colour] at ([x], [y]) of the canvas.
  BitmapSurface inkAt(int x, int y, {List<int> colour = red}) {
    const side = defaultCelTileSize;
    final pixels = Uint8List(side * side * 4);
    final at = (y % side * side + x % side) * 4;
    pixels.setAll(at, colour);
    return BitmapSurface(canvasSize: canvas, tileSize: side).putTiles([
      (
        coord: TileCoord(x: (x / side).floor(), y: (y / side).floor()),
        tile: BitmapTile(size: side, pixels: pixels),
      ),
    ]);
  }

  TransformTrack movedTo(double x, double y) => TransformTrack.empty().copyWith(
    position: PropertyTrack<CanvasPoint>.empty().withKey(
      0,
      CanvasPoint(x: x, y: y),
    ),
  );

  /// The premultiplied pixels of the film frame [pose] sees of a row on
  /// [cel], [output] pixels where named and the camera's size where not;
  /// and a reader of them.
  Future<List<int> Function(int x, int y)> filmed(
    WidgetTester tester, {
    required BitmapSurface cel,
    CameraPose? pose,
    TransformTrack? transform,
    double opacity = 1,
    List<LayerEffect> effects = const [],
    CanvasSize? output,
  }) async {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: canvas,
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
                camera: CutCamera(keyframes: {0: pose ?? atRest}),
                layers: [
                  Layer(
                    id: layerId,
                    name: 'A',
                    frames: [drawing],
                    timeline: {
                      0: TimelineExposure.drawing(drawing.id, length: 4),
                    },
                    opacity: opacity,
                    effects: effects,
                    transformTrack: transform,
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
    final cut = session.requireActiveCut;
    parkCold(session.renderCaches.brushFrameStore, {
      session.brushFrameKeyForCut(cut, layerId, drawing.id): cel,
    });
    final renderer = ExportFrameRenderer(session: session);
    addTearDown(renderer.dispose);
    final (Uint8List bytes, int width) = (await tester.runAsync(() async {
      final image = await renderer.renderVideoFrame(
        ExportFrameTask(cut: cut, frameIndex: 0),
        ExportSizeMode.camera,
        preserveAlpha: false,
        outputSize: output,
      );
      final data = await image.toByteData();
      final width = image.width;
      image.dispose();
      return (data!.buffer.asUint8List(), width);
    }))!;
    return (int x, int y) => bytes.sublist(
      (y * width + x) * 4,
      (y * width + x) * 4 + 4,
    );
  }

  testWidgets('artwork parked off the canvas and posed into the frame reaches '
      'the film: the crop is after the pose, as playback\'s', (tester) async {
    final pixel = await filmed(
      tester,
      cel: inkAt(-1, 2),
      // The anchor is the canvas's middle (4,4): +2 in x, world (-1,2) lands
      // on (1,2).
      transform: movedTo(6, 4),
    );
    expect(pixel(1, 2), red);
    expect(pixel(5, 5), white, reason: 'and nothing else moved');
  });

  testWidgets('artwork no pose brings in stays out of the film — 유저 확정 '
      '「페이스트보드는 포함 안 시킴」', (tester) async {
    final pixel = await filmed(tester, cel: inkAt(-1, 2));
    for (var y = 0; y < 8; y += 1) {
      for (var x = 0; x < 8; x += 1) {
        expect(pixel(x, y), white, reason: '($x,$y)');
      }
    }
  });

  testWidgets('a camera at rest puts canvas pixels 1:1 on the film', (
    tester,
  ) async {
    final pixel = await filmed(tester, cel: inkAt(1, 2));
    expect(pixel(1, 2), red);
    expect(pixel(5, 5), white);
  });

  testWidgets('the backdrop fills what lies past the canvas', (tester) async {
    final pixel = await filmed(
      tester,
      cel: inkAt(0, 0),
      // Centred on the canvas's corner: most of the view is outside it.
      pose: CameraPose(center: CanvasPoint(x: 0, y: 0)),
    );
    // The canvas's corner stands at the film's middle: past its top and its
    // left the backdrop, on it the paper and the ink.
    expect(pixel(0, 0), backdrop);
    expect(pixel(7, 7), white);
    expect(pixel(4, 4), red, reason: 'LIVENESS: the ink is in the view');
  });

  testWidgets('a row\'s transform moves it under the camera', (tester) async {
    final pixel = await filmed(
      tester,
      cel: inkAt(1, 2),
      // The anchor (4,4) lands at (6,5): the ink moves by (+2, +1).
      transform: movedTo(6, 5),
    );
    expect(pixel(3, 3), red);
    expect(pixel(1, 2), white);
  });

  testWidgets('a camera zoomed 2 magnifies around its centre', (tester) async {
    final pixel = await filmed(
      tester,
      cel: inkAt(3, 3),
      pose: CameraPose(center: CanvasPoint(x: 4, y: 4), zoom: 2),
    );
    // Canvas (3,3)..(4,4) maps to the film's 4 + 2 * (3 - 4) = 2..4.
    expect(pixel(2, 2), red);
    expect(pixel(3, 3), red);
    expect(pixel(4, 4), isNot(red));
  });

  testWidgets('a camera turned clockwise turns the world the other way', (
    tester,
  ) async {
    final pixel = await filmed(
      tester,
      // One pixel right of the middle: canvas (5..6, 4..5).
      cel: inkAt(5, 4),
      pose: CameraPose(center: CanvasPoint(x: 4, y: 4), rotationDegrees: 90),
    );
    // What was right of the camera's centre stands above it: through R(-90)
    // the corners (1,0) & (2,1) land on (0,-2)..(1,-1), about the centre.
    expect(pixel(4, 2), red);
    expect(pixel(5, 4), white);
  });

  testWidgets('a row\'s effect filters its own picture on the way to the '
      'film', (tester) async {
    final pixel = await filmed(
      tester,
      cel: inkAt(2, 2, colour: [0x80, 0x80, 0x80, 255]),
      effects: [
        LayerEffect(
          id: const EffectId('fx'),
          kind: EffectKind.brightnessContrast,
          parameters: {'brightness': EffectParameter(value: 20)},
        ),
      ],
    );
    expect(pixel(2, 2)[0], inInclusiveRange(0x80 + 49, 0x80 + 53));
    expect(pixel(2, 2)[3], 255);
  });

  testWidgets('a row\'s opacity lets the ground through', (tester) async {
    final pixel = await filmed(tester, cel: inkAt(1, 1), opacity: 0.5);
    // 50% red over white: red stays, green and blue drop by half.
    expect(pixel(1, 1)[0], inInclusiveRange(250, 255));
    expect(pixel(1, 1)[1], inInclusiveRange(120, 135));
    expect(pixel(1, 1)[2], inInclusiveRange(120, 135));
  });

  testWidgets('a smaller film shows the same view scaled down', (tester) async {
    final pixel = await filmed(
      tester,
      cel: inkAt(2, 2),
      output: const CanvasSize(width: 4, height: 4),
    );
    // Canvas (2..3) maps to the film's (1..1.5).
    expect(pixel(1, 1), isNot(white));
    // Off the ink and off the canvas's edge, which a picture made smaller
    // reads past.
    expect(pixel(2, 2), white);
  });
}
