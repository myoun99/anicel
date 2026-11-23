import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show debugWaitsHere;

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/selection_clip.dart';

import '../helpers/poll_until.dart';

/// What the overlay shows at each coordinate, as
/// `ActiveStrokeOverlayModel.landedTiles` hands it to pen-up: the tile the
/// engine laid there last and the stroke revision it shows.
typedef Shown = Map<TileCoord, ({BitmapTile tile, int revision})>;

/// 🚨★PEN-UP HANDS OVER WHAT THE STEPS PUT (관제 2026-11-24, card
/// the-start-of-every-stroke-stalls-on-the-galaxy-tab ③-2): a coordinate the
/// overlay shows at the stroke's newest revision there is the very tile the
/// step put, the cel's from here on — not laid again, and no wait for the
/// GPU ([BrushLiveStrokeRasterizer.promoteStrokeTiles]). ㉢ What it hands
/// over is what laying the stroke again gives, byte for byte, every brush of
/// the family: each blend, the eraser, the ceiling, a selection, a blur,
/// dabs laid after the last picture, tiles left as they were.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvasSize = CanvasSize(width: 384, height: 256);
  const tileSize = 128;
  final wall = canvasSize.pasteboardAt(PasteboardReach.whole);

  BrushDab dab({
    required double x,
    required double y,
    double size = 26,
    int color = 0xB02266AA,
    double opacity = 0.7,
    int sequence = 0,
    bool blurs = false,
  }) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: color,
    size: size,
    opacity: opacity,
    flow: 0.8,
    hardness: 0.45,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
    blurs: blurs,
  );

  /// A painted base, its left two tiles drawn and the right one bare.
  BitmapSurface paintedBase() => materializeBrushDabSequenceOnBitmapSurface(
    surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
    sequence: BrushDabSequence([
      for (var i = 0; i < 9; i += 1)
        dab(
          x: 18.5 + i * 22.0,
          y: 40.5 + (i.isEven ? 0 : 14),
          size: 34,
          color: 0xD0994411,
          opacity: 0.9,
          sequence: i,
        ),
    ]),
  ).surface;

  BitmapSurface emptyBase() =>
      BitmapSurface(canvasSize: canvasSize, tileSize: tileSize);

  /// Right across three tiles, and back across its own ink.
  List<BrushDab> loopBack({bool blurs = false}) {
    var sequence = 0;
    return [
      for (var i = 0; i < 16; i += 1)
        dab(x: 24.0 + i * 20.0, y: 52.5, sequence: ++sequence, blurs: blurs),
      for (var i = 0; i < 16; i += 1)
        dab(x: 324.0 - i * 20.0, y: 60.5, sequence: ++sequence, blurs: blurs),
    ];
  }

  /// [dabs] drawn as the canvas draws them: a batch at a time, each batch's
  /// tiles shown as the overlay shows them — what it then holds is [Shown].
  ({BrushLiveStrokeRasterizer stroke, Shown shown}) drawn(
    List<BrushDab> dabs, {
    required BitmapSurface base,
    required BrushBlendMode mode,
    void Function(BrushLiveStrokeRasterizer stroke)? asked,
    int batchSize = 4,
  }) {
    final stroke = BrushLiveStrokeRasterizer(
      pasteboard: wall,
      tileSize: tileSize,
    );
    asked?.call(stroke);
    final shown = <TileCoord, ({BitmapTile tile, int revision})>{};
    for (var start = 0; start < dabs.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, dabs.length);
      final region = stroke.blendFrom(dabs.sublist(0, end), from: start);
      for (final coord in region?.toTileCoords(tileSize: tileSize) ?? const <TileCoord>{}) {
        final tile = stroke.preBlendedOverlayTile(
          tileX: coord.x,
          tileY: coord.y,
          base: base,
          mode: mode,
          erase: mode == BrushBlendMode.erase,
        );
        if (tile != null) {
          shown[coord] = (tile: tile.landed, revision: tile.revision);
        }
      }
    }
    return (stroke: stroke, shown: shown);
  }

  Map<TileCoord, Uint8List> bytesOf(BitmapSurface surface) => {
    for (final MapEntry(:key, :value) in surface.tiles.entries)
      key: value.pixels,
  };

  /// [actual] holds [expected]'s picture: a tile of nothing on one side
  /// alone is the same as none.
  void expectSamePicture(
    BitmapSurface actual,
    BitmapSurface expected,
    String reason,
  ) {
    final a = bytesOf(actual);
    final b = bytesOf(expected);
    for (final coord in {...a.keys, ...b.keys}) {
      final one = a[coord];
      final other = b[coord];
      if (one == null || other == null) {
        expect(
          (one ?? other!).every((byte) => byte == 0),
          isTrue,
          reason: '$reason: $coord holds ink on one side alone',
        );
        continue;
      }
      expect(one, other, reason: '$reason: $coord');
    }
  }

  /// [dabs] drawn and lifted the two ways — handed over what the overlay
  /// showed, and every coordinate laid again as before ③-2 — each on [base].
  ({List<PromotedStrokeTile> handed, Shown shown}) liftedBothWays(
    List<BrushDab> dabs, {
    required BitmapSurface base,
    required BrushBlendMode mode,
    void Function(BrushLiveStrokeRasterizer stroke)? asked,
    List<BrushDab> owed = const [],
    String? reason,
  }) {
    final erase = mode == BrushBlendMode.erase;
    ({List<PromotedStrokeTile> promoted, Shown shown}) lifted({
      required bool handsOver,
    }) {
      final (:stroke, :shown) = drawn(
        dabs,
        base: base,
        mode: mode,
        asked: asked,
      );
      if (owed.isNotEmpty) {
        stroke.blendFrom([...dabs, ...owed], from: dabs.length);
      }
      final promoted = stroke.promoteStrokeTiles(
        base: base,
        mode: mode,
        erase: erase,
        dabs: [...dabs, ...owed],
        shown: handsOver ? shown : const {},
      );
      stroke.clear();
      return (promoted: promoted, shown: shown);
    }

    BitmapSurface landed(List<PromotedStrokeTile> promoted) => base.putTiles([
      for (final one in promoted) (coord: one.coord, tile: one.tile),
    ]);

    final (promoted: handed, :shown) = lifted(handsOver: true);
    final (promoted: laid, shown: _) = lifted(handsOver: false);
    expectSamePicture(
      landed(handed),
      landed(laid),
      '${reason ?? mode.name}: ㉢ handed over == laid again',
    );
    return (handed: handed, shown: shown);
  }

  test('every blend and the eraser, over ink and over nothing: what is '
      'handed over is the tile the overlay showed, and what laying the '
      'stroke again gives', () {
    for (final base in [paintedBase(), emptyBase()]) {
      for (final mode in BrushBlendMode.values) {
        final (:handed, :shown) = liftedBothWays(
          loopBack(),
          base: base,
          mode: mode,
        );
        expect(
          {for (final one in handed) one.coord},
          shown.keys.toSet(),
          reason: '${mode.name}: each coordinate shown is handed over',
        );
        for (final one in handed) {
          expect(
            identical(one.tile, shown[one.coord]!.tile),
            isTrue,
            reason: '${mode.name}: ${one.coord} is the very tile shown',
          );
        }
      }
    }
  });

  test('the ceiling and a selection: handed over as laid again', () {
    final base = paintedBase();
    liftedBothWays(
      loopBack(),
      base: base,
      mode: BrushBlendMode.color,
      asked: (stroke) => stroke.strokeOpacity = 0.4,
      reason: 'the ceiling',
    );
    liftedBothWays(
      loopBack(),
      base: base,
      mode: BrushBlendMode.color,
      asked: (stroke) => stroke.selectionClip = SelectionClip.outline(
        CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(left: 60, top: 0, right: 300, bottom: 56),
        ),
      ),
      reason: 'a selection',
    );
  });

  test('a blur: handed over as rubbed again', () {
    final base = paintedBase();
    final (:handed, :shown) = liftedBothWays(
      loopBack(blurs: true),
      base: base,
      mode: BrushBlendMode.color,
      asked: (stroke) => stroke.blurOver(base),
      reason: 'a blur',
    );
    expect(handed, isNotEmpty, reason: '⛔premise: the blur moved ink');
    for (final one in handed) {
      expect(identical(one.tile, shown[one.coord]!.tile), isTrue);
    }
  });

  test('dabs laid after the last picture (後補正 · 抜き) are laid again where '
      'they fall, and only there', () {
    final base = paintedBase();
    final dabs = loopBack();
    // The tail the pen's lift lays: on the first tile alone.
    final owed = [
      dab(x: 30.5, y: 90.5, sequence: dabs.length + 1),
      dab(x: 34.5, y: 92.5, sequence: dabs.length + 2),
    ];
    final (:handed, :shown) = liftedBothWays(
      dabs,
      base: base,
      mode: BrushBlendMode.color,
      owed: owed,
      reason: 'owed',
    );
    final first = TileCoord(x: 0, y: 0);
    for (final one in handed) {
      expect(
        identical(one.tile, shown[one.coord]!.tile),
        one.coord != first,
        reason: '${one.coord}: a tile behind what the stroke laid is laid '
            'again, and one at its newest is handed over',
      );
    }
  });

  test('pen-up waits for no GPU where every tile it hands over was shown',
      () {
    final base = paintedBase();
    final (:stroke, :shown) = drawn(
      loopBack(),
      base: base,
      mode: BrushBlendMode.color,
    );
    final waits = debugWaitsHere;
    final promoted = stroke.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
      dabs: loopBack(),
      shown: shown,
    );
    expect(debugWaitsHere, waits, reason: 'no wait for the GPU here');
    expect(promoted, hasLength(shown.length), reason: '⛔premise');
    stroke.clear();
  });

  test('what each tile handed over is is asked of the GPU, and told',
      () async {
    final base = paintedBase();
    final (:stroke, :shown) = drawn(
      loopBack(),
      base: base,
      mode: BrushBlendMode.color,
    );
    final promoted = stroke.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.color,
      erase: false,
      dabs: loopBack(),
      shown: shown,
    );
    final told = [for (final one in promoted) one.tile.inkTold];
    expect(told, everyElement(isNotNull), reason: 'each is asked');

    await patiently(Future.wait([for (final each in told) each!]));
    expect(
      [for (final one in promoted) one.tile.inkWithNoWait],
      everyElement(isTrue),
      reason: 'and each is told its ink',
    );
    stroke.clear();
  });
}
