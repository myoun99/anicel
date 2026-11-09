import '../helpers/a_canvas_standing_on_a_frame.dart';
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
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/panel_pictures.dart';

import '../helpers/a_plugin_that_shifts.dart';
import '../helpers/poll_until.dart';

/// 🗣️F-533-Q8 (유저 2026-11-05): 「프레임 그림에서 잘라 쓴다」 · 「재료가 둘?
/// … 최대한 하나로 통합하고싶음」 · 「콘티용지패널의 그림도 그렇고 최대한
/// 하나만 쓰는방향으로 하자. 효율적으로」 — a panel's picture is cut from the
/// frame's one picture, the one the canvas and a run show: a frame the
/// warmer has made is no work for a panel.
void main() {
  opensTheEnginesScreens();
  const canvas = CanvasSize(width: 64, height: 64);

  /// A cut of one row whose cel is black on its left half, wearing
  /// [effects], on a device whose installed plugins are [plugins].
  EditorSessionManager halfInked({
    InstalledFxPlugins? plugins,
    List<LayerEffect> effects = const [],
  }) {
    final session = EditorSessionManager(
      fxPlugins: plugins,
      initialProject: Project(
        id: const ProjectId('panels'),
        name: 'Panels',
        cameraSize: const CanvasSize(width: 32, height: 32),
        createdAt: DateTime.utc(2026, 11, 5),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [
              Cut(
                id: const CutId('c'),
                name: '1',
                duration: 2,
                canvasSize: canvas,
                layers: [
                  Layer(
                    id: const LayerId('a'),
                    name: 'A',
                    kind: LayerKind.animation,
                    effects: effects,
                    frames: [
                      Frame(
                        id: const FrameId('f'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: const {
                      0: TimelineExposure.drawing(FrameId('f'), length: 2),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
    for (var y = 0; y < 64; y += 1) {
      for (var x = 0; x < 32; x += 1) {
        pixels[(y * defaultCelTileSize + x) * 4 + 3] = 255;
      }
    }
    session.renderCaches.brushFrameStore.storeBakedSurface(
      session.brushFrameKeyForCut(
        session.requireActiveCut,
        const LayerId('a'),
        const FrameId('f'),
      ),
      BitmapSurface(canvasSize: canvas).putTiles([
        (
          coord: TileCoord(x: 0, y: 0),
          tile: BitmapTile(size: defaultCelTileSize, pixels: pixels),
        ),
      ]),
    );
    return session;
  }

  testWidgets('🚨a panel of a frame the warmer has made is cut from that '
      'picture: none is made for it, at any width, and it stays', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = halfInked();
      addTearDown(session.dispose);
      final cut = session.requireActiveCut;
      final pictures = session.playbackRig.framePictures;
      final scheduler = session.playbackRig.prerenderScheduler;
      session.warmActiveCut();
      expect(
        await pollUntil(
          () => scheduler.progress.value.isComplete && scheduler.isResting,
        ),
        isTrue,
        reason: 'the warmer rests',
      );
      final held = pictures.store.estimatedBytes;
      expect(held, greaterThan(0), reason: 'LIVENESS: the warmer\'s pictures');

      for (final width in [16, 32]) {
        final image = await PanelPictures(
          session: session,
        ).render(cut, 1, width: width);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        image.dispose();
        // The camera's frame stands centred, over the ink's edge.
        expect(bytes.getUint8((width ~/ 2 * width + 1) * 4), 0, reason: 'ink');
        expect(
          bytes.getUint8((width ~/ 2 * width + width - 2) * 4),
          255,
          reason: 'paper',
        );
        expect(
          pictures.store.estimatedBytes,
          held,
          reason: 'none made, none let go',
        );
      }
    });
  });

  /// [cut]'s panel at frame 0 drawn, and whether it was: its left half ink.
  Future<bool> drawn(EditorSessionManager session, Cut cut) async {
    final image = await PanelPictures(
      session: session,
    ).render(cut, 0, width: 16);
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    image.dispose();
    return bytes.getUint8((8 * 16 + 1) * 4) == 0;
  }

  testWidgets('🚨a picture made for a panel alone is let go of once the '
      'panel is drawn: no step of the run wants it', (tester) async {
    await tester.runAsync(() async {
      final session = halfInked();
      addTearDown(session.dispose);
      expect(await drawn(session, session.requireActiveCut), isTrue);
      expect(session.playbackRig.framePictures.store.estimatedBytes, 0);
    });
  });

  testWidgets('🚨a frame a canvas holds as its own is drawn as its cels '
      'stand, its plug-ins run', (tester) async {
    final plugins = await installedShiftingFxPlugin(tester, by: 8);
    await tester.runAsync(() async {
      final session = halfInked(
        plugins: plugins,
        effects: [shiftingFxPluginLayerEffect()],
      );
      addTearDown(session.dispose);
      final cut = session.requireActiveCut;
      final pictures = session.playbackRig.framePictures;
      final frame = panelFrame(cut, 0);
      expect(await pictures.make(frame, shouldAbort: () => false), isTrue);
      final key = pictures.keyOf(frame);
      expect(
        pictures.store.move(from: key, to: key.standingOn(Object())),
        isTrue,
        reason: 'LIVENESS: lent to a canvas, no picture to cut from',
      );

      final image = await PanelPictures(
        session: session,
      ).render(cut, 0, width: 16);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      image.dispose();
      // The ink ended at the panel's middle, 8; the plug-in took it 8 of
      // the canvas's pixels on, 4 of the panel's.
      expect(bytes.getUint8((8 * 16 + 10) * 4), 0);
      expect(bytes.getUint8((8 * 16 + 13) * 4), 255);
    });
  });

  testWidgets('a picture a screen holds stays, once a panel is cut from it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = halfInked();
      addTearDown(session.dispose);
      final cut = session.requireActiveCut;
      final pictures = session.playbackRig.framePictures;
      final frame = panelFrame(cut, 0);
      expect(await pictures.make(frame, shouldAbort: () => false), isTrue);
      pictures.store.retainPin(pictures.keyOf(frame));
      final held = pictures.store.estimatedBytes;
      expect(held, greaterThan(0), reason: 'LIVENESS: the frame\'s picture');
      expect(await drawn(session, cut), isTrue);
      expect(pictures.store.estimatedBytes, held);
    });
  });
}
