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
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_spec.dart' show ExportLayerFx;
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/import/import_warning.dart';
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
/// * Q11 「켬 · 기본만 켬이면 화면 스위치대로, 끔이면 빠짐 — 카메라 행도
///   같이」: the camera row's switch and the V row's hide the camera work
///   and the V row's chain on the screen; an output keeps each as the screen
///   shows it under 켬 and 기본만 켬, and neither under 끔 — a still as a
///   video (Q10 a 「이미지 탭에도 V 행 fx 를 깐다」). ↩️Q8 「출력은 이 머리도
///   안 본다」 kept both whatever the switches and the window said.
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

  testWidgets('🚨an output frames the cut through its camera work as the '
      'camera row\'s switch shows it under 켬 and 기본만 켬 — centred under '
      '끔', (tester) async {
    await tester.runAsync(() async {
      final session = sessionOf();
      session.camera.setCameraKeyframeAtCurrentFrame(
        CameraPose(center: CanvasPoint(x: 19, y: 16)),
      );
      Future<List<(int, int)>> inkThrough(ExportLayerFx? fx) async => inkOf(
        await pictureOf(session, fx, mode: ExportSizeMode.camera),
        canvas.width,
      );
      const worked = [(7, 10)];
      const centred = [(10, 10)];
      expect(await inkThrough(null), worked, reason: 'framed 3 to the right');
      for (final (fx, ink) in [
        (ExportLayerFx.on, worked),
        (ExportLayerFx.basic, worked),
        (ExportLayerFx.off, centred),
      ]) {
        expect(await inkThrough(fx), ink, reason: '$fx, switched on');
      }

      session.effectsAndFx.toggleLayerTransformFx(
        session.requireActiveCut.layers.cameraLayer!.id,
      );
      expect(session.requireActiveCut.layers.cameraWorkBypassed, isTrue);
      expect(await inkThrough(null), centred, reason: 'centred, as shown');
      for (final fx in ExportLayerFx.values) {
        expect(await inkThrough(fx), centred, reason: '$fx, switched off');
      }
    });
    await tester.pumpAndSettle();
  });

  /// The red at the ink of [session]'s first frame, written with [fx] — null
  /// for a picture of the screen — in [mode] by [draw]: a video's frame or
  /// a still's.
  Future<int> redAtTheInk(
    EditorSessionManager session,
    ExportLayerFx? fx,
    ExportSizeMode mode, {
    required Future<ui.Image> Function(
      ExportFrameRenderer renderer,
      ExportFrameTask task,
    )
    draw,
  }) async {
    final rgba = await bytesOf(
      await draw(
        ExportFrameRenderer(session: session, layerFx: fx),
        ExportFrameTask(cut: session.requireActiveCut, frameIndex: 0),
      ),
    );
    return rgba[(10 * canvas.width + 10) * 4];
  }

  for (final (output, draw) in [
    (
      'a film',
      (ExportFrameRenderer renderer, ExportFrameTask task, ExportSizeMode m) =>
          renderer.videoRun([task], m).frame(0),
    ),
    (
      'a picture sequence',
      (ExportFrameRenderer renderer, ExportFrameTask task, ExportSizeMode m) =>
          renderer.stillRun([task], m).frame(0),
    ),
    (
      'a still',
      (ExportFrameRenderer renderer, ExportFrameTask task, ExportSizeMode m) =>
          renderer.renderComposite(task, m),
    ),
  ]) {
    testWidgets('🚨$output lays the V row\'s fx as its switch shows it under '
        '켬 and 기본만 켬 — never under 끔', (tester) async {
      await tester.runAsync(() async {
        final switchedOff = sessionOf(
          trackEffects: [brightness],
          trackFxEnabled: false,
        );
        final switchedOn = sessionOf(trackEffects: [brightness]);

        for (final mode in ExportSizeMode.values) {
          Future<int> red(EditorSessionManager session, ExportLayerFx? fx) =>
              redAtTheInk(
                session,
                fx,
                mode,
                draw: (renderer, task) => draw(renderer, task, mode),
              );
          final bare = await red(switchedOff, null);
          expect(
            bare,
            closeTo(128, 2),
            reason: '$mode: the switch is off on the screen',
          );
          expect(
            await red(switchedOn, null),
            greaterThan(bare + 20),
            reason: '$mode: the switch is on on the screen',
          );
          for (final fx in ExportLayerFx.values) {
            expect(
              await red(switchedOff, fx),
              closeTo(bare, 2),
              reason: '$mode, $fx: switched off',
            );
            final laid = await red(switchedOn, fx);
            expect(
              fx == ExportLayerFx.off ? laid < bare + 20 : laid > bare + 20,
              isTrue,
              reason: '$mode, $fx, switched on: $laid against $bare',
            );
          }
        }
      });
      await tester.pumpAndSettle();
    });
  }

  /// The V row's [brightness] keyed [from] at track frame 0 and [to] at
  /// track frame [at].
  LayerEffect brightening({
    required double from,
    required double to,
    required int at,
  }) => LayerEffect(
    id: const EffectId('fx'),
    kind: EffectKind.brightnessContrast,
    parameters: {
      'brightness': EffectParameter(
        track: PropertyTrack<double>().withKey(0, from).withKey(at, to),
      ),
    },
  );

  testWidgets('a picture sequence lays each frame\'s own chain — the same '
      'drawing under a keyed V row is two pictures', (tester) async {
    await tester.runAsync(() async {
      final session = sessionOf(
        trackEffects: [brightening(from: 0, to: 50, at: 1)],
      );
      final cut = session.requireActiveCut;
      final run = ExportFrameRenderer(
        session: session,
        layerFx: ExportLayerFx.on,
      ).stillRun([
        ExportFrameTask(cut: cut, frameIndex: 0),
        ExportFrameTask(cut: cut, frameIndex: 1),
      ], ExportSizeMode.canvas);
      int red(Uint8List rgba) => rgba[(10 * canvas.width + 10) * 4];

      final first = red(await bytesOf(await run.frame(0)));
      final second = red(await bytesOf(await run.frame(1)));
      expect(first, closeTo(128, 2), reason: 'keyed at nothing there');
      expect(second, greaterThan(first + 20));
    });
    await tester.pumpAndSettle();
  });

  testWidgets('the V row\'s chain is read where the frame stands on the '
      'track, not on the cut', (tester) async {
    await tester.runAsync(() async {
      final session = sessionOf(
        trackEffects: [brightening(from: 0, to: 50, at: 4)],
      );
      session.repository.updateCutLeadingGap(
        cutId: cutId,
        leadingGapFrames: 4,
      );
      final rgba = await pictureOf(session, ExportLayerFx.on);

      expect(
        rgba[(10 * canvas.width + 10) * 4],
        greaterThan(128 + 20),
        reason: 'the cut\'s first frame is the track\'s fifth',
      );
    });
    await tester.pumpAndSettle();
  });

  testWidgets('a layered file lays no V row\'s fx, which none of its rows '
      'can hold — and says it left them out', (tester) async {
    await tester.runAsync(() async {
      const psd = ExportFormatSelection(
        kind: ExportMediaKind.still,
        stillFormat: ExportStillFormat.psd,
      );
      ExportFrameRenderer rendererOf(
        EditorSessionManager session,
        ExportLayerFx fx, {
        ExportFormatSelection format = psd,
      }) => ExportFrameRenderer.forFormat(
        session: session,
        format: format,
        layerFx: fx,
      );
      final session = sessionOf(trackEffects: [brightness]);
      final task = ExportFrameTask(
        cut: session.requireActiveCut,
        frameIndex: 0,
      );
      final rgba = await bytesOf(
        await rendererOf(
          session,
          ExportLayerFx.on,
        ).renderComposite(task, ExportSizeMode.canvas),
      );

      expect(rgba[(10 * canvas.width + 10) * 4], closeTo(128, 2));
      expect(rendererOf(session, ExportLayerFx.on).leftOutOfRows(task), [
        layerEffectsNotApplied('V1'),
      ]);
      expect(
        rendererOf(session, ExportLayerFx.off).leftOutOfRows(task),
        isEmpty,
        reason: 'under 끔 no file lays it',
      );
      final switchedOff = sessionOf(
        trackEffects: [brightness],
        trackFxEnabled: false,
      );
      expect(
        rendererOf(switchedOff, ExportLayerFx.on).leftOutOfRows(
          ExportFrameTask(cut: switchedOff.requireActiveCut, frameIndex: 0),
        ),
        isEmpty,
        reason: 'switched off, no file lays it',
      );
      expect(
        rendererOf(
          session,
          ExportLayerFx.on,
          format: const ExportFormatSelection(kind: ExportMediaKind.still),
        ).leftOutOfRows(task),
        isEmpty,
        reason: 'a PNG lays it',
      );
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
