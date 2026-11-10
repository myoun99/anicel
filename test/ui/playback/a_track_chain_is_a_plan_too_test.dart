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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';

import '../../helpers/cels_parked_cold.dart';

/// 🚨★★★A TRACK'S CHAIN IS A PLAN, LIKE EVERY OTHER ROW'S.
///
/// The V row's policy used to hand back a resolved `CompositeEffectPaint`.
/// A colour key has no paint form — it is a threshold, and a threshold has no
/// colour matrix — so `resolveCompositeEffectPaint` REFUSES one by assert. A
/// track chain with a key in it therefore threw, exactly as the live layer's
/// did until #1314.
///
/// ⛔"NO CALLER" IS NOT A DESIGN. It was unreachable only while the fx menu
/// added to the active layer alone and nothing called `addEffectToTrack`.
/// The round that let the menu reach the V row would have shipped an assert
/// (layer-menu-strings-outlive-their-entries-Q1).
///
/// 🧪ASKED OF THE PIXELS, not of the plan: a unit test that the plan has a
/// step passes on a route that ignores the step. This renders a green cut
/// on its paper under a track chain that keys green away — on a film's road, in the group
/// every route lays the cut in ([underTheCutsFx]) — and counts what survives.
///
/// ↩️It was asked of the playback painter, which filtered a film's finished
/// picture with the chain, until the film drew its cut through the camera
/// as the canvas does (card video-export-speed-Q2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canvasSize = CanvasSize(width: 16, height: 16);

  LayerEffect deleteGreen() => LayerEffect(
    id: const EffectId('fx-key'),
    kind: EffectKind.colorKey,
    colors: {
      'keyColor': PropertyTrack<int>.empty().withKey(0, 0xFF00FF00),
    },
    parameters: {
      'tolerance': EffectParameter(value: 0),
      'amount': EffectParameter(value: 100),
    },
  );

  /// A cut of one row: green, edge to edge.
  BitmapSurface greenCut() {
    const side = defaultCelTileSize;
    final pixels = Uint8List(side * side * 4);
    for (var y = 0; y < 16; y += 1) {
      for (var x = 0; x < 16; x += 1) {
        pixels.setAll((y * side + x) * 4, const [0, 255, 0, 255]);
      }
    }
    return BitmapSurface(canvasSize: canvasSize, tileSize: side).putTiles([
      (
        coord: TileCoord(x: 0, y: 0),
        tile: BitmapTile(size: side, pixels: pixels),
      ),
    ]);
  }

  Future<int> inkedPixels(
    WidgetTester tester,
    List<LayerEffect> trackChain,
  ) async {
    const cutId = CutId('cut');
    const layerId = LayerId('a');
    final drawing = Frame(
      id: const FrameId('f1'),
      duration: 1,
      strokes: const [],
    );
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        cameraSize: canvasSize,
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'V',
            effects: trackChain,
            cuts: [
              Cut(
                id: cutId,
                name: 'CUT',
                duration: 1,
                canvasSize: canvasSize,
                layers: [
                  Layer(
                    id: layerId,
                    name: 'A',
                    frames: [drawing],
                    timeline: {
                      0: TimelineExposure.drawing(drawing.id, length: 1),
                    },
                  ),
                  createCameraLayer(cutId: cutId),
                ],
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
    addTearDown(session.dispose);
    final cut = session.requireActiveCut;
    parkCold(session.renderCaches.brushFrameStore, {
      session.brushFrameKeyForCut(cut, layerId, drawing.id): greenCut(),
    });
    final renderer = ExportFrameRenderer(session: session);
    addTearDown(renderer.dispose);
    final bytes = (await tester.runAsync(() async {
      final image = await renderer.renderVideoFrame(
        ExportFrameTask(cut: cut, frameIndex: 0),
        ExportSizeMode.camera,
        preserveAlpha: true,
      );
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    var n = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i + 1] > bytes[i]) {
        n += 1;
      }
    }
    return n;
  }

  testWidgets('a colour key on a TRACK erases what it names', (tester) async {
    final plain = await inkedPixels(tester, const []);
    expect(plain, 256, reason: 'fixture: the cut drew');

    final keyed = await inkedPixels(tester, [deleteGreen()]);
    expect(
      keyed,
      0,
      reason: 'the V row keyed the picture it composited — before this the '
          'same chain threw on the way to a paint',
    );
  });

  testWidgets('a track chain WITHOUT a key still draws', (tester) async {
    // ⛔The control: only a key removes pixels.
    final darkened = await inkedPixels(tester, [
      LayerEffect(
        id: const EffectId('fx-dark'),
        kind: EffectKind.brightnessContrast,
        parameters: {
          'brightness': EffectParameter(value: -0.5),
          'contrast': EffectParameter(value: 0),
        },
      ),
    ]);
    expect(
      darkened,
      greaterThan(0),
      reason: 'a darken keeps every pixel — only a key removes any',
    );
  });
}
