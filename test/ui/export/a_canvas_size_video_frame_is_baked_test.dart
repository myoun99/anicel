import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart' show ExportLayerFx;
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
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

/// A CANVAS-size video frame is baked: the backdrop under it, the V row's
/// chain through it, a transition's two cuts mixed in it, the names over it
/// — and a still of the same frame takes none of the names.
///
/// What a frame is made of is gathered into one value and painted from it
/// alone (F-289); each part of that value is pinned here by the pixels it
/// leaves. The paper is GREEN — the project's, laid as a camera-size frame
/// lays it (export-film-preview-is-not-the-film-Q1) — on a renderer's WHITE
/// ground, and the backdrop RED, so none passes for another.
void main() {
  const green = ui.Color(0xFF00FF00);
  const white = ui.Color(0xFFFFFFFF);
  const red = 0xFFFF0000;
  // One tile at the engine's side; the pins read it in eighths.
  const tileSide = defaultCelTileSize;
  const eighth = tileSide ~/ 8;
  const small = CanvasSize(width: tileSide, height: tileSide);
  const trackId = TrackId('t');

  Frame drawing(String id, {int length = 1}) =>
      Frame(id: FrameId(id), duration: length, strokes: const []);

  /// A cut of [duration] frames holding one drawing, [id]'s own.
  Cut cutOf(String id, {int duration = 24, CanvasSize size = small}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    canvasSize: size,
    layers: [
      Layer(
        id: LayerId('$id-row'),
        name: 'A',
        frames: [drawing('$id-drawing')],
        timeline: {
          0: TimelineExposure.drawing(FrameId('$id-drawing'), length: duration),
        },
      ),
      createCameraLayer(cutId: CutId(id)),
    ],
  );

  EditorSessionManager sessionOf(
    List<Cut> cuts, {
    List<LayerEffect> effects = const [],
    bool fxEnabled = true,
    List<Layer> seLayers = const [],
    Layer? transitions,
    CanvasSize camera = small,
  }) => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('baked'),
      name: 'Baked',
      createdAt: DateTime.utc(2026),
      cameraSize: camera,
      backdropArgb: red,
      background: ProjectBackground.color(green.toARGB32()),
      tracks: [
        Track(
          id: trackId,
          name: 'V',
          cuts: cuts,
          effects: effects,
          fxEnabled: fxEnabled,
          seLayers: seLayers,
          transitionLayer: transitions,
        ),
      ],
    ),
  );

  /// Parks a tile of one colour as each cut's drawing — its first
  /// [columns], the whole tile unless told — all in one parking, since a
  /// parking replaces the whole store ([parkCold]). ↩️It parked one cut a
  /// call, and the O.L pins below inked their second cut alone: the first
  /// cut's "ink" was the renderer's green ground.
  void ink(
    EditorSessionManager session,
    Map<Cut, (int, int, int)> inks, {
    int columns = tileSide,
  }) {
    BitmapSurface tileOf((int, int, int) rgb) {
      final pixels = Uint8List(tileSide * tileSide * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        if ((i ~/ 4) % tileSide >= columns) {
          continue;
        }
        pixels[i] = rgb.$1;
        pixels[i + 1] = rgb.$2;
        pixels[i + 2] = rgb.$3;
        pixels[i + 3] = 255;
      }
      return BitmapSurface(
        canvasSize: small,
        tileSize: tileSide,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(size: tileSide, pixels: pixels),
        },
      );
    }

    parkCold(session.renderCaches.brushFrameStore, {
      for (final MapEntry(key: cut, value: rgb) in inks.entries)
        session.brushFrameKeyForCut(
          cut,
          cut.layers.first.id,
          cut.layers.first.frames.single.id,
        ): tileOf(rgb),
    });
  }

  /// The pixels of [task] as a canvas-size video frame, written with
  /// [layerFx] — null for a picture of the screen.
  Future<Uint8List> videoFrame(
    EditorSessionManager session,
    ExportFrameTask task, {
    bool preserveAlpha = false,
    ExportLayerFx? layerFx,
    CanvasSize? outputSize,
  }) async {
    final renderer = ExportFrameRenderer(
      session: session,
      ground: white,
      layerFx: layerFx,
    );
    final image = outputSize == null
        ? await renderer
              .videoRun(
                [task],
                ExportSizeMode.canvas,
                preserveAlpha: preserveAlpha,
              )
              .frame(0)
        : await renderer.renderVideoFrame(
            task,
            ExportSizeMode.canvas,
            preserveAlpha: preserveAlpha,
            outputSize: outputSize,
          );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    renderer.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// The pixel at ([x], [y]) of [bytes], a square picture's.
  (int, int, int, int) pixelOf(
    Uint8List bytes,
    int x,
    int y, {
    int side = tileSide,
  }) {
    final offset = (y * side + x) * 4;
    return (
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
      bytes[offset + 3],
    );
  }

  /// The pixel in the middle of [bytes], a square picture's.
  (int, int, int, int) centreOf(Uint8List bytes, {int side = tileSide}) =>
      pixelOf(bytes, side ~/ 2, side ~/ 2, side: side);

  testWidgets('a gap frame is the backdrop — and nothing at all under an '
      'alpha master', (tester) async {
    await tester.runAsync(() async {
      final session = sessionOf([cutOf('c')]);
      addTearDown(session.dispose);
      final gap = ExportFrameTask(cut: session.requireActiveCut, frameIndex: -1);

      expect(centreOf(await videoFrame(session, gap)), (255, 0, 0, 255));
      expect(
        centreOf(await videoFrame(session, gap, preserveAlpha: true)),
        (0, 0, 0, 0),
      );
    });
  });

  // ↩️Two pins stood here and in the O.L group below — 「a track at half
  // its weight thins the cut over the backdrop」 and 「…lets the backdrop
  // through the mix」: the V row's static opacity, which left with its bar
  // (I-73, 2026-10-08). A cut is thinned by a transition alone now.

  testWidgets('the V row\'s chain filters the cut\'s picture — and never the '
      'paper it stands on', (tester) async {
    // ↩️The chain filtered the FINISHED frame, its ground included, so a
    // grade on the V row tinted this route's paper and no other route's —
    // until the chain went into the cut's tree, as every route lays it
    // (`underTheCutsFx`, card video-export-speed-Q2).
    await tester.runAsync(() async {
      // The cut's left half inked, its right half the paper.
      EditorSessionManager halfInked({List<LayerEffect> effects = const []}) {
        final session = sessionOf([cutOf('c')], effects: effects);
        ink(
          session,
          {session.requireActiveCut: (0, 0, 100)},
          columns: tileSide ~/ 2,
        );
        return session;
      }

      final plain = halfInked();
      addTearDown(plain.dispose);
      final graded = halfInked(
        effects: [
          LayerEffect(
            id: const EffectId('fx'),
            kind: EffectKind.brightnessContrast,
            // Half of its range of ±100.
            parameters: {'brightness': EffectParameter(value: 50)},
          ),
        ],
      );
      addTearDown(graded.dispose);
      ExportFrameTask taskOf(EditorSessionManager session) =>
          ExportFrameTask(cut: session.requireActiveCut, frameIndex: 0);

      final plainFrame = await videoFrame(plain, taskOf(plain));
      expect(
        (
          pixelOf(plainFrame, eighth, 4 * eighth),
          pixelOf(plainFrame, 6 * eighth, 4 * eighth),
        ),
        ((0, 0, 100, 255), (0, 255, 0, 255)),
        reason: 'CONTROL: the ink and the paper as they are',
      );
      final gradedFrame = await videoFrame(graded, taskOf(graded));
      final (r, _, b, _) = pixelOf(gradedFrame, eighth, 4 * eighth);
      expect(r, greaterThan(40), reason: 'the ink brightened');
      expect(b, greaterThan(140));
      expect(
        pixelOf(gradedFrame, 6 * eighth, 4 * eighth),
        (0, 255, 0, 255),
        reason: 'the paper as it is',
      );
    });
  });

  group('two cuts an O.L mixes', () {
    /// c1 inked green-ish, c2 inked blue — their first [columns] — an O.L
    /// over frames 12–35, under the V row's [effects] behind its switch
    /// [fxEnabled].
    EditorSessionManager mixing({
      List<LayerEffect> effects = const [],
      bool fxEnabled = true,
      int columns = tileSide,
    }) {
      final session = sessionOf(
        [cutOf('c1'), cutOf('c2')],
        effects: effects,
        fxEnabled: fxEnabled,
        transitions: createTrackTransitionLayer(trackId).copyWith(
          instructions: SplayTreeMap.of({
            12: const InstructionEvent(instructionId: 'ol', length: 24),
          }),
        ),
      );
      final [c1, c2] = session.repository.requireProject().tracks.single.cuts;
      ink(session, {c1: (0, 200, 0), c2: (0, 0, 200)}, columns: columns);
      return session;
    }

    ExportFrameTask midway(EditorSessionManager session) => ExportFrameTask(
      cut: session.repository.requireProject().tracks.single.cuts.first,
      // The O.L's twelfth frame of twenty-four: half of each.
      frameIndex: 23,
    );

    testWidgets('🚨halfway, the frame is half of each cut', (tester) async {
      await tester.runAsync(() async {
        final session = mixing();
        addTearDown(session.dispose);

        final (r, g, b, a) = centreOf(
          await videoFrame(session, midway(session)),
        );
        expect(g, inInclusiveRange(60, 140), reason: 'the leaving cut, thinning');
        expect(b, inInclusiveRange(60, 140), reason: 'the arriving cut, coming');
        expect((r, a), (0, 255), reason: 'two whole cuts hide the backdrop');
      });
    });

    testWidgets('at a preview\'s size the mix is the same, smaller: each cut '
        'laid at that size (export-film-preview-is-not-the-film)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // Their left halves inked, their right halves the paper.
        final session = mixing(columns: tileSide ~/ 2);
        addTearDown(session.dispose);

        const half = tileSide ~/ 2;
        final frame = await videoFrame(
          session,
          midway(session),
          outputSize: const CanvasSize(width: half, height: half),
        );
        expect(frame.length, half * half * 4, reason: 'at the size asked');
        final (_, g, b, _) = pixelOf(frame, eighth, 2 * eighth, side: half);
        expect(g, inInclusiveRange(60, 140), reason: 'the leaving cut\'s ink');
        expect(b, inInclusiveRange(60, 140), reason: 'the arriving cut\'s ink');
        // A pixel in from the ink's edge: reduced as the canvas reduces
        // (7′, the engine's filter for the scale), the ink reaches the
        // first column of paper past it. ↩️Read at that column while each
        // cut was laid by a box of whole pixels.
        expect(
          pixelOf(frame, 3 * eighth, 2 * eighth, side: half),
          (0, 255, 0, 255),
          reason: 'both papers — not the left of a whole-size picture',
        );
      });
    });

    testWidgets('🎯the V row\'s chain filters each cut it mixes', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final session = mixing(
          effects: [
            LayerEffect(
              id: const EffectId('fx'),
              kind: EffectKind.brightnessContrast,
              parameters: {'brightness': EffectParameter(value: 50)},
            ),
          ],
        );
        addTearDown(session.dispose);

        final (r, _, _, a) = centreOf(
          await videoFrame(session, midway(session)),
        );
        expect(r, greaterThan(40), reason: 'neither cut has red but the lift');
        expect(a, 255);
      });
    });

    // 🗣️I-65-Q11 (유저 2026-10-25): 「켬 · 기본만 켬이면 화면 스위치대로, 끔이면
    // 빠짐」. ↩️Q8 laid it whatever the switch said.
    testWidgets('🚨an output lays the V row\'s chain on each cut it mixes as '
        'the row\'s switch shows it under 켬 and 기본만 켬 — never under 끔', (
      tester,
    ) async {
      await tester.runAsync(() async {
        Future<int> redThrough(
          ExportLayerFx? layerFx, {
          required bool switchedOn,
        }) async {
          final session = mixing(
            effects: [
              LayerEffect(
                id: const EffectId('fx'),
                kind: EffectKind.brightnessContrast,
                parameters: {'brightness': EffectParameter(value: 50)},
              ),
            ],
            fxEnabled: switchedOn,
          );
          try {
            final (r, _, _, _) = centreOf(
              await videoFrame(session, midway(session), layerFx: layerFx),
            );
            return r;
          } finally {
            session.dispose();
          }
        }

        for (final switchedOn in [true, false]) {
          final shown = await redThrough(null, switchedOn: switchedOn);
          expect(
            shown > 40,
            switchedOn,
            reason: 'the screen\'s picture, switched ${switchedOn ? 'on' : 'off'}',
          );
          for (final layerFx in ExportLayerFx.values) {
            final laid = await redThrough(layerFx, switchedOn: switchedOn);
            expect(
              laid > 40,
              switchedOn && layerFx != ExportLayerFx.off,
              reason: '$layerFx, switched ${switchedOn ? 'on' : 'off'}',
            );
          }
        }
      });
    });
  });

  group('a name over the picture', () {
    const wide = CanvasSize(width: 320, height: 180);

    /// An SE row whose speaker is named for the whole cut.
    Layer speaker() => Layer(
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
      timeline: const {0: TimelineExposure.drawing(FrameId('line'), length: 24)},
    );

    EditorSessionManager sessionWith({required bool named}) => sessionOf(
      [cutOf('c', size: wide)],
      camera: wide,
      seLayers: [if (named) speaker()],
    );

    testWidgets('🚨a video frame carries it, and a still of the same frame '
        'does not', (tester) async {
      await tester.runAsync(() async {
        final named = sessionWith(named: true);
        addTearDown(named.dispose);
        final bare = sessionWith(named: false);
        addTearDown(bare.dispose);
        ExportFrameTask taskOf(EditorSessionManager session) =>
            ExportFrameTask(cut: session.requireActiveCut, frameIndex: 0);
        expect(
          named.seEntries.seNameTagsForCutFrame(named.requireActiveCut, 0),
          hasLength(1),
          reason: 'LIVENESS: somebody is named',
        );

        expect(
          await videoFrame(named, taskOf(named)),
          isNot(await videoFrame(bare, taskOf(bare))),
          reason: 'the name is in the video',
        );

        Future<Uint8List> still(EditorSessionManager session) async {
          final image = await ExportFrameRenderer(
            session: session,
            ground: green,
          ).renderComposite(taskOf(session), ExportSizeMode.canvas);
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return bytes!.buffer.asUint8List();
        }

        expect(
          await still(named),
          await still(bare),
          reason: 'a still is a compositing source: it stays clean',
        );
      });
    });
  });
}
