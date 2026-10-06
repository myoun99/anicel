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
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
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
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

/// A CANVAS-size video frame is baked: the backdrop under it, the cut
/// thinned to its track's weight, the V row's chain through it, a
/// transition's two cuts mixed in it, the names over it — and a still of
/// the same frame takes none of the names.
///
/// What a frame is made of is gathered into one value and painted from it
/// alone (F-289); each part of that value is pinned here by the pixels it
/// leaves. The paper is GREEN (the canvas route stands a frame on the
/// renderer's own ground) and the backdrop RED, so neither passes for the
/// other.
void main() {
  const green = ui.Color(0xFF00FF00);
  const red = 0xFFFF0000;
  const small = CanvasSize(width: 8, height: 8);
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
    double opacity = 1,
    List<LayerEffect> effects = const [],
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
      tracks: [
        Track(
          id: trackId,
          name: 'V',
          cuts: cuts,
          opacity: opacity,
          effects: effects,
          seLayers: seLayers,
          transitionLayer: transitions,
        ),
      ],
    ),
  );

  /// Parks a whole tile of one colour as [cut]'s drawing.
  void ink(EditorSessionManager session, Cut cut, (int, int, int) rgb) {
    final pixels = Uint8List(8 * 8 * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = rgb.$1;
      pixels[i + 1] = rgb.$2;
      pixels[i + 2] = rgb.$3;
      pixels[i + 3] = 255;
    }
    final layer = cut.layers.first;
    final key = session.brushFrameKeyForCut(
      cut,
      layer.id,
      layer.frames.single.id,
    );
    session.renderCaches.brushFrameStore.restoreBaked({
      key: AnicelCelBlob.encode(
        AnicelCelEntry.fromSurface(
          key,
          BitmapSurface(
            canvasSize: small,
            tileSize: 8,
            tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
          ),
        ),
      ),
    });
  }

  /// The pixels of [task] as a canvas-size video frame.
  Future<Uint8List> videoFrame(
    EditorSessionManager session,
    ExportFrameTask task, {
    bool preserveAlpha = false,
  }) async {
    final renderer = ExportFrameRenderer(session: session, background: green);
    final image = await renderer.renderCompositeForVideo(
      task,
      ExportSizeMode.canvas,
      preserveAlpha: preserveAlpha,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    renderer.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// The pixel in the middle of [bytes], a square picture's.
  (int, int, int, int) centreOf(Uint8List bytes, {int side = 8}) {
    final offset = ((side ~/ 2) * side + side ~/ 2) * 4;
    return (
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
      bytes[offset + 3],
    );
  }

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

  testWidgets('🚨a track at half its weight thins the cut over the backdrop '
      '— and over nothing under an alpha master', (tester) async {
    await tester.runAsync(() async {
      final session = sessionOf([cutOf('c')], opacity: 0.5);
      addTearDown(session.dispose);
      final task = ExportFrameTask(cut: session.requireActiveCut, frameIndex: 0);

      final (r, g, b, a) = centreOf(await videoFrame(session, task));
      expect(r, closeTo(128, 3), reason: 'half the backdrop\'s red');
      expect(g, closeTo(128, 3), reason: 'half the paper\'s green');
      expect((b, a), (0, 255));

      // Premultiplied: half a green, and nothing under it.
      final (clearR, clearG, _, clearA) = centreOf(
        await videoFrame(session, task, preserveAlpha: true),
      );
      expect(clearR, 0);
      expect(clearG, closeTo(128, 3));
      expect(clearA, closeTo(128, 3));
    });
  });

  testWidgets('the V row\'s chain filters the cut\'s picture', (tester) async {
    await tester.runAsync(() async {
      final plain = sessionOf([cutOf('c')]);
      addTearDown(plain.dispose);
      final graded = sessionOf(
        [cutOf('c')],
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

      expect(
        centreOf(await videoFrame(plain, taskOf(plain))),
        (0, 255, 0, 255),
        reason: 'CONTROL: the paper as it is',
      );
      final (r, g, b, _) = centreOf(await videoFrame(graded, taskOf(graded)));
      expect(g, 255);
      expect(r, greaterThan(40), reason: 'brightened');
      expect(b, greaterThan(40));
    });
  });

  group('two cuts an O.L mixes', () {
    /// c1 inked green-ish, c2 inked blue, an O.L over frames 12–35.
    EditorSessionManager mixing({double opacity = 1}) {
      final session = sessionOf(
        [cutOf('c1'), cutOf('c2')],
        opacity: opacity,
        transitions: createTrackTransitionLayer(trackId).copyWith(
          instructions: SplayTreeMap.of({
            12: const InstructionEvent(instructionId: 'ol', length: 24),
          }),
        ),
      );
      final [c1, c2] = session.repository.requireProject().tracks.single.cuts;
      ink(session, c1, (0, 200, 0));
      ink(session, c2, (0, 0, 200));
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

    testWidgets('a track at half its weight lets the backdrop through the '
        'mix', (tester) async {
      await tester.runAsync(() async {
        final session = mixing(opacity: 0.5);
        addTearDown(session.dispose);

        final (r, _, _, a) = centreOf(
          await videoFrame(session, midway(session)),
        );
        expect(r, greaterThan(60), reason: 'the backdrop\'s red, under both');
        expect(a, 255);
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
            background: green,
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
