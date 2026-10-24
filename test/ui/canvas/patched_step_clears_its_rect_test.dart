// A PATCHED STEP CLEARS ITS DIRTY RECT BEFORE IT REPAINTS — TRANSLUCENT INK
// MUST NOT BLEND WITH ITS OWN PREVIOUS FRAME.
//
// A survivor of the mutation campaign (2026-09-04, the display-buffer
// cut): the `BlendMode.clear` before the dirty-rect repaint was dropped
// and every buffer test stayed green — their paper was opaque, so the
// composite drawn over the old pixels hid the double blend. This pin drives
// a LIVE stroke through the overlay model (the path the patch exists for),
// at half opacity on no paper, and compares the patched picture with the
// same stroke drawn as it stands, byte for byte. ↩️The patches went into
// the canvas's display buffer, until a canvas that stands patched its
// strokes into the frame's one picture (one-picture-per-frame ②-5a).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_store.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/cels_kept_in_a_file.dart';
import '../../helpers/settle_async.dart';

void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const viewSize = Size(8, 8);
  final screen = GlobalKey();

  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  final picture = (
    cut: Cut(
      id: key.cutId,
      name: 'c',
      duration: 1,
      canvasSize: canvasSize,
      layers: const [],
    ),
    frameIndex: 0,
    paintPaper: false,
  );
  final nodes = [
    const CompositeLeaf<CanvasStackRow>(
      CanvasActiveLayerRow(opacity: 0.5, frameKey: key),
    ),
  ];

  /// The cel before the stroke: one inked pixel in a corner the dabs do
  /// not reach — a cel with nothing on it is no part of its frame's
  /// picture, and there would be no picture to patch.
  BitmapSurface theCel() {
    final pixels = Uint8List(8 * 8 * 4);
    pixels.setRange((7 * 8 + 7) * 4, (7 * 8 + 7) * 4 + 4, [0, 0, 255, 255]);
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 8,
      tiles: {TileCoord(x: 0, y: 0): BitmapTile(size: 8, pixels: pixels)},
    );
  }

  BrushDab dabAt(double x, {int sequence = 0}) => BrushDab(
    center: CanvasPoint(x: x, y: 4),
    color: 0xFF000000,
    size: 3,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );

  testWidgets('two dabs in one tile: the patched picture equals the same '
      'stroke drawn as it stands', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final cels = BrushFrameStore();
    keepInAFile(cels, {key: theCel()});
    final images = LayerFrameImageCache(frameStore: cels);
    addTearDown(images.dispose);
    final overlay = ActiveStrokeOverlayModel(tileSize: 8);
    addTearDown(overlay.dispose);
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
    );
    final live = BitmapSurfacePainter(
      surface: theCel(),
      overlayModel: overlay,
      showTransparentBackground: false,
    );

    /// A canvas standing on the frame, its pictures kept by [store].
    Future<void> standOn(
      FramePictureStore<FramePictureKey> store, {
      required Key view,
    }) async {
      final run = runOver(
        images,
        store,
        canvasSize: canvasSize,
        stackOf: (_) => nodes,
      );
      await tester.pumpWidget(
        onAScreen(
          screen,
          size: viewSize,
          under: const Color(0xFFFFFFFF),
          view: standingOn(
            run,
            key: view,
            picture: picture,
            nodes: nodes,
            viewport: CanvasViewport(),
            live: (
              activeSurfacePainter: live,
              floatOverlay: null,
              liftedRows: const {},
            ),
          ),
        ),
      );
      final shown = run.pictures.keyOfStack(nodes, picture);
      expect(
        await settleAsync(tester, () => store.bytesOf(shown) != null),
        isTrue,
        reason: 'LIVENESS: the frame\'s picture is made',
      );
      await lendBothClocks(tester, rounds: 2);
    }

    final gpu = WritesNeverLand();
    addTearDown(gpu.letAllThrough);
    final patched = FramePictureStore<FramePictureKey>(gpu: gpu);
    addTearDown(patched.dispose);
    await standOn(patched, view: const ValueKey(0));
    final shown = runOver(
      images,
      patched,
      canvasSize: canvasSize,
      stackOf: (_) => nodes,
    ).pictures.keyOfStack(nodes, picture);

    /// [dabs] stroked so far, the newest over [region]: the step lands in
    /// the picture before the next, held on its way until it is seen there.
    Future<void> step(List<BrushDab> dabs, DirtyRegion region) async {
      gpu.holdsRenders = true;
      await tester.runAsync(() async {
        rasterizer.blendFrom(dabs, from: dabs.length - 1);
        overlay.updateRegion(source: rasterizer, region: region);
      });
      await tester.pump();
      final landing = patched.landingOf(shown);
      expect(
        landing,
        isNotNull,
        reason: 'LIVENESS: the step is patched into the picture — not the '
            'frame drawn as it stands',
      );
      gpu.letAllThrough();
      await tester.runAsync(() => landing!);
      await tester.pump();
    }

    await step(
      [dabAt(2)],
      DirtyRegion.fromXYWH(x: 0, y: 2, width: 5, height: 5),
    );
    await step(
      [dabAt(2), dabAt(5, sequence: 1)],
      DirtyRegion.fromXYWH(x: 3, y: 2, width: 5, height: 5),
    );
    expect(
      patched.peek(shown)!.landing,
      isNotEmpty,
      reason: 'LIVENESS: the steps\' own texels are drawn over the picture',
    );
    final afterPatch = await shotOf(tester, screen);

    // A view of its own, the stroke in hand: the frame drawn as it stands.
    final standing = FramePictureStore<FramePictureKey>(
      gpu: WritesNeverLand(),
    );
    addTearDown(standing.dispose);
    await standOn(standing, view: const ValueKey(1));
    final fresh = await shotOf(tester, screen);
    expect(
      differences(fresh, afterPatch),
      isEmpty,
      reason:
          'the dirty rect is cleared before its repaint — the first dab, '
          'drawn again over its own previous frame, would read darker',
    );
  });
}
