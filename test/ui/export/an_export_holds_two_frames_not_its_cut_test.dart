import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuShown;
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
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
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

import '../../helpers/cels_parked_cold.dart';

/// 🚨★★★**AN EXPORT HOLDS THE PICTURES OF TWO FRAMES, NOT OF ITS CUT**
/// (card `render-reads-thaw-into-hot`).
///
/// A render reads a cel as a LOOK — decoded for the render, never kept by
/// the store. It held its CUT's cels for the whole run (07-29, when a read
/// was free because every cel was hot): on a long cut, every drawing at the
/// canvas's size at once. It holds the pictures of the frame it draws and
/// of the frame before — a frame made of what the frame before was made of
/// is that frame's picture, and nothing older stays.
///
/// A cel it looks at is held so too (`CelLooks`): a drawing held across a
/// run of frames is read once for the run.
///
/// ↩️Until the exports went on the engine (7′) the renderer composed its
/// rows itself, held on playback's line (`HeldRows`). On the engine it read
/// its cels as playback does — thawed hot (`FramePictures.readInStack`) —
/// until `gpu-canonical-store-Q10` (유저 2026-11-10 「추천대로 법 지키도록」).
void main() {
  // One tile at the engine's side.
  const tileSide = defaultCelTileSize;
  const canvasSize = CanvasSize(width: tileSide, height: tileSide);
  const trackId = TrackId('track');
  const layerId = LayerId('layer');

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  BitmapSurface ink(int seed) {
    final pixels = Uint8List(tileSide * tileSide * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = seed * 40;
      pixels[i + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tileSide,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(size: tileSide, pixels: pixels),
      },
    );
  }

  EditorSessionManager sessionOf(
    List<Cut> cuts, {
    Layer? transitions,
    List<Layer> seLayers = const [],
  }) =>
      EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'Project',
          cameraSize: canvasSize,
          tracks: [
            Track(
              id: trackId,
              name: 'Track',
              cuts: cuts,
              transitionLayer: transitions,
              seLayers: seLayers,
            ),
          ],
          createdAt: DateTime.utc(2026),
        ),
      );

  /// Every drawing of [session] COLD — what an open project's cels are
  /// until someone draws on them — each its own colour; the keys, by frame.
  Map<String, BrushFrameKey> parkEvery(EditorSessionManager session) {
    final keys = <String, BrushFrameKey>{};
    for (final cut in session.repository.requireProject().tracks.single.cuts) {
      for (final layer in cut.layers) {
        for (final drawing in layer.frames) {
          keys[drawing.id.value] = session.brushFrameKeyForCut(
            cut,
            layer.id,
            drawing.id,
          );
        }
      }
    }
    var seed = 1;
    parkCold(session.renderCaches.brushFrameStore, {
      for (final key in keys.values) key: ink(seed++),
    });
    return keys;
  }

  /// Every frame of [cut], in order.
  List<ExportFrameTask> framesOf(Cut cut) => [
    for (var index = 0; index < cut.duration; index += 1)
      ExportFrameTask(cut: cut, frameIndex: index),
  ];

  /// A video run in [mode] of every frame of [cut], in order.
  ExportRun<GpuShown> runOf(
    ExportFrameRenderer renderer,
    Cut cut,
    ExportSizeMode mode,
  ) =>
      renderer.videoRun(framesOf(cut), mode);

  Future<Uint8List> bytesOf(ui.Image image) async => (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();

  /// Every frame of [cut] of a video in [mode], in order, as a preview is
  /// handed them ([ExportFrameRenderer.renderVideoFrame]): a frame held on
  /// the engine read back once, and handed again as the same picture.
  Future<ui.Image> Function(int index) filmPicturesOf(
    ExportFrameRenderer renderer,
    Cut cut,
    ExportSizeMode mode,
  ) {
    final plan = framesOf(cut);
    return (index) =>
        renderer.renderVideoFrame(plan[index], mode, preserveAlpha: false);
  }

  /// Every door a frame comes through — opened over a renderer and a cut,
  /// the frame at each index.
  final doors =
      <
        String,
        Future<ui.Image> Function(int index) Function(
          ExportFrameRenderer renderer,
          Cut cut,
        )
      >{
        'a picture (PNG, storyboard, conte)': (renderer, cut) =>
            (index) => renderer.renderComposite(
              ExportFrameTask(cut: cut, frameIndex: index),
              ExportSizeMode.canvas,
            ),
        'a canvas-size video frame': (renderer, cut) =>
            filmPicturesOf(renderer, cut, ExportSizeMode.canvas),
        'a camera video frame (the track stack)': (renderer, cut) =>
            filmPicturesOf(renderer, cut, ExportSizeMode.camera),
      };

  group('f1 held for frames 0–2, then f2, f3, f4 one frame each', () {
    const cutId = CutId('cut');

    EditorSessionManager session() => sessionOf([
      Cut(
        id: cutId,
        name: 'Cut',
        duration: 6,
        canvasSize: canvasSize,
        layers: [
          Layer(
            id: layerId,
            name: 'A',
            frames: [frame('f1'), frame('f2'), frame('f3'), frame('f4')],
            timeline: const {
              0: TimelineExposure.drawing(FrameId('f1'), length: 3),
              3: TimelineExposure.drawing(FrameId('f2'), length: 1),
              4: TimelineExposure.drawing(FrameId('f3'), length: 1),
              5: TimelineExposure.drawing(FrameId('f4'), length: 1),
            },
          ),
          createCameraLayer(cutId: cutId),
        ],
      ),
    ]);

    for (final MapEntry(key: door, value: open) in doors.entries) {
      testWidgets('🎯$door: reads every drawing of the cut as a look — the '
          'store keeps each one cold', (tester) async {
        await tester.runAsync(() async {
          final s = session();
          addTearDown(s.dispose);
          final keys = parkEvery(s);
          final cut = s.requireActiveCut;
          final renderer = ExportFrameRenderer(session: s);
          addTearDown(renderer.dispose);
          final frameAt = open(renderer, cut);

          for (var index = 0; index < cut.duration; index += 1) {
            (await frameAt(index)).dispose();
          }

          final store = s.renderCaches.brushFrameStore;
          expect(store.hotBakedBytes, 0, reason: 'the reads were looks');
          for (final key in keys.values) {
            expect(store.isCelCold(key), isTrue);
          }
        });
      });

      testWidgets('🚨$door: of the cels it looked at, what is held at the end '
          'is the last frame\'s and the one before\'s — f4 and f3', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final s = session();
          addTearDown(s.dispose);
          parkEvery(s);
          final cut = s.requireActiveCut;
          final renderer = ExportFrameRenderer(session: s);
          addTearDown(renderer.dispose);
          final frameAt = open(renderer, cut);

          for (var index = 0; index < cut.duration; index += 1) {
            (await frameAt(index)).dispose();
          }

          expect(renderer.debugCelsHeld, 2, reason: 'f1 and f2 let go');
        });
      });
    }

    testWidgets('what the export draws is the drawing — a look reads the '
        'pixels a use would', (tester) async {
      await tester.runAsync(() async {
        final s = session();
        addTearDown(s.dispose);
        parkEvery(s);

        final image = await ExportFrameRenderer(
          session: s,
          ground: const ui.Color(0x00000000),
        ).renderComposite(
          ExportFrameTask(cut: s.requireActiveCut, frameIndex: 3),
          ExportSizeMode.canvas,
        );
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();

        expect(bytes!.getUint8(0), 80, reason: 'f2 is red 80');
        expect(bytes.getUint8(3), 255);
        expect(s.renderCaches.brushFrameStore.hotBakedBytes, 0);
      });
    });
  });

  group('🚨a drawing held under a row that moves is read ONCE for the frames '
      'it is held for — the frame after takes it from the frame before', () {
    const cutId = CutId('cut');
    const under = LayerId('under');

    /// A cut showing f1 for all of it, and over it a row showing [over] in
    /// turn, each drawing for as many frames as it says.
    EditorSessionManager session(List<(String, int)> over) {
      final duration = over.fold(0, (sum, step) => sum + step.$2);
      final timeline = <int, TimelineExposure>{};
      var at = 0;
      for (final (drawing, length) in over) {
        timeline[at] = TimelineExposure.drawing(
          FrameId(drawing),
          length: length,
        );
        at += length;
      }
      return sessionOf([
        Cut(
          id: cutId,
          name: 'Cut',
          duration: duration,
          canvasSize: canvasSize,
          layers: [
            Layer(
              id: under,
              name: 'Under',
              frames: [frame('f1')],
              timeline: {
                0: TimelineExposure.drawing(
                  const FrameId('f1'),
                  length: duration,
                ),
              },
            ),
            Layer(
              id: layerId,
              name: 'Over',
              frames: [for (final (drawing, _) in over) frame(drawing)],
              timeline: timeline,
            ),
            createCameraLayer(cutId: cutId),
          ],
        ),
      ]);
    }

    for (final MapEntry(key: door, value: open) in doors.entries) {
      testWidgets('🎯$door: under a row that moves every frame, f1 is read '
          'once for the cut', (tester) async {
        await tester.runAsync(() async {
          final s = session([('o1', 1), ('o2', 1), ('o3', 1), ('o4', 1)]);
          addTearDown(s.dispose);
          parkEvery(s);
          final cut = s.requireActiveCut;
          final renderer = ExportFrameRenderer(session: s);
          addTearDown(renderer.dispose);
          final frameAt = open(renderer, cut);

          for (var index = 0; index < cut.duration; index += 1) {
            (await frameAt(index)).dispose();
          }

          expect(
            renderer.debugCelReads,
            1 + 4,
            reason: 'f1 once, and each drawing over it',
          );
        });
      });
    }

    for (final mode in ExportSizeMode.values) {
      testWidgets('🎯a ${mode.name}-size video frame: through the frames a '
          'picture is handed again its cels stay held — the frame that '
          'changes one row reads that row alone', (tester) async {
        await tester.runAsync(() async {
          final s = session([('o1', 4), ('o2', 1)]);
          addTearDown(s.dispose);
          parkEvery(s);
          final cut = s.requireActiveCut;
          final renderer = ExportFrameRenderer(session: s);
          addTearDown(renderer.dispose);
          final run = runOf(renderer, cut, mode);

          await run.frame(0);
          final made = renderer.debugPicturesMade;
          for (var index = 1; index < 4; index += 1) {
            await run.frame(index);
          }
          expect(
            renderer.debugPicturesMade,
            made,
            reason: 'LIVENESS: frames 0–3 are one picture, handed again',
          );
          expect(
            renderer.debugCelReads,
            2,
            reason: 'f1 and o1, read for frame 0',
          );
          await run.frame(4);
          expect(
            renderer.debugCelReads,
            2 + 1,
            reason: 'o2 alone — f1 was held through the frames between',
          );
        });
      });
    }
  });

  group('two cuts an O.L mixes', () {
    /// A 24-frame cut whose row shows [shown] in turn from its frame 0, one
    /// a frame, the last held to the end.
    Cut cutShowing(String id, List<String> shown) => Cut(
      id: CutId(id),
      name: id,
      duration: 24,
      canvasSize: canvasSize,
      layers: [
        Layer(
          id: layerId,
          name: 'A',
          frames: [for (final drawing in {...shown}) frame(drawing)],
          timeline: {
            for (final (index, drawing) in shown.indexed)
              index: TimelineExposure.drawing(
                FrameId(drawing),
                length: index == shown.length - 1 ? 24 - index : 1,
              ),
          },
        ),
        createCameraLayer(cutId: CutId(id)),
      ],
    );

    /// c1, held, and then c2 showing [arriving] — an O.L straddling their
    /// boundary at 24, so frames 12–35 mix both and c2 comes in at its own
    /// frame 0.
    EditorSessionManager mixing(List<String> arriving) => sessionOf(
      [
        cutShowing('c1', ['c1-drawing']),
        cutShowing('c2', arriving),
      ],
      transitions: createTrackTransitionLayer(trackId).copyWith(
        instructions: SplayTreeMap.of({
          12: const InstructionEvent(instructionId: 'ol', length: 24),
        }),
      ),
    );

    /// A video run in [mode] of the O.L's first four frames, 12–15.
    ExportRun<GpuShown> mixedRun(
      ExportFrameRenderer renderer,
      EditorSessionManager s,
      ExportSizeMode mode,
    ) => renderer.videoRun([
      for (var index = 12; index < 16; index += 1)
        ExportFrameTask(
          cut: s.repository.requireProject().tracks.single.cuts.first,
          frameIndex: index,
        ),
    ], mode);

    for (final mode in ExportSizeMode.values) {
      testWidgets('🎯${mode.name}: an O.L frame is ONE frame — its two cuts '
          'do not start one each, so over two held drawings a frame makes '
          'its mix alone', (tester) async {
        await tester.runAsync(() async {
          final s = mixing(['c2-drawing']);
          addTearDown(s.dispose);
          parkEvery(s);
          final renderer = ExportFrameRenderer(session: s);
          addTearDown(renderer.dispose);
          final run = mixedRun(renderer, s, mode);

          await run.frame(0);
          final made = renderer.debugPicturesMade;
          expect(
            made,
            greaterThanOrEqualTo(3),
            reason: 'LIVENESS: each cut\'s picture, and the mix',
          );
          for (var index = 1; index < 4; index += 1) {
            await run.frame(index);
            expect(
              renderer.debugPicturesMade,
              made + index,
              reason: 'frame $index: both cuts\' pictures are the frame '
                  'before\'s — not one let go by the other\'s start',
            );
          }
        });
      });
    }
  });

  group('🚨a frame of a run that is made of what the frame before it was '
      'made of is THAT FRAME\'S PICTURE, handed again (F-289)', () {
    const cutId = CutId('cut');

    // Where a moving camera stands at its first key and at its last: an
    // eighth of the canvas either side of its middle.
    final standsAt = CanvasPoint(x: tileSide * 3 / 8, y: tileSide / 2);
    final movesTo = CanvasPoint(x: tileSide * 5 / 8, y: tileSide / 2);

    /// A: one drawing for the whole cut. B: b1 for frames 0–1, b2 for 2–3.
    Cut cut({CutCamera? camera}) => Cut(
      id: cutId,
      name: 'Cut',
      duration: 4,
      canvasSize: canvasSize,
      camera: camera,
      layers: [
        Layer(
          id: const LayerId('a'),
          name: 'A',
          frames: [frame('a1')],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('a1'), length: 4),
          },
        ),
        Layer(
          id: const LayerId('b'),
          name: 'B',
          frames: [frame('b1'), frame('b2')],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('b1'), length: 2),
            2: TimelineExposure.drawing(FrameId('b2'), length: 2),
          },
        ),
        createCameraLayer(cutId: cutId),
      ],
    );

    /// A: one drawing for the whole cut. B: a cycle — b1, b2, b3, and b1
    /// again.
    Cut cycle({CutCamera? camera}) => Cut(
      id: cutId,
      name: 'Cut',
      duration: 4,
      canvasSize: canvasSize,
      camera: camera,
      layers: [
        Layer(
          id: const LayerId('a'),
          name: 'A',
          frames: [frame('a1')],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('a1'), length: 4),
          },
        ),
        Layer(
          id: const LayerId('b'),
          name: 'B',
          frames: [frame('b1'), frame('b2'), frame('b3')],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('b1'), length: 1),
            1: TimelineExposure.drawing(FrameId('b2'), length: 1),
            2: TimelineExposure.drawing(FrameId('b3'), length: 1),
            3: TimelineExposure.drawing(FrameId('b1'), length: 1),
          },
        ),
        createCameraLayer(cutId: cutId),
      ],
    );

    /// How many handles are open on [image]'s picture — its own, and the
    /// renderer's while the renderer holds it.
    int handlesOn(ui.Image image) =>
        image.debugGetOpenHandleStackTraces()!.length;

    /// Every run whose frames are held pictures, opened over a renderer and
    /// the frames of a cut: the picture at each index.
    final doors =
        <
          String,
          Future<ui.Image> Function(int index) Function(
            ExportFrameRenderer renderer,
            Cut cut,
          )
        >{
          'a canvas-size video frame': (renderer, cut) =>
              filmPicturesOf(renderer, cut, ExportSizeMode.canvas),
          'a camera video frame (the track stack)': (renderer, cut) =>
              filmPicturesOf(renderer, cut, ExportSizeMode.camera),
          'a canvas-size picture of a sequence': (renderer, cut) =>
              renderer.stillRun(framesOf(cut), ExportSizeMode.canvas).frame,
          'a camera-size picture of a sequence': (renderer, cut) =>
              renderer.stillRun(framesOf(cut), ExportSizeMode.camera).frame,
        };

    for (final MapEntry(key: door, value: open) in doors.entries) {
      /// A renderer over [s]'s cut, and the door through it — a run of the
      /// cut's frames.
      ({
        ExportFrameRenderer renderer,
        Future<ui.Image> Function(int index) frameAt,
      })
      over(EditorSessionManager s) {
        final renderer = ExportFrameRenderer(session: s);
        addTearDown(renderer.dispose);
        return (
          renderer: renderer,
          frameAt: open(renderer, s.requireActiveCut),
        );
      }

      testWidgets('$door: frames 0 and 1 are ONE picture and nothing is made '
          'for the second; frame 2 is another', (tester) async {
        await tester.runAsync(() async {
          final s = sessionOf([cut()]);
          addTearDown(s.dispose);
          parkEvery(s);
          final (:renderer, :frameAt) = over(s);

          final first = await frameAt(0);
          final made = renderer.debugPicturesMade;
          expect(made, greaterThan(0), reason: 'LIVENESS: frame 0 was made');

          final again = await frameAt(1);
          expect(again.isCloneOf(first), isTrue);
          expect(renderer.debugPicturesMade, made, reason: 'nothing made');

          final next = await frameAt(2);
          expect(next.isCloneOf(first), isFalse, reason: 'b2 is on');
          expect(renderer.debugPicturesMade, greaterThan(made));
          for (final image in [first, again, next]) {
            image.dispose();
          }
        });
      });

      // 🗣️F-289-Q21 (유저 2026-10-07): 「붙든다 — 재생 줄의 허용치 안에서」 —
      // what holds of a cel is playback's own now (the file's head).
      testWidgets('🚨$door: a frame drawn with room on playback\'s line is '
          'the frame drawn with none, byte for byte', (tester) async {
        await tester.runAsync(() async {
          Future<List<Uint8List>> run({required bool room}) async {
            final s = sessionOf([cycle()]);
            addTearDown(s.dispose);
            parkEvery(s);
            if (!room) {
              s.playbackRig.playbackCache.debugSetPlaybackCacheBudgetBytes(0);
            }
            final (:renderer, :frameAt) = over(s);
            final frames = <Uint8List>[];
            for (final index in [0, 1, 2, 3]) {
              final image = await frameAt(index);
              frames.add(await bytesOf(image));
              image.dispose();
            }
            return frames;
          }

          final held = await run(room: true);
          final none = await run(room: false);
          expect(held, none);
        });
      });

      testWidgets('$door: a picture is let go the frame after the last one '
          'made of it stops being the frame before, and every one when the '
          'run ends', (tester) async {
        await tester.runAsync(() async {
          final s = sessionOf([cut()]);
          addTearDown(s.dispose);
          parkEvery(s);
          final (:renderer, :frameAt) = over(s);

          final first = await frameAt(0);
          expect(handlesOn(first), 2, reason: 'LIVENESS: the renderer\'s too');
          final third = await frameAt(2);
          expect(handlesOn(first), 2, reason: 'still the frame before');
          (await frameAt(3)).dispose();
          expect(handlesOn(first), 1, reason: 'two frames on: let go');

          expect(handlesOn(third), 2, reason: 'frame 3 is frame 2\'s picture');
          renderer.dispose();
          expect(handlesOn(third), 1, reason: 'the run is over');
          first.dispose();
          third.dispose();
        });
      });
    }

    testWidgets('the camera moving over a held drawing: every frame is its '
        'own picture', (tester) async {
      // ↩️It was the cut's PICTURE that was made once — a canvas-space
      // composite the camera projected — until the film drew its cut
      // through the camera as the canvas does (card video-export-speed-Q2):
      // a picture is of its view now, and what the camera moves over is
      // the cels it is made of.
      await tester.runAsync(() async {
        final s = sessionOf([
          cut(
            camera: CutCamera(
              keyframes: {
                0: CameraPose(center: standsAt),
                1: CameraPose(center: movesTo),
              },
            ),
          ),
        ]);
        addTearDown(s.dispose);
        parkEvery(s);
        final renderer = ExportFrameRenderer(session: s);
        addTearDown(renderer.dispose);
        final frameAt = filmPicturesOf(
          renderer,
          s.requireActiveCut,
          ExportSizeMode.camera,
        );

        final first = await frameAt(0);
        final made = renderer.debugPicturesMade;
        expect(made, 2, reason: 'LIVENESS: the cut\'s picture and the frame');
        final moved = await frameAt(1);
        expect(moved.isCloneOf(first), isFalse, reason: 'the camera moved');
        expect(
          renderer.debugPicturesMade,
          made + 2,
          reason: 'the cut through the camera where it stands now, and the '
              'frame',
        );
        final [before, after] = [
          for (final image in [first, moved]) await bytesOf(image),
        ];
        expect(after, isNot(before), reason: 'and it shows another part');
        first.dispose();
        moved.dispose();
      });
    });

    for (final (mode, moves, says) in [
      (ExportSizeMode.camera, true, 'its own, the camera moved'),
      (ExportSizeMode.canvas, false, 'the one before, no camera moves it'),
    ]) {
      testWidgets('🎯the camera moving over a held drawing: a ${mode.name}-size '
          'picture of a sequence is of the view it is drawn through — '
          '$says', (tester) async {
        await tester.runAsync(() async {
          final s = sessionOf([
            cut(
              camera: CutCamera(
                keyframes: {
                  0: CameraPose(center: standsAt),
                  1: CameraPose(center: movesTo),
                },
              ),
            ),
          ]);
          addTearDown(s.dispose);
          parkEvery(s);
          final renderer = ExportFrameRenderer(session: s);
          addTearDown(renderer.dispose);
          final plan = framesOf(s.requireActiveCut);
          final run = renderer.stillRun(plan, mode);

          final frames = [for (final index in [0, 1]) await run.frame(index)];
          expect(
            frames[1].isCloneOf(frames[0]),
            !moves,
            reason: 'frames 0 and 1 show a1 and b1',
          );
          for (final (index, image) in frames.indexed) {
            final plain = await ExportFrameRenderer(
              session: s,
            ).renderComposite(plan[index], mode);
            expect(
              await bytesOf(image),
              await bytesOf(plain),
              reason: 'frame $index',
            );
            plain.dispose();
            image.dispose();
          }
        });
      });
    }

    for (final mode in ExportSizeMode.values) {
      testWidgets('🚨a ${mode.name}-size picture of a sequence is the picture '
          'renderComposite makes of its frame, byte for byte', (tester) async {
        await tester.runAsync(() async {
          final s = sessionOf([
            cycle(
              camera: CutCamera(
                keyframes: {
                  0: CameraPose(center: standsAt),
                  3: CameraPose(center: movesTo),
                },
              ),
            ),
          ]);
          addTearDown(s.dispose);
          parkEvery(s);
          final renderer = ExportFrameRenderer(session: s);
          addTearDown(renderer.dispose);
          final plan = framesOf(s.requireActiveCut);
          final run = renderer.stillRun(plan, mode);

          for (final (index, task) in plan.indexed) {
            final held = await run.frame(index);
            final plain = await ExportFrameRenderer(
              session: s,
            ).renderComposite(task, mode);
            expect(
              await bytesOf(held),
              await bytesOf(plain),
              reason: 'frame $index',
            );
            held.dispose();
            plain.dispose();
          }
        });
      });
    }
  });

  group('what is not in the cut\'s composite is part of the frame all the '
      'same (F-289)', () {
    const cutId = CutId('cut');

    /// One drawing held for the whole cut.
    Cut still() => Cut(
      id: cutId,
      name: 'Cut',
      duration: 4,
      canvasSize: canvasSize,
      layers: [
        Layer(
          id: const LayerId('a'),
          name: 'A',
          frames: [frame('a1')],
          timeline: const {
            0: TimelineExposure.drawing(FrameId('a1'), length: 4),
          },
        ),
        createCameraLayer(cutId: cutId),
      ],
    );

    /// An SE row whose speaker is named from frame 1 on.
    Layer speaker() => Layer(
      id: const LayerId('se'),
      name: 'S1',
      kind: LayerKind.se,
      frames: [
        Frame(
          id: const FrameId('line'),
          duration: 3,
          strokes: const [],
          name: 'the line',
          seName: 'who',
        ),
      ],
      timeline: const {1: TimelineExposure.drawing(FrameId('line'), length: 3)},
    );

    for (final mode in ExportSizeMode.values) {
      testWidgets('${mode.name}: a name coming up over a held drawing is '
          'another picture', (tester) async {
        await tester.runAsync(() async {
          final s = sessionOf([still()], seLayers: [speaker()]);
          addTearDown(s.dispose);
          parkEvery(s);
          final cut = s.requireActiveCut;
          expect(
            [
              for (final index in [0, 1])
                s.seEntries.seNameTagsForCutFrame(cut, index).length,
            ],
            [0, 1],
            reason: 'LIVENESS: nobody is named at 0, and somebody at 1',
          );
          final renderer = ExportFrameRenderer(session: s);
          addTearDown(renderer.dispose);
          final frameAt = filmPicturesOf(renderer, cut, mode);

          final unnamed = await frameAt(0);
          final named = await frameAt(1);
          expect(named.isCloneOf(unnamed), isFalse);
          final held = await frameAt(2);
          expect(held.isCloneOf(named), isTrue, reason: 'the name stays');
          for (final image in [unnamed, named, held]) {
            image.dispose();
          }
        });
      });

      testWidgets('${mode.name}: a picture of a sequence takes no names — a '
          'name coming up over a held drawing is the picture before', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final s = sessionOf([still()], seLayers: [speaker()]);
          addTearDown(s.dispose);
          parkEvery(s);
          final cut = s.requireActiveCut;
          expect(
            s.seEntries.seNameTagsForCutFrame(cut, 1),
            hasLength(1),
            reason: 'LIVENESS: somebody is named at 1',
          );
          final renderer = ExportFrameRenderer(session: s);
          addTearDown(renderer.dispose);
          final run = renderer.stillRun(framesOf(cut), mode);

          final unnamed = await run.frame(0);
          final named = await run.frame(1);
          expect(named.isCloneOf(unnamed), isTrue);
          unnamed.dispose();
          named.dispose();
        });
      });
    }

    testWidgets('the same frame through the other door is another picture: '
        'the stack\'s stands on no ground, the canvas\'s on its own', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final s = sessionOf([still()]);
        addTearDown(s.dispose);
        parkEvery(s);
        final renderer = ExportFrameRenderer(session: s);
        addTearDown(renderer.dispose);
        final task = ExportFrameTask(cut: s.requireActiveCut, frameIndex: 0);

        await renderer.videoRun([task], ExportSizeMode.camera).frame(0);
        final made = renderer.debugPicturesMade;
        expect(made, 2, reason: 'LIVENESS: the cut\'s picture and the frame');
        await renderer.videoRun([task], ExportSizeMode.canvas).frame(0);
        expect(renderer.debugPicturesMade, made + 1);
      });
    });
  });
}
