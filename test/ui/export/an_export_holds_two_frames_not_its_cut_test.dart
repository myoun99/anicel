import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/export/held_rows.dart';

/// 🚨★★★**AN EXPORT HOLDS THE CELS OF TWO FRAMES, NOT OF ITS CUT** (card
/// `render-reads-thaw-into-hot`).
///
/// A render reads a cel as a LOOK — decoded for the render, never kept by
/// the store — so what the renderer holds is held outside every budget.
/// It held its CUT's cels for the whole run (07-29, when a read was free
/// because every cel was hot): on a long cut, every drawing at the canvas's
/// size at once. It holds what the frame it draws read and what the frame
/// before read — a drawing held across frames is read once for the run of
/// them, and nothing older stays.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const trackId = TrackId('track');
  const layerId = LayerId('layer');

  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  BitmapSurface ink(int seed) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = seed * 40;
      pixels[i + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
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
    session.renderCaches.brushFrameStore.restoreBaked({
      for (final key in keys.values)
        key: AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, ink(seed++))),
    });
    return keys;
  }

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

    /// Every door a frame comes through.
    final doors =
        <String, Future<ui.Image> Function(ExportFrameRenderer, Cut, int)>{
          'a picture (PNG, storyboard, conte)': (renderer, cut, index) =>
              renderer.renderComposite(
                ExportFrameTask(cut: cut, frameIndex: index),
                ExportSizeMode.canvas,
              ),
          'a canvas-size video frame': (renderer, cut, index) =>
              renderer.renderCompositeForVideo(
                ExportFrameTask(cut: cut, frameIndex: index),
                ExportSizeMode.canvas,
              ),
          'a camera video frame (the track stack)': (renderer, cut, index) =>
              renderer.renderCompositeForVideo(
                ExportFrameTask(cut: cut, frameIndex: index),
                ExportSizeMode.camera,
              ),
        };

    for (final MapEntry(key: door, value: render) in doors.entries) {
      testWidgets('🎯$door: holds this frame and the one before, and reads a '
          'held drawing once for its run', (tester) async {
        await tester.runAsync(() async {
          final s = session();
          addTearDown(s.dispose);
          final keys = parkEvery(s);
          final cut = s.requireActiveCut;
          final renderer = ExportFrameRenderer(session: s);

          for (final index in [0, 1, 2]) {
            (await render(renderer, cut, index)).dispose();
          }
          expect(renderer.debugCelReads, 1, reason: 'f1 held 0–2: read once');
          expect(renderer.debugHeldSurfaceCount, 1, reason: 'LIVENESS: f1');

          for (final index in [3, 4, 5]) {
            (await render(renderer, cut, index)).dispose();
            expect(
              renderer.debugHeldSurfaceCount,
              lessThanOrEqualTo(2),
              reason: 'frame $index: this frame and the one before',
            );
          }
          expect(renderer.debugCelReads, 4);
          expect(renderer.debugHeldSurfaceCount, 2, reason: 'f3 and f4');

          final store = s.renderCaches.brushFrameStore;
          expect(store.hotBakedBytes, 0, reason: 'the reads were looks');
          for (final key in keys.values) {
            expect(store.isCelCold(key), isTrue);
          }
        });
      });
    }

    testWidgets('a cel export holds the cel it draws and the one before', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final s = session();
        addTearDown(s.dispose);
        parkEvery(s);
        final cut = s.requireActiveCut;
        final layer = cut.layers.firstWhere((layer) => layer.id == layerId);
        final renderer = ExportFrameRenderer(session: s);

        for (final drawing in layer.frames) {
          final image = await renderer.renderCelGroup(
            ExportCelGroupTask(
              cut: cut,
              baseLayer: layer,
              members: [layer],
              memberFrames: [drawing],
              baseFrame: drawing,
              celName: drawing.id.value,
              fileName: '${drawing.id.value}.png',
            ),
            ExportSizeMode.canvas,
          );
          image!.dispose();
          expect(renderer.debugHeldSurfaceCount, lessThanOrEqualTo(2));
        }
        expect(renderer.debugCelReads, 4, reason: 'LIVENESS: every cel read');
        expect(renderer.debugHeldSurfaceCount, 2, reason: 'f3 and f4');
      });
    });

    testWidgets('what the export draws is the drawing — a look reads the '
        'pixels a use would', (tester) async {
      await tester.runAsync(() async {
        final s = session();
        addTearDown(s.dispose);
        parkEvery(s);

        final image = await ExportFrameRenderer(
          session: s,
          background: const ui.Color(0x00000000),
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

  testWidgets('an O.L frame is ONE frame — its two cuts do not start one '
      'each, so both drawings are read once for the run', (tester) async {
    await tester.runAsync(() async {
      Cut cut(String id) => Cut(
        id: CutId(id),
        name: id,
        duration: 24,
        canvasSize: canvasSize,
        layers: [
          Layer(
            id: layerId,
            name: 'A',
            frames: [frame('$id-drawing')],
            timeline: {
              0: TimelineExposure.drawing(FrameId('$id-drawing'), length: 24),
            },
          ),
          createCameraLayer(cutId: CutId(id)),
        ],
      );
      final s = sessionOf(
        [cut('c1'), cut('c2')],
        // Straddles the c1|c2 boundary at 24: frames 12–35 mix both cuts.
        transitions: createTrackTransitionLayer(trackId).copyWith(
          instructions: SplayTreeMap.of({
            12: const InstructionEvent(instructionId: 'ol', length: 24),
          }),
        ),
      );
      addTearDown(s.dispose);
      parkEvery(s);
      final leaving = s.repository.requireProject().tracks.single.cuts.first;
      final renderer = ExportFrameRenderer(session: s);

      for (final index in [12, 13, 14, 15]) {
        (await renderer.renderCompositeForVideo(
          ExportFrameTask(cut: leaving, frameIndex: index),
          ExportSizeMode.canvas,
        )).dispose();
      }

      expect(
        renderer.debugCelReads,
        2,
        reason: 'each cut\'s drawing, once — not once a frame',
      );
      expect(renderer.debugHeldSurfaceCount, 2, reason: 'LIVENESS: both');
    });
  });

  group('🚨a video frame that is made of what the frame before it was made '
      'of is THAT FRAME\'S PICTURE, handed again (F-289)', () {
    const cutId = CutId('cut');

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

    /// How many handles are open on [image]'s picture — its own, and the
    /// renderer's while the renderer holds it.
    int handlesOn(ui.Image image) =>
        image.debugGetOpenHandleStackTraces()!.length;

    const doors = {
      'a canvas-size video frame': ExportSizeMode.canvas,
      'a camera video frame (the track stack)': ExportSizeMode.camera,
    };

    for (final MapEntry(key: door, value: mode) in doors.entries) {
      /// A renderer over [cut], and the door through it.
      ({
        ExportFrameRenderer renderer,
        Future<ui.Image> Function(int index) frameAt,
      })
      over(EditorSessionManager s) {
        final renderer = ExportFrameRenderer(session: s);
        addTearDown(renderer.dispose);
        return (
          renderer: renderer,
          frameAt: (index) => renderer.renderCompositeForVideo(
            ExportFrameTask(cut: s.requireActiveCut, frameIndex: index),
            mode,
          ),
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

      testWidgets('$door: the row that holds while another changes is read '
          'ONCE — a held picture keeps the cels it is made of', (tester) async {
        await tester.runAsync(() async {
          final s = sessionOf([cut()]);
          addTearDown(s.dispose);
          parkEvery(s);
          final (:renderer, :frameAt) = over(s);

          for (final index in [0, 1, 2, 3]) {
            (await frameAt(index)).dispose();
          }
          expect(
            renderer.debugCelReads,
            3,
            reason: 'a1 once, b1, b2 — a1 is not read again at frame 2, where '
                'only B changes after a frame that read nothing',
          );
        });
      });

      // 🗣️F-289-Q21 (유저 2026-10-07): 「붙든다 — 재생 줄의 허용치 안에서」.
      testWidgets('🎯$door: the row that holds while another changes is '
          'COMPOSED once — a held picture keeps the rows it is made of', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final s = sessionOf([cut()]);
          addTearDown(s.dispose);
          parkEvery(s);
          final (:renderer, :frameAt) = over(s);

          for (final index in [0, 1, 2, 3]) {
            (await frameAt(index)).dispose();
          }
          expect(
            renderer.debugRowsMade,
            3,
            reason: 'a1 once, b1, b2 — frame 2 composes b2 alone',
          );
        });
      });

      testWidgets('🚨$door: a frame drawn with held rows is the frame drawn '
          'without them, byte for byte — and a line with no room holds '
          'none', (tester) async {
        await tester.runAsync(() async {
          Future<List<Uint8List>> run({required bool room}) async {
            final s = sessionOf([cut()]);
            addTearDown(s.dispose);
            parkEvery(s);
            if (!room) {
              s.playbackRig.playbackCache.debugSetPlaybackCacheBudgetBytes(0);
            }
            final (:renderer, :frameAt) = over(s);
            final frames = <Uint8List>[];
            for (final index in [0, 1, 2, 3]) {
              final image = await frameAt(index);
              frames.add(
                (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!.buffer.asUint8List(),
              );
              image.dispose();
            }
            expect(
              renderer.debugRowsMade,
              room ? 3 : 4,
              reason: 'LIVENESS: no room, and a1 is composed again',
            );
            return frames;
          }

          final held = await run(room: true);
          final none = await run(room: false);
          expect(held, none);
        });
      });

      testWidgets('$door: the rows are held on playback\'s line while the run '
          'goes — each as long as a held picture is made of it — and it is '
          'all handed back when the run ends', (tester) async {
        await tester.runAsync(() async {
          final s = sessionOf([cut()]);
          addTearDown(s.dispose);
          parkEvery(s);
          final (:renderer, :frameAt) = over(s);
          final line = s.playbackRig.playbackCache;
          final heldBefore = HeldRows.debugHeld;
          const row = 8 * 8 * 4;

          (await frameAt(0)).dispose();
          expect(line.lentBytes, 2 * row, reason: 'a1 and b1');
          (await frameAt(2)).dispose();
          expect(line.lentBytes, 3 * row, reason: 'b1 is the frame before\'s');
          (await frameAt(3)).dispose();
          expect(line.lentBytes, 2 * row, reason: 'two frames on: b1 goes');
          expect(HeldRows.debugHeld - heldBefore, 2);

          renderer.dispose();
          expect(line.lentBytes, 0);
          expect(HeldRows.debugHeld, heldBefore);
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
        'own picture, and the cut\'s picture under them is made ONCE', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final s = sessionOf([
          cut(
            camera: CutCamera(
              keyframes: {
                0: CameraPose(center: CanvasPoint(x: 3, y: 4)),
                1: CameraPose(center: CanvasPoint(x: 5, y: 4)),
              },
            ),
          ),
        ]);
        addTearDown(s.dispose);
        parkEvery(s);
        final renderer = ExportFrameRenderer(session: s);
        addTearDown(renderer.dispose);
        Future<ui.Image> frameAt(int index) =>
            renderer.renderCompositeForVideo(
              ExportFrameTask(cut: s.requireActiveCut, frameIndex: index),
              ExportSizeMode.camera,
            );

        final first = await frameAt(0);
        final made = renderer.debugPicturesMade;
        expect(made, 2, reason: 'LIVENESS: the cut\'s picture and the frame');
        final moved = await frameAt(1);
        expect(moved.isCloneOf(first), isFalse, reason: 'the camera moved');
        expect(
          renderer.debugPicturesMade,
          made + 1,
          reason: 'the frame alone — the cut\'s picture is the one it was',
        );
        final [before, after] = [
          for (final image in [first, moved])
            (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List(),
        ];
        expect(after, isNot(before), reason: 'and it shows another part');
        first.dispose();
        moved.dispose();
      });
    });
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
          Future<ui.Image> frameAt(int index) =>
              renderer.renderCompositeForVideo(
                ExportFrameTask(cut: cut, frameIndex: index),
                mode,
              );

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

        (await renderer.renderCompositeForVideo(
          task,
          ExportSizeMode.camera,
        )).dispose();
        final made = renderer.debugPicturesMade;
        expect(made, 2, reason: 'LIVENESS: the cut\'s picture and the frame');
        (await renderer.renderCompositeForVideo(
          task,
          ExportSizeMode.canvas,
        )).dispose();
        expect(renderer.debugPicturesMade, made + 1);
      });
    });
  });
}
