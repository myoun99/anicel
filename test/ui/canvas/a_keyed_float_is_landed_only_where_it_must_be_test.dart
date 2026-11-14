import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart'
    show CanvasActiveLayerRow;
import 'package:anicel/src/ui/canvas/float_warp.dart' show FloatResampleShown;
import 'package:anicel/src/ui/canvas/landing_preview.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_float.dart';

import '../../helpers/a_plugin_that_shifts.dart';

/// transform-float-skips-colour-key — ON A ROW THAT KEYS A COLOUR AWAY, A
/// FLOAT IS SHOWN AS ITS LANDING ONLY WHERE ITS OWN PIXELS ARE NOT IT.
///
/// The landing made at each place a hand carries a float is exact, and
/// slow: a whole sheet landed again was some 280 ms a move (measured
/// 2026-10-16) — the everyday case, a scanned sheet carried whole, would
/// drag. Where nothing partly clear meets ink, the landing IS the float's
/// own pixels, so there they are keyed once and carried, and no landing is
/// asked for. Whether each is the same bytes as its landing is the app's
/// own pin (`a_float_on_a_keyed_row_shows_what_it_lands_as_test`); this one
/// pins which way each takes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canvasSize = CanvasSize(width: 128, height: 128);
  const tile = defaultCelTileSize;
  const side = 32;
  final keys = [
    ResolvedLayerEffect(
      kind: EffectKind.colorKey,
      values: [0, 0xFF40C060, 10, 100],
    ),
  ];

  /// A cel of one tile at the canvas's corner, a [side]² of it all [alpha].
  BitmapSurface tileOf(int alpha) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tile,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: tile,
        pixels: Uint8List.fromList([
          for (var y = 0; y < tile; y += 1)
            for (var x = 0; x < tile; x += 1)
              ...(x < side && y < side ? [64, 192, 96, alpha] : [0, 0, 0, 0]),
        ]),
      ),
    },
  );

  /// The stamp a float of [width]² shows, its pixels all of [alpha].
  BrushDab stampOf(int width, int alpha) => BrushDab(
    center: CanvasPoint(x: 24, y: 24),
    color: 0xFFFFFFFF,
    size: 1,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
    stamp: BrushStampImage(
      id: 'float-$width-$alpha',
      width: width,
      height: width,
      rgba: Uint8List.fromList([
        for (var i = 0; i < width * width; i += 1) ...[64, 192, 96, alpha],
      ]),
    ),
  );

  /// A float of [alpha] carried to (8, 8)–(40, 40) over [holed] — its own
  /// surface, or [resampled] for a warp.
  ({SelectionFloatPaint float, _Cel cel}) floatOver(
    BitmapSurface holed, {
    int alpha = 255,
    bool onCanvasGrid = true,
    bool resampled = false,
  }) {
    final cel = _Cel(holed, onCanvasGrid: onCanvasGrid);
    final stamp = stampOf(side, alpha);
    final float = resampled
        ? SelectionFloatPaint(
            resampled: FloatResampleShown.of(stamp),
            lands: (stamp: stamp, on: cel),
          )
        : SelectionFloatPaint(
            surface: floatPainter(tileOf(alpha)),
            surfaceOffset: CanvasPoint(x: 8, y: 8),
            lands: (stamp: stamp, on: cel),
          );
    return (float: float, cel: cel);
  }

  final empty = BitmapSurface(canvasSize: canvasSize, tileSize: tile);

  /// The alpha [preview] draws at ([x], [y]) of the canvas, over nothing.
  Future<int> alphaAt(LandingPreview preview, int x, int y) async {
    final recorder = PictureRecorder();
    preview.paintInto(Canvas(recorder), pixelRatio: 1);
    final picture = recorder.endRecording();
    final image = await picture.toImage(canvasSize.width, canvasSize.height);
    picture.dispose();
    final bytes = (await image.toByteData())!;
    image.dispose();
    return bytes.getUint8((y * canvasSize.width + x) * 4 + 3);
  }

  test('an opaque float landing on nothing is its own pixels keyed — no '
      'landing is made, at any place it is carried to', () {
    final (:float, :cel) = floatOver(empty);

    final shown = float.shownOn(keys).preview;

    expect(shown, isNot(same(float)), reason: 'it is keyed');
    expect(shown, isNot(same(_landing)));
    expect(cel.asked, 0);
  });

  test('an opaque float landing on ink is its own pixels keyed too — a '
      'stamp copies an opaque pixel', () {
    final (:float, :cel) = floatOver(tileOf(255));

    expect(float.shownOn(keys).preview, isNot(same(float)));
    expect(cel.asked, 0);
  });

  test('a partly clear float landing on nothing is its own pixels keyed', () {
    final (:float, :cel) = floatOver(empty, alpha: 128);

    expect(float.shownOn(keys).preview, isNot(same(float)));
    expect(cel.asked, 0);
  });

  // ↩️It held the float keyed by its row's keys, keyed again when they
  // changed, until the engine keyed what a hand holds with its row
  // (float-warp-resamples-in-the-c-engine (1), 2026-11-11).
  test('a float its row keys lays its own pixels in place of what it covers, '
      'whatever the keys — the row keys them with the cel', () async {
    final (:float, cel: _) = floatOver(empty);
    final another = [
      ResolvedLayerEffect(
        kind: EffectKind.colorKey,
        values: [0, 0xFFC81414, 10, 100],
      ),
    ];
    final own = float.surface!.surface.tiles;

    for (final rowKeys in [keys, another]) {
      final shown = float.shownOn(rowKeys).preview;
      expect(shown.heldTiles.map((held) => held.tiles), [same(own), same(own)]);
      expect(shown.heldTiles.map((held) => held.laying), [
        isA<LaidErasing>(),
        isA<LaidOver>(),
      ]);
      expect(await alphaAt(shown, 24, 24), 255, reason: 'no key runs here');
    }
  });

  test('a partly clear float landing on ink is the landing — it blends with '
      'what it lands on, and the keys see the blend', () {
    final (:float, :cel) = floatOver(tileOf(255), alpha: 128);

    final shown = float.shownOn(keys);

    expect(shown.preview, same(_landing));
    expect(shown.canvasToRow, isNull, reason: 'the landing is the cel\'s');
    expect(cel.asked, 1);
  });

  test('a float on a posed row is the landing — a rect of the float is no '
      'rect of the cel', () {
    final (:float, :cel) = floatOver(empty, onCanvasGrid: false);

    expect(float.shownOn(keys).preview, same(_landing));
    expect(cel.asked, 1);
  });

  test('🚨a float on a posed row is the landing on a row that keys nothing '
      'too — the pose resamples what lands, and the row the cel again '
      '(flip lane ⓐ-2 · 유저 09-17)', () {
    final (:float, :cel) = floatOver(empty, onCanvasGrid: false);

    expect(float.shownOn(const []).preview, same(_landing));
    expect(cel.asked, 1);
  });

  test('a float a warp resampled is the landing', () {
    final (:float, :cel) = floatOver(empty, resampled: true);

    expect(float.shownOn(keys).preview, same(_landing));
    expect(cel.asked, 1);
  });

  // ↩️🗣️I-132-Q32 b: on a row whose chain ran a plugin at its head a float
  // was the landing, even an opaque one over nothing (the plugin may change
  // the cel anywhere), while that plugin ran on the CPU over the cel alone
  // — until it was a step of the chain, which the engine runs over what
  // floats as over the cel (float-warp-resamples-in-the-c-engine (2),
  // 2026-11-11).
  test('on a row whose chain runs a plugin, a float is what its keys alone '
      'make it — the row asks it through its leading keys', () {
    final (:float, :cel) = floatOver(empty);
    CanvasActiveLayerRow rowOf(List<ResolvedLayerEffect> effects) =>
        CanvasActiveLayerRow(opacity: 1, effects: effects);

    expect(
      float.shownOn(rowOf([shiftingFxPluginEffect()]).sourceEffects).preview,
      same(float),
    );
    expect(
      float
          .shownOn(rowOf([...keys, shiftingFxPluginEffect()]).sourceEffects)
          .preview,
      isNot(same(_landing)),
      reason: 'opaque over nothing, its own pixels in place of what it covers',
    );
    expect(cel.asked, 0);
  });

  test('⛔CONTROL: on a row that keys nothing, a float is itself', () {
    final (:float, :cel) = floatOver(tileOf(255), alpha: 128);

    expect(float.shownOn(const []).preview, same(float));
    expect(cel.asked, 0);
  });

  test('a key that takes nothing away (amount 0) keys nothing — a float on '
      'its row is itself', () {
    final (:float, :cel) = floatOver(tileOf(255), alpha: 128);
    final idle = [
      ResolvedLayerEffect(
        kind: EffectKind.colorKey,
        values: [0, 0xFF40C060, 10, 0],
      ),
    ];

    expect(float.shownOn(idle).preview, same(float));
    expect(cel.asked, 0);
  });

  test('⛔CONTROL: a float the session holds no hole for is itself', () {
    final (:float, :cel) = floatOver(empty);
    cel.holed = null;

    expect(float.shownOn(keys).preview, same(float));
    expect(cel.asked, 0);
  });

  test('every way a float is shown cuts its edge on the DEVICE\'s grid — at '
      'a ratio of 2, through the surface it floats over too', () async {
    // the-walk-draws-off-the-grid-on-impeller (10-28): a float is laid on
    // the screen under a view at 110% off the grid, recorded in logical
    // pixels and laid on the device's as the engine's root lays it. At
    // (8, 8)–(40, 40) its edges fall at device 28.2 · 98.6 and 24.2 · 94.6;
    // cut on the logical grid instead, the far ones would land a device
    // pixel short.
    final (:float, cel: _) = floatOver(empty);
    final another = [
      ResolvedLayerEffect(
        kind: EffectKind.colorKey,
        values: [0, 0xFFC81414, 10, 100],
      ),
    ];
    final keyed = float.shownOn(another).preview;
    expect(keyed, isNot(same(float)), reason: '⛔premise: it is keyed');
    for (final (route, paint) in <(String, void Function(Canvas))>[
      ('itself', (canvas) => float.paintInto(canvas, pixelRatio: 2)),
      ('keyed', (canvas) => keyed.paintInto(canvas, pixelRatio: 2)),
      (
        'a text in hand',
        (canvas) => CelTextFloat(
          held: float,
          above: null,
        ).paintInto(canvas, pixelRatio: 2),
      ),
      (
        'over a surface',
        (canvas) => floatPainter(empty).paintContentInto(
          canvas,
          pixelRatio: 2,
          float: (preview: float, canvasToRow: null),
        ),
      ),
    ]) {
      final recorder = PictureRecorder();
      paint(
        Canvas(recorder, const Rect.fromLTWH(0, 0, 64, 64))
          ..translate(5.3, 3.3)
          ..scale(1.1),
      );
      final device = PictureRecorder();
      Canvas(device)
        ..scale(2)
        ..drawPicture(recorder.endRecording());
      final image = await device.endRecording().toImage(128, 128);
      final bytes = (await image.toByteData())!;
      image.dispose();
      for (var y = 0; y < 128; y += 1) {
        for (var x = 0; x < 128; x += 1) {
          final inside = x >= 28 && x <= 98 && y >= 24 && y <= 94;
          expect(
            bytes.getUint8((y * 128 + x) * 4 + 3),
            inside ? 255 : 0,
            reason: '$route ($x,$y): wholly the float inside the '
                'pixel-centre cut on the device\'s grid, nothing past it',
          );
        }
      }
    }
  });
}

/// What the cel's landing would show — one object, so a test can tell it
/// from anything else.
final LandingPreview _landing = _Landing();

class _Landing implements LandingPreview {
  @override
  Rect get drawnWorldRect => const Rect.fromLTWH(8, 8, 32, 32);

  @override
  void paintInto(Canvas canvas, {required double pixelRatio}) {}

  @override
  List<HeldTiles> get heldTiles => const [];
}

/// A cel under a float, counting the landings it is asked for.
class _Cel implements FloatLandsOn {
  _Cel(this.holed, {required this.onCanvasGrid});

  @override
  BitmapSurface? holed;

  @override
  final bool onCanvasGrid;

  int asked = 0;

  @override
  LandingPreview? landingShown(BrushDab stamp) {
    asked += 1;
    return _landing;
  }
}
