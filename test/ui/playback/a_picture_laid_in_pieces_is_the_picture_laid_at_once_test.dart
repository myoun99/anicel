@Tags(['gpu'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/canvas/directional_blur_shader.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/frame_pictures.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';
import 'package:anicel/src/ui/session/editor_app_settings.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart' show noFlutterGpu;
import '../../helpers/draw_on_current_frame.dart';

/// 🗣️a-picture-lay-once-limit-and-piece-side-apart (유저 2026-10-31):
/// 「조각사이에 선이 보인다던가 픽셀 다르면 안되니까 그부분이 걱정」. A
/// picture laid in pieces is the picture laid at once, byte for byte: a
/// row's blend, its strength, a folder's, a clip, with the ink across the
/// pieces' edges and on no paper as on one.
///
/// ⚠️A chain that spreads is the one that is not, and it is held to how far
/// it may be. It reads a raster cut where the piece cuts it, of another size
/// than the whole's, so its sums round another way: 🔬up to 4/255 at about
/// 5% of the pixels on the runner's Vulkan, up to 1/255 at 0.1–0.3% on the
/// Windows app (Surface Pro 11, GLES, 2026-10-31) — through the piece, not
/// along its edges.
void main() {
  setUpAll(LayerBlendShader.load);
  setUpAll(DirectionalBlurShader.load);

  const canvasSize = CanvasSize(width: 1024, height: 512);
  const pieceSide = 256;

  Layer drawing(
    String id, {
    String? folder,
    bool clips = false,
    double opacity = 1,
    LayerBlendMode blend = LayerBlendMode.normal,
    List<LayerEffect> effects = const [],
  }) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('$id-0'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-0'), length: 1)},
    folderId: folder == null ? null : LayerId(folder),
    clipsToBelow: clips,
    blendMode: blend,
  ).copyWith(opacity: opacity, effects: effects);

  Layer folder({
    double opacity = 1,
    LayerBlendMode blend = LayerBlendMode.normal,
    List<LayerEffect> effects = const [],
  }) => createFolderLayer(
    id: const LayerId('f'),
    name: 'F',
  ).copyWith(opacity: opacity, blendMode: blend, effects: effects);

  LayerEffect effect(EffectKind kind, Map<String, double> values) =>
      LayerEffect(
        id: const EffectId('effect'),
        kind: kind,
        parameters: {
          for (final MapEntry(:key, :value) in values.entries)
            key: EffectParameter(value: value),
        },
      );

  /// A session on [layers], each row's cel inked in dabs across the pieces'
  /// edges, the rows' apart so each shows through the others.
  EditorSessionManager inked(List<Layer> layers) {
    final app = EditorAppSettings();
    addTearDown(app.dispose);
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'T',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: 'cut',
                duration: 1,
                canvasSize: canvasSize,
                layers: layers,
              ),
            ],
          ),
        ],
      ),
      appSettings: app,
    );
    addTearDown(session.dispose);
    final cut = session.requireActiveCut;
    var shade = 0;
    const colors = [0xFF3366CC, 0xC0CC3333, 0xFF33AA55];
    for (final row in layers) {
      if (!row.kind.composites || row.frames.isEmpty) {
        continue;
      }
      for (var y = 40 + shade * 17; y < 500; y += 64) {
        for (var x = 20 + shade * 23; x < 1010; x += 64) {
          inkCelIn(
            session.renderCaches.brushFrameStore,
            session.brushFrameKeyForCut(cut, row.id, row.frames.single.id),
            canvasSize: canvasSize,
            at: CanvasPoint(x: x.toDouble(), y: y.toDouble()),
            size: 46,
            color: colors[shade % colors.length],
            tileSize: 64,
          );
        }
      }
      shade += 1;
    }
    return session;
  }

  /// The picture of [picture] in a store of its own, laid at once up to
  /// [once] a side.
  Future<(ui.Rect, Uint8List)> laid(
    EditorSessionManager session,
    DemandedPicture picture, {
    required int once,
  }) async {
    final its = session.playbackRig.framePictures;
    final store = FramePictureStore<FramePictureKey>(
      onceSide: once,
      pieceSide: pieceSide,
    );
    final pictures = FramePictures(
      store: store,
      layerImages: its.layerImages,
      stackOf: its.stackOf,
      pageOf: its.pageOf,
    );
    addTearDown(() {
      pictures.dispose();
      store.dispose();
    });
    expect(
      await pictures.make(picture, shouldAbort: () => false),
      isTrue,
      reason: '⛔premise: $picture is laid',
    );
    final made = pictures.store.peek(pictures.keyOf(picture))!;
    final bytes = (await made.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    return (made.extent, bytes.buffer.asUint8List());
  }

  /// [layers]' frame laid at once and in pieces, as their bytes.
  Future<(Uint8List, Uint8List)> atOnceAndInPieces(
    List<Layer> layers, {
    required bool paper,
  }) async {
    final session = inked(layers);
    final picture = (
      cut: session.requireActiveCut,
      frameIndex: 0,
      paintPaper: paper,
      ghosts: FrameGhosts.none,
    );
    final (extent, atOnce) = await laid(session, picture, once: 1 << 20);
    final (inExtent, inPieces) = await laid(
      session,
      picture,
      once: pieceSide,
    );
    expect(inExtent, extent);
    expect(
      extent.width,
      greaterThan(pieceSide * 3),
      reason: '⛔premise: laid in pieces across',
    );
    expect(
      extent.height,
      greaterThan(pieceSide),
      reason: '⛔premise: laid in pieces down',
    );
    return (atOnce, inPieces);
  }

  final exactly = <String, List<Layer> Function()>{
    'rows over one another': () => [drawing('under'), drawing('over')],
    'a row at half strength': () => [
      drawing('under'),
      drawing('over', opacity: 0.5),
    ],
    // Each way a blend is drawn: by a shader over its backdrop, separable
    // or not, and in the GPU's own.
    for (final mode in const [
      LayerBlendMode.multiply,
      LayerBlendMode.hue,
      LayerBlendMode.add,
    ])
      'a row in ${mode.name}': () => [
        drawing('under'),
        drawing('over', blend: mode),
      ],
    'a row in multiply at half strength': () => [
      drawing('under'),
      drawing('over', blend: LayerBlendMode.multiply, opacity: 0.5),
    ],
    'a folder at half strength': () => [
      drawing('under'),
      drawing('in', folder: 'f'),
      folder(opacity: 0.5),
    ],
    'a folder in multiply': () => [
      drawing('under'),
      drawing('in', folder: 'f'),
      folder(blend: LayerBlendMode.multiply),
    ],
    'a row clipped to the row under it': () => [
      drawing('under'),
      drawing('over', clips: true),
    ],
  };

  final spreading = <String, List<Layer> Function()>{
    'a row blurred': () => [
      drawing('under'),
      drawing(
        'over',
        effects: [
          effect(EffectKind.blur, {'blurriness': 3}),
        ],
      ),
    ],
    // Far enough to reduce what it reads (`blurReductionCell`).
    'a row blurred far': () => [
      drawing('under'),
      drawing(
        'over',
        effects: [
          effect(EffectKind.blur, {'blurriness': 40}),
        ],
      ),
    ],
    'a folder blurred': () => [
      drawing('under'),
      drawing('in', folder: 'f'),
      folder(
        opacity: 0.5,
        effects: [
          effect(EffectKind.blur, {'blurriness': 3}),
        ],
      ),
    ],
    'a row blurred along a way': () => [
      drawing('under'),
      drawing(
        'over',
        effects: [
          effect(EffectKind.directionalBlur, {
            'direction': 30,
            'blurLength': 40,
          }),
        ],
      ),
    ],
    'a row blurred round a centre': () => [
      drawing('under'),
      drawing(
        'over',
        effects: [
          effect(EffectKind.radialBlur, {'amount': 20}),
        ],
      ),
    ],
  };

  for (final paper in const [true, false]) {
    final on = paper ? 'on its paper' : 'on no paper';
    for (final MapEntry(key: shape, value: layersOf) in exactly.entries) {
      testWidgets('$shape, $on: laid in pieces, the picture laid at once, '
          'byte for byte', (tester) async {
        await tester.runAsync(() async {
          final (atOnce, inPieces) = await atOnceAndInPieces(
            layersOf(),
            paper: paper,
          );
          expect(inPieces, atOnce);
        });
      }, skip: noFlutterGpu != null);
    }
    for (final MapEntry(key: shape, value: layersOf) in spreading.entries) {
      testWidgets('$shape, $on: laid in pieces, within 4/255 of the picture '
          'laid at once', (tester) async {
        await tester.runAsync(() async {
          final (atOnce, inPieces) = await atOnceAndInPieces(
            layersOf(),
            paper: paper,
          );
          var most = 0;
          for (var at = 0; at < atOnce.length; at += 1) {
            final apart = (atOnce[at] - inPieces[at]).abs();
            if (apart > most) {
              most = apart;
            }
          }
          expect(most, lessThanOrEqualTo(4));
        });
      }, skip: noFlutterGpu != null);
    }
  }
}
