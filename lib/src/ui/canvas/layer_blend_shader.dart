import 'dart:ui' as ui;

import '../../models/layer_blend_mode.dart';
import '../../services/brush_stroke_blend.dart';

/// 🚨★★★ONE BLEND, TWO PROCESSORS (brush-fidelity-Q4, 유저 2026-10-17
/// 「레이어까지 같이」).
///
/// A BRUSH in linear burn, divide, darker colour … lands on a cel's bytes,
/// where the pixels are Dart's: [blendStrokeRegionPixels], on the CPU. A
/// LAYER in one is composed over everything below it — a composite, whose
/// pixels only ever exist on the GPU, and the GPU has no blend for these
/// modes. So the layer's road draws a picture of the backdrop and hands both
/// pictures to `shaders/layer_blend.frag`, which takes the CPU's formulas of
/// the same bytes; `test/ui/canvas/one_blend_two_processors_test.dart`
/// sweeps the pair.
///
/// ⛔NOT a fallback pair, as the colour key's two are not: each runs where
/// its pixels are, and neither is the other's stand-in.
///
/// ⚠️The second program loader after `ColourKeyShader`, the same few lines.
/// Not merged, by the rule of three — a third shader merges them.
class LayerBlendShader {
  LayerBlendShader._();

  static const String assetKey = 'shaders/layer_blend.frag';

  static ui.FragmentProgram? _program;

  /// Whether [shaderFor] can be called. False until [load] completes.
  ///
  /// ⚠️`FragmentProgram.fromAsset` is async and a paint is not, so the
  /// program has to be in hand before the first frame: a composite that
  /// reached such a layer with no program would have to draw it in some
  /// other blend, and that is the screen lying about the file.
  static bool get isReady => _program != null;

  /// Loads the program. Idempotent; safe to call from app start and from a
  /// test's setUp.
  static Future<void> load() async {
    _program ??= await ui.FragmentProgram.fromAsset(assetKey);
  }

  /// Releases the loaded program so a test can prove the unloaded path.
  static void debugUnload() {
    _program = null;
  }

  /// A shader that composes [source] over [backdrop] through [mode] for
  /// every pixel of a [width] x [height] draw — both pictures on that grid,
  /// premultiplied, as a raster is.
  ///
  /// ⚠️The caller owns the returned shader and must `dispose()` it after the
  /// draw that used it is recorded.
  static ui.FragmentShader shaderFor({
    required ui.Image backdrop,
    required ui.Image source,
    required LayerBlendMode mode,
    required double width,
    required double height,
  }) {
    if (!mode.needsItsBackdrop) {
      throw ArgumentError.value(
        mode,
        'mode',
        'has a GPU blend of its own — composing it here would draw it in the '
            'shader\'s default, the backdrop',
      );
    }
    final program = _program;
    if (program == null) {
      throw StateError(
        'LayerBlendShader.load() has not completed. A layer whose blend the '
        'GPU lacks cannot be drawn without it, so the load is a prerequisite '
        'of offering those blends at all.',
      );
    }
    final shader = program.fragmentShader();
    // ⛔Indices are declaration order, floats only — a sampler takes no float
    // slot, and getting this wrong does not throw.
    shader.setFloat(0, width);
    shader.setFloat(1, height);
    shader.setFloat(2, _nativeId(mode).toDouble());
    shader.setImageSampler(0, backdrop);
    shader.setImageSampler(1, source);
    return shader;
  }

  /// The kernel's own id for [mode] — the table the brush's C and Dart read.
  static int _nativeId(LayerBlendMode mode) => switch (mode.separable) {
    final separable? => separableBlendModeNativeId(separable),
    null => nonSeparableBlendModeNativeId(mode.nonSeparable!),
  };
}
