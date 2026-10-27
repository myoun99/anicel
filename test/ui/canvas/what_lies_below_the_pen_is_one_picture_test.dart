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
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
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

  ({
    CanvasSize canvasSize,
    PasteboardReach pasteboardReach,
    bool paintPaper,
    ProjectBackground paperBackground,
  })
  pageOn(ProjectBackground paper) => (
    canvasSize: const CanvasSize(width: 24, height: 16),
    pasteboardReach: PasteboardReach.whole,
    paintPaper: true,
    paperBackground: paper,
  );
  final white = pageOn(ProjectBackground.defaultBackground);

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
  CompositeGroup<CanvasStackRow> folder(
    List<CompositeNode<CanvasStackRow>> of,
  ) => CompositeGroup(
    children: of,
    opacity: 0.5,
    blendMode: LayerBlendMode.normal,
    effects: const [],
  );

  /// A row and a folder at half strength — one picture of its own — under
  /// the row a pen is on.
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

  final live = (
    rows: (
      activeSurfacePainter: BitmapSurfacePainter(
        surface: inked,
        showTransparentBackground: false,
      ),
      floatOverlay: null,
      liftedRows: const <BrushFrameKey, LiftedCel>{},
    ),
    painters: LiftedRowPainters(),
  );

  StackedFrame frame(
    List<CompositeNode<CanvasStackRow>> nodes, {
    bool? keeps,
    bool stepping = false,
    ({
      CanvasSize canvasSize,
      PasteboardReach pasteboardReach,
      bool paintPaper,
      ProjectBackground paperBackground,
    })?
    page,
  }) => stackedFrameOf(
    nodes,
    page: page ?? white,
    surfaceOf: (cel) => stored[cel.layerId.value],
    live: stepping ? live : null,
    held: switch (keeps) {
      final keeps? => (
        pictures: (rasters: held, keeps: keeps),
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
    final laid = frame(nodes, keeps: true);
    await drawn(laid, laid.drawing.extent);
  }

  // A step's patch: across the tiles' edges, and not on the page's grid
  // of anything else.
  const step = Rect.fromLTWH(5, 3, 9, 7);

  /// The step patched in, and how many rasters it drew — beside the step
  /// drawn with nothing held, and how many that drew.
  Future<({Uint8List pixels, int rasters, Uint8List fresh, int freshRasters})>
  aStep(List<CompositeNode<CanvasStackRow>> nodes) async {
    debugSubtreeRasterCount = 0;
    final pixels = await drawn(
      frame(nodes, keeps: false, stepping: true),
      step,
    );
    final rasters = debugSubtreeRasterCount;
    debugSubtreeRasterCount = 0;
    final fresh = await drawn(frame(nodes, stepping: true), step);
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
  });

  test('🚨in a folder, what lies below the pen there is one picture more — '
      'the folder the pen is in is not kept: each step changes it', () async {
    final nodes = [
      rowOf('below'),
      folder([rowOf('ramp'), rowOf('other'), pen()]),
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
      rowOf('below'),
      pen(),
      folder([rowOf('ramp'), rowOf('other')]),
    ];
    await lay(nodes);
    expect(held, hasLength(2));

    final stepped = await aStep(nodes);
    expect(stepped.rasters, 0);
    expect(stepped.freshRasters, 1, reason: '⛔premise: the folder');
    expect(stepped.pixels, stepped.fresh);
  });

  test('under a pen on a row that blends with its backdrop, the backdrop is '
      'all below it — one picture', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await LayerBlendShader.load();
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

  test('⚖️where what lies below does not fit its shelf it is drawn in place '
      '— a folder in it then kept on its own', () async {
    held = HeldSubtreeRasters(bytes: () => 1 << 20);
    final nodes = underThePen();
    await lay(nodes);
    expect(held, hasLength(1), reason: 'the folder');

    final stepped = await aStep(nodes);
    expect(stepped.rasters, 0);
    expect(stepped.pixels, stepped.fresh);
  });

  test('🚨where no picture of what lies below is held and none is kept, '
      'none is drawn — a step lays it in place', () async {
    final nodes = underThePen();
    final stepped = await aStep(nodes);
    expect(stepped.rasters, 1, reason: 'the folder, and nothing more');
    expect(stepped.pixels, stepped.fresh);
    expect(held, hasLength(0));
  });

  test('what lies below is drawn again where the paper it lies on is not the '
      'one it was kept on', () async {
    final nodes = underThePen();
    await lay(nodes);
    expect(held, hasLength(1), reason: '⛔premise');

    final grey = pageOn(const ProjectBackground.color(0xFF808080));
    debugSubtreeRasterCount = 0;
    final pixels = await drawn(
      frame(nodes, keeps: false, stepping: true, page: grey),
      step,
    );
    expect(debugSubtreeRasterCount, 1, reason: 'the folder');
    expect(pixels, await drawn(frame(nodes, stepping: true, page: grey), step));
  });
}
