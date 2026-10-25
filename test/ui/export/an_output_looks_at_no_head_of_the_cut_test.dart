import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart' show ExportLayerFx;
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_reference.dart';
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
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

/// What an output keeps of the cut's heads (I-65, 유저 2026-10-25):
///
/// * Q8 「출력은 이 머리도 안 본다」 — 「그 두개는 기본만켬에 포함. 시퀀스
///   출력같은거 얘기잖아」: the camera row's switch and the V row's hide the
///   camera work and the V row's chain on the screen; an output keeps both
///   whatever they and the window's 레이어 FX say.
/// * Q9 「화면 그대로(지금)」: a picture of the screen (no 레이어 FX to ask)
///   keeps both switches.
/// * Q7 「참조 fx 만 따른다」 — 「트랜스폼은 기본만켬에서 빠진다고 몇번이나
///   말했잖아」: a cel goes out on its paper — its reference fx moves it under
///   켬 and 기본만 켬, its transform never.
void main() {
  const canvas = CanvasSize(width: 32, height: 32);
  const cutId = CutId('cut');
  const layerId = LayerId('a');
  final drawing = Frame(
    id: const FrameId('f1'),
    duration: 1,
    strokes: const [],
    name: '1',
  );
  final brightness = LayerEffect(
    id: const EffectId('fx'),
    kind: EffectKind.brightnessContrast,
    parameters: {'brightness': EffectParameter(value: 50)},
  );

  /// One cut on a V row wearing [trackEffects] behind its switch
  /// [trackFxEnabled], its row (as [row] makes it) holding one grey pixel
  /// at (10, 10).
  EditorSessionManager sessionOf({
    Layer Function(Layer layer)? row,
    List<LayerEffect> trackEffects = const [],
    bool trackFxEnabled = true,
  }) {
    final layer = Layer(
      id: layerId,
      name: 'A',
      frames: [drawing],
      timeline: {0: TimelineExposure.drawing(drawing.id, length: 4)},
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
            effects: trackEffects,
            fxEnabled: trackFxEnabled,
            cuts: [
              Cut(
                id: cutId,
                name: 'CUT',
                duration: 4,
                canvasSize: canvas,
                layers: [
                  row?.call(layer) ?? layer,
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
    const ink = (10 * tile + 10) * 4;
    final pixels = Uint8List(tile * tile * 4)
      ..fillRange(ink, ink + 3, 128)
      ..[ink + 3] = 255;
    session.renderCaches.brushFrameStore.storeRebuiltDisplayCache(
      key: session.brushFrameKeyForCut(
        session.requireActiveCut,
        layerId,
        drawing.id,
      ),
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

  Future<Uint8List> bytesOf(ui.Image image) async {
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// The frame written with [fx] — null for a picture of the screen — in
  /// [mode], on white.
  Future<Uint8List> pictureOf(
    EditorSessionManager session,
    ExportLayerFx? fx, {
    ExportSizeMode mode = ExportSizeMode.canvas,
  }) async => bytesOf(
    await ExportFrameRenderer(session: session, layerFx: fx).renderComposite(
      ExportFrameTask(cut: session.requireActiveCut, frameIndex: 0),
      mode,
    ),
  );

  /// The row's cel written with the tab's [fx], on nothing.
  Future<Uint8List> celOf(EditorSessionManager session, ExportLayerFx fx) async {
    final cut = session.requireActiveCut;
    final layer = cut.layers.firstWhere((layer) => layer.id == layerId);
    final image = await ExportFrameRenderer(
      session: session,
      layerFx: fx,
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
      ),
      ExportSizeMode.canvas,
      guideColor: const ui.Color(0xFF000000),
    );
    return bytesOf(image!);
  }

  /// Where [rgba] ([width] wide) holds ink: dark on white, or opaque on
  /// nothing.
  List<(int, int)> inkOf(Uint8List rgba, int width, {bool onWhite = true}) => [
    for (var i = 0; i < rgba.length ~/ 4; i += 1)
      if (onWhite ? rgba[i * 4] < 200 : rgba[i * 4 + 3] > 128)
        (i % width, i ~/ width),
  ];

  testWidgets('🚨an output frames the cut through its camera work whatever '
      'the camera row\'s switch says — a picture of the screen keeps the '
      'switch', (tester) async {
    await tester.runAsync(() async {
      final session = sessionOf();
      session.camera.setCameraKeyframeAtCurrentFrame(
        CameraPose(center: CanvasPoint(x: 19, y: 16)),
      );
      Future<List<(int, int)>> inkThrough(ExportLayerFx? fx) async => inkOf(
        await pictureOf(session, fx, mode: ExportSizeMode.camera),
        canvas.width,
      );
      final worked = await inkThrough(ExportLayerFx.on);
      expect(worked, [(7, 10)], reason: 'framed 3 to the right');

      session.effectsAndFx.toggleLayerTransformFx(
        session.requireActiveCut.layers.cameraLayer!.id,
      );
      expect(session.requireActiveCut.layers.cameraWorkBypassed, isTrue);
      for (final fx in ExportLayerFx.values) {
        expect(await inkThrough(fx), worked, reason: '$fx');
      }
      expect(await inkThrough(null), [(10, 10)], reason: 'centred, as shown');
    });
    await tester.pumpAndSettle();
  });

  testWidgets('🚨a film lays the V row\'s fx whatever its switch says — a '
      'picture of the screen keeps the switch', (tester) async {
    await tester.runAsync(() async {
      final session = sessionOf(
        trackEffects: [brightness],
        trackFxEnabled: false,
      );
      Future<int> redAtTheInk(ExportLayerFx? fx, ExportSizeMode mode) async {
        final rgba = await bytesOf(
          await ExportFrameRenderer(session: session, layerFx: fx)
              .videoRun([
                ExportFrameTask(cut: session.requireActiveCut, frameIndex: 0),
              ], mode)
              .frame(0),
        );
        return rgba[(10 * canvas.width + 10) * 4];
      }

      for (final mode in ExportSizeMode.values) {
        final bare = await redAtTheInk(null, mode);
        expect(
          bare,
          closeTo(128, 2),
          reason: '$mode: the switch is off on the screen',
        );
        for (final fx in ExportLayerFx.values) {
          expect(
            await redAtTheInk(fx, mode),
            greaterThan(bare + 20),
            reason: '$mode, $fx: the chain brightens the ink',
          );
        }
      }
    });
    await tester.pumpAndSettle();
  });

  testWidgets('🚨a cel goes out on its paper — its reference fx moves it '
      'under 켬 and 기본만 켬, its transform never', (tester) async {
    await tester.runAsync(() async {
      final session = sessionOf(
        row: (layer) => layer.copyWith(
          mediaReference: MediaReference(
            assetPath: 'paper.png',
            laid: TransformPose(center: CanvasPoint(x: 16, y: 16)),
            pose: TransformPose(center: CanvasPoint(x: 19, y: 16)),
            pictureSize: canvas,
          ),
          transformTrack: TransformTrack.empty().copyWith(
            position: PropertyTrack<CanvasPoint>().withKey(
              0,
              CanvasPoint(x: 16, y: 21),
            ),
          ),
        ),
      );
      for (final (fx, ink) in [
        (ExportLayerFx.on, (13, 10)),
        (ExportLayerFx.basic, (13, 10)),
        (ExportLayerFx.off, (10, 10)),
      ]) {
        expect(
          inkOf(await celOf(session, fx), canvas.width, onWhite: false),
          [ink],
          reason: '$fx',
        );
      }
    });
    await tester.pumpAndSettle();
  });
}
