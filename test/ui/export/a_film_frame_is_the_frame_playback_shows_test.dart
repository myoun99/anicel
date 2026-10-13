import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

/// 🗣️유저 2026-10-13 (card video-export-speed-Q2): 「캔버스 규칙으로」 — a
/// film is drawn as the canvas draws: each cut through its camera at the
/// film's size, reduced by the display's halvings (`displayLevelOf`), cut
/// at its canvas's edge, and laid on its stage as playback lays it.
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

  /// [paint] decides each pixel of a [canvas] in tiles of [tile] —
  /// premultiplied, as the tiles hold it — over the tiles [coords] names,
  /// the canvas's own unless told.
  BitmapSurface surfaceOf(
    CanvasSize canvas,
    int? Function(int x, int y) paint, {
    int tile = 16,
    Iterable<TileCoord>? coords,
  }) {
    final tiles = <TileCoord, BitmapTile>{};
    for (final coord
        in coords ??
            [
              for (var ty = 0; ty < canvas.height ~/ tile; ty += 1)
                for (var tx = 0; tx < canvas.width ~/ tile; tx += 1)
                  TileCoord(x: tx, y: ty),
            ]) {
      final pixels = Uint8List(tile * tile * 4);
      var any = false;
      for (var y = 0; y < tile; y += 1) {
        for (var x = 0; x < tile; x += 1) {
          final argb = paint(coord.x * tile + x, coord.y * tile + y);
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
  /// drawing — as every drawing [session] holds: `restoreBaked` puts back
  /// the whole store, so they go in at once.
  void ink(
    EditorSessionManager session,
    List<(Cut, String, BitmapSurface)> drawings,
  ) {
    session.renderCaches.brushFrameStore.restoreBaked({
      for (final (cut, id, surface) in drawings)
        if (session.brushFrameKeyForCut(cut, LayerId(id), FrameId('$id-f'))
            case final key)
          key: AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, surface)),
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
    EditorSessionManager session(double zoom) {
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
                  camera: CutCamera(
                    keyframes: {
                      0: CameraPose(
                        center: CanvasPoint(x: 121.3, y: 79.6),
                        zoom: zoom,
                      ),
                    },
                  ),
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

    /// The cut's frame as a film's frame, a picture of the sequence and a
    /// panel's picture as wide as the film.
    Future<({Uint8List video, Uint8List still, Uint8List panel})> routes(
      double zoom,
    ) async {
      final s = session(zoom);
      addTearDown(s.dispose);
      final renderer = ExportFrameRenderer(session: s);
      addTearDown(renderer.dispose);
      final cut = s.requireActiveCut;
      final task = ExportFrameTask(cut: cut, frameIndex: 0);
      return (
        video: await bytesOf(
          await renderer.videoRun([task], ExportSizeMode.camera).frame(0),
        ),
        still: await bytesOf(
          await renderer.renderComposite(task, ExportSizeMode.camera),
        ),
        panel: await bytesOf(
          await renderer.renderPicture(cut, 0, width: frameSize.width),
        ),
      );
    }

    for (final zoom in [0.47, 0.42, 0.94]) {
      testWidgets('🎯at a zoom of $zoom, a film\'s frame, a picture of the '
          'sequence and a panel\'s picture are one picture', (tester) async {
        await tester.runAsync(() async {
          final (:video, :still, :panel) = await routes(zoom);
          expect(still.length, frameSize.width * frameSize.height * 4);

          expect(still, panel, reason: 'the reduction the canvas draws');
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
        // The film's second row crosses the down lines alone: canvas rows
        // 49.8–52.2, between the lines across at 45 and 54.
        const y = 1;
        // A line at canvas column x lies at film column
        // 24 + (x + 0.5 − 121.3) × 0.42; it covers 0.42 of a film pixel,
        // so it darkens the white by 0.42 × (255 − 0x14) ≈ 99 all told —
        // over the two pixels whose centres stand either side of it.
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
            inInclusiveRange(75, 125),
            reason: 'the line at canvas column $x, at film column $at',
          );
        }
        expect(lines, 16, reason: 'LIVENESS: the lines in shot');
      });
    });
  });

  testWidgets('🎯the film shows no pasteboard: what is parked past the canvas '
      'stays out of a film\'s frame and a picture of the sequence, where the '
      'camera sees past the canvas', (tester) async {
    await tester.runAsync(() async {
      const canvas = CanvasSize(width: 32, height: 32);
      const cutId = CutId('cut');
      // Red ink on the pasteboard tile left of the canvas — x −16 to −1.
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
                  // Its frame from canvas x −8 to 24: a quarter past the
                  // canvas's left edge.
                  camera: CutCamera(
                    keyframes: {
                      0: CameraPose(center: CanvasPoint(x: 8, y: 16)),
                    },
                  ),
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
        await renderer.videoRun([task], ExportSizeMode.camera).frame(0),
      );
      final still = await bytesOf(
        await renderer.renderComposite(task, ExportSizeMode.camera),
      );
      expect(
        pixelOf(video, 32, 3, 16),
        (0, 0, 255, 255),
        reason: 'the stage\'s apron, past the paper',
      );
      expect(
        pixelOf(still, 32, 3, 16),
        (255, 255, 255, 255),
        reason: 'the picture\'s ground, past the canvas',
      );
    });
  });

  // 🗣️playback-picture-is-not-the-canvas-picture (유저 10-13: 「배율따라서
  // 끝에 흰 선」): the canvas's edge, where rows reduced to a level end in a
  // pixel they cover in part, is drawn as the canvas draws it — the paper
  // laid with the rows, one level pixel in, and the cut out past every
  // pixel they cover.
  group('at the canvas\'s edge', () {
    // No whole number of tiles; its edges fall inside the film's pixels, and
    // at a quarter its foot inside a level pixel too (38 = 9½ × 4).
    const canvas = CanvasSize(width: 60, height: 38);
    const cutId = CutId('cut');
    const blue = 0xFF0000FF;
    // Ink to the canvas's edge and not a pixel past it.
    final filled = surfaceOf(
      canvas,
      (x, y) => x < canvas.width && y < canvas.height ? 0xFF102030 : null,
      coords: [
        for (var ty = 0; ty < 3; ty += 1)
          for (var tx = 0; tx < 4; tx += 1) TileCoord(x: tx, y: ty),
      ],
    );

    /// The filled cut through a camera at [pose], on a blue apron.
    (EditorSessionManager, ExportFrameRenderer) filmAt(CameraPose pose) {
      final s = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'Project',
          cameraSize: canvas,
          pasteboardArgb: blue,
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
                  layers: [row('filled'), createCameraLayer(cutId: cutId)],
                ),
              ],
            ),
          ],
          createdAt: DateTime.utc(2026),
        ),
      );
      addTearDown(s.dispose);
      ink(s, [(s.requireActiveCut, 'filled', filled)]);
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
            await renderer.videoRun([
              ExportFrameTask(cut: s.requireActiveCut, frameIndex: 0),
            ], ExportSizeMode.camera).frame(0),
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
          'pixel the rows cover in part: a picture of the sequence is the '
          'panel\'s picture, which is cut nowhere', (tester) async {
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
          expect(
            still,
            await bytesOf(
              await renderer.renderPicture(cut, 0, width: canvas.width),
            ),
          );
        });
      });
    }
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
          (cut, cut.id.value, surfaceOf(canvas, (_, _) => argb, tile: 8)),
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
        await renderer.videoRun([
          ExportFrameTask(cut: cut, frameIndex: index),
        ], ExportSizeMode.camera).frame(0),
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
            await renderer.videoRun([
              ExportFrameTask(cut: cut, frameIndex: 0),
            ], ExportSizeMode.camera).frame(0),
          );
        }

        expect(await filmOf(named: true), isNot(await filmOf(named: false)));
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
            surfaceOf(canvas, (x, _) => x < 4 ? 0xFF000064 : null, tile: 8),
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
              await renderer.videoRun([
                ExportFrameTask(cut: s.requireActiveCut, frameIndex: 0),
              ], ExportSizeMode.camera).frame(0),
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

      for (final mode in ExportSizeMode.values) {
        testWidgets('🎯${mode.name}: a held drawing under a chain that moves '
            'is another picture every frame — and under one that stands, '
            'the picture before', (tester) async {
          await tester.runAsync(() async {
            Future<(ui.Image, ui.Image)> twoFrames(EffectParameter p) async {
              final s = halfInked([brightness(p)]);
              addTearDown(s.dispose);
              final renderer = ExportFrameRenderer(session: s);
              addTearDown(renderer.dispose);
              final cut = s.requireActiveCut;
              final run = renderer.videoRun([
                for (final index in [0, 1])
                  ExportFrameTask(cut: cut, frameIndex: index),
              ], mode);
              return (await run.frame(0), await run.frame(1));
            }

            final (still0, still1) = await twoFrames(
              EffectParameter(value: 50),
            );
            expect(
              still1.isCloneOf(still0),
              isTrue,
              reason: 'the chain resolved again, equal: the picture held',
            );
            still0.dispose();
            still1.dispose();

            final (moving0, moving1) = await twoFrames(
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
