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
import 'package:anicel/src/models/fx_plugin_description.dart';
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
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/export/still_image_encoders.dart';

import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/cels_parked_cold.dart';
import '../../helpers/no_guides_laid.dart';

/// 🗣️I-132-Q32 b (유저 2026-10-30): a plugin runs where the colour keys'
/// CPU road runs, 「네 길이 저절로 같다」 — so an export runs the plugin this
/// device has installed on a cel row's chain as the canvas does: a frame of
/// the film, its rows kept apart, a cel, and its row of the cel's file. And
/// the session binds it reading each row it names as the store holds that
/// row's cel.
void main() {
  const width = 32;
  const height = 16;
  const canvas = CanvasSize(width: width, height: height);
  const red = [255, 0, 0, 255];
  const cel = LayerId('cel');
  const drawing = FrameId('cel-f');

  /// A cel with one opaque red pixel, at (10, 5).
  BitmapSurface oneRed() => BitmapSurface(
    canvasSize: canvas,
    tileSize: width,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: width,
        pixels: Uint8List(width * width * 4)
          ..setAll((5 * width + 10) * 4, red),
      ),
    },
  );

  /// A cut of one row showing [oneRed], wearing [effects] — in a folder
  /// wearing [folder] where one is named, on a track whose V row wears
  /// [track] — on a device whose installed plugins are [plugins].
  EditorSessionManager sessionOn(
    InstalledFxPlugins plugins, {
    required List<LayerEffect> effects,
    List<LayerEffect>? folder,
    List<LayerEffect> track = const [],
  }) {
    const inFolder = LayerId('folder');
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
            effects: track,
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: 'Cut',
                duration: 1,
                canvasSize: canvas,
                layers: [
                  Layer(
                    id: cel,
                    name: 'cel',
                    frames: [Frame(id: drawing, duration: 1, strokes: [])],
                    timeline: const {
                      0: TimelineExposure.drawing(drawing, length: 1),
                    },
                    effects: effects,
                    folderId: folder == null ? null : inFolder,
                  ),
                  if (folder != null)
                    createFolderLayer(
                      id: inFolder,
                      name: 'folder',
                    ).copyWith(effects: folder),
                ],
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
    addTearDown(s.dispose);
    parkCold(s.renderCaches.brushFrameStore, {
      s.brushFrameKeyForCut(s.requireActiveCut, cel, drawing): oneRed(),
    });
    return s;
  }

  ExportCelGroupTask celOf(Cut cut) {
    final row = cut.layers.single;
    return ExportCelGroupTask(
      cut: cut,
      baseLayer: row,
      members: [row],
      memberFrames: [row.frames.single],
      baseFrame: row.frames.single,
      celName: '1',
      fileName: 'cel1.png',
    );
  }

  /// Each road out, drawing the session's cut.
  final roads =
      <String, Future<ui.Image> Function(EditorSessionManager s, Cut cut)>{
        'a frame of the film': (s, cut) => _rendererOf(s)
            .videoRun([
              ExportFrameTask(cut: cut, frameIndex: 0),
            ], ExportSizeMode.canvas)
            .frame(0),
        'its rows kept apart': (s, cut) => _rendererOf(s, apart: true)
            .frameRows(
              ExportFrameTask(cut: cut, frameIndex: 0),
              ExportSizeMode.canvas,
            )
            .whereType<ExportLayerRow>()
            .singleWhere((row) => row.name == 'cel')
            .draw(),
        'a cel': (s, cut) async => (await _rendererOf(s).renderCelGroup(
          celOf(cut),
          ExportSizeMode.canvas,
          guideColor: noGuidesLaid,
        ))!,
        'its row of the cel\'s file': (s, cut) => _rendererOf(s)
            .celGroupRows(
              celOf(cut),
              ExportSizeMode.canvas,
              guideColor: noGuidesLaid,
            )
            .single
            .draw(),
      };

  /// Where the red is, by column, on its row in what [draw] makes of the
  /// cut ([sessionOn]).
  Future<List<int>> redIn(
    Future<ui.Image> Function(EditorSessionManager s, Cut cut) draw,
    InstalledFxPlugins plugins, {
    required List<LayerEffect> effects,
    List<LayerEffect>? folder,
    List<LayerEffect> track = const [],
  }) async {
    final s = sessionOn(
      plugins,
      effects: effects,
      folder: folder,
      track: track,
    );
    final image = await draw(s, s.requireActiveCut);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final columns = image.width;
    image.dispose();
    final bytes = data!.buffer.asUint8List();
    bool isRed(int x) {
      final at = (5 * columns + x) * 4;
      return bytes[at] == 255 && bytes[at + 1] == 0 && bytes[at + 3] == 255;
    }

    return [
      for (var x = 0; x < columns; x += 1)
        if (isRed(x)) x,
    ];
  }

  final shift = shiftingFxPluginLayerEffect();
  final again = LayerEffect.defaults(
    id: const EffectId('again'),
    kind: EffectKind.plugin,
    plugin: shiftingFxPluginDescription,
  );

  for (final MapEntry(key: road, value: draw) in roads.entries) {
    testWidgets('🎯$road runs the plugin this device has installed', (
      tester,
    ) async {
      final plugins = await installedShiftingFxPlugin(tester);
      await tester.runAsync(() async {
        expect(
          await redIn(draw, plugins, effects: const []),
          [10],
          reason: '⛔CONTROL: with no plugin the red stands where it is drawn',
        );
        expect(
          await redIn(draw, plugins, effects: [shift]),
          [11],
          reason: 'the plugin moved it one to the right',
        );
        expect(
          await redIn(draw, plugins, effects: [shift, again]),
          [12],
          reason: '🗣️I-132-Q34 a 「어디에 걸어도 돌고」: and one past it, over '
              'what that made — the render waits for it',
        );
      });
    });
  }

  testWidgets('🗣️I-132-Q34 a: a film runs one on a folder\'s chain and on the '
      'V row\'s', (tester) async {
    final plugins = await installedShiftingFxPlugin(tester);
    final film = roads['a frame of the film']!;
    await tester.runAsync(() async {
      expect(
        await redIn(film, plugins, effects: const [], folder: const []),
        [10],
        reason: '⛔CONTROL: in a folder with nothing on it',
      );
      expect(
        await redIn(film, plugins, effects: const [], folder: [shift]),
        [11],
        reason: 'on the folder',
      );
      expect(
        await redIn(film, plugins, effects: const [], track: [shift]),
        [11],
        reason: 'on the V row',
      );
    });
  });

  testWidgets('the session binds the plugin reading each row it names as '
      'the store holds that row\'s cel', (tester) async {
    final reading = FxPluginDescription.fromJson({
      ...shiftingFxPluginDescription.toJson(),
      'params': [
        {'id': 'map', 'kind': 'layer', 'label': 'Map'},
      ],
    })!;
    final plugins = await installedShiftingFxPlugin(tester, as: reading);
    await tester.runAsync(() async {
      final s = sessionOn(
        plugins,
        effects: [
          LayerEffect.defaults(
            id: const EffectId('shift'),
            kind: EffectKind.plugin,
            plugin: reading,
          ).withLayer('map', cel),
        ],
      );
      final cut = s.requireActiveCut;
      final row = cut.layers.single;

      final run = s
          .fxPluginsIn(cut)(
            resolveLayerEffectsAt(effects: row.effects, frameIndex: 0),
            cut: cut,
            frameIndex: 0,
          )
          .single
          .run!;

      expect(run.rows.keys, [cel]);
      expect(run.rows[cel]?.tiles.keys, [TileCoord(x: 0, y: 0)]);
    });
  });
}

/// A renderer of [s] on no ground — [apart], one that keeps a frame's rows
/// apart — let go of when the test ends.
ExportFrameRenderer _rendererOf(
  EditorSessionManager s, {
  bool apart = false,
}) {
  final renderer = ExportFrameRenderer(
    session: s,
    background: const ui.Color(0x00000000),
    keepsRowsApart: apart,
  );
  addTearDown(renderer.dispose);
  return renderer;
}
