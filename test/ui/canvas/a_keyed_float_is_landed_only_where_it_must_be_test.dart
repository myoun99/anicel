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
import 'package:anicel/src/ui/canvas/landing_preview.dart';
import 'package:anicel/src/ui/canvas/selection_float_overlay.dart';

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
  const tile = 32;
  final keys = [
    ResolvedLayerEffect(
      kind: EffectKind.deleteColor,
      values: [64, 192, 96, 10, 100],
    ),
  ];

  /// A cel of one tile at the canvas's corner, every pixel of it [alpha].
  BitmapSurface tileOf(int alpha) => BitmapSurface(
    canvasSize: canvasSize,
    tileSize: tile,
    tiles: {
      TileCoord(x: 0, y: 0): BitmapTile(
        size: tile,
        pixels: Uint8List.fromList([
          for (var i = 0; i < tile * tile; i += 1) ...[64, 192, 96, alpha],
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
  /// surface, or [image] for a warp.
  ({SelectionFloatPaint float, _Cel cel}) floatOver(
    BitmapSurface holed, {
    int alpha = 255,
    bool onCanvasGrid = true,
    bool image = false,
  }) {
    final cel = _Cel(holed, onCanvasGrid: onCanvasGrid);
    final stamp = stampOf(tile, alpha);
    final float = image
        ? SelectionFloatPaint(
            image: _image,
            imageLeft: 8,
            imageTop: 8,
            lands: (stamp: stamp, on: cel),
          )
        : SelectionFloatPaint(
            surface: floatPainter(tileOf(alpha), const []),
            surfaceOffset: CanvasPoint(x: 8, y: 8),
            lands: (stamp: stamp, on: cel),
          );
    return (float: float, cel: cel);
  }

  final empty = BitmapSurface(canvasSize: canvasSize, tileSize: tile);

  /// The alpha [preview] draws at ([x], [y]) of the canvas, over nothing.
  Future<int> alphaAt(LandingPreview preview, int x, int y) async {
    final recorder = PictureRecorder();
    preview.paintInto(Canvas(recorder));
    final picture = recorder.endRecording();
    final image = await picture.toImage(canvasSize.width, canvasSize.height);
    picture.dispose();
    final bytes = (await image.toByteData())!;
    image.dispose();
    return bytes.getUint8((y * canvasSize.width + x) * 4 + 3);
  }

  setUpAll(() async {
    _image = await _imageOf(tile);
  });

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

  test('a float keyed once is keyed again when its row keys another colour '
      '— and by the first keys when they come back', () async {
    final (:float, cel: _) = floatOver(empty);
    final another = [
      ResolvedLayerEffect(
        kind: EffectKind.deleteColor,
        values: [200, 20, 20, 10, 100],
      ),
    ];

    final away = await alphaAt(float.shownOn(keys).preview, 24, 24);
    final kept = await alphaAt(float.shownOn(another).preview, 24, 24);
    final awayAgain = await alphaAt(float.shownOn(keys).preview, 24, 24);

    expect(away, 0, reason: 'its own colour is keyed away');
    expect(kept, 255, reason: 'another colour keyed leaves it be');
    expect(awayAgain, 0);
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

  test('a float a warp resampled is the landing', () {
    final (:float, :cel) = floatOver(empty, image: true);

    expect(float.shownOn(keys).preview, same(_landing));
    expect(cel.asked, 1);
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
        kind: EffectKind.deleteColor,
        values: [64, 192, 96, 10, 0],
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
}

late Image _image;

Future<Image> _imageOf(int size) async {
  final recorder = PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0xFF40C060),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  return image;
}

/// What the cel's landing would show — one object, so a test can tell it
/// from anything else.
final LandingPreview _landing = _Landing();

class _Landing implements LandingPreview {
  @override
  Rect get drawnWorldRect => const Rect.fromLTWH(8, 8, 32, 32);

  @override
  void paintInto(Canvas canvas) {}
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
  LandingPreview? landingShown(
    BrushDab stamp,
    List<ResolvedLayerEffect> keys,
  ) {
    asked += 1;
    return _landing;
  }
}
