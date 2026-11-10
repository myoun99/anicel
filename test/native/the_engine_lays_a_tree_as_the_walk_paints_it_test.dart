import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_number_letters.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/dirty_region.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/composite_tree_plan.dart';
import 'package:anicel/src/native/engine_letters.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart'
    show strokeBlendModeNativeId;
import 'package:anicel/src/services/cut_frame_composite_plan.dart';
import 'package:anicel/src/services/guide_geometry.dart';

import '../helpers/app_faces.dart';

/// 🚨THE ENGINE LAYS A TREE AS THE WALK PAINTED IT (screen-on-the-engine
/// c5): one tree, laid by the translator on the engine
/// (`planCompositeTree` → `run`), comes out the pixels the walk every route
/// composited by painted — each node kind, each blend, a pose, a colour, a
/// ghost and a chain past colour.
///
/// ↩️Compared with the walk itself (`paintCompositeTree`, through the camera
/// at rest, flutter_tester on Impeller) until the routes all stood on the
/// engine and it was deleted (flip lane ⓔ): what it painted of each case
/// is kept beside this file, as prints of it ([printOf], taken 11-10).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canvas = CanvasSize(width: 256, height: 128);
  const side = 128;
  late GpuComposite composite;
  late EngineLetters letters;

  setUpAll(() async {
    composite = GpuComposite(appGpuEngine);
    letters = await EngineLetters.open(composite);
  });
  tearDownAll(() {
    composite.free();
  });

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

  int shownOf(Uint8List bytes, int at, int channel) => channel == 3
      ? bytes[at + 3]
      : (bytes[at + channel] * bytes[at + 3] / 255).round();

  /// [picture], straight pixels of the canvas, in a few bytes: of each cell
  /// of 16 pixels the mean of what its pixels show, premultiplied — and what
  /// one pixel off its middle shows, which a picture moved a pixel over
  /// a noise changes where a mean would not.
  List<int> printOf(Uint8List picture) {
    const cell = 16;
    final columns = canvas.width ~/ cell;
    final rows = canvas.height ~/ cell;
    final made = Uint8List(columns * rows * 8);
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final o = (row * columns + column) * 8;
        for (var channel = 0; channel < 4; channel++) {
          var sum = 0;
          for (var y = 0; y < cell; y++) {
            for (var x = 0; x < cell; x++) {
              sum += shownOf(
                picture,
                ((row * cell + y) * canvas.width + column * cell + x) * 4,
                channel,
              );
            }
          }
          made[o + channel] = (sum / (cell * cell)).round();
          made[o + 4 + channel] = shownOf(
            picture,
            ((row * cell + 11) * canvas.width + column * cell + 5) * 4,
            channel,
          );
        }
      }
    }
    return made;
  }

  final kept =
      jsonDecode(
            File(
              'test/native/a_tree_as_the_walk_painted_it.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  /// [picture] shows what the walk painted of the case [name], [most] apart
  /// at the most in a channel — a mean, rounded, a level further.
  void asTheWalkPainted(String name, Uint8List picture, int most) {
    final walked = base64Decode((kept['prints'] as Map)[name] as String);
    final laid = printOf(picture);
    expect(laid.length, walked.length);
    var worst = 0;
    for (var at = 0; at < laid.length; at++) {
      final mean = at % 8 < 4;
      worst = math.max(worst, (laid[at] - walked[at]).abs() - (mean ? 1 : 0));
    }
    expect(worst, lessThanOrEqualTo(most));
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
  /// them ([onUnderlay]) — on the canvas's paper, or on [paper] where one
  /// is named.
  Uint8List laid(
    List<CompositeNode<CutFrameCompositeLayer>> nodes,
    ui.Color ground, {
    ui.Rect? paper,
  }) {
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
        paper: paper ?? canvas.canvasRect,
        letters: letters,
      ),
    );
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
    test('$name is laid as the walk painted it', () {
      // The walk kept its pictures as premultiplied bytes, a draw after a
      // draw, where the engine keeps 16 bits a channel: what a pixel shows
      // lies 2 apart at the most (measured 11-08 — 0 where a row is copied,
      // posed or not).
      asTheWalkPainted('cases/$name', laid(nodes, ground), 2);
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
    test('$name is laid as the walk painted it', () {
      // A chain's picture is kept as straight bytes from one op to the
      // next and to its draw's colour (rust/src/kernels/chain/mod.rs),
      // where the walk kept premultiplied ones: 3 apart at the most — one
      // channel of an adjustment's at whole mix (measured 11-08).
      asTheWalkPainted('chained/$name', laid(nodes, ground), 3);
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

  // 🗣️gpu-canonical-store-Q2 (유저 2026-11-08 「모든 흐림을 진짜
  // 가우시안」): fx Gaussian Blur is laid as the Gaussian itself at every
  // Blurriness, reaching 3 sigma. The walk's is Impeller's, which is not
  // (gaussian_blur_filter_contents.cc): it reaches
  // round((σ′ − 0.5)·√3), σ′ a shade under σ — about half as far — so it
  // leaves Blurriness 2 (σ ⅔, a reach of none) sharp, and past σ 4 it
  // blurs a picture made smaller. So the two are held apart by what each
  // case measured (11-08, an RTX 4080): the engine's is the one the ledger
  // pins.
  //
  // 🔬And a row spread past its picture — the canvas it stands on, and its
  // tiles where they reach past that — onto the canvas shown lies no
  // further apart than one that cannot: a chain put no further than its
  // picture would leave the canvas clear where the walk spreads it, ~100
  // a pixel past a solid edge. A folder's buffer holds its reach already
  // (effectBufferBounds), so past its picture it spreads nothing.
  ResolvedLayerEffect gaussian(
    double blurriness, {
    int dimensions = 0,
    bool repeats = false,
  }) => fx(EffectKind.blur, {
    'blurriness': blurriness,
    'blurDimensions': dimensions.toDouble(),
    'repeatEdgePixels': repeats ? 1 : 0,
  });
  final gaussians =
      <
        String,
        (List<CompositeNode<CutFrameCompositeLayer>>, ui.Color, int)
      >{
        for (final (blurriness, most) in [
          (2.0, 127),
          (2.5, 17),
          (5.0, 32),
          (10.0, 32),
          (20.0, 26),
          (50.0, 16),
        ])
          'a row blurred at Blurriness $blurriness': (
            [
              row(1, columns: [-1, 0, 1], effects: [gaussian(blurriness)]),
            ],
            clear,
            most,
          ),
        'a row blurred across': (
          [
            row(1, effects: [gaussian(10, dimensions: 1)]),
          ],
          clear,
          23,
        ),
        'a row blurred down': (
          [
            row(1, effects: [gaussian(10, dimensions: 2)]),
          ],
          clear,
          12,
        ),
        'a row blurred past its picture': (
          [
            row(1, columns: [0], width: side, effects: [gaussian(20)]),
          ],
          clear,
          26,
        ),
        'a moved row blurred past its picture': (
          [
            row(
              1,
              columns: [0],
              width: side,
              placement: moved(40, 30),
              effects: [gaussian(10)],
            ),
          ],
          clear,
          32,
        ),
        'a turned row blurred across past its picture': (
          [
            row(
              1,
              columns: [0],
              width: side,
              placement: quarter,
              effects: [gaussian(10, dimensions: 1)],
            ),
          ],
          clear,
          23,
        ),
        'a folder blurred past its moved row': (
          [
            CompositeGroup(
              children: [
                row(1, columns: [0], width: side, placement: moved(40, 30)),
              ],
              opacity: 1,
              blendMode: LayerBlendMode.normal,
              effects: [gaussian(10)],
            ),
          ],
          clear,
          32,
        ),
        'a row in a colour, blurred after': (
          [
            row(1, effects: [colour, gaussian(5)]),
          ],
          clear,
          32,
        ),
        'a row blurred twice, in a colour between': (
          [
            row(1, columns: [0], effects: [gaussian(5), colour, gaussian(10)]),
          ],
          clear,
          32,
        ),
        // A step's: on the picture, cut there — its ink kept off the edge
        // the blur along a way reads past (the chain's margin, above).
        'a row blurred, then blurred along a way': (
          [
            row(1, margin: 8, effects: [gaussian(5), along]),
          ],
          clear,
          12,
        ),
        'a row blurred along a way, blurred after': (
          [
            row(1, margin: 8, effects: [along, gaussian(5)]),
          ],
          clear,
          12,
        ),
        'a folder blurred, its row moved, in a colour after': (
          [
            row(4),
            CompositeGroup(
              children: [
                row(1, placement: moved(20, 10)),
                row(2, opacity: 0.8),
              ],
              opacity: 0.8,
              blendMode: LayerBlendMode.normal,
              effects: [gaussian(10), colour],
            ),
          ],
          clear,
          13,
        ),
        'an adjustment blurred at part mix': (
          [
            CompositeAdjustment(
              children: [row(1), row(2, opacity: 0.6)],
              effects: [gaussian(5)],
              mix: 0.4,
            ),
          ],
          clear,
          12,
        ),
        'a row blurred repeating the paper\'s edge': (
          [
            row(1, columns: [-1, 0, 1], effects: [gaussian(10, repeats: true)]),
          ],
          clear,
          24,
        ),
        'a folder blurred repeating the paper\'s edge, its row moved': (
          [
            CompositeGroup(
              children: [row(1, placement: moved(40, 30))],
              opacity: 1,
              blendMode: LayerBlendMode.normal,
              effects: [gaussian(10, repeats: true)],
            ),
          ],
          clear,
          24,
        ),
        'a folder blurred repeating a paper it lies off': (
          [
            row(3),
            CompositeGroup(
              children: [row(1, placement: moved(300, 0))],
              opacity: 1,
              blendMode: LayerBlendMode.normal,
              effects: [gaussian(10, repeats: true)],
            ),
          ],
          clear,
          0,
        ),
      };

  for (final MapEntry(key: name, value: (nodes, ground, most))
      in gaussians.entries) {
    test('$name is laid as the walk painted it', () {
      asTheWalkPainted('gaussians/$name', laid(nodes, ground), most);
    });
  }

  // 🗣️I-132-Q14: with Repeat Edge Pixels on, artwork on the pasteboard
  // stays out of sight — where the canvas shows past its paper, a row
  // half on it and a folder off it show nothing there, and what lies there
  // is no part of the edge it repeats. The walk's camera shows the paper
  // alone, and blurs nearly as near the edge whatever it reads past it, so
  // the engine is held to the law by itself.
  test('a Gaussian repeating the paper\'s edge puts nothing on the '
      'pasteboard, nor reads it', () {
    const paper = ui.Rect.fromLTWH(0, 0, 128, 128);
    List<CompositeNode<CutFrameCompositeLayer>> nodes(
      List<ResolvedLayerEffect> effects,
    ) => [
      row(1, effects: effects),
      CompositeGroup(
        children: [
          row(2, columns: [0], placement: moved(140, 0)),
        ],
        opacity: 1,
        blendMode: LayerBlendMode.normal,
        effects: effects,
      ),
    ];
    int inkPast(Uint8List pixels, int x) {
      var ink = 0;
      for (var at = 0; at < pixels.length; at += 4) {
        if ((at ~/ 4) % canvas.width >= x && pixels[at + 3] > 0) {
          ink += 1;
        }
      }
      return ink;
    }

    final edge = [gaussian(10, repeats: true)];
    final repeating = laid(nodes(edge), clear, paper: paper);
    expect(inkPast(laid(nodes(const []), clear, paper: paper), 128), isNot(0));
    expect(inkPast(repeating, 0), isNot(0));
    expect(inkPast(repeating, 128), 0);
    expect(
      laid([row(1, columns: [-1, 0, 1], effects: edge)], clear),
      laid([row(1, effects: edge)], clear),
      reason: 'the ink left of the paper is no part of its edge',
    );
  });

  // 🚨A CEL NUMBER (cel-number-on-the-engine-letters): the walk lays the
  // app's plate of the letters (`celNumberPlate`), the engine its own
  // raster of the app's one layout of them — set in the app's faces, the
  // unnamed drawing's mark and all, standing where the number's own
  // Position and Scale put them, laid as the row's picture is, at rest or
  // moved and scaled with it. Two rasters of one outline: where the ink
  // lies and how much of it, not each pixel — and every pixel off the
  // letters as the row's, unnumbered. ⚠️The row's own, on the engine: a row
  // scaled by 1.25 from half a pixel is no pose the walk and the engine
  // sample alike — of a picture whose neighbours share no colour, a texel
  // apart is up to 253 apart —, so the rows laid alike are the poses that
  // land on whole texels (「a row moved by whole pixels」 and the rest).
  group('a cel number', () {
    setUpAll(loadTheAppFaces);

    /// The animation row 「A」 of [surface], its drawing unnamed, numbered
    /// in a blue ink where its own stand puts the letters — but where
    /// [number] is false — and placed by [transform] where one is given.
    List<CompositeNode<CutFrameCompositeLayer>> numbered(
      BitmapSurface surface, {
      TransformTrack? transform,
      bool number = true,
    }) => planCutFrameCompositeTree(
      cut: Cut(
        id: const CutId('cut'),
        name: 'Cut',
        canvasSize: canvas,
        duration: 1,
        layers: [
          Layer(
            id: const LayerId('a'),
            name: 'A',
            kind: LayerKind.animation,
            frames: [
              Frame(id: const FrameId('f'), duration: 1, strokes: const []),
            ],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('f'), length: 1),
            },
            transformTrack: transform,
            effects: [
              if (number)
                LayerEffect(
                  id: const EffectId('n'),
                  kind: EffectKind.celNumber,
                  stand: TransformTrack.empty().copyWith(
                    position: PropertyTrack<CanvasPoint>.empty().withKey(
                      0,
                      CanvasPoint(x: 96.4, y: 58.7),
                    ),
                    scale: PropertyTrack<CanvasPoint>.empty().withKey(
                      0,
                      CanvasPoint(x: 1.5, y: 1.5),
                    ),
                  ),
                  colors: {
                    'ink': PropertyTrack<int>.empty().withKey(0, 0xFF2050C0),
                  },
                ),
            ],
          ),
        ],
      ),
      frameIndex: 0,
      reading: (surfaces: (_, _) => surface, plugins: null),
    );

    /// Where the letters on the row [name] lay, as the walk painted them.
    ({ui.Rect box, int ink}) lettersWalked(String name) {
      final numbers = ((kept['letters'] as Map)[name] as List).cast<num>();
      final [left, top, right, bottom, ink] = numbers;
      return (
        box: ui.Rect.fromLTRB(
          left.toDouble(),
          top.toDouble(),
          right.toDouble(),
          bottom.toDouble(),
        ),
        ink: ink.toInt(),
      );
    }

    /// Where [pixels] hold any alpha, and how much of it they hold.
    ({ui.Rect box, int ink}) inkOf(Uint8List pixels) {
      var (left, top) = (canvas.width, canvas.height);
      var (right, bottom, ink) = (0, 0, 0);
      for (var at = 0; at < pixels.length; at += 4) {
        final alpha = pixels[at + 3];
        if (alpha == 0) {
          continue;
        }
        final x = (at ~/ 4) % canvas.width;
        final y = (at ~/ 4) ~/ canvas.width;
        (left, top) = (math.min(left, x), math.min(top, y));
        (right, bottom) = (math.max(right, x + 1), math.max(bottom, y + 1));
        ink += alpha;
      }
      final box = ui.Rect.fromLTRB(
        left.toDouble(),
        top.toDouble(),
        right.toDouble(),
        bottom.toDouble(),
      );
      return (box: box, ink: ink);
    }

    final placements = <String, TransformTrack?>{
      'at rest': null,
      'moved and scaled': TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 128 + 20.5, y: 64 - 10.25),
        ),
        scale: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 1.25, y: 1.25),
        ),
      ),
    };
    for (final MapEntry(key: name, value: transform) in placements.entries) {
      test('on a row $name is laid where the walk laid it', () {
      final bare = numbered(
        BitmapSurface(canvasSize: canvas, tileSize: side),
        transform: transform,
      );
      final walk = lettersWalked(name);
      final engine = inkOf(laid(bare, clear));
      // 📏flutter_tester on Impeller, Windows, 11-08: the boxes a pixel
      // apart at the left and alike elsewhere, the engine's ink 0.993
      // and 0.991 of the walk's, at rest and moved. A pixel more and a
      // part in fifty more, for another device's raster of the walk's.
      final edges = [
        walk.box.left - engine.box.left,
        walk.box.top - engine.box.top,
        walk.box.right - engine.box.right,
        walk.box.bottom - engine.box.bottom,
      ];
      expect(
        [for (final edge in edges) edge.abs()],
        everyElement(lessThanOrEqualTo(2)),
        reason: 'the ink lies at ${walk.box} walked, ${engine.box} laid',
      );
      expect(
        engine.ink / walk.ink,
        closeTo(1, 0.03),
        reason: 'ink ${walk.ink} walked, ${engine.ink} laid',
      );

      final put = laid(numbered(cel(1), transform: transform), clear);
      final row = laid(
        numbered(cel(1), transform: transform, number: false),
        clear,
      );
      expect(put, isNot(row), reason: 'LIVENESS: the number was laid');
      final letters = walk.box.inflate(2);
      for (final picture in [put, row]) {
        for (var at = 0; at < picture.length; at += 4) {
          final x = (at ~/ 4) % canvas.width;
          final y = (at ~/ 4) ~/ canvas.width;
          if (letters.contains(ui.Offset(x + 0.5, y + 0.5))) {
            picture.fillRange(at, at + 4, 0);
          }
        }
      }
      expect(put, row, reason: 'off the letters the row is as it lies');
      });
    }

    test('letters that cover no pixel are a plate of no tile — a row named '
        'nothing over an unnamed drawing — and a plate is kept by its '
        'letters', () {
      final paper = BitmapSurface(canvasSize: canvas, tileSize: side);
      CelNumberLetters writing(String text) => CelNumberLetters(
        text: text,
        color: 0xFF2050C0,
        center: CanvasPoint(x: 96, y: 58),
        scale: CanvasPoint(x: 1, y: 1),
      );
      expect(letters.celNumberPlate(writing(''), paper).tiles, isEmpty);
      expect(letters.celNumberPlate(writing(' '), paper).tiles, isEmpty);
      final a = letters.celNumberPlate(writing('A'), paper);
      expect(a.tiles, isNotEmpty, reason: 'LIVENESS: letters were set');
      expect(letters.celNumberPlate(writing('A'), paper), same(a));
      expect(
        letters.celNumberPlate(writing('B'), paper),
        isNot(same(a)),
        reason: 'another letter, another plate',
      );
    });
  });

  // ⏳What the engine lays no step for yet is refused, never dropped: a
  // tree laid without it would show a picture with a row missing.
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
