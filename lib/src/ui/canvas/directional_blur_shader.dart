import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../services/shaded_passes.dart';
import 'loaded_fragment_program.dart';

/// The fragment program one pass of a blur along a way runs — a
/// directional blur's line, a radial blur's circle or ray ([LineBoxPass],
/// `shaders/directional_blur.frag`) — in a step's raster at the identity
/// ([applyEffectSteps], `ShadedEffect`): a raster a pass on Skia, a layer's
/// filter a pass on Impeller (`applyEffectSteps`), where the engine
/// binds the layer over [shaderFor]'s source and size.
class DirectionalBlurShader {
  DirectionalBlurShader._();

  static final _program = LoadedFragmentProgram(
    'shaders/directional_blur.frag',
    whyAwaited:
        'A composite that reached a directional or a radial blur with no '
        'program would have to drop the effect, so the load is a '
        'prerequisite of offering it at all.',
  );

  /// Whether [shaderFor] can be called ([LoadedFragmentProgram.isReady]).
  static bool get isReady => _program.isReady;

  /// Loads the program ([LoadedFragmentProgram.load]).
  static Future<void> load() => _program.load();

  /// A shader that draws [pass] over [source] for every pixel of a draw
  /// [source]'s size.
  ///
  /// ⚠️The caller owns the returned shader and must `dispose()` it after the
  /// draw that used it is recorded.
  static ui.FragmentShader shaderFor({
    required ui.Image source,
    required LineBoxPass pass,
  }) {
    final first = _mapOf(pass, -(pass.taps - 1) / 2);
    final each = _mapOf(pass, 1);
    // ⛔Indices are declaration order, floats only — a sampler takes no
    // float slot.
    final shader = _program.shader()
      ..setFloat(0, source.width.toDouble())
      ..setFloat(1, source.height.toDouble())
      ..setFloat(2, pass.stepX)
      ..setFloat(3, pass.stepY)
      ..setFloat(4, pass.taps.toDouble())
      ..setFloat(5, pass.centerX)
      ..setFloat(6, pass.centerY);
    for (final (index, value) in [...first, ...each].indexed) {
      shader.setFloat(7 + index, value);
    }
    // Between texels, as a tap a fraction of a pixel along the way lands:
    // a step under one pixel weighs the two it falls between.
    return shader
      ..setImageSampler(0, source, filterQuality: ui.FilterQuality.low);
  }

  /// [taps] taps of [pass]'s turn and scale, as the columns of their 2×2
  /// map — the identity on a line, whose taps turn and grow by nothing.
  static List<double> _mapOf(LineBoxPass pass, double taps) {
    final scale = math.exp(pass.grow * taps);
    final angle = pass.turn * taps;
    final (cos, sin) = (math.cos(angle) * scale, math.sin(angle) * scale);
    return [cos, sin, -sin, cos];
  }
}
