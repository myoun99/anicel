// On Impeller, the app's: the walk lays a camera lens blur's row sums in
// floats, which the Skia tester does not lay (11-08: a row through one came
// out all but empty).
@Tags(['impeller'])
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/composite_tree_plan.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart'
    show strokeBlendModeNativeId;
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/guide_geometry.dart';
import 'package:anicel/src/ui/camera/camera_frame_render_service.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/canvas/directional_blur_shader.dart';
import 'package:anicel/src/ui/canvas/iris_blur_shader.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';

/// 🚨THE ENGINE LAYS A TREE AS THE WALK PAINTS IT (screen-on-the-engine
/// c5): one tree, painted by the walk every route composites by
/// (`paintCompositeTree`, here through the camera at rest) and laid by the
/// translator on the engine (`planCompositeTree` → `run`), comes out the
/// same pixels — each node kind, each blend, a pose, a colour, a ghost and
/// a chain past colour.
void main() {
  const canvas = CanvasSize(width: 256, height: 128);
  const side = 128;
  late GpuComposite composite;

  setUpAll(() => composite = GpuComposite(appGpuEngine));
  tearDownAll(() => composite.free());

  /// A cel of [width] × 128 whose pixels are [seed]'s, in the tiles of
  /// [columns] it holds: colours no two neighbours share, and alphas in
  /// bands — none, part and whole — so a blend meets every kind of pixel
  /// under and over it; none at all within [margin] of the tiles' edge.
  BitmapSurface cel(
    int seed, {
    List<int> columns = const [0, 1],
    int margin = 0,
    int width = 256,
  }) {
    final (first, last) = columns.isEmpty
        ? (0, 0)
        : (columns.reduce(math.min), columns.reduce(math.max));
    final left = first * side + margin;
    final right = (last + 1) * side - margin;
    BitmapTile tile(int column) {
      final pixels = Uint8List(side * side * 4);
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final at = (y * side + x) * 4;
          final n = (x + column * side) * 7 + y * 13 + seed * 101;
          final inside =
              x + column * side >= left &&
              x + column * side < right &&
              y >= margin &&
              y < side - margin;
          pixels[at] = (n * 37 + seed * 59) & 255;
          pixels[at + 1] = (n * 23 + 91) & 255;
          pixels[at + 2] = (n * 11 + seed * 17) & 255;
          pixels[at + 3] = !inside
              ? 0
              : switch (((x + seed * 9) ~/ 16 + y ~/ 32) % 4) {
                  0 => 0,
                  1 => 255,
                  2 => 96 + (n & 63),
                  _ => 200 + (n & 31),
                };
        }
      }
      return BitmapTile(size: side, pixels: pixels);
    }

    return BitmapSurface(
      canvasSize: CanvasSize(width: width, height: side),
      tileSize: side,
      tiles: {
        for (final column in columns)
          TileCoord(x: column, y: 0): tile(column),
      },
    );
  }

  CompositeLeaf<CutFrameCompositeLayer> row(
    int seed, {
    double opacity = 1,
    LayerBlendMode blendMode = LayerBlendMode.normal,
    GuideTransform? placement,
    List<ResolvedLayerEffect> effects = const [],
    int? tint,
    List<int> columns = const [0, 1],
    int margin = 0,
    int width = 256,
  }) => CompositeLeaf(
    CutFrameCompositeLayer(
      surface: cel(seed, columns: columns, margin: margin, width: width),
      opacity: opacity,
      blendMode: blendMode,
      placement: placement,
      effects: effects,
      tint: tint,
    ),
  );

  /// [nodes] each in an advanced blend composed over its backdrop, as the
  /// plans lay them ([composeOverTheirBackdrops]).
  List<CompositeNode<CutFrameCompositeLayer>> lawful(
    List<CompositeNode<CutFrameCompositeLayer>> nodes,
  ) => composeOverTheirBackdrops(
    nodes,
    blendOf: (layer) => layer.blendMode,
    paintedNormal: (layer) => layer.paintedNormal(),
  );

  /// [scope] clipped to [base] by the clip law ([clippedOnto]) — a row, or
  /// a clip it joins.
  CompositeNode<CutFrameCompositeLayer> clipped(
    CompositeNode<CutFrameCompositeLayer> base,
    CompositeLeaf<CutFrameCompositeLayer> scope,
  ) => clippedOnto(
    base,
    scope,
    blendOf: (layer) => layer.blendMode,
    asClipBase: (layer) => (
      base: CutFrameCompositeLayer(surface: layer.surface, opacity: 1),
      opacity: layer.opacity,
      blendMode: layer.blendMode,
    ),
  );

  /// The straight pixels of [nodes] painted by the walk, through a camera
  /// at rest — over [ground].
  Future<Uint8List> walked(
    List<CompositeNode<CutFrameCompositeLayer>> nodes,
    ui.Color ground,
  ) async {
    final image = await CameraFrameRenderService(
      background: ground,
    ).renderThroughCamera(
      canvasSize: canvas,
      nodes: nodes,
      pose: CameraPose(center: CanvasPoint(x: 128, y: 64)),
      cameraFrameSize: canvas,
    );
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// The straight pixels, row by row as the walk's are, of the plan [lay]
  /// builds of tiles a hold holds.
  Uint8List ran(void Function(GpuPlan plan, TileHold hold) lay) {
    final ledger = EngineTileLedger(appGpuEngine);
    addTearDown(ledger.pool.free);
    final tiles = ledger.held((hold) {
      final plan = GpuPlan();
      addTearDown(plan.free);
      lay(plan, hold);
      final out = composite.run(
        ledger.pool,
        plan,
        const [(0, 0), (1, 0)],
        (0, 0, canvas.width, canvas.height),
      );
      addTearDown(out.free);
      return out.read();
    });
    final image = Uint8List(canvas.width * canvas.height * 4);
    for (var y = 0; y < side; y++) {
      for (var column = 0; column < 2; column++) {
        final from = (column * side * side + y * side) * 4;
        image.setRange(
          (y * canvas.width + column * side) * 4,
          (y * canvas.width + (column + 1) * side) * 4,
          tiles,
          from,
        );
      }
    }
    return image;
  }

  /// The whole canvas, as a solid takes it.
  final everywhere = DirtyRegion(
    left: 0,
    top: 0,
    rightExclusive: canvas.width,
    bottomExclusive: canvas.height,
  );

  /// The straight pixels of [nodes] laid on the engine over [ground], as a
  /// route folds its rows ([mapCompositeLeaves]) and lays its ground under
  /// them ([onUnderlay]).
  Uint8List laid(
    List<CompositeNode<CutFrameCompositeLayer>> nodes,
    ui.Color ground,
  ) {
    final tree = onUnderlay<EngineRow>(
      mapCompositeLeaves<CutFrameCompositeLayer, EngineRow>(
        nodes,
        (layer) => EngineTiles(
          lineage: layer,
          surface: layer.surface,
          placement: layer.placement,
          opacity: layer.opacity,
          blendMode: layer.blendMode,
          effects: layer.effects,
          tint: layer.tint,
        ),
      ),
      EngineSolid(argb: ground.toARGB32(), rect: everywhere),
    );
    return ran(
      (plan, hold) => planCompositeTree(
        plan,
        tree,
        hold: hold,
        paper: canvas.canvasRect,
      ),
    );
  }

  /// The most a channel of [a] and [b] lie apart premultiplied — what a
  /// pixel shows, the walk's own picture being premultiplied bytes — and
  /// how many channels lie apart at all.
  ({int most, int apart, int far}) apartness(Uint8List a, Uint8List b) {
    var most = 0;
    var apart = 0;
    var far = 0;
    int shown(Uint8List bytes, int at, int channel) => channel == 3
        ? bytes[at + 3]
        : (bytes[at + channel] * bytes[at + 3] / 255).round();
    for (var at = 0; at < a.length; at += 4) {
      for (var channel = 0; channel < 4; channel++) {
        final gap = (shown(a, at, channel) - shown(b, at, channel)).abs();
        if (gap > 0) {
          apart += 1;
          if (gap > 2) {
            far += 1;
          }
          if (gap > most) {
            most = gap;
          }
        }
      }
    }
    return (most: most, apart: apart, far: far);
  }

  /// [kind] at its defaults but for [lanes], standing on [points] and
  /// reading the rows [layers] name.
  ResolvedLayerEffect fx(
    EffectKind kind,
    Map<String, double> lanes, {
    Map<String, CanvasPoint?> points = const {},
    Map<String, LayerId?> layers = const {},
  }) => ResolvedLayerEffect(
    kind: kind,
    values: [
      for (final spec in kind.parameters) lanes[spec.id] ?? spec.defaultValue,
    ],
    points: points,
    layers: layers,
  );

  final colour = fx(EffectKind.hueSaturation, {
    'hue': 40,
    'saturation': 30,
    'lightness': -10,
  });
  ResolvedLayerEffect key({bool restores = false, double tolerance = 40}) =>
      fx(EffectKind.colorKey, {
        'keyOperation': restores ? 1 : 0,
        'keyColor': 0xFF808080,
        'tolerance': tolerance,
        'amount': 100,
      });
  final along = fx(EffectKind.directionalBlur, {
    'direction': 30,
    'blurLength': 12,
  });
  ResolvedLayerEffect about({required bool spin}) => fx(
    EffectKind.radialBlur,
    {'amount': spin ? 8 : 15, 'type': spin ? 0 : 1},
    points: {'center': CanvasPoint(x: 90, y: 40)},
  );
  /// The row a lens's blur map is read from ([lens]'s `reads`).
  const depth = LayerId('depth');
  ResolvedLayerEffect lens({
    bool repeats = false,
    Map<String, double> light = const {},
    Map<String, double>? reads,
  }) => fx(
    EffectKind.cameraLensBlur,
    {
      'blurRadius': 5,
      'irisShape': 3,
      'irisRoundness': 20,
      'irisAspectRatio': 1.3,
      'irisRotation': 15,
      'irisDiffractionFringe': 100,
      'repeatEdgePixels': repeats ? 1 : 0,
      ...light,
      if (reads != null) ...{'blurFocalDistance': 128, ...reads},
    },
    layers: {if (reads != null) 'blurMapLayer': depth},
  );
  GuideTransform moved(double x, double y) => GuideTransform(1, 0, 0, 1, x, y);
  const quarter = GuideTransform(0, 1, -1, 0, 192, -64);

  const clear = ui.Color(0x00000000);
  const white = ui.Color(0xFFFFFFFF);
  final cases =
      <String, (List<CompositeNode<CutFrameCompositeLayer>>, ui.Color)>{
        'a row': ([row(1)], clear),
        'a row at part strength': ([row(1, opacity: 0.6)], clear),
        'two rows': ([row(1), row(2, opacity: 0.7)], clear),
        'a row over a ground of a colour': (
          [row(3, opacity: 0.8)],
          const ui.Color(0xFF2050C0),
        ),
        'a row holding its right tile alone': ([row(1, columns: [1])], clear),
        'an empty row over a row': ([row(1), row(2, columns: [])], clear),
        'a row moved by whole pixels': (
          [row(1, placement: const GuideTransform(1, 0, 0, 1, 7, -3))],
          clear,
        ),
        'a row enlarged twice': (
          [row(1, placement: const GuideTransform(2, 0, 0, 2, -64, -32))],
          clear,
        ),
        'a row turned a quarter': (
          [row(1, placement: quarter)],
          clear,
        ),
        'a row in a colour': (
          [
            row(
              1,
              effects: [
                ResolvedLayerEffect(
                  kind: EffectKind.hueSaturation,
                  values: [40, 30, -10],
                ),
              ],
            ),
          ],
          clear,
        ),
        'a ghost': ([row(1, tint: 0xC03070E0)], clear),
        'a ghost of a row in a colour': (
          [
            row(
              1,
              tint: 0xC03070E0,
              effects: [
                ResolvedLayerEffect(
                  kind: EffectKind.brightnessContrast,
                  values: [20, 35],
                ),
              ],
            ),
          ],
          clear,
        ),
        'a folder at part strength in a colour': (
          [
            row(4),
            CompositeGroup(
              children: [row(1), row(2, opacity: 0.8)],
              opacity: 0.55,
              blendMode: LayerBlendMode.normal,
              effects: [
                ResolvedLayerEffect(
                  kind: EffectKind.brightnessContrast,
                  values: [-25, 40],
                ),
              ],
            ),
          ],
          clear,
        ),
        'a clip': (
          [
            CompositeClip(
              base: row(1),
              scope: [row(2, opacity: 0.9)],
              opacity: 0.7,
              blendMode: LayerBlendMode.normal,
            ),
          ],
          clear,
        ),
        'an adjustment at whole mix': (
          [
            CompositeAdjustment(
              children: [row(1), row(2, opacity: 0.6)],
              effects: [
                ResolvedLayerEffect(
                  kind: EffectKind.hueSaturation,
                  values: [-70, 50, 20],
                ),
              ],
              mix: 1,
            ),
          ],
          clear,
        ),
        'an adjustment at part mix': (
          [
            CompositeAdjustment(
              children: [row(1), row(2, opacity: 0.6)],
              effects: [
                ResolvedLayerEffect(
                  kind: EffectKind.hueSaturation,
                  values: [-70, 50, 20],
                ),
              ],
              mix: 0.4,
            ),
          ],
          clear,
        ),
        // A pass-through folder buffers where its chain needs one
        // (folderNeedsCompositeBuffer), and closes as normal.
        'a pass-through folder in a colour': (
          [
            row(4),
            CompositeGroup(
              children: [row(1), row(2, opacity: 0.8)],
              opacity: 0.75,
              blendMode: LayerBlendMode.passThrough,
              effects: [
                ResolvedLayerEffect(
                  kind: EffectKind.hueSaturation,
                  values: [25, -40, 10],
                ),
              ],
            ),
          ],
          clear,
        ),
        'a folder in a folder': (
          [
            CompositeGroup(
              children: [
                row(1),
                CompositeGroup(
                  children: [row(2), row(3, opacity: 0.5)],
                  opacity: 0.6,
                  blendMode: LayerBlendMode.normal,
                ),
              ],
              opacity: 0.8,
              blendMode: LayerBlendMode.normal,
            ),
          ],
          clear,
        ),
        // The law the plans lay their trees by: a row in an advanced blend
        // over its backdrop, and the rows a clip holds.
        'a folder in multiply over a row': (
          lawful([
            row(1),
            CompositeGroup(
              children: [row(2), row(3, opacity: 0.6)],
              opacity: 0.7,
              blendMode: LayerBlendMode.multiply,
            ),
          ]),
          white,
        ),
        'a clip whose row multiplies its base': (
          lawful([clipped(row(1), row(2, blendMode: LayerBlendMode.multiply))]),
          clear,
        ),
        'a clip whose rows multiply its base and lie over that': (
          lawful([
            clipped(
              clipped(row(1), row(2, blendMode: LayerBlendMode.multiply)),
              row(3, opacity: 0.7),
            ),
          ]),
          clear,
        ),
        'a clip in screen over a row': (
          lawful([
            row(3),
            clipped(
              row(1, opacity: 0.6, blendMode: LayerBlendMode.screen),
              row(2, opacity: 0.8),
            ),
          ]),
          clear,
        ),
      };

  for (final MapEntry(key: name, value: (nodes, ground)) in cases.entries) {
    testWidgets('$name is laid as the walk paints it', (tester) async {
      await tester.runAsync(() async {
        await LayerBlendShader.load();
        final walk = await walked(nodes, ground);
        // The walk keeps its pictures as premultiplied bytes, a draw after
        // a draw, where the engine keeps 16 bits a channel: what a pixel
        // shows lies 2 apart at the most (measured 11-08 — 0 where a row is
        // copied, posed or not).
        expect(apartness(walk, laid(nodes, ground)).most, lessThanOrEqualTo(2));
      });
    });
  }

  // A chain past colour: its steps run on the row's own picture — with ink
  // on the pasteboard, a picture that starts left of the paper — or on a
  // buffer's, which a moved row starts off the canvas's corner.
  //
  // 🔬Its ink kept off the picture's edge where a blur along a way reads
  // it (margin): the walk's pass samples its raster clamped, so a tap
  // within half a pixel of the edge reads the edge pixel whole, where the
  // engine reads nothing past it — the decal directional_blur.frag says
  // it lays. A buffer's raster holds the chain's reach of nothing about
  // its ink, so there the two lie 1 apart; a row's picture whose ink
  // touches its edge, 13 there (measured 11-08).
  //
  // 🔬And a key's tolerance no pixel's colour lies at, through the colour
  // before it: where one does, the walk's premultiplied bytes and the
  // engine's straight ones fall either side of it (a row: 99 on 32 pixels
  // at a tolerance of 90 — measured 11-08, the blends' thresholds' kind).
  final chained =
      <String, (List<CompositeNode<CutFrameCompositeLayer>>, ui.Color)>{
        'a row keyed past a colour': (
          [
            row(1, effects: [colour, key()]),
          ],
          clear,
        ),
        'a row keyed past a colour, in a colour after': (
          [
            row(
              1,
              effects: [
                colour,
                key(),
                fx(EffectKind.brightnessContrast, {
                  'brightness': 20,
                  'contrast': 35,
                }),
              ],
            ),
          ],
          clear,
        ),
        // Past a set of tables, a key still gives back to the run's input.
        'a row keyed past a colour by more keys than a set holds': (
          [
            row(
              1,
              effects: [
                colour,
                for (var at = 0; at < 32; at++) key(),
                key(restores: true, tolerance: 30),
              ],
            ),
          ],
          clear,
        ),
        'a row blurred along a way': (
          [
            row(1, columns: [-1, 0, 1], margin: 8, effects: [along]),
          ],
          clear,
        ),
        'a row spun about a point': (
          [
            row(1, columns: [-1, 0, 1], margin: 8, effects: [about(spin: true)]),
          ],
          clear,
        ),
        'a row zoomed about a point': (
          [
            row(
              1,
              columns: [-1, 0, 1],
              margin: 8,
              effects: [about(spin: false)],
            ),
          ],
          clear,
        ),
        // Cut to what the row stands for — its canvas, where that reaches
        // past its tiles — not to the tiles its chain runs over.
        'a row blurred across past the canvas it stands on': (
          [
            row(
              1,
              columns: [0],
              margin: 8,
              width: 200,
              effects: [
                fx(EffectKind.directionalBlur, {
                  'direction': 90,
                  'blurLength': 200,
                }),
              ],
            ),
          ],
          clear,
        ),
        'a row through a lens': (
          [
            row(1, columns: [-1, 0, 1], effects: [lens()]),
          ],
          clear,
        ),
        'a row through a lens repeating the paper\'s edge': (
          [
            row(1, columns: [-1, 0, 1], effects: [lens(repeats: true)]),
          ],
          clear,
        ),
        'a row through a lens in its own light': (
          [
            row(
              1,
              effects: [
                lens(
                  light: {
                    'highlightGain': 20,
                    'highlightThreshold': 180,
                    'highlightSaturation': 50,
                    'useLinearWorkingSpace': 1,
                  },
                ),
              ],
            ),
          ],
          clear,
        ),
        'a ghost of a row blurred along a way': (
          [
            row(1, tint: 0xC03070E0, margin: 8, effects: [along]),
          ],
          clear,
        ),
        'a row blurred along a way, turned': (
          [
            row(
              1,
              placement: quarter,
              margin: 8,
              effects: [along],
            ),
          ],
          clear,
        ),
        'a folder blurred along a way, in a colour after': (
          [
            row(4),
            CompositeGroup(
              children: [
                row(1, placement: moved(20, 10)),
                row(2, opacity: 0.8),
              ],
              opacity: 0.8,
              blendMode: LayerBlendMode.normal,
              effects: [along, colour],
            ),
          ],
          clear,
        ),
        'a folder spun about a point, its row moved': (
          [
            CompositeGroup(
              children: [row(1, placement: moved(40, 30))],
              opacity: 1,
              blendMode: LayerBlendMode.normal,
              effects: [about(spin: true)],
            ),
          ],
          clear,
        ),
        'a folder through a lens repeating the paper\'s edge, its row moved': (
          [
            CompositeGroup(
              children: [row(1, placement: moved(40, 30))],
              opacity: 1,
              blendMode: LayerBlendMode.normal,
              effects: [lens(repeats: true)],
            ),
          ],
          clear,
        ),
        'a folder through a lens repeating a paper it lies off': (
          [
            row(3),
            CompositeGroup(
              children: [row(1, placement: moved(300, 0))],
              opacity: 1,
              blendMode: LayerBlendMode.normal,
              effects: [lens(repeats: true)],
            ),
          ],
          clear,
        ),
        'an adjustment blurred along a way at whole mix': (
          [
            CompositeAdjustment(
              children: [row(1), row(2, opacity: 0.6)],
              effects: [along, colour],
              mix: 1,
            ),
          ],
          clear,
        ),
        'an adjustment blurred along a way at part mix, in a colour after': (
          [
            CompositeAdjustment(
              children: [row(1), row(2, opacity: 0.6)],
              effects: [along, colour],
              mix: 0.4,
            ),
          ],
          clear,
        ),
        'an adjustment keyed past a colour at part mix': (
          [
            CompositeAdjustment(
              children: [row(1)],
              effects: [colour, key()],
              mix: 0.4,
            ),
          ],
          clear,
        ),
        // A lens reading its blur map from a row, drawn as it shows by
        // itself where the chain runs: under a posed row's pose undone.
        'a row through a lens reading a map': (
          [
            CompositeReadsRows(
              node: row(1, effects: [lens(reads: {})]),
              rows: {
                depth: [row(5)],
              },
            ),
          ],
          clear,
        ),
        'a moved row through a lens reading a map, a row over it': (
          [
            CompositeReadsRows(
              node: row(1, placement: moved(20, 10), effects: [lens(reads: {})]),
              rows: {
                depth: [row(5)],
              },
            ),
            row(2, opacity: 0.6),
          ],
          clear,
        ),
        'a turned row through a lens reading a moved map': (
          [
            CompositeReadsRows(
              node: row(1, placement: quarter, effects: [lens(reads: {})]),
              rows: {
                depth: [row(5, placement: moved(10, 5))],
              },
            ),
          ],
          clear,
        ),
        'a row through a lens reading a map\'s alpha inverted, in focus '
            'far': (
          [
            CompositeReadsRows(
              node: row(
                1,
                effects: [
                  lens(
                    reads: {
                      'blurMapChannel': 4,
                      'blurFocalDistance': 220,
                      'invertBlurMap': 1,
                    },
                  ),
                ],
              ),
              rows: {
                depth: [row(5)],
              },
            ),
          ],
          clear,
        ),
        'a row through a lens reading a map that draws nothing': (
          [
            CompositeReadsRows(
              node: row(1, effects: [lens(reads: {})]),
              rows: {depth: const []},
            ),
          ],
          clear,
        ),
        // A row it names that the cut does not hold reads as none: the
        // blur at its whole radius.
        'a row through a lens reading a row the cut does not hold': (
          [
            CompositeReadsRows(
              node: row(1, effects: [lens(reads: {})]),
              rows: {
                const LayerId('another'): [row(5)],
              },
            ),
          ],
          clear,
        ),
        'a folder through a lens reading a map': (
          [
            CompositeReadsRows(
              node: CompositeGroup(
                children: [row(1, placement: moved(40, 30))],
                opacity: 1,
                blendMode: LayerBlendMode.normal,
                effects: [lens(reads: {})],
              ),
              rows: {
                depth: [row(5)],
              },
            ),
          ],
          clear,
        ),
        'an adjustment through a lens reading a map at part mix': (
          [
            CompositeReadsRows(
              node: CompositeAdjustment(
                children: [row(1), row(2, opacity: 0.6)],
                effects: [lens(reads: {})],
                mix: 0.4,
              ),
              rows: {
                depth: [row(5)],
              },
            ),
          ],
          clear,
        ),
      };

  for (final MapEntry(key: name, value: (nodes, ground)) in chained.entries) {
    testWidgets('$name is laid as the walk paints it', (tester) async {
      await tester.runAsync(() async {
        await LayerBlendShader.load();
        await ColourKeyShader.load();
        await DirectionalBlurShader.load();
        await IrisBlurShader.load();
        final walk = await walked(nodes, ground);
        // A chain's picture is kept as straight bytes from one op to the
        // next and to its draw's colour (rust/src/kernels/chain/mod.rs),
        // where the walk keeps premultiplied ones: 3 apart at the most —
        // one channel of an adjustment's at whole mix (measured 11-08).
        expect(apartness(walk, laid(nodes, ground)).most, lessThanOrEqualTo(3));
      });
    });
  }

  // 🗣️brush-fidelity-Q4 (유저 2026-10-17 「레이어까지 같이」): a row takes
  // every mode the brush does — by the brush's own ids, the engine's table.
  // Not the walk's: where a mode's formula breaks (a burn, a dodge, a hard
  // mix), the walk's shader in floats and the engine's integers fall either
  // side of it.
  for (final mode in LayerBlendMode.values) {
    if (!mode.needsItsBackdrop) {
      continue;
    }
    test('a row in ${mode.name} is laid in the brush\'s ${mode.name}', () {
      final (under, over) = (row(1), row(2, opacity: 0.8, blendMode: mode));
      final byHand = ran((plan, hold) {
        int setOf(CutFrameCompositeLayer row) => plan.set(
          0,
          0,
          2,
          1,
          hold.slotsOf(row, [
            row.surface.tileAt(TileCoord(x: 0, y: 0))!,
            row.surface.tileAt(TileCoord(x: 1, y: 0))!,
          ]),
        );
        void lay(CutFrameCompositeLayer row, int mode, int opacity) =>
            plan.row(
              set: setOf(row),
              inverse: const [1, 0, 0, 0, 1, 0, 0, 0, 1],
              sampling: GpuSampling.nearest,
              columns: canvas.width,
              rows: canvas.height,
              mode: mode,
              opacity: opacity,
            );
        plan.solid(0xFFFFFFFF, 0, 0, canvas.width, canvas.height);
        lay(under.payload, GpuBlend.normal, 65535);
        lay(
          over.payload,
          strokeBlendModeNativeId(BrushBlendMode.values.byName(mode.name)),
          52428,
        );
      });

      expect(laid(lawful([under, over]), white), byHand);
    });
  }

  // ⏳What the engine lays no step for yet is refused, never dropped: a
  // tree laid without it would show a picture with a row missing.
  // ⏳gpu-canonical-store-Q2: the Gaussian — painted, or a step repeating
  // the paper's edge.
  for (final repeats in [false, true]) {
    test('a tree holding what the engine cannot lay yet is refused — a '
        'Gaussian${repeats ? ' repeating the paper\'s edge' : ''}', () {
      final blurred = row(
        1,
        effects: [
          fx(EffectKind.blur, {
            'blurriness': 6,
            'repeatEdgePixels': repeats ? 1 : 0,
          }),
        ],
      );
      expect(() => laid([blurred], clear), throwsUnsupportedError);
    });
  }

  // ⏳A folder's chain in the blur map a posed row reads: the walk spreads
  // it on the canvas's grid, laid under the row's pose undone.
  test('a tree holding what the engine cannot lay yet is refused — a '
      'folder\'s chain in the map a moved row reads', () {
    final reading = CompositeReadsRows(
      node: row(1, placement: moved(20, 10), effects: [lens(reads: {})]),
      rows: {
        depth: [
          CompositeGroup(
            children: [row(5)],
            opacity: 1,
            blendMode: LayerBlendMode.normal,
            effects: [along],
          ),
        ],
      },
    );
    expect(() => laid([reading], clear), throwsUnsupportedError);
  });
}
