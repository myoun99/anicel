import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/ui/canvas/colour_key_shader.dart';
import 'package:anicel/src/ui/playback/playback_frame_painter.dart';
import 'package:anicel/src/ui/track_effect_paint_policy.dart';

/// 🚨★★★A TRACK'S CHAIN IS A PLAN, LIKE EVERY OTHER ROW'S.
///
/// The V row's policy used to hand back a resolved `CompositeEffectPaint`.
/// A colour key has no paint form — it is a threshold, and a threshold has no
/// colour matrix — so `resolveCompositeEffectPaint` REFUSES one by assert. A
/// track chain with a key in it therefore threw, exactly as the live layer's
/// did until #1314.
///
/// ⛔"NO CALLER" IS NOT A DESIGN. It was unreachable only because the fx menu
/// adds to the active layer and nothing calls `addEffectToTrack`. The next
/// round to add that menu would have shipped an assert.
///
/// 🧪ASKED OF THE PIXELS, not of the plan: a unit test that the plan has a
/// step passes on a painter that ignores the step. This paints a white cut
/// through a track chain that keys white away, and counts what survives.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(ColourKeyShader.load);

  const canvasSize = CanvasSize(width: 16, height: 16);

  LayerEffect deleteWhite() => LayerEffect(
    id: const EffectId('fx-key'),
    kind: EffectKind.deleteColor,
    parameters: {
      'keyRed': EffectParameter(value: 255),
      'keyGreen': EffectParameter(value: 255),
      'keyBlue': EffectParameter(value: 255),
      'tolerance': EffectParameter(value: 0),
      'amount': EffectParameter(value: 100),
    },
  );

  /// A finished cut picture: white, edge to edge.
  ui.Image whiteCut() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 16, 16),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..isAntiAlias = false,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(16, 16);
    picture.dispose();
    return image;
  }

  Future<int> opaquePixels(
    WidgetTester tester,
    List<LayerEffect> trackChain,
  ) async {
    final composite = whiteCut();
    addTearDown(composite.dispose);
    final painter = PlaybackFramePainter(
      image: composite,
      canvasSize: canvasSize,
      cutEffects: trackEffectsAt(trackChain, 0),
      paintPaper: false,
    );
    const size = Size(16, 16);
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder, Offset.zero & size), size);
    final picture = recorder.endRecording();
    final out = picture.toImageSync(16, 16);
    picture.dispose();
    final bytes = await tester.runAsync(
      () => out.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    out.dispose();
    final list = bytes!.buffer.asUint8List();
    var n = 0;
    for (var i = 3; i < list.length; i += 4) {
      if (list[i] != 0) {
        n += 1;
      }
    }
    return n;
  }

  testWidgets('a colour key on a TRACK erases what it names', (tester) async {
    final plain = await opaquePixels(tester, const []);
    expect(plain, greaterThan(0), reason: 'fixture: the cut drew');

    final keyed = await opaquePixels(tester, [deleteWhite()]);
    expect(
      keyed,
      0,
      reason: 'the V row keyed the picture it composited — before this the '
          'same chain threw on the way to a paint',
    );
  });

  testWidgets('a track chain WITHOUT a key still draws in one pass', (
    tester,
  ) async {
    // ⛔The control: the plan's fast path must stay fast. A chain with no key
    // is one draw, exactly as it always was, and the cut's own image is what
    // reaches the canvas — no raster, nothing to dispose.
    final darkened = await opaquePixels(tester, [
      LayerEffect(
        id: const EffectId('fx-dark'),
        kind: EffectKind.brightnessContrast,
        parameters: {
          'brightness': EffectParameter(value: -0.5),
          'contrast': EffectParameter(value: 0),
        },
      ),
    ]);
    expect(
      darkened,
      greaterThan(0),
      reason: 'a darken keeps every pixel — only a key removes any',
    );
  });

  testWidgets('the painter repaints when the chain changes, and only then', (
    tester,
  ) async {
    // 🚨THE FIELD THE PAINTER DIFFS IS A LIST NOW, so the comparison had to
    // change with it — `!=` on a list is identity, and a chain rebuilt every
    // frame is a new list every frame. 🧪Caught by mutation: neutering this
    // line left every other test green, and what it breaks is an ANIMATED
    // track fx that never reaches the screen.
    final composite = whiteCut();
    addTearDown(composite.dispose);

    PlaybackFramePainter withChain(List<LayerEffect> chain) =>
        PlaybackFramePainter(
          image: composite,
          canvasSize: canvasSize,
          cutEffects: trackEffectsAt(chain, 0),
          paintPaper: false,
        );

    final none = withChain(const []);
    final keyed = withChain([deleteWhite()]);
    expect(
      keyed.shouldRepaint(none),
      isTrue,
      reason: 'adding a colour key changes the picture',
    );
    expect(
      none.shouldRepaint(keyed),
      isTrue,
      reason: 'and removing it changes it back',
    );

    // ⛔EQUAL BUT NOT IDENTICAL: the chain is resolved fresh on every build,
    // so a static grade hands over a NEW list with the same values. Comparing
    // by identity would repaint every frame forever.
    final again = withChain([deleteWhite()]);
    expect(
      identical(again.cutEffects, keyed.cutEffects),
      isFalse,
      reason: 'fixture: two separate resolves',
    );
    expect(
      again.shouldRepaint(keyed),
      isFalse,
      reason: 'a static chain is not a repaint',
    );
  });
}
