@Tags(['impeller'])
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/canvas/iris_blur_shader.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/export/still_image_encoders.dart'
    show ExportLayerRow;

import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/cels_parked_cold.dart';

/// 🗣️I-132-Q16 a (유저 2026-10-28): a camera lens blur's blur map is a row of
/// its cut — and a layered file (a PSD) lays the row it blurs as the film
/// does, reading that row where it shows (🗣️I-132-Q21 a).
///
/// The map is black left of [seam] and white from it. With the focal
/// distance at black, the row it blurs comes out of the file sharp left of
/// the seam, the pixel itself, and at the blur's whole radius right of it.
void main() {
  setUpAll(IrisBlurShader.load);

  const width = 64;
  const height = 32;
  const canvas = CanvasSize(width: width, height: height);
  const seam = 32;

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
  Layer row(
    String id, {
    List<LayerEffect> effects = const [],
    String? folder,
  }) => Layer(
    id: LayerId(id),
    name: id,
    frames: [Frame(id: FrameId('$id-f'), duration: 1, strokes: [])],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-f'), length: 1)},
    effects: effects,
    folderId: folder == null ? null : LayerId(folder),
  );

  /// The checker's row of a PSD of a cut where it wears what [scene] names:
  /// nothing (`sharp`), a lens blur of radius 4 with no map (`uniform`), or
  /// one whose map is the depth row (`mapped`) — or, [inAFolder], the
  /// folder that holds it, darkening it all the way. The depth row shows
  /// [map] where it is given one and wears [mapEffects], on a device
  /// whose installed plugins are [plugins].
  Future<Uint8List> drawn(
    String scene, {
    bool inAFolder = false,
    BitmapSurface? map,
    List<LayerEffect> mapEffects = const [],
    InstalledFxPlugins? plugins,
  }) async {
    final lens = LayerEffect.defaults(
      id: const EffectId('lens'),
      kind: EffectKind.cameraLensBlur,
    ).withParameter('blurRadius', EffectParameter(value: 4));
    final s = EditorSessionManager(
      fxPlugins: plugins,
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
                  row(
                    'depth',
                    effects: mapEffects,
                    folder: inAFolder ? 'f' : null,
                  ),
                  if (inAFolder)
                    createFolderLayer(id: const LayerId('f'), name: 'f')
                        .copyWith(
                          effects: [
                            LayerEffect.defaults(
                              id: const EffectId('dark'),
                              kind: EffectKind.brightnessContrast,
                            ).withParameter(
                              'brightness',
                              EffectParameter(value: -100),
                            ),
                          ],
                        ),
                  row(
                    'checker',
                    effects: switch (scene) {
                      'sharp' => const [],
                      'uniform' => [lens],
                      _ => [
                        lens.withLayer(
                          'blurMapLayer',
                          LayerId(inAFolder ? 'f' : 'depth'),
                        ),
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
      for (final (id, surface) in [
        ('depth', map ?? depth),
        ('checker', checker),
      ])
        s.brushFrameKeyForCut(cut, LayerId(id), FrameId('$id-f')): surface,
    });
    final renderer = ExportFrameRenderer(session: s, keepsRowsApart: true);
    addTearDown(renderer.dispose);
    final layered = renderer
        .frameRows(
          ExportFrameTask(cut: cut, frameIndex: 0),
          ExportSizeMode.canvas,
        )
        .whereType<ExportLayerRow>()
        .singleWhere((row) => row.name == 'checker');
    final image = await layered.draw();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  for (final inAFolder in [false, true]) {
    final where = inAFolder
        ? ' — a folder\'s map without the folder\'s chain, which the file '
              'leaves out'
        : '';
    testWidgets('🎯the row it blurs is sharp where the map is black and '
        'blurred whole where it is white$where', (tester) async {
      await tester.runAsync(() async {
        final sharp = await drawn('sharp');
        final uniform = await drawn('uniform');
        final mapped = await drawn('mapped', inAFolder: inAFolder);
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

  testWidgets('🎯a map row whose chain runs a PLUGIN is read as the plugin '
      'makes it — its seam where the plugin moved it (🗣️I-132-Q32 b)', (
    tester,
  ) async {
    final plugins = await installedShiftingFxPlugin(tester, by: 8);
    await tester.runAsync(() async {
      // The depth row as the stand-in leaves it: moved right by 8, clear
      // where nothing moved in.
      final movedMap = surfaceOf(
        (x, _) => x < 8
            ? const [0, 0, 0, 0]
            : x < seam + 8
            ? const [0, 0, 0, 0xFF]
            : const [0xFF, 0xFF, 0xFF, 0xFF],
      );
      final unmoved = await drawn('mapped');
      final asMoved = await drawn('mapped', map: movedMap);
      final throughThePlugin = await drawn(
        'mapped',
        mapEffects: [shiftingFxPluginLayerEffect()],
        plugins: plugins,
      );

      var moves = 0;
      for (var at = 0; at < unmoved.length; at += 1) {
        if (unmoved[at] != asMoved[at]) {
          moves += 1;
        }
      }
      expect(moves, greaterThan(0), reason: '⛔premise: the seam shows');
      expect(throughThePlugin, asMoved);
    });
  });
}
