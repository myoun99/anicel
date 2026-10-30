import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/canvas/active_stroke_overlay.dart';
import 'package:anicel/src/ui/canvas/bitmap_surface_painter.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/canvas/composite_tree_paint.dart'
    show readsPastOf;
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

/// 🚨A STEP UNDER A FOLDER OR AN ADJUSTMENT THAT SPREADS IS TOLD BY ITS
/// SPREAD — where it moved, grown by as far as each chain it passes
/// through reads past a pixel, the row's own chain among them; a step on a
/// row posed along the axes with no chain of its own, through its pose —
/// and one on a row turned off them, or posed under a chain of its own, is
/// not told at all ([StackedFrame.movedSince]): a canvas that stands
/// patches the first into its picture and draws the frame as it stands for
/// the second (one-picture-per-frame, 유저 2026-10-25 「원본 기준 위에서
/// 푼다」). ↩️A spread anywhere over the row was not told, and the row's own
/// until it read its spread off the canvas's grid
/// (nested-folder-buffers-read-past-the-view-Q1 = c); no pose was told
/// until 2026-10-30.
///
/// The width is asserted, not that a rect came: a rect that is not grown
/// by the spread still comes, and patches a step whose blur it cuts.
void main() {
  // 24×8 at tile size 8: the dab's tile is 8 wide.
  const canvasSize = CanvasSize(width: 24, height: 8);
  final blur = [
    ResolvedLayerEffect(kind: EffectKind.blur, values: [4, 0]),
  ];

  BrushDab dabAt(double x) => BrushDab(
    center: CanvasPoint(x: x, y: 4),
    color: 0xFF000000,
    size: 3,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: 0,
  );

  /// What [nodes] say of a dab in the first tile, the live row drawn where
  /// [nodes] stand it.
  Future<({bool located, Rect? dirty})> aDabUnder(
    WidgetTester tester,
    List<CompositeNode<CanvasStackRow>> nodes,
  ) async {
    final overlay = ActiveStrokeOverlayModel(tileSize: 8);
    addTearDown(overlay.dispose);
    final rasterizer = BrushLiveStrokeRasterizer(
      pasteboard: canvasSize.pasteboardAt(PasteboardReach.whole),
    );
    final frame = stackedFrameOf(
      nodes,
      page: (
        canvasSize: canvasSize,
        pasteboardReach: PasteboardReach.whole,
        paintPaper: true,
        paperBackground: const ProjectBackground.color(0xFF00FF00),
      ),
      // A row another reads a blur map by is drawn from a cel of its own.
      surfaceOf: (_) => BitmapSurface(canvasSize: canvasSize, tileSize: 8),
      live: (
        rows: (
          activeSurfacePainter: BitmapSurfacePainter(
            surface: BitmapSurface(
              canvasSize: canvasSize,
              tileSize: 8,
              tiles: {
                for (var x = 0; x < 3; x += 1)
                  TileCoord(x: x, y: 0): BitmapTile.blank(size: 8),
              },
            ),
            overlayModel: overlay,
            showTransparentBackground: false,
          ),
          floatOverlay: null,
          liftedRows: const {},
        ),
        painters: LiftedRowPainters(),
      ),
    );
    final before = frame.tokens;
    expect(before, isNotNull, reason: '⛔premise: the live row is in hand');
    await tester.runAsync(() async {
      rasterizer.blendFrom([dabAt(2)], from: 0);
      overlay.updateRegion(
        source: rasterizer,
        region: DirtyRegion.fromXYWH(x: 0, y: 2, width: 5, height: 5),
      );
    });
    final moved = frame.movedSince(before!);
    return (located: moved.located, dirty: moved.dirty);
  }

  CompositeNode<CanvasStackRow> row({
    GuideTransform? placement,
    List<ResolvedLayerEffect> effects = const [],
    LayerBlendMode blendMode = LayerBlendMode.normal,
  }) => CompositeLeaf<CanvasStackRow>(
    CanvasActiveLayerRow(
      opacity: 1,
      placement: placement,
      effects: effects,
      blendMode: blendMode,
    ),
  );

  CompositeNode<CanvasStackRow> blurredFolder(
    List<CompositeNode<CanvasStackRow>> children,
  ) => CompositeGroup<CanvasStackRow>(
    children: children,
    opacity: 1,
    blendMode: LayerBlendMode.normal,
    effects: blur,
  );

  testWidgets('a row alone: its tile and the hairline', (tester) async {
    final moved = await aDabUnder(tester, [row()]);
    expect(moved.located, isTrue);
    expect(moved.dirty, const Rect.fromLTRB(-1, -1, 9, 9));
  });

  testWidgets('a row in a blurred folder: grown by the folder\'s blur', (
    tester,
  ) async {
    final moved = await aDabUnder(tester, [
      blurredFolder([row()]),
    ]);
    expect(moved.located, isTrue);
    expect(
      moved.dirty,
      const Rect.fromLTRB(-5, -5, 13, 13),
      reason: 'the 8-wide tile, the blur\'s 4 on each side and the hairline',
    );
  });

  testWidgets('a row in a blurred folder in a blurred folder: grown by both',
      (tester) async {
    final moved = await aDabUnder(tester, [
      blurredFolder([
        blurredFolder([row()]),
      ]),
    ]);
    expect(moved.located, isTrue);
    expect(moved.dirty, const Rect.fromLTRB(-9, -9, 17, 17));
  });

  testWidgets('a row under a blurring adjustment: grown by its blur', (
    tester,
  ) async {
    final moved = await aDabUnder(tester, [
      CompositeAdjustment<CanvasStackRow>(
        children: [row()],
        effects: blur,
        mix: 1,
      ),
    ]);
    expect(moved.located, isTrue);
    expect(moved.dirty, const Rect.fromLTRB(-5, -5, 13, 13));
  });

  // The tile where each pose lays it, and the hairline past it.
  for (final (name, pose, dirty) in [
    ('moved', const GuideTransform(1, 0, 0, 1, 3, 0), const Rect.fromLTRB(
      2,
      -1,
      12,
      9,
    )),
    ('doubled', const GuideTransform(2, 0, 0, 2, 0, 0), const Rect.fromLTRB(
      -1,
      -1,
      17,
      17,
    )),
    ('flipped', const GuideTransform(-1, 0, 0, 1, 24, 0), const Rect.fromLTRB(
      15,
      -1,
      25,
      9,
    )),
    ('turned a quarter', const GuideTransform(0, 1, -1, 0, 8, 2),
        const Rect.fromLTRB(-1, 1, 9, 11)),
  ]) {
    testWidgets('a row $name: told where its pose lays the step', (
      tester,
    ) async {
      final moved = await aDabUnder(tester, [row(placement: pose)]);
      expect(moved.located, isTrue);
      expect(moved.dirty, dirty);
    });
  }

  testWidgets('⛔a row doubled that blurs of its own is not told', (
    tester,
  ) async {
    final moved = await aDabUnder(tester, [
      row(placement: const GuideTransform(2, 0, 0, 2, 0, 0), effects: blur),
    ]);
    expect(moved.located, isFalse);
  });

  testWidgets('⛔a row doubled that adds is not told', (tester) async {
    final moved = await aDabUnder(tester, [
      row(
        placement: const GuideTransform(2, 0, 0, 2, 0, 0),
        blendMode: LayerBlendMode.add,
      ),
    ]);
    expect(moved.located, isFalse);
  });

  testWidgets('a row that adds, unposed: told where the step is', (
    tester,
  ) async {
    final moved = await aDabUnder(tester, [
      row(blendMode: LayerBlendMode.add),
    ]);
    expect(moved.dirty, const Rect.fromLTRB(-1, -1, 9, 9));
  });

  testWidgets('⛔a row turned off the axes is not told', (tester) async {
    final moved = await aDabUnder(tester, [
      row(placement: const GuideTransform(0.8, 0.6, -0.6, 0.8, 3, 0)),
    ]);
    expect(moved.located, isFalse);
  });

  testWidgets('a row that blurs of its own: grown by its own blur', (
    tester,
  ) async {
    final moved = await aDabUnder(tester, [row(effects: blur)]);
    expect(moved.located, isTrue);
    expect(moved.dirty, const Rect.fromLTRB(-5, -5, 13, 13));
  });

  testWidgets('a row that blurs of its own in a blurred folder: grown by '
      'both', (tester) async {
    final moved = await aDabUnder(tester, [
      blurredFolder([row(effects: blur)]),
    ]);
    expect(moved.located, isTrue);
    expect(moved.dirty, const Rect.fromLTRB(-9, -9, 17, 17));
  });

  // I-132-Q3: a spin reaches as far as the paper's farthest corner moves
  // about its centre — the paper's middle, (12, 4): the corner 12.6 out,
  // turned 45° each way, moves 9.7, and the texel past it.
  testWidgets('a row in a spinning folder: grown by how far the paper\'s '
      'corner moves', (tester) async {
    final reach = 2 * math.sqrt(12 * 12 + 4 * 4) * math.sin(math.pi / 8) + 1;
    final moved = await aDabUnder(tester, [
      CompositeGroup<CanvasStackRow>(
        children: [row()],
        opacity: 1,
        blendMode: LayerBlendMode.normal,
        effects: [
          ResolvedLayerEffect(
            kind: EffectKind.radialBlur,
            values: [90, 0, 0, 0],
            points: {'center': null},
          ),
        ],
      ),
    ]);
    expect(moved.located, isTrue);
    final dirty = moved.dirty!;
    // The tile, the reach on each side and the hairline.
    for (final (side, was) in [
      (dirty.left, -reach - 1),
      (dirty.top, -reach - 1),
      (dirty.right, 8 + reach + 1),
      (dirty.bottom, 8 + reach + 1),
    ]) {
      expect(side, closeTo(was, 1e-9));
    }
  });

  // 🗣️I-132-Q21 a: a camera lens blur reads its blur map's row where it
  // shows, pixel for pixel — so a step on that row moves the row that reads
  // it there, and as far past as that row's chain reads past a pixel.
  group('a step on a blur map\'s row', () {
    const map = LayerId('map');
    const cel = BrushFrameKey(
      projectId: ProjectId('p'),
      trackId: TrackId('t'),
      cutId: CutId('c'),
      layerId: LayerId('reader'),
      frameId: FrameId('f'),
    );
    final lens = ResolvedLayerEffect(
      kind: EffectKind.cameraLensBlur,
      values: [
        for (final spec in EffectKind.cameraLensBlur.parameters)
          if (spec.id == 'blurRadius') 4 else spec.defaultValue,
      ],
      layers: {'blurMapLayer': map},
    );

    /// A row whose lens blur reads the live row as its map.
    CompositeNode<CanvasStackRow> reading({
      GuideTransform? placement,
      List<ResolvedLayerEffect> after = const [],
    }) => CompositeReadsRows<CanvasStackRow>(
      node: CompositeLeaf(
        CanvasLayerImageRequest(
          frameKey: cel,
          opacity: 1,
          placement: placement,
          effects: [lens, ...after],
        ),
      ),
      rows: {
        map: [row()],
      },
    );

    test('a cell is read as far past it as the folder that reads the map '
        'reads past a pixel', () {
      const paper = Rect.fromLTWH(0, 0, 24, 8);
      final folder = blurredFolder([row()]);
      final past = readsPastOf([folder], paper: paper);
      expect(past, greaterThan(0), reason: '⛔premise: its chain spreads');
      expect(
        readsPastOf([
          CompositeReadsRows<CanvasStackRow>(
            node: folder,
            rows: {
              map: [row()],
            },
          ),
        ], paper: paper),
        past,
      );
    });

    testWidgets('its eye off: told where it is read, grown by the reading '
        'row\'s chain', (tester) async {
      final moved = await aDabUnder(tester, [reading()]);
      expect(moved.located, isTrue);
      expect(moved.dirty, const Rect.fromLTRB(-5, -5, 13, 13));
      final blurred = await aDabUnder(tester, [reading(after: blur)]);
      expect(blurred.dirty, const Rect.fromLTRB(-9, -9, 17, 17));
    });

    testWidgets('shown as well: told where it stands and where it is read, '
        'both', (tester) async {
      final moved = await aDabUnder(tester, [row(), reading(after: blur)]);
      expect(moved.located, isTrue);
      expect(moved.dirty, const Rect.fromLTRB(-9, -9, 17, 17));
    });

    testWidgets('read by a row in a blurred folder: grown by both', (
      tester,
    ) async {
      final moved = await aDabUnder(tester, [
        blurredFolder([reading()]),
      ]);
      expect(moved.dirty, const Rect.fromLTRB(-9, -9, 17, 17));
    });

    testWidgets('⛔read by a posed row: not told — its chain reads past a '
        'pixel, as a posed row\'s own does', (tester) async {
      final moved = await aDabUnder(tester, [
        reading(placement: const GuideTransform(2, 0, 0, 2, 0, 0)),
      ]);
      expect(moved.located, isFalse);
    });
  });
}
