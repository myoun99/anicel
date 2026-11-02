import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/composite_effect_paint.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/canvas/composite_tree_paint.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨★A NODE THAT DREW THE SAME PICTURE DOES NOT DRAW IT AGAIN
/// ([HeldSubtreeRasters]; card paint-walk-redoes-the-same-work-each-step):
/// a folder drawn whole as its frame is laid is cut from, not drawn again,
/// as a stroke's steps are patched into that frame and as a screen draws the
/// frame as it stands (card a-dragged-opacity-slider-lags-at-rest) — and only
/// where what it draws is what was held.
///
/// Whether a node was drawn again is invisible in the pixels, so each test
/// counts the rasters ([debugSubtreeRasterCount]) and reads the pixels the
/// patch lays beside a patch drawn with nothing held.
void main() {
  setUpAll(ColourKeyShader.load);

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
        pictures: (
          rasters: held,
          keeps: keeps,
          below: keeps ? BelowThePen.whole : BelowThePen.inCells,
        ),
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

  /// [frame]'s pixels as a screen draws it as it stands, at [zoom] on a
  /// [ratio] — through the display buffer, or on the walk that [buffered]
  /// says it falls back on ([StackedFrame.paintOnScreen]).
  Future<Uint8List> onScreen(
    StackedFrame frame, {
    double zoom = 1,
    double ratio = 1,
    bool buffered = true,
  }) async {
    final recorder = ui.PictureRecorder();
    frame.paintOnScreen(
      ui.Canvas(recorder),
      Size(
        page.canvasSize.width.toDouble(),
        page.canvasSize.height.toDouble(),
      ),
      viewport: CanvasViewport(zoom: zoom),
      devicePixelRatio: ratio,
      debugDisableSingleBuffer: !buffered,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      page.canvasSize.width,
      page.canvasSize.height,
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

  CompositeLeaf<CanvasStackRow> rowOf(String id, {double opacity = 1}) =>
      CompositeLeaf(
        CanvasLayerImageRequest(frameKey: cel(id), opacity: opacity),
      );

  // A chain that is no colour of a pass's paint: a raster of its own
  // ([CompositeEffectPlan.preSteps]).
  final keyed = [
    ResolvedLayerEffect(
      kind: EffectKind.colorKey,
      values: [0, 0xFF3A8B6A.toDouble(), 120, 80],
    ),
  ];

  // Every node drawn as one picture of its own ([drawSubtreeAsImage]), at the
  // strength it is laid with. ⛔In fifths: a strength that lands on exact
  // halves is compared by the rasterizer's tie (`what_lies_below_the_pen_is_
  // one_picture_test`).
  final nodes =
      <String, List<CompositeNode<CanvasStackRow>> Function([double])>{
    'a folder': ([strength = 0.6]) => stack(folderOpacity: strength),
    'a folder that reads a row': ([strength = 0.6]) => [
      rowOf('below'),
      CompositeReadsRows(
        node: CompositeGroup(
          children: [rowOf('ramp'), rowOf('other', opacity: 0.7)],
          opacity: strength,
          blendMode: LayerBlendMode.normal,
          effects: const [],
        ),
        rows: {
          const LayerId('below'): [rowOf('below')],
        },
      ),
    ],
    'an adjustment\'s scope': ([strength = 0.6]) => [
      rowOf('below'),
      CompositeAdjustment(
        children: [rowOf('ramp'), rowOf('other', opacity: 0.7)],
        effects: [
          ResolvedLayerEffect(
            kind: EffectKind.brightnessContrast,
            values: [20, 0],
          ),
        ],
        mix: strength,
      ),
    ],
    // Both of its rasters read at a mix below 1 ([composeAdjustmentScope]).
    'an adjustment\'s scope over a keyed raster': ([strength = 1.0]) => [
      rowOf('below'),
      CompositeAdjustment(
        children: [rowOf('ramp'), rowOf('other', opacity: 0.7)],
        effects: keyed,
        mix: strength,
      ),
    ],
    'a clipping group': ([strength = 0.6]) => [
      rowOf('below'),
      CompositeClip(
        base: rowOf('ramp'),
        scope: [rowOf('other', opacity: 0.7)],
        opacity: strength,
        blendMode: LayerBlendMode.normal,
      ),
    ],
  };
  for (final MapEntry(key: name, value: nodesOf) in nodes.entries) {
    test('$name drawn whole as its frame is laid is not drawn again for a '
        'step — and the step is the pixels it would have drawn', () async {
      await lay(nodesOf());
      expect(held.length, 1, reason: '⛔premise: the node was kept');

      debugSubtreeRasterCount = 0;
      final patched = await drawn(frame(nodesOf(), keeps: false), step);
      expect(debugSubtreeRasterCount, 0, reason: 'the node was cut from');

      final fresh = await drawn(frame(nodesOf()), step);
      expect(
        debugSubtreeRasterCount,
        1,
        reason: '⛔premise: with nothing held the node is drawn',
      );
      expect(patched, fresh);
    });

    for (final strength in const [0.2, 1.0]) {
      test('🚨$name laid at $strength is the picture it was — found by a '
          'step, by a screen and by the frame\'s next picture, the pixels it '
          'would have drawn', () async {
        await lay(nodesOf());
        expect(held.length, 1, reason: '⛔premise: the node was kept');
        final laidOtherwise = nodesOf(strength);
        final extent = frame(laidOtherwise).drawing.extent;

        debugSubtreeRasterCount = 0;
        await drawn(frame(laidOtherwise, keeps: false), step);
        final shown = await onScreen(frame(laidOtherwise, keeps: false));
        final laid = await drawn(frame(laidOtherwise, keeps: true), extent);
        expect(debugSubtreeRasterCount, 0, reason: 'the node was found');
        expect(held.length, 1, reason: 'and stays held');

        // ⛔Not a step's pixels against a step's drawn fresh: a key crossfaded
        // by a mix comes out 1/255 apart in a raster of part of it, held or
        // not (known; 🔬this file's own keyed scope at 0.6, the tester's Skia
        // raster, 2026-11-02).
        expect(laid, await drawn(frame(laidOtherwise), extent));
        expect(shown, await onScreen(frame(laidOtherwise)));
        expect(
          debugSubtreeRasterCount,
          2,
          reason: '⛔premise: with nothing held the node is drawn',
        );
      });
    }

    for (final (:zoom, :ratio) in const [
      (zoom: 1.0, ratio: 1.0),
      (zoom: 3.0, ratio: 1.0),
      (zoom: 0.4, ratio: 1.0),
      (zoom: 1.0, ratio: 2.0),
    ]) {
      test('🚨$name drawn whole as its frame is laid is found by a screen '
          'drawing the frame as it stands, at $zoom on a ratio of $ratio — '
          'the pixels it would have drawn, and nothing kept', () async {
        await lay(nodesOf());
        expect(held.length, 1, reason: '⛔premise: the node was kept');
        final kept = held.heldBytes;

        debugSubtreeRasterCount = 0;
        final shown = await onScreen(
          frame(nodesOf(), keeps: false),
          zoom: zoom,
          ratio: ratio,
        );
        expect(debugSubtreeRasterCount, 0, reason: 'the node was found');
        expect(held.heldBytes, kept);

        final fresh = await onScreen(
          frame(nodesOf()),
          zoom: zoom,
          ratio: ratio,
        );
        expect(
          debugSubtreeRasterCount,
          1,
          reason: '⛔premise: with nothing held the node is drawn',
        );
        expect(shown, fresh);
      });
    }
  }

  test('🚨a screen finds no folder that draws something else now — a row gone '
      'out of hand, a row drawn on since', () async {
    await lay(stack());
    expect(held.length, 1, reason: '⛔premise');

    Future<void> drawnAgain(List<CompositeNode<CanvasStackRow>> nodes) async {
      debugSubtreeRasterCount = 0;
      final shown = await onScreen(frame(nodes, keeps: false));
      expect(debugSubtreeRasterCount, 1);
      expect(shown, await onScreen(frame(nodes)));
    }

    final inHand = stored.remove('other')!;
    await drawnAgain(stack());
    stored['other'] = inHand;

    stored['ramp'] = other;
    revisions['ramp'] = 2;
    await drawnAgain(stack());
  });

  test('⛔the walk a screen falls back on looks for none: what it rasters '
      'lies on the screen\'s pixels', () async {
    await lay(stack());
    expect(held.length, 1, reason: '⛔premise');

    debugSubtreeRasterCount = 0;
    await onScreen(frame(stack(), keeps: false), buffered: false);
    expect(debugSubtreeRasterCount, 1);
  });

  test('a folder whose row was drawn on since is drawn again', () async {
    await lay(stack());
    expect(held.length, 1, reason: '⛔premise');

    stored['ramp'] = other;
    revisions['ramp'] = 2;
    debugSubtreeRasterCount = 0;
    final drawnOn = await drawn(frame(stack(), keeps: false), step);
    expect(debugSubtreeRasterCount, 1);
    expect(drawnOn, await drawn(frame(stack()), step));
  });

  test('🚨a folder holding the row a pen draws is drawn again each step — '
      'the first stroke on an empty cel there included', () async {
    final withThePen = stack(
      inFolder: [
        CompositeLeaf(CanvasActiveLayerRow(opacity: 1, frameKey: cel('pen'))),
      ],
    );
    // Laid with nothing stored on the pen's cel, the row stands bare: the
    // folder it is in is not kept.
    await lay(withThePen);
    expect(held, hasLength(0));

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
    const whole = Rect.fromLTWH(0, 0, 16, 16);
    // A step of a chain: the picture taken again before it is laid, a
    // second image beside the raster.
    final stepped = [
      CompositeEffectStep(
        then: [
          ResolvedLayerEffect(
            kind: EffectKind.brightnessContrast,
            values: [20, 0],
          ),
        ],
      ),
    ];

    void draw(
      ui.Canvas canvas,
      SubtreeHold hold, {
      Rect bounds = whole,
      double rasterScale = 1,
      int maxPixelSide = maxSubtreeRasterSide,
      List<CompositeEffectStep> steps = const [],
    }) => drawSubtreeAsImage(
      canvas: canvas,
      bounds: bounds,
      paper: bounds,
      rasterScale: rasterScale,
      maxPixelSide: maxPixelSide,
      paintSubtree: (into, _) => into.drawRect(
        const Rect.fromLTWH(2, 2, 10, 10),
        Paint()..color = const Color(0xFFFF0000),
      ),
      compose: (blit) => blit(Paint()),
      steps: steps,
      held: hold,
    );

    void drawOnce(
      SubtreeHold hold, {
      Rect bounds = whole,
      double rasterScale = 1,
      List<CompositeEffectStep> steps = const [],
    }) {
      final recorder = ui.PictureRecorder();
      draw(
        ui.Canvas(recorder),
        hold,
        bounds: bounds,
        rasterScale: rasterScale,
        steps: steps,
      );
      recorder.endRecording().dispose();
    }

    /// What [rasters] hold for [key], as a draw over the whole finds it.
    HeldSubtreeRaster? heldFor(HeldSubtreeRasters rasters, Object key) =>
        SubtreeHold(rasters, key: key, keeps: false).covering(
          const SubtreeRasterPlan(
            bounds: whole,
            destination: whole,
            pixelWidth: 16,
            pixelHeight: 16,
            scale: 1,
            rasterScale: 1,
          ),
        );

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

    test('a part cut from what is held lays the picture its compose asks for '
        '— the raster, or the image its steps made of it', () async {
      Future<Uint8List> laid(SubtreeHold? hold, {bool steps = false}) async {
        final recorder = ui.PictureRecorder();
        drawSubtreeAsImage(
          canvas: ui.Canvas(recorder),
          bounds: whole,
          paper: whole,
          rasterScale: 1,
          paintSubtree: (into, _) => into.drawRect(
            const Rect.fromLTWH(2, 2, 10, 10),
            Paint()..color = const Color(0xFF804020),
          ),
          compose: (blit) => blit(Paint(), stepped: steps),
          steps: stepped,
          held: hold,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(16, 16);
        picture.dispose();
        final bytes = await image.toByteData();
        image.dispose();
        return bytes!.buffer.asUint8List();
      }

      final raw = await laid(SubtreeHold(held, key: 'node', keeps: true));
      expect(
        await laid(null, steps: true),
        isNot(raw),
        reason: '⛔premise: the steps change the picture',
      );
      debugSubtreeRasterCount = 0;
      final cut = await laid(SubtreeHold(held, key: 'node', keeps: false));
      expect(debugSubtreeRasterCount, 0, reason: '⛔premise: cut from it');
      expect(cut, raw);
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
      final first = heldFor(room, 'first')!;
      drawOnce(SubtreeHold(room, key: 'second', keeps: true));
      expect(room, hasLength(1));
      expect(heldFor(room, 'second'), isNotNull, reason: 'the newest stays');
      expect(first.raster.debugDisposed, isTrue, reason: 'the other goes');

      final none = HeldSubtreeRasters(bytes: () => 16 * 16 * 4 - 1);
      addTearDown(none.clear);
      drawOnce(SubtreeHold(none, key: 'first', keeps: true));
      expect(none, hasLength(0));

      // A stepped picture is two images, and weighs two.
      final two = HeldSubtreeRasters(bytes: () => 2 * 16 * 16 * 4);
      addTearDown(two.clear);
      drawOnce(SubtreeHold(two, key: 'first', keeps: true), steps: stepped);
      expect(two, hasLength(1), reason: '⛔premise');
      expect(two.heldBytes, 2 * 16 * 16 * 4);
      final short = HeldSubtreeRasters(bytes: () => 2 * 16 * 16 * 4 - 1);
      addTearDown(short.clear);
      drawOnce(SubtreeHold(short, key: 'first', keeps: true), steps: stepped);
      expect(short, hasLength(0));
    });

    test('🚨what is held is let go of — replaced, or all at once — both of '
        'its images', () {
      drawOnce(SubtreeHold(held, key: 'node', keeps: true), steps: stepped);
      final first = heldFor(held, 'node')!;
      expect(
        identical(first.image, first.raster),
        isFalse,
        reason: '⛔premise: a stepped picture beside its raster',
      );
      // Drawn whole again where the one held does not serve — at another
      // scale — the new one takes its place.
      drawOnce(
        SubtreeHold(held, key: 'node', keeps: true),
        rasterScale: 2,
        steps: stepped,
      );
      expect(held, hasLength(1), reason: '⛔premise: in its place');
      expect(first.raster.debugDisposed, isTrue);
      expect(first.image.debugDisposed, isTrue);

      final second = SubtreeHold(held, key: 'node', keeps: false).covering(
        const SubtreeRasterPlan(
          bounds: whole,
          destination: whole,
          pixelWidth: 32,
          pixelHeight: 32,
          scale: 2,
          rasterScale: 2,
        ),
      )!;
      expect(second.raster.debugDisposed, isFalse, reason: '⛔premise');
      held.clear();
      expect(second.raster.debugDisposed, isTrue);
      expect(second.image.debugDisposed, isTrue);
      expect(held, hasLength(0));
    });
  });
}
