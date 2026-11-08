import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

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
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/fill_range_mark.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨★★★THE ENGINE'S SCREEN MARKS THE RANGE A HELD FILL WILL COVER (flip
/// lane ⓐ-3, I-160-Q1 a, 유저 2026-11-04 「TVPaint 처럼 체크 격자」 —
/// 「체크격자가 그림 위에 오는것임. 즉 현재 행 위. 그 위에 레이어있으면
/// 체크격자 가려져서 사라지는거 인지하고있음」): the pen's row marked shows as
/// the row with a row of the mark's cells laid right over it — white and
/// black cells of eight of its pixels at half alpha over the range alone,
/// its hole kept, pushed as far as the press moved (F-568-Q1 a) —, outside
/// its opacity, under every row above it, under its pose, and in a
/// blurred folder's picture where it reaches past the row's ink.
void main() {
  // The letters read their faces from the bundle.
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvas = CanvasSize(width: 256, height: 128);
  const side = 128;
  const page = (
    canvasSize: canvas,
    pasteboardReach: PasteboardReach.whole,
    paintPaper: true,
    paperBackground: ProjectBackground.color(0xFF30A060),
  );
  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    letters.free();
    composite.free();
  });

  BrushFrameKey keyOf(String layer) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: LayerId(layer),
    frameId: const FrameId('f'),
  );

  /// A surface of [columns] tiles along the canvas's row of them — its two,
  /// and one past it on the pasteboard for three —, each pixel [pixel]'s
  /// straight RGBA, none where it answers null.
  BitmapSurface surfaceOf(
    List<int>? Function(int x, int y) pixel, {
    int columns = 2,
  }) {
    BitmapTile tileAt(int column) {
      final pixels = Uint8List(side * side * 4);
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final rgba = pixel(column * side + x, y);
          if (rgba != null) {
            pixels.setAll((y * side + x) * 4, rgba);
          }
        }
      }
      return BitmapTile(size: side, pixels: pixels);
    }

    return BitmapSurface(
      canvasSize: canvas,
      tileSize: side,
      tiles: {
        for (var column = 0; column < columns; column++)
          TileCoord(x: column, y: 0): tileAt(column),
      },
    );
  }

  /// The pen's cel: ink of every alpha over both tiles.
  BitmapSurface cel() => surfaceOf((x, y) {
    final n = x * 7 + y * 13;
    return switch ((x ~/ 16 + y ~/ 32) % 3) {
      0 => null,
      1 => [(n * 37) & 255, (n * 23 + 91) & 255, (n * 11) & 255, 255],
      _ => [(n * 11) & 255, (n * 37) & 255, 200, 96 + (n & 63)],
    };
  });

  /// A range off the tile grid across both tiles, soft at its left edge,
  /// with a hole: what a held fill covers there.
  FillRangeCover covered() {
    const left = 30;
    const top = 10;
    const width = 170;
    const height = 90;
    final mask = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final hole = (x - 40).abs() < 9 && (y - 30).abs() < 12;
        mask[y * width + x] = hole ? 0 : (x == 0 ? 40 : 255);
      }
    }
    return FillRange.over(
      FloodFillRegion(
        left: left,
        top: top,
        width: width,
        height: height,
        mask: mask,
      ),
    ).coveredWithin(null)!;
  }

  /// The mark's cells as a row of pixels: white where the cell's column and
  /// row add up even, black where odd, each at half alpha, over [cover]
  /// alone, the cells pushed [shift] — the checker the canvas marks
  /// (fill_range_mark.dart).
  BitmapSurface cellsOf(
    FloodFillRegion cover,
    ui.Offset shift, {
    int columns = 2,
  }) => surfaceOf(columns: columns, (x, y) {
    final (column, row) = (x - cover.left, y - cover.top);
    if (column < 0 ||
        row < 0 ||
        column >= cover.width ||
        row >= cover.height ||
        cover.mask[row * cover.width + column] == 0) {
      return null;
    }
    final across = ((x + 0.5 - shift.dx) / 8).floor();
    final down = ((y + 0.5 - shift.dy) / 8).floor();
    return (across + down).isEven
        ? const [255, 255, 255, 128]
        : const [0, 0, 0, 128];
  });

  StackedFrame frameOf(
    List<CompositeNode<CanvasStackRow>> nodes, {
    required BitmapSurfacePainter live,
    Map<BrushFrameKey, BitmapSurface> cels = const {},
  }) => stackedFrameOf(
    nodes,
    page: page,
    surfaceOf: (cel) => cels[cel],
    live: (
      rows: (
        activeSurfacePainter: live,
        floatOverlay: null,
        liftedRows: const {},
      ),
      painters: LiftedRowPainters(),
    ),
  );

  /// What the engine's screen shows of [frame] — its fingerprint.
  int shown(StackedFrame frame) {
    final screen = EngineStackScreen(composite, letters);
    addTearDown(screen.free);
    screen.compose(frame);
    const size = (256, 128);
    final target = () {
      try {
        return appGpuEngine.surface(size.$1, size.$2, bgra: false);
      } on StateError {
        return appGpuEngine.surface(size.$1, size.$2, bgra: true);
      }
    }();
    addTearDown(target.free);
    screen.show(
      target,
      size,
      viewport: CanvasViewport(),
      devicePixelRatio: 1,
    );
    return target.fingerprint();
  }

  late ActiveStrokeOverlayModel overlay;
  setUp(() => overlay = ActiveStrokeOverlayModel(tileSize: side));
  tearDown(() => overlay.dispose());

  /// The pen's row drawing [surface], marked where the overlay holds a
  /// range.
  BitmapSurfacePainter penOn(BitmapSurface surface) => BitmapSurfacePainter(
    surface: surface,
    overlayModel: overlay,
    showTransparentBackground: false,
  );

  final pen = keyOf('pen');
  final cells = keyOf('cells');
  final above = keyOf('above');

  /// The row of the mark's cells, posed by [placement].
  CompositeLeaf<CanvasStackRow> cellsRow([GuideTransform? placement]) =>
      CompositeLeaf(
        CanvasLayerImageRequest(
          frameKey: cells,
          opacity: 1,
          placement: placement,
        ),
      );

  for (final shift in const [
    ui.Offset.zero,
    ui.Offset(3.5, -2.25),
    ui.Offset(-13, 7.5),
  ]) {
    test('🚨a held fill\'s range pushed $shift shows as a row of its cells '
        'right over the row it lands on', () {
      final range = covered();
      final row = CanvasActiveLayerRow(opacity: 1, frameKey: pen);
      overlay.showFillRange(FillRangeMark(range).shifted(shift));

      final marked = shown(frameOf([CompositeLeaf(row)], live: penOn(cel())));

      expect(
        marked,
        shown(
          frameOf(
            [
              CompositeLeaf(row),
              cellsRow(),
            ],
            live: BitmapSurfacePainter(surface: cel()),
            cels: {cells: cellsOf(range.cover, shift)},
          ),
        ),
      );
      expect(
        marked,
        isNot(
          shown(
            frameOf(
              [CompositeLeaf(row)],
              live: BitmapSurfacePainter(surface: cel()),
            ),
          ),
        ),
        reason: 'the range is marked',
      );
    });
  }

  test('🚨under the rows above it, which hide it', () {
    final range = covered();
    final row = CanvasActiveLayerRow(opacity: 1, frameKey: pen);
    final over = CompositeLeaf<CanvasStackRow>(
      CanvasLayerImageRequest(frameKey: above, opacity: 1),
    );
    // Over the left half: opaque in places, half there in others.
    final ink = surfaceOf(
      (x, y) => x >= 128
          ? null
          : (x ~/ 8).isEven
          ? [200, 30, 30, 255]
          : [30, 30, 200, 128],
    );
    overlay.showFillRange(FillRangeMark(range));

    final marked = shown(
      frameOf(
        [CompositeLeaf(row), over],
        live: penOn(cel()),
        cels: {above: ink},
      ),
    );

    final both = {above: ink, cells: cellsOf(range.cover, ui.Offset.zero)};
    StackedFrame unmarked(List<CompositeNode<CanvasStackRow>> nodes) =>
        frameOf(nodes, live: BitmapSurfacePainter(surface: cel()), cels: both);
    expect(marked, shown(unmarked([CompositeLeaf(row), cellsRow(), over])));
    expect(
      marked,
      isNot(shown(unmarked([CompositeLeaf(row), over, cellsRow()]))),
      reason: 'not over the rows above',
    );
  });

  test('🚨outside the row\'s own opacity', () {
    final range = covered();
    final row = CanvasActiveLayerRow(opacity: 0.5, frameKey: pen);
    overlay.showFillRange(FillRangeMark(range));

    expect(
      shown(frameOf([CompositeLeaf(row)], live: penOn(cel()))),
      shown(
        frameOf(
          [
            CompositeLeaf(row),
            cellsRow(),
          ],
          live: BitmapSurfacePainter(surface: cel()),
          cels: {cells: cellsOf(range.cover, ui.Offset.zero)},
        ),
      ),
    );
  });

  test('🚨under the row\'s pose, in its own pixels', () {
    const placement = GuideTransform(1, 0, 0, 1, 7, -3);
    final range = covered();
    final row = CanvasActiveLayerRow(
      opacity: 1,
      frameKey: pen,
      placement: placement,
    );
    overlay.showFillRange(FillRangeMark(range).shifted(const ui.Offset(3, 1)));

    expect(
      shown(frameOf([CompositeLeaf(row)], live: penOn(cel()))),
      shown(
        frameOf(
          [CompositeLeaf(row), cellsRow(placement)],
          live: BitmapSurfacePainter(surface: cel()),
          cels: {cells: cellsOf(range.cover, const ui.Offset(3, 1))},
        ),
      ),
    );
  });

  test('🚨on a row of no ink, the range alone', () {
    final range = covered();
    final row = CanvasActiveLayerRow(opacity: 1, frameKey: pen);
    final nothing = BitmapSurface(canvasSize: canvas, tileSize: side);
    overlay.showFillRange(FillRangeMark(range));

    expect(
      shown(frameOf([CompositeLeaf(row)], live: penOn(nothing))),
      shown(
        frameOf(
          [
            CompositeLeaf(row),
            cellsRow(),
          ],
          live: BitmapSurfacePainter(surface: nothing),
          cels: {cells: cellsOf(range.cover, ui.Offset.zero)},
        ),
      ),
    );
  });

  test('🚨in a blurred folder, a range past the row\'s ink is laid in the '
      'folder\'s picture and blurred with it, as a row of its cells is', () {
    // A tile past the canvas, covered whole: where the row holds no ink,
    // so only the range's own extent puts it in the folder's picture —
    // whose blur spreads it back over the canvas's edge.
    final range = FillRange.over(
      FloodFillRegion(
        left: 256,
        top: 0,
        width: side,
        height: side,
        mask: Uint8List(side * side)..fillRange(0, side * side, 255),
      ),
    ).coveredWithin(null)!;
    CompositeNode<CanvasStackRow> blurred(
      List<CompositeNode<CanvasStackRow>> children,
    ) => CompositeGroup(
      children: children,
      opacity: 1,
      blendMode: LayerBlendMode.normal,
      effects: [
        ResolvedLayerEffect(
          kind: EffectKind.blur,
          values: [
            for (final spec in EffectKind.blur.parameters)
              switch (spec.id) {
                'blurriness' => 6,
                'blurDimensions' => 0,
                _ => spec.defaultValue,
              },
          ],
        ),
      ],
    );
    final row = CanvasActiveLayerRow(opacity: 1, frameKey: pen);
    overlay.showFillRange(FillRangeMark(range));

    expect(
      shown(
        frameOf([
          blurred([CompositeLeaf(row)]),
        ], live: penOn(cel())),
      ),
      shown(
        frameOf(
          [
            blurred([CompositeLeaf(row), cellsRow()]),
          ],
          live: BitmapSurfacePainter(surface: cel()),
          cels: {cells: cellsOf(range.cover, ui.Offset.zero, columns: 3)},
        ),
      ),
    );
  });
}
