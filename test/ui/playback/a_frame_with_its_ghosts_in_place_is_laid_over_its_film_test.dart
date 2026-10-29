@Tags(['impeller'])
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
import 'package:anicel/src/models/onion_skin_settings.dart';
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

import '../../helpers/draw_on_current_frame.dart';

/// 🗣️onion-ghosts-in-place ② (유저 2026-10-26 「보통 합성이 아닌 경우라도
/// 최대한 극한으로 개선해보자」): a frame with its ghosts in place is laid
/// over its film — the frame as a run plays it: those texels as they are,
/// and where the ghosts show a picture of that place alone in their stead.
/// Byte for byte the frame laid whole, whatever lies over the ghosts: a
/// row's blend, a folder's strength and blur, a clip.
///
/// Laid by pictures of their own beside the session's, from its cels and
/// trees: one laid whole, one over the film laid first.
void main() {
  setUpAll(LayerBlendShader.load);
  setUpAll(DirectionalBlurShader.load);

  const canvasSize = CanvasSize(width: 128, height: 128);
  const pen = LayerId('pen');
  // The pen's cels before and after the playhead, the ghosts at frame 1:
  // one on the left, one on the right — and the drawing between them.
  final before = CanvasPoint(x: 14, y: 30);
  final after = CanvasPoint(x: 50, y: 30);
  final current = CanvasPoint(x: 32, y: 52);
  // Where no ghost shows, nor any spread of one: past the cells of a
  // blur round them (`blurReductionCell`).
  final away = CanvasPoint(x: 32, y: 112);

  Layer drawing(
    String id, {
    List<String>? cels,
    String? folder,
    bool clips = false,
    LayerBlendMode blend = LayerBlendMode.normal,
  }) {
    final names = cels ?? ['$id-0'];
    return Layer(
      id: LayerId(id),
      name: id.toUpperCase(),
      frames: [
        for (final cel in names)
          Frame(id: FrameId(cel), duration: 1, strokes: const []),
      ],
      timeline: names.length == 1
          ? {0: TimelineExposure.drawing(FrameId(names.single), length: 3)}
          : {
              for (var at = 0; at < names.length; at += 1)
                at: TimelineExposure.drawing(FrameId(names[at]), length: 1),
            },
      folderId: folder == null ? null : LayerId(folder),
      clipsToBelow: clips,
      blendMode: blend,
    );
  }

  Layer theRowWithTheOnion({
    String? folder,
    bool clips = false,
    LayerBlendMode blend = LayerBlendMode.normal,
  }) => drawing(
    'pen',
    cels: ['pen-0', 'pen-1', 'pen-2'],
    folder: folder,
    clips: clips,
    blend: blend,
  );

  LayerEffect blur(double radius) => LayerEffect(
    id: const EffectId('blur'),
    kind: EffectKind.blur,
    parameters: {'blurriness': EffectParameter(value: radius)},
  );

  /// A session on [layers], the onion on the pen's row at frame 1, laid in
  /// place — each row's cels inked: the pen's where its frame puts them
  /// (the cel before at [ghostAt], [ghostSize] across), every other row
  /// over the ghost before and in a band through the page.
  EditorSessionManager inked(
    List<Layer> layers, {
    CanvasPoint? ghostAt,
    double ghostSize = 9,
  }) {
    final app = EditorAppSettings();
    addTearDown(app.dispose);
    app.onionSkinSettings.value = app.onionSkinSettings.value.copyWith(
      placement: OnionSkinPlacement.inPlace,
    );
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
                duration: 3,
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
    void ink(Layer row, String cel, CanvasPoint at, double size, int color) =>
        inkCelIn(
          session.renderCaches.brushFrameStore,
          session.brushFrameKeyForCut(cut, row.id, FrameId(cel)),
          canvasSize: canvasSize,
          at: at,
          size: size,
          color: color,
          tileSize: 16,
        );
    var shade = 0;
    const colors = [0xFF3366CC, 0xC0CC3333, 0xFF33AA55, 0xA0EECC22];
    for (final row in layers) {
      if (!row.kind.composites || row.frames.isEmpty) {
        continue;
      }
      if (row.id == pen) {
        ink(row, 'pen-0', ghostAt ?? before, ghostSize, 0xFF000000);
        ink(row, 'pen-1', current, 9, 0xFF000000);
        ink(row, 'pen-2', after, 9, 0xFF000000);
        continue;
      }
      final color = colors[shade++ % colors.length];
      final cel = row.frames.single.id.value;
      ink(row, cel, before, 7, color);
      ink(row, cel, CanvasPoint(x: 32, y: 40), 13, color);
    }
    session.selectFrameIndex(1);
    session.onionSkin.toggleLayerOnionSkin(pen);
    return session;
  }

  /// Pictures of [session]'s frames in a store of their own.
  FramePictures besideThe(EditorSessionManager session) {
    final its = session.playbackRig.framePictures;
    final store = FramePictureStore<FramePictureKey>();
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
    return pictures;
  }

  Future<void> make(FramePictures pictures, DemandedPicture picture) async {
    expect(
      await pictures.make(picture, shouldAbort: () => false),
      isTrue,
      reason: '⛔premise: $picture is laid',
    );
  }

  Future<(ui.Rect, Uint8List)> bytesOf(
    FramePictures pictures,
    DemandedPicture picture,
  ) async {
    final made = pictures.store.peek(pictures.keyOf(picture));
    expect(made, isNotNull, reason: '⛔premise: $picture is held');
    final bytes = (await made!.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    return (made.extent, bytes.buffer.asUint8List());
  }

  Uint8List pixelOf((ui.Rect, Uint8List) picture, CanvasPoint at) {
    final (extent, bytes) = picture;
    final x = at.x.floor() - extent.left.round();
    final y = at.y.floor() - extent.top.round();
    final at4 = (y * extent.width.round() + x) * 4;
    return bytes.sublist(at4, at4 + 4);
  }

  ({DemandedPicture inPlace, DemandedPicture film}) atTheHead(
    EditorSessionManager session, {
    bool paper = true,
  }) {
    final cut = session.requireActiveCut;
    return (
      inPlace: standingPicturesOf(
        cut,
        1,
        OnionSkinPlacement.inPlace,
        paintPaper: paper,
      ).frame,
      film: (
        cut: cut,
        frameIndex: 1,
        paintPaper: paper,
        ghosts: FrameGhosts.none,
      ),
    );
  }

  /// Lays [session]'s frame at the head with its ghosts in place twice —
  /// whole, and over its film laid first — on its paper or on none, and
  /// asks the two for one picture.
  Future<void> expectOverItsFilmAsWhole(
    EditorSessionManager session, {
    bool paper = true,
  }) async {
    final (:inPlace, :film) = atTheHead(session, paper: paper);

    final whole = besideThe(session);
    await make(whole, inPlace);

    final over = besideThe(session);
    await make(over, film);
    await make(over, inPlace);

    expect(
      over.keyOf(inPlace),
      isNot(over.keyOf(film)),
      reason: '⛔premise: the ghosts are in the frame',
    );
    final (extent, bytes) = await bytesOf(over, inPlace);
    final (wholeExtent, wholeBytes) = await bytesOf(whole, inPlace);
    expect(extent, wholeExtent);
    expect(bytes, wholeBytes);
  }

  final shapes = <String, List<Layer> Function()>{
    'rows over and under it': () => [
      drawing('under'),
      theRowWithTheOnion(),
      drawing('over'),
    ],
    'a row multiplied over it': () => [
      drawing('under'),
      theRowWithTheOnion(),
      drawing('over', blend: LayerBlendMode.multiply),
    ],
    'its own row multiplied': () => [
      drawing('under'),
      theRowWithTheOnion(blend: LayerBlendMode.multiply),
    ],
    'a folder at half strength, blurred': () => [
      drawing('under'),
      drawing('in', folder: 'f'),
      theRowWithTheOnion(folder: 'f'),
      createFolderLayer(
        id: const LayerId('f'),
        name: 'F',
      ).copyWith(opacity: 0.5, effects: [blur(3)]),
      drawing('over'),
    ],
    'a row clipped to it': () => [
      theRowWithTheOnion(),
      drawing('clipped', clips: true),
    ],
    'clipped to the row under it': () => [
      drawing('base'),
      theRowWithTheOnion(clips: true),
    ],
  };

  for (final MapEntry(key: shape, value: layersOf) in shapes.entries) {
    testWidgets('$shape: laid over its film, the frame is the frame laid '
        'whole, byte for byte', (tester) async {
      await tester.runAsync(
        () => expectOverItsFilmAsWhole(inked(layersOf())),
      );
    });
  }

  // On no paper what lies over the ghosts can let the film's texels through
  // where they show: taken in their stead, not laid over them.
  testWidgets('on no paper, a row at half strength over it: laid over its '
      'film, the frame is the frame laid whole', (tester) async {
    await tester.runAsync(
      () => expectOverItsFilmAsWhole(
        inked([
          theRowWithTheOnion(),
          drawing('over').copyWith(opacity: 0.5),
        ]),
        paper: false,
      ),
    );
  });

  // A spread of the folder the ghost is in reaches past the cells round its
  // ink, and is told by the folder, not by the row under it.
  testWidgets('a folder blurring its ghost far past its cells, a row under '
      'the folder: laid over its film, the frame is the frame laid whole', (
    tester,
  ) async {
    await tester.runAsync(
      () => expectOverItsFilmAsWhole(
        inked([
          drawing('under'),
          theRowWithTheOnion(folder: 'f'),
          createFolderLayer(
            id: const LayerId('f'),
            name: 'F',
          ).copyWith(effects: [blur(48)]),
        ], ghostSize: 33),
      ),
    );
  });

  // I-132-Q3: so does a spin's, which turns the ghost about the paper's
  // middle — as far as the paper's farthest corner moves.
  testWidgets('a folder spinning its ghost about the paper\'s middle: laid '
      'over its film, the frame is the frame laid whole', (tester) async {
    await tester.runAsync(
      () => expectOverItsFilmAsWhole(
        inked([
          drawing('under'),
          theRowWithTheOnion(folder: 'f'),
          createFolderLayer(id: const LayerId('f'), name: 'F').copyWith(
            effects: [
              LayerEffect(
                id: const EffectId('spin'),
                kind: EffectKind.radialBlur,
                parameters: {'amount': EffectParameter(value: 40)},
              ),
            ],
          ),
        ]),
      ),
    );
  });

  // Over its film a frame draws its nodes only where its ghosts show; a
  // canvas that draws on it holds them in a turn of their own
  // (`FramePictures.holdNodesOf`).
  testWidgets('laid over its film for a canvas that draws on it, the frame '
      'keeps none of its nodes', (tester) async {
    await tester.runAsync(() async {
      final session = inked(shapes['rows over and under it']!());
      final (:inPlace, :film) = atTheHead(session);
      Future<bool> keptLaidForAPen(FramePictures pictures) async {
        expect(
          await pictures.makeShown(
            pictures.stackOf(inPlace),
            inPlace,
            shouldAbort: () => false,
            keepsNodes: true,
          ),
          isTrue,
          reason: '⛔premise: the frame is laid',
        );
        return pictures.heldNodes.holdsAllOf(pictures.keyOf(inPlace));
      }

      expect(
        await keptLaidForAPen(besideThe(session)),
        isTrue,
        reason: '⛔premise: laid whole for a pen, it keeps them',
      );
      final over = besideThe(session);
      await make(over, film);
      expect(await keptLaidForAPen(over), isFalse);
    });
  });

  // A frame covers its page and every row's buffer: past the film's, the
  // frame holds its ghosts alone.
  testWidgets('a ghost out on the pasteboard takes the frame past its film: '
      'laid over it all the same', (tester) async {
    await tester.runAsync(() async {
      final session = inked(
        [drawing('under'), theRowWithTheOnion()],
        ghostAt: CanvasPoint(x: -30, y: 30),
      );
      final (:inPlace, :film) = atTheHead(session);
      final whole = besideThe(session);
      await make(whole, inPlace);
      final over = besideThe(session);
      await make(over, film);
      await make(over, inPlace);

      final (extent, bytes) = await bytesOf(over, inPlace);
      final (filmExtent, _) = await bytesOf(over, film);
      expect(
        extent.left,
        lessThan(filmExtent.left),
        reason: '⛔premise: the ghost takes the frame past its film',
      );
      final (wholeExtent, wholeBytes) = await bytesOf(whole, inPlace);
      expect(extent, wholeExtent);
      expect(bytes, wholeBytes);
    });
  });

  testWidgets('🚨the film\'s texels are taken as they are wherever no ghost '
      'shows — and where one does, the frame is drawn there anew', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = inked(shapes['rows over and under it']!());
      final (:inPlace, :film) = atTheHead(session);
      final whole = besideThe(session);
      await make(whole, inPlace);
      final wholePicture = await bytesOf(whole, inPlace);

      // A film no frame draws: red from edge to edge, under the film's key.
      final poisoned = besideThe(session);
      await poisoned.store.lay(poisoned.keyOf(film), (
        extent: wholePicture.$1,
        outside: const ui.Color(0x00000000),
        draw: (canvas) => canvas.drawColor(
          const ui.Color(0xFFFF0000),
          ui.BlendMode.src,
        ),
      ));
      await make(poisoned, inPlace);
      final laid = await bytesOf(poisoned, inPlace);

      expect(pixelOf(laid, away), [255, 0, 0, 255], reason: 'the film');
      for (final ghost in [before, after]) {
        expect(
          pixelOf(laid, ghost),
          pixelOf(wholePicture, ghost),
          reason: 'drawn anew at $ghost',
        );
      }
    });
  });
}
