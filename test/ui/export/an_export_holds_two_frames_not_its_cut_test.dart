import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
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

  EditorSessionManager sessionOf(List<Cut> cuts, {Layer? transitions}) =>
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
}
