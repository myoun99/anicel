import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/services/brush_stroke_blend.dart';
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/canvas/subtree_image_composite.dart';

/// 🚨★★★ONE BLEND, TWO PROCESSORS (brush-fidelity-Q4) — and they agree.
///
/// A brush in multiply, linear burn, hue … lands on a cel's bytes on the
/// CPU ([blendStrokeRegionPixels]); a layer in one is composed over its
/// backdrop on the GPU ([drawBlendOverBackdrop], `layer_blend.frag`), where
/// a composite's pixels are. Two implementations of one blend is a licence
/// to drift, so this does not sample the domain — it SWEEPS it: every source
/// byte over every backdrop byte, for every advanced layer blend, through
/// the very function both walks call.
///
/// 📐WHERE THE TWO MAY PART, AND ONLY THERE. A formula that divides
/// (divide, vivid light) and the composite over partial alpha round a
/// quotient once on the GPU, in a float, where the CPU carries it in a
/// double. Where the exact value lies on a half step — or within a float's
/// reach of one — the two may round it a byte apart. Each such pair is
/// computed here from the exact value and named; a byte apart anywhere
/// else, or more than a byte anywhere, fails.
///
/// ⚠️AT ALPHA 255 premultiplied and straight are the same bytes, so the
/// formulas are swept there; the alpha arithmetic is swept on colours a
/// premultiply carries exactly (0 and 255), over every pair of alphas.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(LayerBlendShader.load);

  const side = 256;

  /// A PREMULTIPLIED image from straight [pixels], as a composite hands one
  /// over.
  Future<ui.Image> imageOf(Uint8List straight) {
    final premultiplied = Uint8List.fromList(straight);
    for (var i = 0; i < premultiplied.length; i += 4) {
      final alpha = premultiplied[i + 3];
      for (var c = 0; c < 3; c += 1) {
        premultiplied[i + c] = (premultiplied[i + c] * alpha + 127) ~/ 255;
      }
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      premultiplied,
      side,
      side,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  /// [source] composed over [backdrop] through [mode] by the walks' own
  /// function, read back as the premultiplied bytes the screen gets.
  Future<Uint8List> composed(
    Uint8List backdrop,
    Uint8List source,
    LayerBlendMode mode,
  ) async {
    final below = await imageOf(backdrop);
    final row = await imageOf(source);
    final recorder = ui.PictureRecorder();
    final whole = Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble());
    drawBlendOverBackdrop(
      canvas: Canvas(recorder),
      bounds: whole,
      rasterScale: 1,
      paintBackdrop: (into, _) => into.drawImage(below, Offset.zero, Paint()),
      paintSource: (into, _) => into.drawImage(row, Offset.zero, Paint()),
      blendMode: mode,
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(side, side);
    picture.dispose();
    below.dispose();
    row.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  /// The brush's mode of the same name — the CPU half of [mode].
  BrushBlendMode brushTwinOf(LayerBlendMode mode) =>
      BrushBlendMode.named(mode.name) ??
      (throw StateError('${mode.name} has no brush twin to agree with'));

  /// How far [exact] lies from the nearest half step, in bytes.
  double offTheHalf(double exact) =>
      (exact - exact.floorToDouble() - 0.5).abs();

  /// The reach of a float's one rounding of a byte-scale value.
  const floatReach = 1e-4;

  final needsItsBackdrop = [
    for (final mode in LayerBlendMode.values)
      if (mode.needsItsBackdrop) mode,
  ];

  test('every advanced blend is swept here', () {
    // Liveness: a list that came back empty would sweep nothing and pass.
    expect(
      needsItsBackdrop.map((mode) => mode.name),
      containsAll(<String>[
        'darken',
        'multiply',
        'colorBurn',
        'lighten',
        'screen',
        'colorDodge',
        'overlay',
        'softLight',
        'hardLight',
        'difference',
        'exclusion',
        'hue',
        'saturation',
        'chroma',
        'luminosity',
        'linearBurn',
        'subtract',
        'vividLight',
        'linearLight',
        'pinLight',
        'hardMix',
        'divide',
        'darkerColor',
        'lighterColor',
      ]),
    );
  });

  group('every source byte over every backdrop byte, at alpha 255', () {
    // x = the source's byte, y = the backdrop's — and the other two
    // channels take the pairs the other way round and mirrored, so a
    // channel the shader reads from the wrong place cannot agree by luck.
    Uint8List sweep({required bool source}) {
      final bytes = Uint8List(side * side * 4);
      for (var y = 0; y < side; y += 1) {
        for (var x = 0; x < side; x += 1) {
          final at = (y * side + x) * 4;
          bytes[at] = source ? x : y;
          bytes[at + 1] = source ? y : x;
          bytes[at + 2] = source ? x : 255 - y;
          bytes[at + 3] = 255;
        }
      }
      return bytes;
    }

    for (final mode in needsItsBackdrop) {
      final twin = brushTwinOf(mode);
      final separable = twin.separable;
      if (separable == null) {
        continue; // The six that mix the channels have their own sweeps.
      }
      test('${mode.name}: the GPU lands what the brush lands', () async {
        final backdrop = sweep(source: false);
        final source = sweep(source: true);
        final gpu = await composed(backdrop, source, mode);
        final cpu = blendStrokeRegionPixels(
          dst: backdrop,
          src: source,
          mode: twin,
          pixelCount: side * side,
        );
        var onTheHalf = 0;
        final apart = <String>[];
        for (var i = 0; i < cpu.length; i += 1) {
          if (gpu[i] == cpu[i]) {
            continue;
          }
          final pixel = i - i % 4;
          final exact =
              blendSeparableChannel(
                separable,
                source[i] / 255,
                backdrop[i] / 255,
              ) *
              255;
          if (i % 4 != 3 &&
              (gpu[i] - cpu[i]).abs() == 1 &&
              offTheHalf(exact) < floatReach) {
            onTheHalf += 1;
            continue;
          }
          apart.add(
            'pixel ${pixel ~/ 4} channel ${i % 4}: source ${source[i]} over '
            '${backdrop[i]} — GPU ${gpu[i]}, CPU ${cpu[i]} (exact $exact)',
          );
        }
        expect(
          apart,
          isEmpty,
          reason: 'a byte apart is allowed only ON a half step',
        );
        // The pairs that may part, named by count: a formula with no
        // quotient has none to name.
        printOnFailure('${mode.name}: $onTheHalf pairs on a half step');
      });
    }
  });

  test('darker and lighter colour take the whole colour whose total is '
      'lower / higher, and a tie keeps the backdrop', () async {
    // Totals x against y, the tie down the diagonal; the colours are
    // different channels so a mixed answer cannot pass for either one.
    final source = Uint8List(side * side * 4);
    final backdrop = Uint8List(side * side * 4);
    for (var y = 0; y < side; y += 1) {
      for (var x = 0; x < side; x += 1) {
        final at = (y * side + x) * 4;
        source[at] = x;
        source[at + 3] = 255;
        backdrop[at + 1] = y;
        backdrop[at + 3] = 255;
      }
    }
    for (final mode in [
      LayerBlendMode.darkerColor,
      LayerBlendMode.lighterColor,
    ]) {
      final gpu = await composed(backdrop, source, mode);
      final cpu = blendStrokeRegionPixels(
        dst: backdrop,
        src: source,
        mode: brushTwinOf(mode),
        pixelCount: side * side,
      );
      expect(gpu, cpu, reason: '${mode.name}: totals of bytes, no rounding');
      // Liveness: each colour was taken somewhere — a shader that always
      // kept one would agree only where the brush did too.
      var tookTheRow = 0;
      var keptTheBackdrop = 0;
      for (var i = 0; i < gpu.length; i += 4) {
        tookTheRow += gpu[i] > 0 ? 1 : 0;
        keptTheBackdrop += gpu[i + 1] > 0 ? 1 : 0;
      }
      expect(tookTheRow, greaterThan(0));
      expect(keptTheBackdrop, greaterThan(0));
    }
  });

  test('hue, saturation, colour and luminosity: the GPU lands what the brush '
      'lands', () async {
    // 65,536 pairs of colours, every channel moving at its own rate so hue,
    // saturation and luminosity all sweep — greys, primaries and the pairs
    // whose SetLum leaves the cube and is clipped back on either side.
    final source = Uint8List(side * side * 4);
    final backdrop = Uint8List(side * side * 4);
    for (var y = 0; y < side; y += 1) {
      for (var x = 0; x < side; x += 1) {
        final at = (y * side + x) * 4;
        source
          ..[at] = x
          ..[at + 1] = (x * 7) % 256
          ..[at + 2] = (x * 13 + 50) % 256
          ..[at + 3] = 255;
        backdrop
          ..[at] = (y * 11 + 90) % 256
          ..[at + 1] = y
          ..[at + 2] = (y * 5) % 256
          ..[at + 3] = 255;
      }
    }
    for (final mode in [
      LayerBlendMode.hue,
      LayerBlendMode.saturation,
      LayerBlendMode.chroma,
      LayerBlendMode.luminosity,
    ]) {
      final gpu = await composed(backdrop, source, mode);
      final cpu = blendStrokeRegionPixels(
        dst: backdrop,
        src: source,
        mode: brushTwinOf(mode),
        pixelCount: side * side,
      );
      var aByteApart = 0;
      final apart = <String>[];
      for (var i = 0; i < cpu.length; i += 1) {
        final off = (gpu[i] - cpu[i]).abs();
        if (off == 0) {
          continue;
        }
        if (off == 1 && i % 4 != 3) {
          aByteApart += 1;
          continue;
        }
        apart.add(
          'pixel ${i ~/ 4} channel ${i % 4}: GPU ${gpu[i]}, CPU ${cpu[i]}',
        );
      }
      expect(apart, isEmpty, reason: '${mode.name}: never more than a byte');
      printOnFailure('${mode.name}: $aByteApart channels a byte apart');
    }
  });

  test('the composite over every pair of alphas is the brush\'s', () async {
    // Colours a premultiply carries exactly; subtract, whose B on them is
    // 0 or 1: red is a source over none of itself, green a backdrop the
    // source takes nothing from, blue both full.
    final source = Uint8List(side * side * 4);
    final backdrop = Uint8List(side * side * 4);
    for (var y = 0; y < side; y += 1) {
      for (var x = 0; x < side; x += 1) {
        final at = (y * side + x) * 4;
        source
          ..[at] = 255
          ..[at + 2] = 255
          ..[at + 3] = x;
        backdrop
          ..[at + 1] = 255
          ..[at + 2] = 255
          ..[at + 3] = y;
      }
    }
    const mode = LayerBlendMode.subtract;
    final gpu = await composed(backdrop, source, mode);
    final cpu = blendStrokeRegionPixels(
      dst: backdrop,
      src: source,
      mode: brushTwinOf(mode),
      pixelCount: side * side,
    );
    var onTheHalf = 0;
    final apart = <String>[];
    for (var y = 0; y < side; y += 1) {
      for (var x = 0; x < side; x += 1) {
        final at = (y * side + x) * 4;
        // The screen's bytes: the brush's straight answer, premultiplied.
        final alpha = cpu[at + 3];
        for (var c = 0; c < 4; c += 1) {
          final expected = c == 3
              ? alpha
              : (cpu[at + c] * alpha / 255).round();
          if (gpu[at + c] == expected) {
            continue;
          }
          // The composite exactly, in whole numbers: co·255 = P / Q.
          final q = 255 * x + y * (255 - x);
          final p = switch (c) {
            0 => 255 * x * (255 - y),
            1 => 255 * 255 * y,
            _ => 255 * x * (255 - y) + 255 * y * (255 - x),
          };
          if (c != 3 &&
              (gpu[at + c] - expected).abs() == 1 &&
              q > 0 &&
              offTheHalf(p / q) < floatReach) {
            onTheHalf += 1;
            continue;
          }
          apart.add(
            'alphas $x over $y, channel $c: GPU ${gpu[at + c]}, '
            'brush $expected',
          );
        }
      }
    }
    expect(
      apart,
      isEmpty,
      reason: 'a byte apart is allowed only ON a half step',
    );
    printOnFailure('$onTheHalf pairs on a half step');
  });

  test('no row leaves the backdrop exactly as it was, no backdrop leaves the '
      'row exactly as it is', () async {
    // The brush's two verbatim copies: alpha 0 on either side.
    final source = Uint8List(side * side * 4);
    final backdrop = Uint8List(side * side * 4);
    for (var y = 0; y < side; y += 1) {
      for (var x = 0; x < side; x += 1) {
        final at = (y * side + x) * 4;
        source
          ..[at] = x
          ..[at + 1] = 200
          ..[at + 3] = y.isEven ? 0 : 255;
        backdrop
          ..[at] = 255 - x
          ..[at + 2] = 90
          ..[at + 3] = y.isEven ? 255 : 0;
      }
    }
    final gpu = await composed(backdrop, source, LayerBlendMode.divide);
    for (var y = 0; y < side; y += 1) {
      final kept = y.isEven ? backdrop : source;
      final at = y * side * 4;
      expect(
        gpu.sublist(at, at + side * 4),
        kept.sublist(at, at + side * 4),
        reason: y.isEven ? 'nothing over it: the backdrop' : 'nothing under it',
      );
    }
  });

  test('a mode the GPU lays where it draws is refused', () {
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    final picture = recorder.endRecording();
    final blank = picture.toImageSync(1, 1);
    picture.dispose();
    addTearDown(blank.dispose);
    expect(
      () => LayerBlendShader.shaderFor(
        backdrop: blank,
        source: blank,
        mode: LayerBlendMode.add,
        width: 1,
        height: 1,
      ),
      throwsArgumentError,
    );
  });
}
