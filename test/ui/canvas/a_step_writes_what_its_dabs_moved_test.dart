// A STROKE'S STEP WRITES WHAT ITS DABS MOVED, NOT THEIR TILES (F-533) — AND THE
// PICTURE COMES OUT THE SAME.
//
// A tile is what a picture is made of; a step's patch was its tiles, so ink
// past a dab's rect could not be missed. Told by the dabs, a patch is as wide
// as they are, and the rest of the tile in the picture stays what it was: so
// these compare a stroke patched in step by step with the same stroke drawn
// as it stands, byte for byte, over a cel inked in every tile, the dabs over
// the tiles' edges. `widestPatch` says the patches were the dabs' at all: at
// a tile's width the comparison passes whatever is told.
//
// The writes are Flutter GPU's: the picture holds the steps only where
// the GPU wrote them, so this runs in the `gpu` tag's batch.
@Tags(['gpu'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/playback/frame_demand.dart' show FrameGhosts;
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
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/cel_surface_as_shown.dart';
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
  const canvasSize = CanvasSize(width: 48, height: 32);
  const viewSize = Size(48, 32);
  const tileSize = 16;
  const ground = [64, 192, 96];
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
    ghosts: FrameGhosts.none,
  );

  /// The ground keyed away — a sheet's paper.
  final keyed = [
    ResolvedLayerEffect(
      kind: EffectKind.colorKey,
      values: const [0, 0xFF40C060, 10, 100],
    ),
  ];

  /// Ink in every tile, some of it not fully opaque, some of it the ground.
  BitmapSurface theCel() => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tileSize,
    tiles: {
      for (var y = 0; y < 2; y += 1)
        for (var x = 0; x < 3; x += 1)
          TileCoord(x: x, y: y): BitmapTile(
            size: tileSize,
            pixels: Uint8List.fromList([
              for (var row = 0; row < tileSize; row += 1)
                for (var column = 0; column < tileSize; column += 1)
                  if (column % 4 == 0) ...[
                    ...ground,
                    255,
                  ] else ...[
                    (column * 13) % 256,
                    (row * 17) % 256,
                    120,
                    if ((row + column).isEven) 255 else 128,
                  ],
            ]),
          ),
    },
  );

  /// A line over the tiles' edges, in a colour the keys keep and in the one
  /// they key away.
  final dabs = [
    for (var i = 0; i < 12; i += 1)
      BrushDab(
        center: CanvasPoint(x: 3.3 + i * 3.7, y: 4.6 + i * 2.1),
        color: i % 3 == 0 ? 0xFF40C060 : 0xFF102030,
        size: 5,
        opacity: 0.6,
        flow: 1,
        hardness: 0.4,
        tipShape: BrushTipShape.round,
        pressure: 1,
        sequence: i,
      ),
  ];

  for (final (name, inPlace, effects, zoom) in [
    ('the stroke over its cel', false, const <ResolvedLayerEffect>[], 1.0),
    ('the result in place of its cel', true, const <ResolvedLayerEffect>[], 1.0),
    ('at a half', true, const <ResolvedLayerEffect>[], 0.5),
    ('at a quarter', true, const <ResolvedLayerEffect>[], 0.25),
    ('through its row\'s keys', true, keyed, 1.0),
  ]) {
    testWidgets('$name: patched in steps, the picture is the stroke as it '
        'stands', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final nodes = [
        CompositeLeaf<CanvasStackRow>(
          CanvasActiveLayerRow(opacity: 0.5, frameKey: key, effects: effects),
        ),
      ];
      final viewport = CanvasViewport(zoom: zoom);
      final cels = BrushFrameStore();
      keepInAFile(cels, {key: theCel()});
      final images = LayerFrameImageCache(frameStore: cels);
      addTearDown(images.dispose);
      final overlay = ActiveStrokeOverlayModel(tileSize: tileSize)
        ..sourceEffects = effects
        ..preBlendBase = inPlace ? theCel() : null;
      addTearDown(overlay.dispose);
      final rasterizer = BrushLiveStrokeRasterizer(
        pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
        tileSize: tileSize,
      );
      final live = BitmapSurfacePainter(
        surface: celSurfaceAsShown(theCel(), effects),
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
              viewport: viewport,
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

      final gpu = WritesLand();
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

      for (final dab in dabs) {
        gpu.holdsRenders = true;
        await tester.runAsync(() async {
          final from = overlay.dabs.length;
          overlay.dabs.add(dab);
          overlay.updateRegion(
            source: rasterizer,
            region: rasterizer.blendFrom(overlay.dabs, from: from)!,
          );
        });
        await tester.pump();
        final landing = patched.landingOf(keptByTheCanvas(tester, shown));
        expect(
          landing,
          isNotNull,
          reason: 'LIVENESS: the step is patched into the picture — not the '
              'frame drawn as it stands',
        );
        gpu.letAllThrough();
        await inThePicture(tester, landing);
      }
      expect(
        gpu.widestPatch,
        lessThan(tileSize),
        reason: '⛔premise: the patches were the dabs\', not their tiles',
      );
      final afterPatches = await shotOf(tester, screen);

      // A view of its own, the stroke in hand: the frame drawn as it stands.
      final standing = FramePictureStore<FramePictureKey>(
        gpu: WritesNeverLand(),
      );
      addTearDown(standing.dispose);
      await standOn(standing, view: const ValueKey(1));
      expect(differences(await shotOf(tester, screen), afterPatches), isEmpty);
    }, skip: noFlutterGpu != null);
  }
}
