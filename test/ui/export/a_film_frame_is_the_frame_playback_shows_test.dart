import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuShown;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_instruction.dart';
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
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart' show CelRead;
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/panel_pictures.dart';
import 'package:anicel/src/ui/export/still_image_encoders.dart'
    show ExportLayerRow;
import 'package:anicel/src/native/app_gpu_engine.dart' show appGpuExport;
import 'package:anicel/src/ui/frame_shots.dart'
    show debugOverlayRasters, pictureOfLaid;

import '../../helpers/a_film_frame_on_the_engine.dart';
import '../../helpers/cels_parked_cold.dart';

/// 🗣️유저 2026-10-13 (card video-export-speed-Q2): 「캔버스 규칙으로」 — a
/// film is drawn as the canvas draws: each cut through its camera at the
/// film's size, reduced as the canvas reduces — each row from its own mip
/// chain (`filterQualityForDisplayScale`) — cut at its canvas's edge, and
/// laid on its stage as playback lays it. ↩️Reduced by the display's
/// halvings (`displayLevelOf`), until one-picture-per-frame ②-5b-3.
///
/// ↩️A film's cut was composited at the canvas's full size and projected
/// through the camera in one bilinear draw. 🔬On a grid of lines a pixel
/// wide through a camera at a zoom of 0.47, 1,009 of 1,296 pixels came out
/// apart from the canvas's reduction, by up to 125 levels; at 0.42 lines
/// went missing ten pixels and more at a stretch — the user's film runs at
/// 0.42–0.52.
void main() {
  /// Every pixel's bytes of [image], which this lets go of.
  Future<Uint8List> bytesOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// The pixel at ([x], [y]) of [bytes], a picture [width] pixels wide.
  (int, int, int, int) pixelOf(Uint8List bytes, int width, int x, int y) {
    final i = (y * width + x) * 4;
    return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]);
  }

  /// [paint] decides each pixel of a [canvas] in the engine's tiles —
  /// premultiplied, as the tiles hold it — over the tiles [coords] names,
  /// or, unless told, inside the canvas alone, over the tiles it lies in.
  BitmapSurface surfaceOf(
    CanvasSize canvas,
    int? Function(int x, int y) paint, {
    Iterable<TileCoord>? coords,
  }) {
    const tile = defaultCelTileSize;
    final insideTheCanvas = coords == null;
    final tiles = <TileCoord, BitmapTile>{};
    for (final coord
        in coords ??
            [
              for (var ty = 0; ty * tile < canvas.height; ty += 1)
                for (var tx = 0; tx * tile < canvas.width; tx += 1)
                  TileCoord(x: tx, y: ty),
            ]) {
      final pixels = Uint8List(tile * tile * 4);
      var any = false;
      for (var y = 0; y < tile; y += 1) {
        for (var x = 0; x < tile; x += 1) {
          final (atX, atY) = (coord.x * tile + x, coord.y * tile + y);
          if (insideTheCanvas &&
              (atX >= canvas.width || atY >= canvas.height)) {
            continue;
          }
          final argb = paint(atX, atY);
          if (argb == null) {
            continue;
          }
          any = true;
          final a = argb >>> 24;
          final i = (y * tile + x) * 4;
          pixels[i] = ((argb >> 16 & 0xFF) * a / 255).round();
          pixels[i + 1] = ((argb >> 8 & 0xFF) * a / 255).round();
          pixels[i + 2] = ((argb & 0xFF) * a / 255).round();
          pixels[i + 3] = a;
        }
      }
      if (any) {
        tiles[coord] = BitmapTile(size: tile, pixels: pixels);
      }
    }
    return BitmapSurface(canvasSize: canvas, tileSize: tile, tiles: tiles);
  }

  /// A row [id] showing its one drawing for [duration] frames.
  Layer row(String id, {int duration = 1}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f'), duration: duration, strokes: [])],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$id-f'), length: duration),
    },
  );

  /// Parks [drawings] — each a cut, one of its rows by id, and that row's
  /// drawing — as every drawing [session] holds: parking puts back the
  /// whole store, so they go in at once.
  void ink(
    EditorSessionManager session,
    List<(Cut, String, BitmapSurface)> drawings,
  ) {
    parkCold(session.renderCaches.brushFrameStore, {
      for (final (cut, id, surface) in drawings)
        session.brushFrameKeyForCut(cut, LayerId(id), FrameId('$id-f')):
            surface,
    });
  }

  group('through a camera that reduces', () {
    const canvas = CanvasSize(width: 240, height: 160);
    const frameSize = CanvasSize(width: 48, height: 27);
    const cutId = CutId('cut');

    // Lines a pixel wide: down every 7th column, across every 9th row.
    final lines = surfaceOf(
      canvas,
      (x, y) => x % 7 == 0 || y % 9 == 0 ? 0xFF141414 : null,
    );
    // A half-clear red block over part of them.
    final block = surfaceOf(
      canvas,
      (x, y) => x >= 100 && x < 150 && y >= 60 && y < 100 ? 0x80E02020 : null,
    );

    /// The grid's cut through a camera at [zoom], its centre between pixels.
    CameraPose poseAt(double zoom) =>
        CameraPose(center: CanvasPoint(x: 121.3, y: 79.6), zoom: zoom);

    /// The grid's cut through a camera at [pose].
    EditorSessionManager session(CameraPose pose) {
      final s = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'Project',
          cameraSize: frameSize,
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Track',
              cuts: [
                Cut(
                  id: cutId,
                  name: 'Cut',
                  duration: 1,
                  canvasSize: canvas,
                  camera: CutCamera(keyframes: {0: pose}),
                  layers: [
                    row('block'),
                    row('lines'),
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
      ink(s, [(cut, 'lines', lines), (cut, 'block', block)]);
      return s;
    }

    /// A picture of the sequence of [s]'s cut.
    Future<Uint8List> stillOf(EditorSessionManager s) async {
      final renderer = ExportFrameRenderer(session: s);
      addTearDown(renderer.dispose);
      return bytesOf(
        await renderer.renderComposite(
          ExportFrameTask(cut: s.requireActiveCut, frameIndex: 0),
          ExportSizeMode.camera,
        ),
      );
    }

    /// The cut's frame as a film's frame, a picture of the sequence and a
    /// panel's picture as wide as the film.
    Future<({Uint8List video, Uint8List still, Uint8List panel})> routes(
      double zoom,
    ) async {
      final s = session(poseAt(zoom));
      addTearDown(s.dispose);
      final renderer = ExportFrameRenderer(session: s);
      addTearDown(renderer.dispose);
      final cut = s.requireActiveCut;
      final task = ExportFrameTask(cut: cut, frameIndex: 0);
      return (
        video: await bytesOf(
          await pictureOfFilmFrame(
            renderer.videoRun([task], ExportSizeMode.camera).frame(0),
          ),
        ),
        still: await stillOf(s),
        panel: await bytesOf(
          await PanelPictures(
            session: s,
          ).render(cut, 0, width: frameSize.width),
        ),
      );
    }

    for (final zoom in [0.47, 0.42, 0.94]) {
      testWidgets('🎯at a zoom of $zoom, a film\'s frame and a picture of the '
          'sequence are one picture, and a panel\'s picture is the picture '
          'of the sequence, byte for byte', (tester) async {
        await tester.runAsync(() async {
          final (:video, :still, :panel) = await routes(zoom);
          expect(still.length, frameSize.width * frameSize.height * 4);
          // 🗣️유저 11-08: 「지금화면이랑 맞출필요는없어. 어차피 더
          // 개선되는방향성이고, 바뀌고 나서만 동일하면되」 — both are the
          // frame's one picture through one view on one paper now (7′,
          // `frameOnTheEngine`). ↩️A panel was cut from that picture while a
          // still composed its rows again through the camera: a few levels
          // apart, and only beside a still at a camera moved by the panel's
          // snap.
          expect(panel, still);
          // The film lays the cut's picture — composed on clear — on its
          // stage's paper, as playback lays it: rounded once more than a
          // picture composed straight onto its ground.
          var most = 0;
          for (var i = 0; i < video.length; i += 1) {
            final apart = (video[i] - still[i]).abs();
            most = apart > most ? apart : most;
          }
          expect(most, lessThanOrEqualTo(2));
        });
      });
    }

    testWidgets('🎯at a zoom of 0.42, every line a pixel wide reaches the '
        'film with its own ink — none lost between the samples, none '
        'doubled', (tester) async {
      await tester.runAsync(() async {
        final (:video, still: _, panel: _) = await routes(0.42);
        // The film's second row: canvas rows 49.8–52.2, between the lines
        // across at 45 and 54.
        const y = 1;
        // A line at canvas column x lies at film column
        // 24 + (x + 0.5 − 121.3) × 0.42; it covers 0.42 of a film pixel,
        // so it darkens the white by 0.42 × (255 − 0x14) ≈ 99 all told —
        // most of it over the two pixels whose centres stand either side
        // of it. Lost between the samples it was ~0 there, doubled ~198:
        // each line holds within half of its own. 🔬Read from its chain
        // (one-picture-per-frame ②-5b-3) the two hold 71–127 (2026-10-25):
        // a level's texel is wider than a film pixel, so a line spreads a
        // little past the two, and the line across at 54 reaches row 1.
        // ↩️Within a quarter (75–125) while each row was halved, a 2×2 box
        // a time, and only the rest of the reduction filtered.
        var lines = 0;
        for (var x = 0; x < canvas.width; x += 7) {
          final at = 24 + (x + 0.5 - 121.3) * 0.42;
          final left = (at - 0.5).floor();
          if (left < 0 || left + 1 >= frameSize.width) {
            continue;
          }
          lines += 1;
          var ink = 0;
          for (final column in [left, left + 1]) {
            ink += 255 - pixelOf(video, frameSize.width, column, y).$2;
          }
          expect(
            ink,
            inInclusiveRange(50, 148),
            reason: 'the line at canvas column $x, at film column $at',
          );
        }
        expect(lines, 16, reason: 'LIVENESS: the lines in shot');
      });
    });
  });

  /// What is parked past the canvas, filmed through a camera at [pose] that
  /// sees past its left edge, read at the film's pixel [probe]: canvas
  /// (−40, 128), in the red.
  Future<void> parkedStaysOut(
    WidgetTester tester,
    CameraPose pose,
    (int, int) probe,
  ) async {
    final (px, py) = probe;
    await tester.runAsync(() async {
      // Two tiles a side.
      const canvas = CanvasSize(
        width: 2 * defaultCelTileSize,
        height: 2 * defaultCelTileSize,
      );
      const cutId = CutId('cut');
      // Red ink on the pasteboard tiles left of the canvas — x −128 to −1.
      final parked = surfaceOf(
        canvas,
        (_, _) => 0xFFFF0000,
        coords: [TileCoord(x: -1, y: 0), TileCoord(x: -1, y: 1)],
      );
      final s = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'Project',
          cameraSize: canvas,
          pasteboardArgb: 0xFF0000FF,
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Track',
              cuts: [
                Cut(
                  id: cutId,
                  name: 'Cut',
                  duration: 1,
                  canvasSize: canvas,
                  camera: CutCamera(keyframes: {0: pose}),
                  layers: [row('parked'), createCameraLayer(cutId: cutId)],
                ),
              ],
            ),
          ],
          createdAt: DateTime.utc(2026),
        ),
      );
      addTearDown(s.dispose);
      final cut = s.requireActiveCut;
      ink(s, [(cut, 'parked', parked)]);
      final key = s.brushFrameKeyForCut(
        cut,
        const LayerId('parked'),
        const FrameId('parked-f'),
      );
      expect(
        s.renderCaches.brushFrameStore
            .currentSurfaceWithoutReplay(
              key,
              canvasSize: canvas,
              read: CelRead.look,
            )
            ?.tiles
            .keys,
        contains(TileCoord(x: -1, y: 0)),
        reason: 'LIVENESS: the cel holds the parked ink',
      );
      final renderer = ExportFrameRenderer(session: s);
      addTearDown(renderer.dispose);
      final task = ExportFrameTask(cut: cut, frameIndex: 0);

      final video = await bytesOf(
        await pictureOfFilmFrame(
          renderer.videoRun([task], ExportSizeMode.camera).frame(0),
        ),
      );
      final still = await bytesOf(
        await renderer.renderComposite(task, ExportSizeMode.camera),
      );
      // Canvas (−40, 128), in the red.
      expect(
        pixelOf(video, canvas.width, px, py),
        (0, 0, 255, 255),
        reason: 'the stage\'s apron, past the paper',
      );
      expect(
        pixelOf(still, canvas.width, px, py),
        (255, 255, 255, 255),
        reason: 'the picture\'s ground, past the canvas',
      );
      // A layered file's row of it, drawn by itself on nothing — cut at the
      // canvas's edge as the frame is.
      final parkedRow = renderer
          .frameRows(task, ExportSizeMode.camera)
          .whereType<ExportLayerRow>()
          .singleWhere((row) => row.name == 'parked');
      final layered = await bytesOf(await parkedRow.draw());
      expect(
        pixelOf(layered, canvas.width, px, py),
        (0, 0, 0, 0),
        reason: 'a layered file\'s row, past the canvas',
      );
    });
  }

  // Its frame from canvas x −64 to 192: a quarter past the canvas's left
  // edge. Canvas (−40, 128) stands where the canvas does at (24, 128).
  testWidgets('🎯the film shows no pasteboard: what is parked past the canvas '
      'stays out of a film\'s frame and a picture of the sequence, where the '
      'camera sees past the canvas', (tester) async {
    await parkedStaysOut(
      tester,
      CameraPose(center: CanvasPoint(x: 64, y: 128)),
      (24, 128),
    );
  });

  // A camera turned cuts the canvas's edge through the cover the app
  // rasters of it, where a level one cuts on whole pixels
  // (`frameOnTheEngine`). Canvas (−40, 128) is (−104, 0) from the centre:
  // turned 45°, (−73.5, 73.5) from the film's — its pixel (54, 201).
  testWidgets('🎯the film shows no pasteboard through a camera turned 45° '
      'either', (tester) async {
    await parkedStaysOut(
      tester,
      CameraPose(center: CanvasPoint(x: 64, y: 128), rotationDegrees: 45),
      (54, 201),
    );
  });

  // 🗣️playback-picture-is-not-the-canvas-picture (유저 10-13: 「배율따라서
  // 끝에 흰 선」): the canvas's edge, where rows reduced end in a pixel they
  // cover in part, is drawn as the canvas draws it — no paper past the ink
  // there (the paper yields that output pixel to the rows, #15), and the
  // cut out past every pixel they cover. ↩️The paper yielded a level pixel
  // to rows reduced to a level, until one-picture-per-frame ②-5b-3.
  group('at the canvas\'s edge', () {
    // No whole number of tiles; its edges fall inside the film's pixels.
    const canvas = CanvasSize(width: 60, height: 38);
    const cutId = CutId('cut');
    const blue = 0xFF0000FF;
    const black = 0xFF000000;
    // Ink to the canvas's edge and not a pixel past it.
    final filled = surfaceOf(
      canvas,
      (x, y) => x < canvas.width && y < canvas.height ? 0xFF102030 : null,
    );

    /// The cut through a camera at [pose], on a blue apron over a black
    /// floor — the apron stops at the pasteboard's wall (I-109), and the
    /// floor shows past it: filled to the edge where [inked], blank where
    /// not; [size] for a canvas, and a camera, other than the group's.
    (EditorSessionManager, ExportFrameRenderer) filmAt(
      CameraPose pose, {
      bool inked = true,
      CanvasSize size = canvas,
    }) {
      final s = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'Project',
          cameraSize: size,
          pasteboardArgb: blue,
          backdropArgb: black,
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Track',
              cuts: [
                Cut(
                  id: cutId,
                  name: 'Cut',
                  duration: 1,
                  canvasSize: size,
                  camera: CutCamera(keyframes: {0: pose}),
                  layers: [row('filled'), createCameraLayer(cutId: cutId)],
                ),
              ],
            ),
          ],
          createdAt: DateTime.utc(2026),
        ),
      );
      addTearDown(s.dispose);
      if (inked) {
        ink(s, [(s.requireActiveCut, 'filled', filled)]);
      }
      final renderer = ExportFrameRenderer(session: s);
      addTearDown(renderer.dispose);
      return (s, renderer);
    }

    // Each with the film's row its foot falls in.
    for (final (pose, foot) in [
      (CameraPose(center: CanvasPoint(x: 30, y: 19), zoom: 0.4), 26),
      (CameraPose(center: CanvasPoint(x: 30.3, y: 19.7), zoom: 0.4), 26),
      (CameraPose(center: CanvasPoint(x: 30, y: 19), zoom: 0.2), 22),
    ]) {
      final where =
          '(${pose.center.x}, ${pose.center.y}) at a zoom of ${pose.zoom}';

      testWidgets('🎯through a camera at $where, ink drawn to the edge ends '
          'on the stage\'s apron — no line of paper past it', (tester) async {
        await tester.runAsync(() async {
          final (s, renderer) = filmAt(pose);
          final film = await bytesOf(
            await pictureOfFilmFrame(renderer.videoRun([
              ExportFrameTask(cut: s.requireActiveCut, frameIndex: 0),
            ], ExportSizeMode.camera).frame(0)),
          );
          expect(
            pixelOf(film, canvas.width, 30, 10),
            (0, 0, 255, 255),
            reason: 'LIVENESS: the apron past the canvas',
          );
          final (_, _, edge, _) = pixelOf(film, canvas.width, 30, foot);
          expect(
            edge,
            inExclusiveRange(0x30, 0xFF),
            reason: 'LIVENESS: the edge falls inside a pixel',
          );
          for (var i = 0; i < film.length; i += 4) {
            expect(
              film[i],
              lessThanOrEqualTo(0x11),
              reason:
                  'no white at pixel ${i ~/ 4 % canvas.width}, '
                  '${i ~/ 4 ~/ canvas.width}: the ink\'s red and the apron\'s',
            );
          }
        });
      });

      testWidgets('🎯through a camera at $where, the cut takes nothing of a '
          'pixel the canvas covers in part: a picture of the sequence is the '
          'panel\'s picture, cut where the film is, byte for byte', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final (s, renderer) = filmAt(pose);
          final cut = s.requireActiveCut;
          final still = await bytesOf(
            await renderer.renderComposite(
              ExportFrameTask(cut: cut, frameIndex: 0),
              ExportSizeMode.camera,
            ),
          );
          final (r, _, _, _) = pixelOf(still, canvas.width, 30, foot);
          expect(
            r,
            inExclusiveRange(0x10, 0xFF),
            reason: 'LIVENESS: the edge falls inside a pixel',
          );
          final panel = await bytesOf(
            await PanelPictures(
              session: s,
            ).render(cut, 0, width: canvas.width),
          );
          final apart = <String>[
            for (var y = 0; y < canvas.height; y += 1)
              for (var x = 0; x < canvas.width; x += 1)
                if (pixelOf(still, canvas.width, x, y) !=
                    pixelOf(panel, canvas.width, x, y))
                  '($x, $y): ${pixelOf(still, canvas.width, x, y)} → '
                      '${pixelOf(panel, canvas.width, x, y)}',
          ];
          // ↩️Beside the still at a camera moved by the panel's snap, while
          // a still composed its rows again through the camera — until both
          // were the frame's one picture through one view (7′,
          // `frameOnTheEngine`).
          expect(apart, isEmpty);
        });
      });
    }

    // ↩️The paper yielded the output pixel the canvas's edge falls inside
    // to the rows (#15) while a camera render composed its rows apart from
    // its paper, on Flutter. Composed in one picture with them on the
    // engine and reduced with them (7′), ink drawn to the edge leaves no
    // paper past it (above) — and the paper reaches the canvas's edge.
    testWidgets('🎯where nothing is drawn over it, the paper reaches the '
        'canvas\'s edge — anti-aliased where the edge falls inside a pixel', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final (s, renderer) = filmAt(
          CameraPose(center: CanvasPoint(x: 30.3, y: 19.7), zoom: 0.4),
          inked: false,
        );
        final film = await bytesOf(
          await pictureOfFilmFrame(renderer.videoRun([
            ExportFrameTask(cut: s.requireActiveCut, frameIndex: 0),
          ], ExportSizeMode.camera).frame(0)),
        );
        // The canvas's foot, at canvas row 38: film row
        // 19 + (38 − 19.7) × 0.4 = 26.32.
        expect(
          pixelOf(film, canvas.width, 30, 24),
          (255, 255, 255, 255),
          reason: 'LIVENESS: the paper above its foot',
        );
        final (r, _, _, _) = pixelOf(film, canvas.width, 30, 26);
        expect(r, inExclusiveRange(0x20, 0xE0), reason: 'paper over apron');
      });
    });

    testWidgets('🎯a canvas a few output pixels wide keeps its paper — it '
        'does not vanish', (tester) async {
      await tester.runAsync(() async {
        // At a quarter, two film pixels a side.
        const small = CanvasSize(width: 8, height: 8);
        final (s, renderer) = filmAt(
          CameraPose(center: CanvasPoint(x: 4, y: 4), zoom: 0.25),
          inked: false,
          size: small,
        );
        final film = await bytesOf(
          await pictureOfFilmFrame(renderer.videoRun([
            ExportFrameTask(cut: s.requireActiveCut, frameIndex: 0),
          ], ExportSizeMode.camera).frame(0)),
        );
        // Film pixel p sees canvas [4 + (p − 4) × 4, 4 + (p − 3) × 4):
        // pixel 2, [-4, 0), is past the canvas and inside the 3x wall at
        // -8; pixel 0, [-12, -8), is past the wall.
        expect(
          pixelOf(film, small.width, 2, 2),
          (0, 0, 255, 255),
          reason: 'LIVENESS: the apron past the canvas',
        );
        expect(
          pixelOf(film, small.width, 0, 0),
          (0, 0, 0, 255),
          reason: 'the floor past the pasteboard\'s wall (I-109)',
        );
        // Reduced as the canvas reduces it — a level's texel spreads the
        // apron a little into a two-pixel paper: paper still, over apron.
        final (r, g, b, a) = pixelOf(film, small.width, 4, 4);
        expect((b, a), (255, 255));
        expect(r, greaterThan(0x80), reason: 'more paper than apron');
        expect(g, r);
      });
    });
  });

  group('the stage', () {
    const canvas = CanvasSize(width: 8, height: 8);
    const red = 0xFFFF0000;
    const blue = 0xFF0000FF;

    /// A cut of [duration] frames whose one row, [id], shows one drawing
    /// throughout.
    Cut cutOf(String id, {int duration = 24}) => Cut(
      id: CutId(id),
      name: id,
      duration: duration,
      canvasSize: canvas,
      layers: [
        row(id, duration: duration),
        createCameraLayer(cutId: CutId(id)),
      ],
    );

    /// An O.L over [track]'s frames 12–35, across its cuts' boundary at 24.
    Layer dissolve(TrackId track) => createTrackTransitionLayer(track).copyWith(
      instructions: SplayTreeMap.of({
        12: const InstructionEvent(instructionId: 'ol', length: 24),
      }),
    );

    /// [tracks], bottom up, under a camera standing square over the canvas.
    EditorSessionManager sessionOf(List<Track> tracks) => EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: canvas,
        tracks: tracks,
        createdAt: DateTime.utc(2026),
      ),
    );

    /// Each cut's drawing, its colour edge to edge.
    void fill(EditorSessionManager session, List<(Cut, int)> cuts) => ink(
      session,
      [
        for (final (cut, argb) in cuts)
          (cut, cut.id.value, surfaceOf(canvas, (_, _) => argb)),
      ],
    );

    /// The centre of the film's frame at [cut]'s frame [index].
    Future<(int, int, int, int)> centreAt(
      EditorSessionManager session,
      Cut cut,
      int index,
    ) async {
      final renderer = ExportFrameRenderer(session: session);
      addTearDown(renderer.dispose);
      final frame = await bytesOf(
        await pictureOfFilmFrame(renderer.videoRun([
          ExportFrameTask(cut: cut, frameIndex: index),
        ], ExportSizeMode.camera).frame(0)),
      );
      return pixelOf(frame, 8, 4, 4);
    }

    testWidgets('🎯halfway through an O.L, the arriving cut\'s whole unit — '
        'its paper too — is laid at half over the leaving one', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const track = TrackId('stage');
        final s = sessionOf([
          Track(
            id: track,
            name: 'V',
            cuts: [cutOf('leaving'), cutOf('arriving')],
            transitionLayer: dissolve(track),
          ),
        ]);
        addTearDown(s.dispose);
        final [leaving, _] = s.repository.requireProject().tracks.single.cuts;
        fill(s, [(leaving, red)]);

        // The O.L's twelfth frame of twenty-four.
        final (r, g, b, a) = await centreAt(s, leaving, 23);
        expect((r, a), (255, 255));
        // The red half covered by the arriving cut's white paper.
        expect(g, inInclusiveRange(100, 155));
        expect(b, inInclusiveRange(100, 155));
      });
    });

    testWidgets('🎯halfway through an O.L on a track above the stage, the '
        'arriving cut\'s picture is laid at half — the stage under it shows '
        'through', (tester) async {
      await tester.runAsync(() async {
        const upper = TrackId('upper');
        final s = sessionOf([
          Track(
            id: const TrackId('lower'),
            name: 'V1',
            cuts: [cutOf('stage', duration: 48)],
          ),
          Track(
            id: upper,
            name: 'V2',
            cuts: [cutOf('leaving'), cutOf('arriving')],
            transitionLayer: dissolve(upper),
          ),
        ]);
        addTearDown(s.dispose);
        final [lowerTrack, upperTrack] = s.repository.requireProject().tracks;
        final [leaving, arriving] = upperTrack.cuts;
        fill(s, [(lowerTrack.cuts.single, red), (arriving, blue)]);

        final (r, g, b, a) = await centreAt(s, leaving, 23);
        expect((g, a), (0, 255));
        expect(r, inInclusiveRange(100, 155), reason: 'the stage\'s red…');
        expect(b, inInclusiveRange(100, 155), reason: '…under blue at half');
      });
    });

    testWidgets('🎯a cut that becomes the stage where the track under it '
        'ends brings its paper — after a frame it lay over that track, in '
        'one run', (tester) async {
      await tester.runAsync(() async {
        final s = sessionOf([
          Track(
            id: const TrackId('lower'),
            name: 'V1',
            cuts: [cutOf('low', duration: 12)],
          ),
          Track(
            id: const TrackId('upper'),
            name: 'V2',
            cuts: [cutOf('high', duration: 24)],
          ),
        ]);
        addTearDown(s.dispose);
        final [lowerTrack, upperTrack] = s.repository.requireProject().tracks;
        fill(s, [(lowerTrack.cuts.single, red)]);
        final high = upperTrack.cuts.single;
        final renderer = ExportFrameRenderer(session: s);
        addTearDown(renderer.dispose);
        final run = renderer.videoRun([
          for (final index in [5, 15])
            ExportFrameTask(cut: high, frameIndex: index),
        ], ExportSizeMode.camera);

        expect(
          pixelOf(
            await bytesOf(await pictureOfFilmFrame(run.frame(0))),
            8,
            4,
            4,
          ),
          (255, 0, 0, 255),
          reason: 'CONTROL: the stage\'s red through the blank cut over it',
        );
        expect(
          pixelOf(
            await bytesOf(await pictureOfFilmFrame(run.frame(1))),
            8,
            4,
            4,
          ),
          (255, 255, 255, 255),
          reason: 'its own paper, where nothing lies under it',
        );
      });
    });

    testWidgets('🎯a name is laid over the cut\'s picture — its paper and '
        'all', (tester) async {
      await tester.runAsync(() async {
        // Room for the name.
        const wide = CanvasSize(width: 320, height: 180);
        const cutId = CutId('cut');
        Future<Uint8List> filmOf({required bool named}) async {
          final s = EditorSessionManager(
            initialProject: Project(
              id: const ProjectId('project'),
              name: 'Project',
              cameraSize: wide,
              tracks: [
                Track(
                  id: const TrackId('track'),
                  name: 'V',
                  cuts: [
                    Cut(
                      id: cutId,
                      name: 'Cut',
                      duration: 24,
                      canvasSize: wide,
                      layers: [
                        row('blank', duration: 24),
                        createCameraLayer(cutId: cutId),
                      ],
                    ),
                  ],
                  seLayers: [
                    if (named)
                      Layer(
                        id: const LayerId('se'),
                        name: 'S1',
                        kind: LayerKind.se,
                        frames: [
                          Frame(
                            id: const FrameId('line'),
                            duration: 24,
                            strokes: const [],
                            name: 'the line',
                            seName: 'who',
                          ),
                        ],
                        timeline: const {
                          0: TimelineExposure.drawing(
                            FrameId('line'),
                            length: 24,
                          ),
                        },
                      ),
                  ],
                ),
              ],
              createdAt: DateTime.utc(2026),
            ),
          );
          addTearDown(s.dispose);
          final cut = s.requireActiveCut;
          expect(
            s.seEntries.seNameTagsForCutFrame(cut, 0),
            hasLength(named ? 1 : 0),
            reason: 'LIVENESS: somebody is named, or nobody',
          );
          final renderer = ExportFrameRenderer(session: s);
          addTearDown(renderer.dispose);
          return bytesOf(
            await pictureOfFilmFrame(renderer.videoRun([
              ExportFrameTask(cut: cut, frameIndex: 0),
            ], ExportSizeMode.camera).frame(0)),
          );
        }

        debugOverlayRasters = [];
        addTearDown(() => debugOverlayRasters = null);
        final named = await filmOf(named: true);
        // Rastered only round where it inks (card
        // an-exports-overlay-raster-reads-back-the-whole-frame) — which
        // its pixels do not show.
        expect(
          debugOverlayRasters,
          contains(
            predicate<(int, int)>(
              (raster) => raster.$1 * raster.$2 < wide.width * wide.height,
            ),
          ),
          reason: 'the name is rastered round it, not on the whole frame',
        );
        expect(named, isNot(await filmOf(named: false)));
      });
    });

    group('under the V row\'s chain', () {
      const track = TrackId('track');

      /// The cut's left half inked blue, its right half the paper.
      EditorSessionManager halfInked(List<LayerEffect> effects) {
        final s = sessionOf([
          Track(id: track, name: 'V', cuts: [cutOf('c')], effects: effects),
        ]);
        ink(s, [
          (
            s.requireActiveCut,
            'c',
            surfaceOf(canvas, (x, _) => x < 4 ? 0xFF000064 : null),
          ),
        ]);
        return s;
      }

      LayerEffect brightness(EffectParameter parameter) => LayerEffect(
        id: const EffectId('fx'),
        kind: EffectKind.brightnessContrast,
        parameters: {'brightness': parameter},
      );

      testWidgets('🎯a film\'s cut is filtered by it — never the paper it '
          'stands on', (tester) async {
        await tester.runAsync(() async {
          final plain = halfInked(const []);
          addTearDown(plain.dispose);
          final graded = halfInked([brightness(EffectParameter(value: 50))]);
          addTearDown(graded.dispose);

          Future<Uint8List> frameOf(EditorSessionManager s) async {
            final renderer = ExportFrameRenderer(session: s);
            addTearDown(renderer.dispose);
            return bytesOf(
              await pictureOfFilmFrame(renderer.videoRun([
                ExportFrameTask(cut: s.requireActiveCut, frameIndex: 0),
              ], ExportSizeMode.camera).frame(0)),
            );
          }

          final plainFrame = await frameOf(plain);
          expect(
            (pixelOf(plainFrame, 8, 1, 4), pixelOf(plainFrame, 8, 6, 4)),
            ((0, 0, 100, 255), (255, 255, 255, 255)),
            reason: 'CONTROL: the ink and the paper as they are',
          );
          final gradedFrame = await frameOf(graded);
          final (r, _, b, _) = pixelOf(gradedFrame, 8, 1, 4);
          expect(r, greaterThan(40), reason: 'the ink brightened');
          expect(b, greaterThan(140));
          expect(
            pixelOf(gradedFrame, 8, 6, 4),
            (255, 255, 255, 255),
            reason: 'the paper as it is',
          );
        });
      });

      testWidgets('🎯a panel\'s picture is the cut\'s own: the chain is the '
          'track\'s, not the block\'s (R4)', (tester) async {
        await tester.runAsync(() async {
          final graded = halfInked([brightness(EffectParameter(value: 50))]);
          addTearDown(graded.dispose);
          final panel = await bytesOf(
            await PanelPictures(
              session: graded,
            ).render(graded.requireActiveCut, 0, width: 8),
          );
          expect(
            (pixelOf(panel, 8, 1, 4), pixelOf(panel, 8, 6, 4)),
            ((0, 0, 100, 255), (255, 255, 255, 255)),
            reason: 'the ink and the paper as they are',
          );
        });
      });

      for (final mode in ExportSizeMode.values) {
        testWidgets('🎯${mode.name}: a held drawing under a chain that moves '
            'is another picture every frame — and under one that stands, '
            'the picture before', (tester) async {
          await tester.runAsync(() async {
            /// The run's two frames, as its writer takes them — and the
            /// picture of each.
            Future<((GpuShown, ui.Image), (GpuShown, ui.Image))> twoFrames(
              EffectParameter p,
            ) async {
              final s = halfInked([brightness(p)]);
              addTearDown(s.dispose);
              final renderer = ExportFrameRenderer(session: s);
              addTearDown(renderer.dispose);
              final cut = s.requireActiveCut;
              final run = renderer.videoRun([
                for (final index in [0, 1])
                  ExportFrameTask(cut: cut, frameIndex: index),
              ], mode);
              Future<(GpuShown, ui.Image)> at(int index) async {
                final frame = await run.frame(index);
                return (frame, pictureOfLaid(appGpuExport, frame));
              }

              return (await at(0), await at(1));
            }

            final ((still0, picture0), (still1, picture1)) = await twoFrames(
              EffectParameter(value: 50),
            );
            expect(
              still1,
              same(still0),
              reason: 'the chain resolved again, equal: the frame held',
            );
            picture0.dispose();
            picture1.dispose();

            final ((_, moving0), (_, moving1)) = await twoFrames(
              EffectParameter(
                value: 0,
                track: PropertyTrack<double>(
                  keys: {
                    0: const PropertyKey<double>(0),
                    1: const PropertyKey<double>(50),
                  },
                ),
              ),
            );
            expect(
              await bytesOf(moving1),
              isNot(await bytesOf(moving0)),
              reason: 'brightened at the second frame',
            );
          });
        });
      }
    });
  });
}
