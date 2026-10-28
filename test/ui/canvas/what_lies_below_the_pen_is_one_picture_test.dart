@Tags(['impeller'])
library;

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
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/composite_tree_paint.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨★WHAT LIES BELOW THE ROW A PEN DRAWS ON IS ONE PICTURE (card
/// paint-walk-redoes-the-same-work-each-step, 🗣️유저 2026-10-27, Q2 = c
/// 「그리는 행 아래 · 위를 한 장씩 묶어 든다」): laid for a canvas that
/// stands on it, a frame keeps what its pen's row lies on — rows, folders,
/// the paper — as one picture at each depth the pen is at, and each folder
/// over the pen on its own; a stroke's step patched in is cut from them.
///
/// 🚨★★★AND IN CELLS, WHERE A STEP NEEDS IT ([BelowThePen], card
/// a-scrub-prepares-every-frame-it-crosses, 유저 2026-10-28): a frame a
/// canvas comes to draws nothing below its pen, and a step draws the cells
/// of it it lands in, once — each the pixels the one picture holds there.
///
/// Whether anything was drawn again is invisible in the pixels, so each
/// test counts the rasters ([debugSubtreeRasterCount]) and reads the pixels
/// the step lays beside a step drawn with nothing held.
void main() {
  BrushFrameKey cel(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  FramePage pageOn(
    ProjectBackground paper, {
    CanvasSize canvasSize = const CanvasSize(width: 24, height: 16),
  }) => (
    canvasSize: canvasSize,
    pasteboardReach: PasteboardReach.whole,
    paintPaper: true,
    paperBackground: paper,
  );
  final white = pageOn(ProjectBackground.defaultBackground);
  final grey = pageOn(const ProjectBackground.color(0xFF808080));

  /// A cel whose every pixel is its own colour ([rgbaAt]) — a patch cut
  /// from the wrong place reads another.
  BitmapSurface surface(List<int> Function(int x, int y) rgbaAt) =>
      BitmapSurface(
        canvasSize: white.canvasSize,
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

  final stored = {
    'below': surface((x, y) => [0x40, 0x90, 0xFF, if (x < 12) 0xFF else 0]),
    'ramp': surface((x, y) => [x * 10, y * 15, 0x80, 0xFF]),
    'other': surface((x, y) => [0x20, 0xFF - x * 9, y * 12, 0x90]),
    'pen': surface((x, y) => [0x10, 0x10, 0x10, if (x > 16) 0xFF else 0]),
  };
  // The pen's step: ink where the cel had none.
  final inked = surface(
    (x, y) => [0x10, 0x10, 0x10, if (x > 16 || x == 8) 0xFF else 0],
  );

  CompositeLeaf<CanvasStackRow> rowOf(String id, {double opacity = 1}) =>
      CompositeLeaf(
        CanvasLayerImageRequest(frameKey: cel(id), opacity: opacity),
      );
  CompositeLeaf<CanvasStackRow> pen() =>
      CompositeLeaf(CanvasActiveLayerRow(opacity: 1, frameKey: cel('pen')));
  // ⛔Not at half strength: a folder at 0.5 over whole pixels lands on exact
  // halves (57 · 0.5 + 64 · 0.5 = 60.5), which a rasterizer rounds by its
  // last bit — the Surface Pro 11's tester rounded the one picture's and a
  // fresh draw's apart, this PC's alike (2026-10-29). At 0.6 a folder's
  // pixel over another lands on fifths, never on a half, so the two ways
  // are compared and not the rasterizer's tie.
  CompositeGroup<CanvasStackRow> folder(
    List<CompositeNode<CanvasStackRow>> of, {
    List<ResolvedLayerEffect> effects = const [],
  }) => CompositeGroup(
    children: of,
    opacity: 0.6,
    blendMode: LayerBlendMode.normal,
    effects: effects,
  );

  /// A row and a folder at 0.6 — one picture of its own — under the row a
  /// pen is on.
  List<CompositeNode<CanvasStackRow>> underThePen() => [
    rowOf('below'),
    folder([rowOf('ramp'), rowOf('other')]),
    pen(),
  ];

  late HeldSubtreeRasters held;
  setUp(() {
    held = HeldSubtreeRasters(
      bytes: () => 1 << 20,
      bytesBelow: () => 1 << 20,
    );
    debugSubtreeRasterCount = 0;
  });
  tearDown(() => held.clear());

  /// A canvas that stands with [stroke] on the pen's row.
  ({LiveRows rows, LiftedRowPainters painters}) penOn(BitmapSurface stroke) =>
      (
        rows: (
          activeSurfacePainter: BitmapSurfacePainter(
            surface: stroke,
            showTransparentBackground: false,
          ),
          floatOverlay: null,
          liftedRows: const <BrushFrameKey, LiftedCel>{},
        ),
        painters: LiftedRowPainters(),
      );
  final penStep = penOn(inked);

  /// [nodes]' frame — what lies below its pen drawn as [below] says, and
  /// none held where it says nothing.
  StackedFrame frame(
    List<CompositeNode<CanvasStackRow>> nodes, {
    BelowThePen? below,
    bool keeps = false,
    ({LiveRows rows, LiftedRowPainters painters})? live,
    FramePage? page,
    Map<String, BitmapSurface>? cels,
  }) => stackedFrameOf(
    nodes,
    page: page ?? white,
    surfaceOf: (cel) => (cels ?? stored)[cel.layerId.value],
    live: live,
    held: switch (below) {
      final below? => (
        pictures: (rasters: held, keeps: keeps, below: below),
        revisionOf: (_) => 1,
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

  /// The frame laid whole for a canvas that stands on it, its nodes kept.
  Future<void> lay(List<CompositeNode<CanvasStackRow>> nodes) async {
    final laid = frame(nodes, below: BelowThePen.whole, keeps: true);
    await drawn(laid, laid.drawing.extent);
  }

  /// The frame drawn as a canvas comes to it, laid ahead: for what it holds
  /// alone (`FramePictures.holdNodesOf`).
  Future<void> comeTo(
    List<CompositeNode<CanvasStackRow>> nodes, {
    FramePage? page,
  }) async {
    final come = frame(
      nodes,
      below: BelowThePen.asHeld,
      keeps: true,
      page: page,
    );
    await drawn(come, come.drawing.extent);
  }

  // A step's patch: across the tiles' edges, and not on the page's grid
  // of anything else.
  const step = Rect.fromLTWH(5, 3, 9, 7);

  /// The step patched in as a stroke's step is ([BelowThePen.inCells]),
  /// and how many rasters it drew — beside the step drawn with nothing
  /// held, and how many that drew.
  Future<({Uint8List pixels, int rasters, Uint8List fresh, int freshRasters})>
  aStep(
    List<CompositeNode<CanvasStackRow>> nodes, {
    Rect at = step,
    ({LiveRows rows, LiftedRowPainters painters})? live,
    FramePage? page,
    Map<String, BitmapSurface>? cels,
  }) async {
    debugSubtreeRasterCount = 0;
    final pixels = await drawn(
      frame(
        nodes,
        below: BelowThePen.inCells,
        live: live ?? penStep,
        page: page,
        cels: cels,
      ),
      at,
    );
    final rasters = debugSubtreeRasterCount;
    debugSubtreeRasterCount = 0;
    final fresh = await drawn(
      frame(nodes, live: live ?? penStep, page: page, cels: cels),
      at,
    );
    return (
      pixels: pixels,
      rasters: rasters,
      fresh: fresh,
      freshRasters: debugSubtreeRasterCount,
    );
  }

  test('the paper, a row and a folder under the pen are kept as one picture '
      '— a step draws none of them, and lays the pixels they would', () async {
    final nodes = underThePen();
    await lay(nodes);
    expect(held, hasLength(1), reason: 'one picture, the folder in it');

    final stepped = await aStep(nodes);
    expect(stepped.rasters, 0);
    expect(stepped.freshRasters, 1, reason: '⛔premise: the folder');
    expect(stepped.pixels, stepped.fresh);
    expect(held, hasLength(1), reason: 'no cell of what is held whole');
  });

  test('🚨a step is cut from that one picture — nothing under the pen is '
      'drawn, though no node is held on its own', () async {
    held = HeldSubtreeRasters(bytes: () => 0, bytesBelow: () => 1 << 20);
    final nodes = underThePen();
    await lay(nodes);
    expect(held, hasLength(1), reason: '⛔premise');

    final stepped = await aStep(nodes);
    expect(stepped.rasters, 0);
    expect(stepped.pixels, stepped.fresh);
  });

  test('🚨the first stroke on an empty cel finds what lies below kept too — '
      'the row stands bare as the frame is laid', () async {
    held = HeldSubtreeRasters(bytes: () => 0, bytesBelow: () => 1 << 20);
    final empty = {...stored}..remove('pen');
    final nodes = underThePen();
    final laid = frame(
      nodes,
      below: BelowThePen.whole,
      keeps: true,
      cels: empty,
    );
    await drawn(laid, laid.drawing.extent);
    expect(held, hasLength(1));

    final stepped = await aStep(nodes, cels: empty);
    expect(stepped.rasters, 0);
    expect(stepped.pixels, stepped.fresh);
  });

  test('what lies below drawn in part is not kept', () async {
    await drawn(
      frame(underThePen(), below: BelowThePen.whole, keeps: true),
      step,
    );
    expect(held, hasLength(0));
  });

  test('what lies below drawn whole where nothing keeps is not kept', () async {
    final laid = frame(underThePen(), below: BelowThePen.whole);
    await drawn(laid, laid.drawing.extent);
    expect(held, hasLength(0));
  });

  test('🚨a frame laid ahead keeps nothing of what lies below — not a cell: '
      'with none held, it is laid in place', () async {
    debugSubtreeRasterCount = 0;
    final pixels = await drawn(
      frame(underThePen(), below: BelowThePen.whole, live: penStep),
      step,
    );
    expect(debugSubtreeRasterCount, 1, reason: 'the folder, and nothing more');
    expect(held, hasLength(0));
    expect(pixels, await drawn(frame(underThePen(), live: penStep), step));
  });

  test('what lies below is laid in place where its one picture would be '
      'shrunk to fit — the folder in it then kept on its own', () async {
    const wide = CanvasSize(width: maxSubtreeRasterSide + 8, height: 8);
    final page = pageOn(
      ProjectBackground.defaultBackground,
      canvasSize: wide,
    );
    final cels = {
      'below': BitmapSurface(
        canvasSize: wide,
        tileSize: 8,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            size: 8,
            pixels: Uint8List.fromList([
              for (var at = 0; at < 64; at += 1) ...[at * 4, 0x40, 0x80, 0xFF],
            ]),
          ),
        },
      ),
      'pen': BitmapSurface(canvasSize: wide, tileSize: 8),
    };
    final nodes = [folder([rowOf('below')]), pen()];
    final laid = frame(
      nodes,
      below: BelowThePen.whole,
      keeps: true,
      page: page,
      cels: cels,
    );
    final pixels = await drawn(laid, laid.drawing.extent);
    expect(held, hasLength(1));
    final fresh = frame(nodes, page: page, cels: cels);
    expect(pixels, await drawn(fresh, fresh.drawing.extent));
  });

  test('🚨a folder a lifted row is in is drawn again — the row stood for '
      'nothing as the frame was laid', () async {
    final nodes = [
      rowOf('below'),
      folder([rowOf('ramp'), rowOf('lifted')]),
    ];
    await lay(nodes);
    expect(held, hasLength(1), reason: '⛔premise: the folder');

    final float = SelectionFloatOverlay(null);
    addTearDown(float.dispose);
    final lifted = (
      rows: (
        activeSurfacePainter: null,
        floatOverlay: null,
        liftedRows: {cel('lifted'): (surface: inked, float: float)},
      ),
      painters: LiftedRowPainters(),
    );
    final stepped = await aStep(nodes, live: lifted);
    expect(stepped.rasters, 1);
    expect(stepped.pixels, stepped.fresh);
  });

  test('🚨in a folder, what lies below the pen there is one picture more — '
      'the folder the pen is in is not kept: each step changes it', () async {
    final nodes = [
      folder([rowOf('below')]),
      folder([
        folder([rowOf('ramp'), rowOf('other')]),
        pen(),
      ]),
    ];
    await lay(nodes);
    expect(held, hasLength(2), reason: 'below the folder, and inside it');

    final stepped = await aStep(nodes);
    expect(stepped.rasters, 1, reason: 'the folder the pen is in');
    expect(stepped.pixels, stepped.fresh);
  });

  test('a folder over the pen is kept on its own, beside what lies below',
      () async {
    final nodes = [
      folder([rowOf('below')]),
      pen(),
      folder([rowOf('ramp'), rowOf('other')]),
    ];
    await lay(nodes);
    expect(held, hasLength(2));

    final stepped = await aStep(nodes);
    expect(stepped.rasters, 0);
    expect(stepped.freshRasters, 2, reason: '⛔premise: the folders');
    expect(stepped.pixels, stepped.fresh);
  });

  test('⚖️rows and the paper alone under the pen are drawn straight — no '
      'picture of them is kept: it would cut no work', () async {
    final nodes = [rowOf('below'), rowOf('ramp'), pen()];
    await lay(nodes);
    expect(held, hasLength(0));

    final stepped = await aStep(nodes);
    expect(stepped.rasters, 0);
    expect(stepped.pixels, stepped.fresh);
    expect(held, hasLength(0), reason: 'nor a cell of them');
  });

  test('under a pen on a row that blends with its backdrop, the backdrop is '
      'all below it — one picture', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await LayerBlendShader.load();
    held = HeldSubtreeRasters(bytes: () => 0, bytesBelow: () => 1 << 20);
    final nodes = <CompositeNode<CanvasStackRow>>[
      CompositeBackdropBlend(
        backdrop: [rowOf('below'), folder([rowOf('ramp'), rowOf('other')])],
        // The row painting normal, as the backdrop law composes it.
        source: pen(),
        blendMode: LayerBlendMode.overlay,
      ),
    ];
    await lay(nodes);
    expect(held, hasLength(1));

    final stepped = await aStep(nodes);
    expect(
      stepped.freshRasters - stepped.rasters,
      1,
      reason: 'the folder in the backdrop is not drawn',
    );
    expect(stepped.pixels, stepped.fresh);
  });

  /// A pen over a row that blends with its backdrop: the paper lies in that
  /// blend, the bottom of the frame ([onUnderlay]).
  List<CompositeNode<CanvasStackRow>> overABlend() => [
    CompositeBackdropBlend(
      backdrop: [rowOf('below'), folder([rowOf('other')])],
      source: rowOf('ramp'),
      blendMode: LayerBlendMode.overlay,
    ),
    pen(),
  ];

  test('🚨under a pen over a row that blends with its backdrop, all below is '
      'one picture — the paper in that blend with it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await LayerBlendShader.load();
    held = HeldSubtreeRasters(bytes: () => 0, bytesBelow: () => 1 << 20);
    final nodes = overABlend();
    await lay(nodes);
    expect(held, hasLength(1));

    final stepped = await aStep(nodes);
    expect(stepped.rasters, 0);
    expect(stepped.freshRasters, greaterThan(0), reason: '⛔premise');
    expect(stepped.pixels, stepped.fresh);
  });

  test('what lies below a pen over a blend is drawn again where the paper in '
      'that blend is not the one it was kept on — in its cell', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await LayerBlendShader.load();
    held = HeldSubtreeRasters(bytes: () => 0, bytesBelow: () => 1 << 20);
    final nodes = overABlend();
    await lay(nodes);
    expect(held, hasLength(1), reason: '⛔premise');

    final stepped = await aStep(nodes, page: grey);
    expect(stepped.rasters, greaterThan(0));
    expect(stepped.pixels, stepped.fresh);
    expect(held, hasLength(2), reason: 'the white one, and a grey cell');
  });

  test('⚖️where what lies below does not fit its shelf it is drawn in place '
      '— a folder in it then kept on its own, and no cell', () async {
    held = HeldSubtreeRasters(bytes: () => 1 << 20);
    final nodes = underThePen();
    await lay(nodes);
    expect(held, hasLength(1), reason: 'the folder');

    final stepped = await aStep(nodes);
    expect(stepped.rasters, 0);
    expect(stepped.pixels, stepped.fresh);
    expect(held, hasLength(1));
  });

  test('🚨a step keeps the cell of what lies below it lands in — the next '
      'step there draws none of it', () async {
    final nodes = underThePen();
    final first = await aStep(nodes);
    expect(first.rasters, 2, reason: 'its cell, and the folder in it');
    expect(first.pixels, first.fresh);
    expect(held, hasLength(1));

    final next = await aStep(nodes, at: const Rect.fromLTWH(9, 6, 7, 5));
    expect(next.rasters, 0);
    expect(next.pixels, next.fresh);
  });

  test('what lies below is drawn again where the paper it lies on is not the '
      'one it was kept on — in the cell the step lands in', () async {
    final nodes = underThePen();
    await lay(nodes);
    expect(held, hasLength(1), reason: '⛔premise');

    final stepped = await aStep(nodes, page: grey);
    expect(stepped.rasters, 2, reason: 'its cell, and the folder in it');
    expect(stepped.pixels, stepped.fresh);
  });

  group('🚨★★★a frame a canvas comes to draws nothing below its pen', () {
    test('what is held of it stays, whole or in cells, and a step is cut '
        'from it', () async {
      final nodes = underThePen();
      await lay(nodes);
      debugSubtreeRasterCount = 0;
      await comeTo(nodes);
      expect(debugSubtreeRasterCount, 0);
      expect(held, hasLength(1), reason: 'the one picture, kept');
      expect((await aStep(nodes)).rasters, 0);

      held.clear();
      await aStep(nodes);
      expect(held, hasLength(1), reason: '⛔premise: a cell');
      debugSubtreeRasterCount = 0;
      await comeTo(nodes);
      expect(debugSubtreeRasterCount, 0);
      expect(held, hasLength(1), reason: 'the cell, kept');
    });

    test('and what was held of another frame is let go of', () async {
      final nodes = underThePen();
      await lay(nodes);
      await aStep(nodes, page: grey);
      expect(held, hasLength(2), reason: '⛔premise: white whole, grey cell');

      await comeTo(nodes, page: grey);
      expect(held, hasLength(1), reason: 'the grey cell');
      await comeTo(nodes);
      expect(held, hasLength(0));
    });

    test('a folder over the pen is drawn whole to be held — and no more',
        () async {
      final nodes = [
        folder([rowOf('below')]),
        pen(),
        folder([rowOf('ramp'), rowOf('other')]),
      ];
      debugSubtreeRasterCount = 0;
      await comeTo(nodes);
      expect(debugSubtreeRasterCount, 1, reason: 'the folder over the pen');
      expect(held, hasLength(1));

      final stepped = await aStep(nodes);
      expect(stepped.rasters, 2, reason: 'the cell below, the folder in it');
      expect(stepped.pixels, stepped.fresh);
    });

    // 🗣️I-132-Q21 a: what a folder's chain reads is drawn afresh as it
    // changes; what lies in the folder is held as in any other.
    test('and into a folder that reads a row: the folder over the pen in it '
        'drawn whole to be held', () async {
      final nodes = <CompositeNode<CanvasStackRow>>[
        CompositeReadsRows(
          node: folder([
            pen(),
            folder([rowOf('ramp'), rowOf('other')]),
          ]),
          rows: {
            const LayerId('below'): [rowOf('below')],
          },
        ),
      ];
      debugSubtreeRasterCount = 0;
      await comeTo(nodes);
      expect(debugSubtreeRasterCount, 1, reason: 'the folder over the pen');
      expect(held, hasLength(1));
    });

    test('nor below the pen inside the folder it is in, nor in a blend over '
        'what lies below — each found in its cells after', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await LayerBlendShader.load();
      final nodes = <CompositeNode<CanvasStackRow>>[
        folder([rowOf('below')]),
        folder([
          CompositeBackdropBlend(
            backdrop: [folder([rowOf('ramp'), rowOf('other')])],
            source: pen(),
            blendMode: LayerBlendMode.overlay,
          ),
        ]),
      ];
      debugSubtreeRasterCount = 0;
      await comeTo(nodes);
      expect(debugSubtreeRasterCount, 0);
      expect(held, hasLength(0));

      final first = await aStep(nodes);
      expect(first.pixels, first.fresh);
      expect(held, hasLength(2), reason: 'a cell at each depth');
      final next = await aStep(nodes);
      expect(next.rasters, first.freshRasters - 2, reason: 'the two below');
      expect(next.pixels, next.fresh);
    });
  });

  group('🚨★★★each cell is the pixels the one picture holds there', () {
    // A page past one cell ([belowCellSide]), its paper's edge on no grid
    // of the cells, and ink beside a cell's edge in a folder whose blur
    // reaches over it — and on the pasteboard, left of the page, so the
    // frame's corner lies on no grid of the cells either.
    const size = CanvasSize(width: 300, height: 140);
    final page = pageOn(ProjectBackground.defaultBackground, canvasSize: size);
    BitmapSurface inkAt(Iterable<TileCoord> at, List<int> rgba) =>
        BitmapSurface(
          canvasSize: size,
          tileSize: 8,
          tiles: {
            for (final coord in at)
              coord: BitmapTile(
                size: 8,
                pixels: Uint8List.fromList([
                  for (var i = 0; i < 64; i += 1) ...rgba,
                ]),
              ),
          },
        );
    final cels = {
      // Up to x = 256, the cells' edge, from x = 240.
      'below': inkAt([
        for (var y = 10; y < 14; y += 1) ...[
          TileCoord(x: 30, y: y),
          TileCoord(x: 31, y: y),
        ],
      ], [0xE0, 0x30, 0x20, 0xFF]),
      'far': inkAt([TileCoord(x: -5, y: 2)], [0x20, 0x60, 0xE0, 0xFF]),
      'pen': BitmapSurface(canvasSize: size, tileSize: 8),
    };
    final stroke = penOn(
      inkAt([TileCoord(x: 33, y: 12)], [0x10, 0x10, 0x10, 0xFF]),
    );
    // Wide enough that a cell read only as far past it as the blur's own
    // spread is 1/255 off the one picture — at 8 it was not, and the walk
    // that draws the cells could stand in the cells alone (mutants,
    // 2026-10-28). Read beside the one picture alone: a step drawn with
    // nothing held is that 1/255 off too.
    final blur = [ResolvedLayerEffect(kind: EffectKind.blur, values: [30, 0])];
    List<CompositeNode<CanvasStackRow>> blurred() => [
      rowOf('far'),
      folder([rowOf('below')], effects: blur),
      pen(),
    ];

    /// [nodes]' frame laid whole, with nothing held — read over a rect.
    Future<Uint8List Function(Rect rect)> laidWholeOf(
      List<CompositeNode<CanvasStackRow>> nodes,
    ) async {
      final whole = frame(nodes, live: stroke, page: page, cels: cels);
      final extent = whole.drawing.extent;
      expect(extent.left % 16, isNot(0), reason: '⛔premise: off the grid');
      final all = await drawn(whole, extent);
      final width = extent.width.ceil();
      return (Rect rect) {
        final left = (rect.left - extent.left).toInt();
        final top = (rect.top - extent.top).toInt();
        return Uint8List.fromList([
          for (var y = top; y < top + rect.height.toInt(); y += 1)
            ...all.sublist(
              (y * width + left) * 4,
              (y * width + left + rect.width.toInt()) * 4,
            ),
        ]);
      };
    }

    /// The frame laid whole, with nothing held — its texels over [rect].
    Future<Uint8List> laidWhole(Rect rect) async =>
        (await laidWholeOf(blurred()))(rect);

    for (final (name, at, cells) in [
      ('beside the edge the blur spills over', const Rect.fromLTWH(258, 84, 13, 11), 1),
      ('across that edge', const Rect.fromLTWH(249, 70, 14, 40), 2),
      ('across a cell edge left of the page', const Rect.fromLTWH(-7, 18, 13, 9), 2),
    ]) {
      test(name, () async {
        final stepped = await aStep(
          blurred(),
          at: at,
          live: stroke,
          page: page,
          cels: cels,
        );
        expect(
          held,
          hasLength(cells),
          reason: 'the cells it lands in — not those the blur reads past it',
        );
        expect(stepped.pixels, await laidWhole(at));

        final again = await aStep(
          blurred(),
          at: at,
          live: stroke,
          page: page,
          cels: cels,
        );
        expect(again.rasters, 0);
        expect(again.pixels, stepped.pixels);
      });
    }

    // 🚨A STEP DRAWN WITH NOTHING HELD READS AS FAR AS THE FRAME (card
    // a-step-drawn-in-place-reads-short-of-the-one-picture, 2026-10-28): a
    // row blurred on its own in the blurred folder, beside the step's
    // edge, was 12 to 47/255 off the frame laid whole — the walk stood in
    // the step alone, and the row's buffer grew by its own spread, short
    // of what the folder reads past it.
    for (final (folderBlur, rowBlur) in <(double, double?)>[
      (8, 1),
      (8, 2),
      (30, 1),
      (30, null),
      (8, null),
    ]) {
      final row = rowBlur == null ? 'a row' : 'a row blurred $rowBlur';
      test('a step drawn with nothing held is the frame laid whole — $row in '
          'a folder blurred $folderBlur', () async {
        final nodes = [
          rowOf('far'),
          folder(
            [
              CompositeLeaf<CanvasStackRow>(
                CanvasLayerImageRequest(
                  frameKey: cel('below'),
                  opacity: 1,
                  effects: [
                    if (rowBlur != null)
                      ResolvedLayerEffect(
                        kind: EffectKind.blur,
                        values: [rowBlur, 0],
                      ),
                  ],
                ),
              ),
            ],
            effects: [
              ResolvedLayerEffect(kind: EffectKind.blur, values: [folderBlur, 0]),
            ],
          ),
          pen(),
        ];
        final whole = await laidWholeOf(nodes);
        // Across the folder's spread over the cells' edge, x = 256.
        for (var x = 256.0; x <= 290; x += 2) {
          final at = Rect.fromLTWH(x, 84, 13, 11);
          expect(
            await drawn(
              frame(nodes, live: stroke, page: page, cels: cels),
              at,
            ),
            whole(at),
            reason: 'a step at x = $x',
          );
        }
      });
    }
  });
}
