import 'dart:typed_data';

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

/// 🚨A SHOT HOLDS THE PICTURE IT SHOWS, AND LETS GO OF IT (`frameShot`; the
/// store's law 「HELD BY WHOEVER SHOWS IT」, 관제 11-10 08:48): the frame's
/// one picture is handed to a shot held (`FramePictures.pictureOf`) — the
/// store may let it go while the shot waits for the engine — and the shot
/// releases it when it is done, so a picture the store let go is freed.
void main() {
  opensTheEnginesScreens();
  const canvas = CanvasSize(
    width: defaultCelTileSize,
    height: defaultCelTileSize,
  );
  const layerId = LayerId('a');
  const frameId = FrameId('f');

  EditorSessionManager oneCut() => EditorSessionManager(
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
            Cut(
              id: const CutId('c'),
              name: '1',
              duration: 1,
              canvasSize: canvas,
              layers: [
                Layer(
                  id: layerId,
                  name: 'A',
                  kind: LayerKind.animation,
                  frames: [
                    Frame(id: frameId, duration: 1, strokes: const []),
                  ],
                  timeline: {
                    0: const TimelineExposure.drawing(frameId, length: 1),
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  BitmapSurface ink() {
    final pixels = Uint8List(defaultCelTileSize * defaultCelTileSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = 255;
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

  testWidgets('🚨once the store lets go of the picture a panel was shot '
      'from, nothing of it is kept: the shot released its hold', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final session = oneCut();
      addTearDown(session.dispose);
      final cut = session.repository.requireProject().tracks.single.cuts.single;
      parkCold(session.renderCaches.brushFrameStore, {
        session.brushFrameKeyForCut(cut, layerId, frameId): ink(),
      });
      final pictures = session.playbackRig.framePictures;
      final frame = panelFrame(cut, 0);
      expect(
        await pictures.make(frame, shouldAbort: () => false),
        isTrue,
        reason: 'LIVENESS: the frame\'s picture, made ahead',
      );
      final picture = pictures.store.peek(pictures.keyOf(frame))!;

      (await PanelPictures(session: session).render(cut, 0, width: 32))
          .dispose();
      pictures.store.enforceBudget(maxBytes: 0, wantedAt: (_) => null);

      expect(picture.gone, isTrue, reason: 'LIVENESS: the store let it go');
      expect(picture.bytes, 0, reason: 'freed: no shot holds it');
    });
  });
}
