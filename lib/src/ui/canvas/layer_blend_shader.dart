import 'dart:ui' as ui;

import '../../models/layer_blend_mode.dart';
import '../../services/brush_stroke_blend.dart';
import 'loaded_fragment_program.dart';

/// 🚨★★★ONE BLEND, TWO PROCESSORS (brush-fidelity-Q4, 유저 2026-10-17
/// 「레이어까지 같이」).
///
/// A BRUSH in multiply, linear burn, hue … lands on a cel's bytes, where the
/// pixels are Dart's: [blendStrokeRegionPixels], on the CPU. A LAYER in one
/// is composed over everything below it — a composite, whose pixels only
/// ever exist on the GPU. So the layer's road draws a picture of the
/// backdrop and hands both pictures to `shaders/layer_blend.frag`, which
/// takes the CPU's formulas of the same bytes;
/// `test/ui/canvas/one_blend_two_processors_test.dart` sweeps the pair. Why
/// none of them is left to the GPU's own blend is the shader's header.
///
/// ⛔NOT a fallback pair, as the colour key's two are not: each runs where
/// its pixels are, and neither is the other's stand-in.
class LayerBlendShader {
  LayerBlendShader._();

  static final _program = LoadedFragmentProgram(
    'shaders/layer_blend.frag',
    whyAwaited:
        'A layer in an advanced blend cannot be drawn without it — drawn in '
        'some other blend it would be the screen lying about the file — so '
        'the load is a prerequisite of offering those blends at all.',
  );

  /// Whether [shaderFor] can be called ([LoadedFragmentProgram.isReady]).
  static bool get isReady => _program.isReady;

  /// Loads the program ([LoadedFragmentProgram.load]).
  static Future<void> load() => _program.load();

  /// Releases the loaded program so a test can prove the unloaded path.
  static void debugUnload() => _program.debugUnload();

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
        'is laid by the GPU where it draws — composing it here would draw '
            'it in the shader\'s default, the backdrop',
      );
    }
    final shader = _program.shader();
    // ⛔Indices are declaration order, floats only — a sampler takes no float
    // slot, and getting this wrong does not throw.
    shader.setFloat(0, width);
    shader.setFloat(1, height);
    shader.setFloat(2, _nativeId(mode).toDouble());
    shader.setImageSampler(0, backdrop);
    shader.setImageSampler(1, source);
    return shader;
  }

  /// [shaderFor] as an image filter's (`ui.ImageFilter.shader`): the ENGINE
  /// binds the layer filtered — the backdrop, drawn into it — to the first
  /// sampler and that layer's size to `uSize`; [source] is the second.
  ///
  /// ⚠️The first sampler is handed [source] only so that none is left unset;
  /// the engine binds the layer over it.
  static ui.FragmentShader filterFor({
    required ui.Image source,
    required LayerBlendMode mode,
  }) => shaderFor(
    backdrop: source,
    source: source,
    mode: mode,
    width: source.width.toDouble(),
    height: source.height.toDouble(),
  );

  /// The kernel's own id for [mode] — the table the brush's C and Dart read.
  static int _nativeId(LayerBlendMode mode) => switch (mode.separable) {
    final separable? => separableBlendModeNativeId(separable),
    null => nonSeparableBlendModeNativeId(mode.nonSeparable!),
  };
}
