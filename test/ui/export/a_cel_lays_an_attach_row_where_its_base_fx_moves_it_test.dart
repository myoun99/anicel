// 🗣️F-578 ⑨ (유저 2026-11-10): 「물론 참조fx같은거 생각해서 어태치에도
// 참조fx에서 옮긴거 적용되게」 — a cel lays an attach row where its base's
// reference fx moves the base, as the screen does (I-65-Q7: a cel goes out
// on its paper, moved by reference fx alone).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart' show ExportLayerFx;
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

import '../../helpers/cels_parked_cold.dart';

void main() {
  const canvas = CanvasSize(width: 32, height: 32);
  const cutId = CutId('cut');
  final paperCel = Frame(
    id: const FrameId('f1'),
    duration: 1,
    strokes: const [],
    name: '1',
  );
  final sheetCel = Frame(
    id: const FrameId('f2'),
    duration: 1,
    strokes: const [],
    name: '1',
  );

  /// A 용지 its reference fx stands 3 to the right of where it was laid,
  /// with a sheet attached to it — each holding one grey pixel of its own:
  /// the paper's at (5, 5), the sheet's at (10, 10).
  EditorSessionManager sessionOf() {
    final paper = Layer(
      id: const LayerId('paper'),
      name: 'A',
      frames: [paperCel],
      timeline: {0: TimelineExposure.drawing(paperCel.id, length: 4)},
      mediaReference: MediaReference(
        assetPath: 'paper.png',
        laid: TransformPose(center: CanvasPoint(x: 16, y: 16)),
        pose: TransformPose(center: CanvasPoint(x: 19, y: 16)),
        pictureSize: canvas,
      ),
    );
    final sheet = Layer(
      id: const LayerId('sheet'),
      name: 'A-작감',
      frames: [sheetCel],
      timeline: const {},
      attachedToLayerId: paper.id,
      baseFrameLinks: {paperCel.id: sheetCel.id},
    );
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: canvas,
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'V1',
            cuts: [
              Cut(
                id: cutId,
                name: 'CUT',
                duration: 4,
                canvasSize: canvas,
                layers: [paper, sheet, createCameraLayer(cutId: cutId)],
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
    addTearDown(session.dispose);
    const tile = defaultCelTileSize;
    BitmapSurface inkAt(int x, int y) {
      final ink = (y * tile + x) * 4;
      final pixels = Uint8List(tile * tile * 4)
        ..fillRange(ink, ink + 3, 128)
        ..[ink + 3] = 255;
      return BitmapSurface(canvasSize: canvas, tileSize: tile).putTiles([
        (
          coord: TileCoord(x: 0, y: 0),
          tile: BitmapTile(size: tile, pixels: pixels),
        ),
      ]);
    }

    final cut = session.requireActiveCut;
    parkCold(session.renderCaches.brushFrameStore, {
      session.brushFrameKeyForCut(cut, paper.id, paperCel.id): inkAt(5, 5),
      session.brushFrameKeyForCut(cut, sheet.id, sheetCel.id): inkAt(10, 10),
    });
    return session;
  }

  Future<Uint8List> bytesOf(ui.Image image) async {
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// The paper's cel, the sheet on it, written with the tab's [fx] on
  /// nothing.
  Future<Uint8List> celOf(
    EditorSessionManager session,
    ExportLayerFx fx,
  ) async {
    final cut = session.requireActiveCut;
    final image = await ExportFrameRenderer(
      session: session,
      layerFx: fx,
      ground: const ui.Color(0x00000000),
    ).renderCelGroup(
      ExportCelGroupTask(
        cut: cut,
        baseLayer: cut.layers[0],
        members: [cut.layers[0], cut.layers[1]],
        memberFrames: [paperCel, sheetCel],
        baseFrame: paperCel,
        celName: '1',
        fileName: 'A1.png',
      ),
      ExportSizeMode.canvas,
      guideColor: const ui.Color(0xFF000000),
    );
    return bytesOf(image!);
  }

  /// The cut's frame 0 as the screen shows it, on white.
  Future<Uint8List> frameOf(EditorSessionManager session) async => bytesOf(
    await ExportFrameRenderer(session: session).renderComposite(
      ExportFrameTask(cut: session.requireActiveCut, frameIndex: 0),
      ExportSizeMode.canvas,
    ),
  );

  /// Where [rgba] holds ink: dark on white, or opaque on nothing.
  List<(int, int)> inkOf(Uint8List rgba, {bool onWhite = true}) => [
    for (var i = 0; i < rgba.length ~/ 4; i += 1)
      if (onWhite ? rgba[i * 4] < 200 : rgba[i * 4 + 3] > 128)
        (i % canvas.width, i ~/ canvas.width),
  ];

  testWidgets('🚨a cel lays the sheet where the paper\'s reference fx moves '
      'the paper — as the screen shows it, and laid as drawn under 끔', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = sessionOf();
      const moved = [(8, 5), (13, 10)];

      expect(
        inkOf(await frameOf(session)),
        moved,
        reason: 'the screen: the fx carries both 3 to the right',
      );
      for (final (fx, ink) in [
        (ExportLayerFx.on, moved),
        (ExportLayerFx.basic, moved),
        (ExportLayerFx.off, [(5, 5), (10, 10)]),
      ]) {
        expect(
          inkOf(await celOf(session, fx), onWhite: false),
          ink,
          reason: '$fx',
        );
      }
    });
    await tester.pumpAndSettle();
  });
}
