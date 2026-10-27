import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨★A NODE THAT DREW THE SAME PICTURE DOES NOT DRAW IT AGAIN
/// ([HeldSubtreeRasters]; card paint-walk-redoes-the-same-work-each-step):
/// a folder drawn whole as its frame is laid is cut from, not drawn again,
/// as a stroke's steps are patched into that frame — and only where what
/// it draws is what was held.
///
/// Whether a node was drawn again is invisible in the pixels, so each test
/// counts the rasters ([debugSubtreeRasterCount]) and reads the pixels the
/// patch lays beside a patch drawn with nothing held.
void main() {
  BrushFrameKey cel(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  const page = (
    canvasSize: CanvasSize(width: 24, height: 16),
    pasteboardReach: PasteboardReach.whole,
    paintPaper: false,
    paperBackground: ProjectBackground.defaultBackground,
  );

  /// A cel whose every pixel is its own colour ([rgbaAt]) — a patch cut
  /// from the wrong place reads another.
  BitmapSurface surface(List<int> Function(int x, int y) rgbaAt) =>
      BitmapSurface(
        canvasSize: page.canvasSize,
        tileSize: 8,
        tiles: {
          for (var tx = 0; tx < 3; tx += 1)
            for (var ty = 0; ty < 2; ty += 1)
              TileCoord(x: tx, y: ty): BitmapTile(
                size: 8,
                pixels: Uint8List.fromList([
                  for (var y = 0; y < 8; y += 1)
                    for (var x = 0; x < 8; x += 1)
                      ...rgbaAt(tx * 8 + x, ty * 8 + y),
                ]),
              ),
        },
      );

  final ramp = surface((x, y) => [x * 10, y * 15, 0x80, 0xFF]);
  final other = surface((x, y) => [0x20, 0xFF - x * 9, y * 12, 0xFF]);
  final below = surface(
    (x, y) => [0xFF, 0xFF, 0xFF, if (x < 12) 0xFF else 0],
  );

  /// A row under a folder at half strength — one picture of its own — over
  /// two rows, and [inFolder] beside them.
  List<CompositeNode<CanvasStackRow>> stack({
    double folderOpacity = 0.5,
    List<CompositeNode<CanvasStackRow>> inFolder = const [],
  }) => [
    CompositeLeaf(
      CanvasLayerImageRequest(frameKey: cel('below'), opacity: 1.0),
    ),
    CompositeGroup(
      children: [
        CompositeLeaf(
          CanvasLayerImageRequest(frameKey: cel('ramp'), opacity: 1.0),
        ),
        CompositeLeaf(
          CanvasLayerImageRequest(
            frameKey: cel('other'),
            opacity: 0.7,
          ),
        ),
        ...inFolder,
      ],
      opacity: folderOpacity,
      blendMode: LayerBlendMode.normal,
      effects: const [],
    ),
  ];

  late Map<String, BitmapSurface> stored;
  late Map<String, int> revisions;
  late HeldSubtreeRasters held;
  setUp(() {
    stored = {'below': below, 'ramp': ramp, 'other': other};
    revisions = {};
    held = HeldSubtreeRasters(bytes: () => 1 << 20);
    debugSubtreeRasterCount = 0;
  });
  tearDown(() => held.clear());

  StackedFrame frame(
    List<CompositeNode<CanvasStackRow>> nodes, {
    bool? keeps,
    ({LiveRows rows, LiftedRowPainters painters})? live,
  }) => stackedFrameOf(
    nodes,
    page: page,
    surfaceOf: (cel) => stored[cel.layerId.value],
    live: live,
    held: switch (keeps) {
      final keeps? => (
        pictures: (rasters: held, keeps: keeps),
        revisionOf: (cel) => revisions[cel.layerId.value] ?? 1,
      ),
      null => null,
    },
  );

  /// [frame]'s pixels over [rect], recorded as the frame's picture records
  /// a patch: on nothing, cut to [rect] (`FramePictureStore.patch`).
  Future<Uint8List> drawn(StackedFrame frame, Rect rect) async {
    final recorder = ui.PictureRecorder();
    frame.drawing.draw(
      ui.Canvas(recorder)
        ..translate(-rect.left, -rect.top)
        ..clipRect(rect),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      rect.width.ceil(),
      rect.height.ceil(),
    );
    picture.dispose();
    final bytes = await image.toByteData();
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// The frame laid whole, its nodes kept.
  Future<void> lay(List<CompositeNode<CanvasStackRow>> nodes) async {
    final laid = frame(nodes, keeps: true);
    await drawn(laid, laid.drawing.extent);
  }

  // A step's patch: across the tiles' edges, and not on the page's grid
  // of anything else.
  const step = Rect.fromLTWH(5, 3, 9, 7);

  test('a folder drawn whole as its frame is laid is not drawn again for a '
      'step — and the step is the pixels it would have drawn', () async {
    await lay(stack());
    expect(held.length, 1, reason: '⛔premise: the folder was kept');

    debugSubtreeRasterCount = 0;
    final patched = await drawn(frame(stack(), keeps: false), step);
    expect(debugSubtreeRasterCount, 0, reason: 'the folder was cut from');

    final fresh = await drawn(frame(stack()), step);
    expect(
      debugSubtreeRasterCount,
      1,
      reason: '⛔premise: with nothing held the folder is drawn',
    );
    expect(patched, fresh);
  });

  test('a folder whose row was drawn on since is drawn again — and so is '
      'one whose own strength changed', () async {
    await lay(stack());
    expect(held.length, 1, reason: '⛔premise');

    stored['ramp'] = other;
    revisions['ramp'] = 2;
    debugSubtreeRasterCount = 0;
    final drawnOn = await drawn(frame(stack(), keeps: false), step);
    expect(debugSubtreeRasterCount, 1);
    expect(drawnOn, await drawn(frame(stack()), step));

    debugSubtreeRasterCount = 0;
    final fainter = await drawn(
      frame(stack(folderOpacity: 0.3), keeps: false),
      step,
    );
    expect(debugSubtreeRasterCount, 1);
    expect(fainter, await drawn(frame(stack(folderOpacity: 0.3)), step));
  });

  test('🚨a folder holding the row a pen draws is drawn again each step — '
      'the first stroke on an empty cel there included', () async {
    final withThePen = stack(
      inFolder: [
        CompositeLeaf(CanvasActiveLayerRow(opacity: 1, frameKey: cel('pen'))),
      ],
    );
    // Laid with nothing stored on the pen's cel: the folder is kept as the
    // two rows beside it, which is all it drew then.
    await lay(withThePen);
    expect(held.length, 1, reason: '⛔premise');

    final pen = surface(
      (x, y) => [0, 0, 0, if (x > 6 && y > 4) 0xFF else 0],
    );
    final live = (
      rows: (
        activeSurfacePainter: BitmapSurfacePainter(
          surface: pen,
          showTransparentBackground: false,
        ),
        floatOverlay: null,
        liftedRows: const <BrushFrameKey, LiftedCel>{},
      ),
      painters: LiftedRowPainters(),
    );
    debugSubtreeRasterCount = 0;
    final stepped = await drawn(
      frame(withThePen, keeps: false, live: live),
      step,
    );
    expect(debugSubtreeRasterCount, 1);
    expect(stepped, await drawn(frame(withThePen, live: live), step));
  });

  test('a folder drawn in part is not kept', () async {
    await drawn(frame(stack(), keeps: true), step);
    expect(held, hasLength(0));
  });

  test('a folder drawn whole where nothing keeps is not kept', () async {
    final laid = frame(stack(), keeps: false);
    await drawn(laid, laid.drawing.extent);
    expect(held, hasLength(0));
  });

  group('the hold itself', () {
    // The node's picture at the scale and over the bounds asked, a red
    // square — counted as it is drawn.
    void draw(
      ui.Canvas canvas,
      SubtreeHold hold, {
      Rect bounds = const Rect.fromLTWH(0, 0, 16, 16),
      double rasterScale = 1,
      int maxPixelSide = maxSubtreeRasterSide,
    }) => drawSubtreeAsImage(
      canvas: canvas,
      bounds: bounds,
      rasterScale: rasterScale,
      maxPixelSide: maxPixelSide,
      paintSubtree: (into, _) => into.drawRect(
        const Rect.fromLTWH(2, 2, 10, 10),
        Paint()..color = const Color(0xFFFF0000),
      ),
      compose: (blit) => blit(Paint()),
      held: hold,
    );

    void drawOnce(SubtreeHold hold, {Rect? bounds, double rasterScale = 1}) {
      final recorder = ui.PictureRecorder();
      draw(
        ui.Canvas(recorder),
        hold,
        bounds: bounds ?? const Rect.fromLTWH(0, 0, 16, 16),
        rasterScale: rasterScale,
      );
      recorder.endRecording().dispose();
    }

    test('one drawn whole is found by what it draws, at its scale, where it '
        'covers what is asked', () {
      drawOnce(SubtreeHold(held, key: 'node', keeps: true));
      expect(held, hasLength(1), reason: '⛔premise');

      debugSubtreeRasterCount = 0;
      drawOnce(
        SubtreeHold(held, key: 'node', keeps: false),
        bounds: const Rect.fromLTWH(3, 4, 5, 6),
      );
      expect(debugSubtreeRasterCount, 0, reason: 'a part of it');

      drawOnce(SubtreeHold(held, key: 'another', keeps: false));
      expect(debugSubtreeRasterCount, 1, reason: 'another node');

      drawOnce(
        SubtreeHold(held, key: 'node', keeps: false),
        bounds: const Rect.fromLTWH(8, 8, 16, 16),
      );
      expect(debugSubtreeRasterCount, 2, reason: 'past what it covers');

      drawOnce(SubtreeHold(held, key: 'node', keeps: false), rasterScale: 2);
      expect(debugSubtreeRasterCount, 3, reason: 'at another scale');
    });

    test('one the cap magnified is not kept', () {
      final recorder = ui.PictureRecorder();
      draw(
        ui.Canvas(recorder),
        SubtreeHold(held, key: 'node', keeps: true),
        maxPixelSide: 10,
      );
      recorder.endRecording().dispose();
      expect(held, hasLength(0));
    });

    test('⚖️what is held stays within its bytes — one past them is not kept '
        'at all', () {
      // 16×16 at four bytes a pixel.
      final room = HeldSubtreeRasters(bytes: () => 16 * 16 * 4);
      addTearDown(room.clear);
      drawOnce(SubtreeHold(room, key: 'first', keeps: true));
      drawOnce(SubtreeHold(room, key: 'second', keeps: true));
      expect(room, hasLength(1));

      final none = HeldSubtreeRasters(bytes: () => 16 * 16 * 4 - 1);
      addTearDown(none.clear);
      drawOnce(SubtreeHold(none, key: 'first', keeps: true));
      expect(none, hasLength(0));
    });
  });
}
