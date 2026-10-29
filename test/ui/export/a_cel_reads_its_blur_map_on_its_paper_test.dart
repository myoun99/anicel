@Tags(['impeller'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/canvas/iris_blur_shader.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

import '../../helpers/cels_parked_cold.dart';
import '../../helpers/no_guides_laid.dart';

/// 🗣️I-132-Q26 a (유저 2026-10-29): 「셀처럼 종이 그대로 읽는다」 — a cel goes
/// out on its paper, its transform never moving it, and its camera lens
/// blur reads its blur map's row the same way: where that row is drawn on
/// its paper, whatever its transform does on screen.
///
/// The map is black left of [seam] and white from it, its row moved
/// [shift] to the right by its transform. With the focal distance at
/// black, the cel comes out sharp left of the seam and blurred whole right
/// of it — the seam where the map is drawn, not where the screen shows it.
void main() {
  setUpAll(IrisBlurShader.load);

  const width = 64;
  const height = 32;
  const canvas = CanvasSize(width: width, height: height);
  const seam = 32;
  const shift = 8.0;

  BitmapSurface surfaceOf(List<int> Function(int x, int y) rgbaAt) {
    final pixels = Uint8List(width * width * 4);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        pixels.setAll((y * width + x) * 4, rgbaAt(x, y));
      }
    }
    return BitmapSurface(
      canvasSize: canvas,
      tileSize: width,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(size: width, pixels: pixels),
      },
    );
  }

  final checker = surfaceOf(
    (x, y) => (x ~/ 2 + y ~/ 2).isEven
        ? const [0xE0, 0x40, 0x20, 0xFF]
        : const [0x20, 0x40, 0xE0, 0xFF],
  );
  final depth = surfaceOf(
    (x, _) => x < seam ? const [0, 0, 0, 0xFF] : const [0xFF, 0xFF, 0xFF, 0xFF],
  );

  /// A row [id] showing its one drawing.
  Layer row(String id, {List<LayerEffect> effects = const []}) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 1)},
    effects: effects,
  );

  /// The checker's cel — its picture ([ExportFrameRenderer.renderCelGroup])
  /// or, [apart], its row of the cel's PSD — where it wears what [scene]
  /// names: nothing (`sharp`), a lens blur of radius 4 with no map
  /// (`uniform`), or one whose map is the moved depth row (`mapped`).
  Future<Uint8List> drawn(String scene, {required bool apart}) async {
    final lens = LayerEffect.defaults(
      id: const EffectId('lens'),
      kind: EffectKind.cameraLensBlur,
    ).withParameter('blurRadius', EffectParameter(value: 4));
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: canvas,
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: 'Cut',
                duration: 1,
                canvasSize: canvas,
                layers: [
                  row('depth').copyWith(
                    transformTrack: TransformTrack.empty().copyWith(
                      position: PropertyTrack<CanvasPoint>().withKey(
                        0,
                        CanvasPoint(x: width / 2 + shift, y: height / 2),
                      ),
                    ),
                  ),
                  row(
                    'checker',
                    effects: switch (scene) {
                      'sharp' => const [],
                      'uniform' => [lens],
                      _ => [
                        lens.withLayer('blurMapLayer', const LayerId('depth')),
                      ],
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
    addTearDown(s.dispose);
    final cut = s.requireActiveCut;
    parkCold(s.renderCaches.brushFrameStore, {
      for (final (id, surface) in [('depth', depth), ('checker', checker)])
        s.brushFrameKeyForCut(cut, LayerId(id), FrameId('$id-f')): surface,
    });
    final renderer = ExportFrameRenderer(
      session: s,
      background: const ui.Color(0x00000000),
    );
    addTearDown(renderer.dispose);
    final cel = cut.layers.last;
    final task = ExportCelGroupTask(
      cut: cut,
      baseLayer: cel,
      members: [cel],
      memberFrames: [cel.frames.single],
      baseFrame: cel.frames.single,
      celName: '1',
      fileName: 'checker1.png',
    );
    final image = apart
        ? await renderer
              .celGroupRows(
                task,
                ExportSizeMode.canvas,
                guideColor: noGuidesLaid,
              )
              .single
              .draw()
        : await renderer.renderCelGroup(
            task,
            ExportSizeMode.canvas,
            guideColor: noGuidesLaid,
          );
    final data = await image!.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  for (final apart in [false, true]) {
    testWidgets('🎯${apart ? 'its row of a PSD' : 'a cel'} is sharp where the '
        'map is drawn black and blurred whole where it is drawn white', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final sharp = await drawn('sharp', apart: apart);
        final uniform = await drawn('uniform', apart: apart);
        final mapped = await drawn('mapped', apart: apart);
        var unlikeLeft = 0;
        var unlikeRight = 0;
        final off = <String>[];
        for (var y = 0; y < height; y += 1) {
          for (var x = 0; x < width; x += 1) {
            final at = (y * width + x) * 4;
            final want = x < seam ? sharp : uniform;
            for (var c = 0; c < 4; c += 1) {
              if (sharp[at + c] != uniform[at + c]) {
                x < seam ? unlikeLeft++ : unlikeRight++;
              }
              if (mapped[at + c] != want[at + c] && off.length < 8) {
                off.add('($x, $y)[$c] ${mapped[at + c]} != ${want[at + c]}');
              }
            }
          }
        }
        expect(unlikeLeft, greaterThan(0), reason: '⛔premise: left, a blur');
        expect(unlikeRight, greaterThan(0), reason: '⛔premise: right, a blur');
        expect(off, isEmpty);
      });
    });
  }
}
