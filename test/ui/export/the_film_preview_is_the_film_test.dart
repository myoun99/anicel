import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_format_selection.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/persistence/app_export_settings.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_dialog.dart';
import 'package:anicel/src/ui/export/export_format_availability.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

import '../../helpers/cels_parked_cold.dart';
import '../../helpers/export_preview_probe.dart';

/// 🗣️export-film-preview-is-not-the-film (11-04): the export window's
/// preview of a film is the frame its file holds — the stage and its
/// paper, the tracks over it, the pose and the fade — drawn at the
/// preview's size. ↩️It drew a still of the cut: on the format's ground, a
/// checkerboard under a film that keeps its clear colour, where the file
/// lays the paper.
///
/// And Q1 (유저 2026-11-04: 「깐다 — 카메라 크기와 같게」): a canvas-size
/// film lays the paper as a camera-size one does. ↩️It stood on its ground
/// alone, whatever the paper.
void main() {
  setUp(() => AppExport.settings.value = AppExportSettings());
  tearDown(() => AppExport.settings.value = AppExportSettings());

  const cream = 0xFFFFEECC;
  const creamPixel = (0xFF, 0xEE, 0xCC, 0xFF);
  const ink = (0, 0, 200, 255);
  const size = CanvasSize(width: 8, height: 8);
  const cutId = CutId('c');
  const rowId = LayerId('row');
  const drawingId = FrameId('drawing');

  const mp4 = ExportFormatSelection();
  const gif = ExportFormatSelection(
    container: ExportVideoContainer.gif,
    videoCodec: ExportVideoCodec.gif,
  );

  /// One cut of one drawing, its camera the canvas — on [paper].
  EditorSessionManager sessionOn(ProjectBackground paper) {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        cameraSize: size,
        background: paper,
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              Cut(
                id: cutId,
                name: 'c',
                duration: 4,
                canvasSize: size,
                layers: [
                  Layer(
                    id: rowId,
                    name: 'A',
                    frames: [
                      Frame(id: drawingId, duration: 4, strokes: const []),
                    ],
                    timeline: const {
                      0: TimelineExposure.drawing(drawingId, length: 4),
                    },
                  ),
                  createCameraLayer(cutId: cutId),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// [session]'s drawing inked on its left half, its right half bare.
  void inkLeftHalf(EditorSessionManager session) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      if ((i ~/ 4) % 8 < 4) {
        pixels
          ..[i + 2] = ink.$3
          ..[i + 3] = 255;
      }
    }
    parkCold(session.renderCaches.brushFrameStore, {
      session.brushFrameKeyForCut(session.requireActiveCut, rowId, drawingId):
          BitmapSurface(
            canvasSize: size,
            tileSize: 8,
            tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
          ),
    });
  }

  ExportFrameTask first(EditorSessionManager session) =>
      ExportFrameTask(cut: session.requireActiveCut, frameIndex: 0);

  /// The renderer the window writes a film in [format] with.
  ExportFrameRenderer filmRenderer(
    EditorSessionManager session,
    ExportFormatSelection format,
  ) {
    final renderer = ExportFrameRenderer.forFormat(
      session: session,
      format: format,
      layerFx: ExportLayerFx.on,
      alphaVideo: format.wantsAlpha,
    );
    addTearDown(renderer.dispose);
    return renderer;
  }

  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  (int, int, int, int) pixelOf(Uint8List rgba, int x, int y, int width) {
    final at = (y * width + x) * 4;
    return (rgba[at], rgba[at + 1], rgba[at + 2], rgba[at + 3]);
  }

  /// [session]'s first frame as a film in [format] draws it in [mode], at
  /// [outputSize] where one is asked.
  Future<Uint8List> filmFrame(
    EditorSessionManager session,
    ExportFormatSelection format,
    ExportSizeMode mode, {
    CanvasSize? outputSize,
  }) async => bytesOf(
    await filmRenderer(session, format).renderVideoFrame(
      first(session),
      mode,
      preserveAlpha: format.wantsAlpha,
      outputSize: outputSize,
    ),
  );

  testWidgets('🚨a canvas-size film lays the paper, as a camera-size one '
      'does — in an opaque film and in one that keeps its clear colour', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = sessionOn(const ProjectBackground.color(cream));
      inkLeftHalf(session);
      for (final format in [mp4, gif]) {
        expect(format.wantsAlpha, format == gif, reason: '⛔premise');
        for (final mode in ExportSizeMode.values) {
          final frame = await filmFrame(session, format, mode);
          expect(
            (pixelOf(frame, 1, 4, 8), pixelOf(frame, 6, 4, 8)),
            (ink, creamPixel),
            reason: '${format.container} at the $mode size',
          );
        }
      }
    });
  });

  testWidgets('under a paper that is NONE a canvas-size film lays nothing: '
      'clear where it keeps its clear colour, the white it stands on where '
      'it is opaque', (tester) async {
    // Q1's own words: 「캔버스 색이 「없음」이면 알파 형식에서 투명, 불투명
    // 형식에서 흰 바탕」. (A camera-size film shows the backdrop there, the
    // stage's floor — R3b.)
    await tester.runAsync(() async {
      final session = sessionOn(
        const ProjectBackground.color(cream, none: true),
      );
      expect(
        pixelOf(await filmFrame(session, gif, ExportSizeMode.canvas), 4, 4, 8),
        (0, 0, 0, 0),
      );
      expect(
        pixelOf(await filmFrame(session, mp4, ExportSizeMode.canvas), 4, 4, 8),
        (255, 255, 255, 255),
      );
    });
  });

  testWidgets('🚨a film\'s frame asked at a preview\'s size is the same '
      'frame, smaller — and at its own size, the frame its run writes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = sessionOn(const ProjectBackground.color(cream));
      inkLeftHalf(session);
      for (final mode in ExportSizeMode.values) {
        final half = await filmFrame(
          session,
          mp4,
          mode,
          outputSize: const CanvasSize(width: 4, height: 4),
        );
        expect(half.length, 4 * 4 * 4, reason: 'at the size asked ($mode)');
        // Inside the edge: a reduced render's paper yields the pixel the
        // canvas's edge falls in to the rows (#15).
        expect(
          (pixelOf(half, 1, 2, 4), pixelOf(half, 2, 2, 4)),
          (ink, creamPixel),
          reason: 'the ink on the left, the paper on the right ($mode)',
        );

        final renderer = filmRenderer(session, mp4);
        expect(
          await filmFrame(session, mp4, mode),
          await bytesOf(
            await renderer
                .videoRun([first(session)], mode, preserveAlpha: false)
                .frame(0),
          ),
          reason: 'one frame, whoever asks for it ($mode)',
        );
      }
    });
  });

  testWidgets('one renderer asked for a frame at two sizes draws each at '
      'its own — and a frame nothing plays in at the size asked too', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = sessionOn(const ProjectBackground.color(cream));
      inkLeftHalf(session);
      const quarter = CanvasSize(width: 4, height: 4);
      for (final mode in ExportSizeMode.values) {
        // The window keeps one renderer for its preview, whatever the size
        // the preview asks at.
        final renderer = filmRenderer(session, mp4);
        Future<Uint8List> at(CanvasSize? size, {int frameIndex = 0}) async =>
            bytesOf(
              await renderer.renderVideoFrame(
                ExportFrameTask(
                  cut: session.requireActiveCut,
                  frameIndex: frameIndex,
                ),
                mode,
                preserveAlpha: false,
                outputSize: size,
              ),
            );
        expect((await at(null)).length, 8 * 8 * 4, reason: '$mode');
        final small = await at(quarter);
        expect(
          (small.length, pixelOf(small, 1, 2, 4), pixelOf(small, 2, 2, 4)),
          (4 * 4 * 4, ink, creamPixel),
          reason: 'not the picture held from the size before ($mode)',
        );
        expect(
          (await at(quarter, frameIndex: -1)).length,
          4 * 4 * 4,
          reason: 'a gap ($mode)',
        );
      }
    });
  });

  group('the window', () {
    Future<void> pumpWindow(
      WidgetTester tester,
      EditorSessionManager session, {
      required ExportFormatSelection format,
      required ExportSizeMode sizeMode,
    }) async {
      AppExport.settings.value = AppExportSettings(
        lastSpecs: ExportTabSpecs(
          sequence: SequenceExportSpec(format: format, sizeMode: sizeMode),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExportDialog(
              session: session,
              formatAvailability: ExportFormatAvailability.permissive(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.settleExportPreview();
    }

    /// The pixel of the preview's picture over the canvas's ([x], [y]).
    Future<(int, int, int, int)> previewPixel(
      WidgetTester tester,
      int x,
      int y,
    ) async {
      final image = tester.exportPreviewImage!;
      final width = image.width;
      final scale = width / size.width;
      final rgba = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!.buffer.asUint8List();
      return pixelOf(rgba, (x * scale).floor(), (y * scale).floor(), width);
    }

    for (final format in [mp4, gif]) {
      for (final sizeMode in ExportSizeMode.values) {
        testWidgets('🚨the Sequence tab\'s preview of a film is its file\'s '
            'frame: the paper under the bare canvas — ${format.container} '
            'at the ${sizeMode.name} size', (tester) async {
          final session = sessionOn(const ProjectBackground.color(cream));
          inkLeftHalf(session);
          await pumpWindow(
            tester,
            session,
            format: format,
            sizeMode: sizeMode,
          );
          expect(tester.exportPreviewImage, isNotNull, reason: 'LIVENESS');
          expect(await previewPixel(tester, 1, 4), ink);
          expect(await previewPixel(tester, 6, 4), creamPixel);
          session.playbackRig.prerenderScheduler.cancel();
        });
      }
    }

    testWidgets('a film that keeps its clear colour is previewed clear where '
        'its file is: a canvas-size GIF under a paper that is none', (
      tester,
    ) async {
      final session = sessionOn(
        const ProjectBackground.color(cream, none: true),
      );
      inkLeftHalf(session);
      await pumpWindow(
        tester,
        session,
        format: gif,
        sizeMode: ExportSizeMode.canvas,
      );
      expect(await previewPixel(tester, 1, 4), ink, reason: 'LIVENESS');
      expect(await previewPixel(tester, 6, 4), (0, 0, 0, 0));
      session.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('an opaque film\'s preview stands on the white its file '
        'stands on, whatever colour the choice still carries for a still', (
      tester,
    ) async {
      final session = sessionOn(
        const ProjectBackground.color(cream, none: true),
      );
      await pumpWindow(
        tester,
        session,
        format: mp4.copyWith(backgroundArgb: 0xFF000000),
        sizeMode: ExportSizeMode.canvas,
      );
      expect(await previewPixel(tester, 4, 4), (255, 255, 255, 255));
      session.playbackRig.prerenderScheduler.cancel();
    });
  });
}
