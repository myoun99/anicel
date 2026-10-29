import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/layer_image_draw.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/placement_reading.dart';
import '../../helpers/the_frame_as_it_stands.dart';

/// 🚨★★★WHICH ROUTES COPY A LAYER IMAGE AND WHICH RESAMPLE IT (유저
/// 2026-09-24 「통일해서」) — the routes that draw one, each asked.
///
/// A raster on canvas space's grid lays each image down one texel per pixel
/// — a copy, drawn at `none` like the active layer's tiles
/// (`a_texel_copy_is_drawn_unfiltered_test`): the camera render where its
/// projection moves canvas pixels onto output pixels whole (↩️and the
/// editing stack's display buffer, until it drew no row's image,
/// one-picture-per-frame ②-5b-1). A route that draws onto the screen, or
/// through a projection that moves the image off the pixel grid, has to
/// resample it with the filter its zoom chose: the editing stack's walk, and
/// the camera render where it turns, zooms or stands between pixels.
///
/// ↩️The camera resampled at every pose, the identity too: a sort of the
/// routes when the law was written (f047e8aa2), not a ruling on cameras. A
/// camera that moves pixels whole is a raster on canvas space's grid, and
/// laying its rows down as copies is what lets an export compose a row from
/// its ink alone (card export-folders-and-rows-at-their-extent, 2026-10-13).
///
/// ⚠️The copies are read off the draw counter because their pixels cannot
/// tell: in this runner a bilinear draw at 1:1 IS a copy (it is not on
/// Impeller Vulkan, Android's default). The walk's resample is pixels too:
/// copied off the grid the image would snap to whole pixels where the filter
/// blends them, and an identity pose — which only ever resamples — is the
/// reference that needs no second route.
void main() {
  group('the editing stack', () {
    const canvasSize = CanvasSize(width: 150, height: 101);
    const view = Size(176, 128);
    final screenKey = GlobalKey();
    const key = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('ink'),
      frameId: FrameId('ink-f'),
    );

    BrushFrameStore storeWithInk() {
      final store = BrushFrameStore();
      BrushFrameEditingCoordinator(
        initialFrameKey: key,
        frameStore: store,
        sessionStore: BrushFrameEditSessionStore(
          canvasSize: canvasSize,
          tileSize: 16,
        ),
        historyPolicy: const BrushHistoryPolicy(),
      ).commitSourceStroke(
        sourceDabs: [
          for (final (i, p) in const [
            (30.0, 30.0),
            (60.0, 44.0),
            (90.0, 60.0),
            (120.0, 72.0),
          ].indexed)
            BrushDab(
              center: CanvasPoint(x: p.$1, y: p.$2),
              color: 0xFF2040C0,
              size: 13,
              opacity: 1,
              flow: 1,
              hardness: 0.9,
              tipShape: BrushTipShape.round,
              pressure: 1,
              sequence: i,
            ),
        ],
      );
      return store;
    }

    /// The stack's screen for one row of the ink, [posed] with the identity
    /// pose or not, on the buffer or the walk.
    Future<Uint8List> screen(
      WidgetTester tester, {
      required CanvasViewport viewport,
      required bool walk,
      required bool posed,
    }) async {
      final images = LayerFrameImageCache(frameStore: storeWithInk());
      addTearDown(images.dispose);
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: screenKey,
                child: ClipRect(
                  child: SizedBox(
                    width: view.width,
                    height: view.height,
                    child: TheFrameAsItStands(
                      nodes: [
                        CompositeLeaf<CanvasStackRow>(
                          CanvasLayerImageRequest(
                            frameKey: key,
                            opacity: 1,
                            // The identity: centred on the canvas, no zoom,
                            // no turn — the pose that moves nothing.
                            placement: posed
                                ? placedBy(
                                    TransformPose(
                                      center: CanvasPoint(
                                        x: canvasSize.width / 2,
                                        y: canvasSize.height / 2,
                                      ),
                                    ),
                                    canvasSize,
                                  )
                                : null,
                          ),
                        ),
                      ],
                      imageCache: images,
                      canvasSize: canvasSize,
                      viewport: viewport,
                      paintPaper: true,
                      paperBackground: const ProjectBackground.color(
                        0xFFF4EEE0,
                      ),
                      debugDisableSingleBuffer: walk,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final render =
          screenKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final bytes = await tester.runAsync(() async {
        final image = await render.toImage();
        final data = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return data!.buffer.asUint8List();
      });
      return bytes!;
    }

    // Half zoom with a pan off the pixel grid.
    final halfOffGrid = CanvasViewport(zoom: 0.5, panX: 30.5, panY: 20.25);

    // ↩️Below 100% the buffer copied each level image, until a row was drawn
    // from its cel's tiles and no level image was made (one-picture-per-frame
    // ②-5b-1); and the walk copied nothing, by the counter, until no screen
    // drew a row's image.
    testWidgets('the walk resamples: off the grid the row draws as a pose '
        'that moves nothing draws it', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final plain = await screen(
        tester,
        viewport: halfOffGrid,
        walk: true,
        posed: false,
      );
      final posed = await screen(
        tester,
        viewport: halfOffGrid,
        walk: true,
        posed: true,
      );
      var differing = 0;
      for (var i = 0; i < plain.length; i += 1) {
        if (plain[i] != posed[i]) {
          differing += 1;
        }
      }
      expect(differing, 0);
    });
  });

  group('the camera', () {
    const canvasSize = CanvasSize(width: 8, height: 8);
    final pixels = Uint8List(8 * 8 * 4);
    const offset = (2 * 8 + 2) * 4;
    pixels[offset] = 255;
    pixels[offset + 3] = 255;
    final surface = BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
    );

    /// The texel copies one render of the row through [pose] draws.
    Future<int> copiesThrough(WidgetTester tester, CameraPose pose) async {
      debugTexelCopies = 0;
      await tester.runAsync(() async {
        const service = CameraFrameRenderService();
        final image = await service.renderThroughCamera(
          canvasSize: canvasSize,
          layers: [CutFrameCompositeLayer(surface: surface, opacity: 1)],
          pose: pose,
          cameraFrameSize: canvasSize,
        );
        image.dispose();
      });
      return debugTexelCopies;
    }

    CameraPose at(double x, double y, {double zoom = 1, double turn = 0}) =>
        CameraPose(
          center: CanvasPoint(x: x, y: y),
          zoom: zoom,
          rotationDegrees: turn,
        );

    for (final (says, pose) in [
      ('at the identity', at(4, 4)),
      ('moved by whole pixels', at(6, 3)),
    ]) {
      testWidgets('🎯copies the row $says — its projection moves canvas '
          'pixels onto output pixels whole', (tester) async {
        expect(await copiesThrough(tester, pose), greaterThan(0));
      });
    }

    for (final (says, pose) in [
      ('turned', at(4, 4, turn: 30)),
      ('zoomed', at(4, 4, zoom: 1.5)),
      ('between pixels', at(4.5, 4)),
    ]) {
      testWidgets('resamples the row $says', (tester) async {
        expect(await copiesThrough(tester, pose), 0);
      });
    }
  });
}
