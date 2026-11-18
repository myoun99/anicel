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
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/panel_pictures.dart';

import '../helpers/a_canvas_standing_on_a_frame.dart';
import '../helpers/cels_parked_cold.dart';

/// 🚨★★★A PANEL LOOKS AT ITS CELS AND LETS GO (card
/// `render-reads-thaw-into-hot`; `gpu-canonical-store-Q10`, 유저
/// 2026-11-10 「추천대로 법 지키도록」): a storyboard block's or a conte
/// cell's picture reads cels nobody is drawing on and leaves the store as it
/// stood. ↩️Read as the app's own use, filling a 13-cut film's storyboard
/// took the hot tier from 149 to 529MB (measured 09-28); cut from the
/// frame's one picture (F-533-Q8, 11-05), the panels read their cels as
/// playback does, thawed hot, until that answer.
void main() {
  opensTheEnginesScreens();
  const canvas = CanvasSize(
    width: defaultCelTileSize,
    height: defaultCelTileSize,
  );
  const cutCount = 13;
  const layerId = LayerId('a');

  EditorSessionManager thirteenCuts() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('film'),
      name: 'Film',
      cameraSize: canvas,
      createdAt: DateTime.utc(2026, 11, 10),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Video',
          cuts: [
            for (var index = 0; index < cutCount; index += 1)
              Cut(
                id: CutId('c$index'),
                name: '${index + 1}',
                duration: 1,
                canvasSize: canvas,
                layers: [
                  Layer(
                    id: layerId,
                    name: 'A',
                    kind: LayerKind.animation,
                    frames: [
                      Frame(
                        id: FrameId('f$index'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: {
                      0: TimelineExposure.drawing(FrameId('f$index'), length: 1),
                    },
                  ),
                ],
              ),
          ],
        ),
      ],
    ),
  );

  /// Cut [index]'s drawing: the whole cel one red, its own.
  int redOf(int index) => index * 16 + 15;

  BitmapSurface ink(int index) {
    final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = redOf(index);
      pixels[i + 3] = 255;
    }
    return BitmapSurface(
      canvasSize: canvas,
      tileSize: defaultCelTileSize,
      tiles: {
        TileCoord(x: 0, y: 0): BitmapTile(
          size: defaultCelTileSize,
          pixels: pixels,
        ),
      },
    );
  }

  testWidgets('🎯the panels of a 13-cut film read every cut\'s drawing as a '
      'look — the store keeps each one cold, and nothing goes hot', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = thirteenCuts();
      addTearDown(session.dispose);
      final store = session.renderCaches.brushFrameStore;
      final cuts = session.repository.requireProject().tracks.single.cuts;
      final keys = [
        for (final (index, cut) in cuts.indexed)
          session.brushFrameKeyForCut(cut, layerId, FrameId('f$index')),
      ];
      parkCold(store, {
        for (final (index, key) in keys.indexed) key: ink(index),
      });

      const width = 32;
      for (final (index, cut) in cuts.indexed) {
        final image = await PanelPictures(
          session: session,
        ).render(cut, 0, width: width);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        image.dispose();
        expect(
          bytes.getUint8((width ~/ 2 * width + width ~/ 2) * 4),
          redOf(index),
          reason: 'LIVENESS: cut ${index + 1}\'s drawing',
        );
      }

      expect(store.hotBakedBytes, 0, reason: 'the reads were looks');
      for (final key in keys) {
        expect(store.isCelCold(key), isTrue);
      }
    });
  });
}
