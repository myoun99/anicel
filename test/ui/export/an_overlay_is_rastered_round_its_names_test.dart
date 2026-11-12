import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/layer_effect.dart'
    show EffectKind, ResolvedLayerEffect;
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/native/app_gpu_engine.dart' show appGpuExport;
import 'package:anicel/src/services/layer_pose_matrix.dart'
    show LayerPlacement;
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/frame_shots.dart' show drawnOnTheEngine;
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';

import '../../helpers/app_faces.dart';

/// An export's overlay is rastered only round where its painter inks
/// ([PlaybackFramePainter.inkOf]) and laid where it stands on a blank of
/// the whole raster ([drawnOnTheEngine]) — and the frame it makes on the
/// engine is the whole raster's — to a channel's rounding where a name is
/// resampled.
///
/// Card an-exports-overlay-raster-reads-back-the-whole-frame: 🔬a 4K
/// frame's names inked 1–20% of it, and the whole of it was rastered, read
/// back and put on the GPU.
void main() {
  // The names in the app's own faces, as an export letters them: a glyph's
  // edge is where a raster moved by whole pixels would part from the whole.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTheAppFaces);
  const canvas = CanvasSize(width: 1280, height: 720);
  const frame = CanvasSize(width: 640, height: 360);
  // Turned and zoomed, off the canvas's middle: the names' box is laid
  // through all of it.
  final pose = CameraPose(
    center: CanvasPoint(x: 700, y: 380),
    zoom: 1.2,
    rotationDegrees: 30,
  );

  ResolvedSeNameTag tag(
    String text,
    ui.Offset at, {
    List<ResolvedLayerEffect> effects = const [],
    double opacity = 1,
  }) => ResolvedSeNameTag(
    layerId: text,
    widthBudget: 120,
    shot: const LayerPlacement.identity(),
    opacity: opacity,
    effects: effects,
    content: TextCelContent(
      text: text,
      style: SeNameTag.defaultStyle,
      position: at,
    ),
  );

  final names = [
    tag('A', const ui.Offset(640, 330)),
    // A blur: its buffer reaches past its plate.
    tag(
      'あ',
      const ui.Offset(690, 370),
      effects: [
        ResolvedLayerEffect(kind: EffectKind.blur, values: const [12, 0]),
      ],
    ),
    // Across the frame's top: cut where it is.
    tag('가', const ui.Offset(700, 250)),
  ];

  PlaybackFramePainter over({
    List<ResolvedSeNameTag>? tags,
    CameraPose? camera,
    CanvasViewport? viewport,
    double imageOpacity = 1,
    bool paintPaper = false,
    bool paintLetterbox = false,
    ui.Color? pasteboardColor,
    List<({int color, double opacity})> veils = const [],
  }) => PlaybackFramePainter(
    canvasSize: canvas,
    viewport: viewport,
    cameraPose: camera ?? pose,
    cameraFrameSize: frame,
    paintPaper: paintPaper,
    paintLetterbox: paintLetterbox,
    pasteboardColor: pasteboardColor,
    seNameTags: tags ?? names,
    imageOpacity: imageOpacity,
    veils: veils,
  );

  /// What [painter] draws on a [width] × [height] raster — rastered round
  /// where it says it inks, or whole — laid on the engine over a frame of
  /// nothing, as an export lays it over its picture, read back.
  Future<Uint8List> laid(
    PlaybackFramePainter painter,
    int width,
    int height, {
    required bool round,
  }) async {
    final size = ui.Size(width.toDouble(), height.toDouble());
    final shown = await drawnOnTheEngine(
      appGpuExport,
      width,
      height,
      (canvas) => painter.paint(canvas, size),
      inks: round ? painter.inkOf(size) : null,
    );
    final frame = appGpuExport.blank(width, height);
    try {
      appGpuExport.lay(frame, shown);
      return appGpuExport.read(frame).take();
    } finally {
      frame.free();
      shown.free();
    }
  }

  int inked(Uint8List rgba) {
    var count = 0;
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 0) {
        count += 1;
      }
    }
    return count;
  }

  /// How far [a] and [b] part, in the most any channel of a pixel does.
  int parted(Uint8List a, Uint8List b) {
    var most = 0;
    for (var i = 0; i < a.length; i += 1) {
      final apart = (a[i] - b[i]).abs();
      if (apart > most) {
        most = apart;
      }
    }
    return most;
  }

  group('🚨names alone: rastered round them, the whole frame', () {
    for (final (name, painter, width, height) in [
      ('through the camera', over(), 640, 360),
      // A preview's size of the frame: the view scales the names.
      (
        'at a preview\'s scale',
        over(viewport: CanvasViewport(zoom: 0.75)),
        480,
        270,
      ),
      // An upper track's names, thinned with its picture.
      ('thinned', over(imageOpacity: 0.6), 640, 360),
      // Square to the frame the box is its plate's own, with no corner to
      // spare: a blur that spreads far past the plate is held by its reach.
      (
        'a wide blur, the camera square to the frame',
        over(
          camera: CameraPose(center: CanvasPoint(x: 700, y: 380), zoom: 1.2),
          tags: [
            tag(
              'あ',
              const ui.Offset(690, 370),
              effects: [
                ResolvedLayerEffect(
                  kind: EffectKind.blur,
                  values: const [90, 0],
                ),
              ],
            ),
          ],
        ),
        640,
        360,
      ),
    ]) {
      test(name, () async {
        final box = painter.inkOf(
          ui.Size(width.toDouble(), height.toDouble()),
        )!;
        expect(
          box.width * box.height,
          lessThan(width * height),
          reason: 'LIVENESS: less than the frame is rastered ($box)',
        );
        final whole = await laid(painter, width, height, round: false);
        expect(inked(whole), greaterThan(0), reason: 'LIVENESS: names');
        // Moved by whole pixels, a name resampled through a turned or zoomed
        // camera rounds a sample a hair apart: a channel parts by one at
        // most (🔬11-12: 1–2 pixels of the frame, 101–106 px inside the
        // box). A name cut short, a blur's reach left out or a part laid off
        // its place parts by far more.
        final round = await laid(painter, width, height, round: true);
        expect(round.length, whole.length);
        expect(parted(round, whole), lessThanOrEqualTo(1));
      });
    }
  });

  group('names that ink nowhere make a blank, rastering nothing', () {
    for (final (name, tags) in [
      ('none handed', const <ResolvedSeNameTag>[]),
      (
        'one thinned to nothing',
        [tag('A', const ui.Offset(640, 330), opacity: 0)],
      ),
    ]) {
      test(name, () async {
        final painter = over(tags: tags);
        expect(painter.inkOf(const ui.Size(640, 360)), ui.Rect.zero);
        final round = await laid(painter, 640, 360, round: true);
        expect(inked(round), 0);
        expect(round, await laid(painter, 640, 360, round: false));
      });
    }
  });

  group('🚨a painter handed more than names answers anywhere — the frame is '
      'rastered whole', () {
    for (final (name, painter) in [
      (
        'the stage\'s apron',
        over(tags: const [], pasteboardColor: const ui.Color(0xFF3355AA)),
      ),
      (
        'a veil over the names',
        over(veils: const [(color: 0xFF000000, opacity: 0.5)]),
      ),
      ('the paper under them', over(paintPaper: true)),
      ('the letterbox round them', over(paintLetterbox: true)),
    ]) {
      test(name, () async {
        expect(painter.inkOf(const ui.Size(640, 360)), isNull);
        final whole = await laid(painter, 640, 360, round: false);
        expect(inked(whole), greaterThan(0), reason: 'LIVENESS: drawn');
        expect(await laid(painter, 640, 360, round: true), whole);
      });
    }
  });
}
