import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/track_effect_paint_policy.dart';

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
/// step passes on a route that ignores the step. This renders a white cut
/// under a track chain that keys white away — in the group every route lays
/// the cut in ([underTheCutsFx]) — and counts what survives.
///
/// ↩️It was asked of the playback painter, which filtered a film's finished
/// picture with the chain, until the film drew its cut through the camera
/// as the canvas does (card video-export-speed-Q2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ColourKeyShader.load);

  const canvasSize = CanvasSize(width: 16, height: 16);

  LayerEffect deleteWhite() => LayerEffect(
    id: const EffectId('fx-key'),
    kind: EffectKind.colorKey,
    colors: {
      'keyColor': PropertyTrack<int>.empty().withKey(0, 0xFFFFFFFF),
    },
    parameters: {
      'tolerance': EffectParameter(value: 0),
      'amount': EffectParameter(value: 100),
    },
  );

  /// A cut of one row: white, edge to edge.
  BitmapSurface whiteCut() => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: 16,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: 16,
        pixels: Uint8List(16 * 16 * 4)..fillRange(0, 16 * 16 * 4, 255),
      ),
    },
  );

  Future<int> opaquePixels(
    WidgetTester tester,
    List<LayerEffect> trackChain,
  ) async {
    final bytes = (await tester.runAsync(() async {
      final image =
          await const CameraFrameRenderService(
            background: ui.Color(0x00000000),
          ).renderThroughCamera(
            canvasSize: canvasSize,
            nodes: underTheCutsFx([
              CompositeLeaf(
                CutFrameCompositeLayer(surface: whiteCut(), opacity: 1),
              ),
            ], trackEffectsAt(trackChain, 0)),
            pose: CameraPose(center: CanvasPoint(x: 8, y: 8)),
            cameraFrameSize: canvasSize,
          );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    var n = 0;
    for (var i = 3; i < bytes.length; i += 4) {
      if (bytes[i] != 0) {
        n += 1;
      }
    }
    return n;
  }

  testWidgets('a colour key on a TRACK erases what it names', (tester) async {
    final plain = await opaquePixels(tester, const []);
    expect(plain, greaterThan(0), reason: 'fixture: the cut drew');

    final keyed = await opaquePixels(tester, [deleteWhite()]);
    expect(
      keyed,
      0,
      reason: 'the V row keyed the picture it composited — before this the '
          'same chain threw on the way to a paint',
    );
  });

  testWidgets('a track chain WITHOUT a key still draws', (tester) async {
    // ⛔The control: only a key removes pixels.
    final darkened = await opaquePixels(tester, [
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
