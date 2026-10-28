import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../services/directional_blur_passes.dart';

/// The fragment program one pass of a blur along a way runs — a
/// directional blur's line, a radial blur's circle or ray ([LineBoxPass],
/// `shaders/directional_blur.frag`) — a raster of its own at the identity,
/// as a colour key is ([applyEffectSteps], `ShadedEffect`).
class DirectionalBlurShader {
  DirectionalBlurShader._();

  static const String assetKey = 'shaders/directional_blur.frag';

  static ui.FragmentProgram? _program;

  /// Whether [shaderFor] can be called. False until [load] completes.
  static bool get isReady => _program != null;

  /// Loads the program. Idempotent; safe to call from app start and from a
  /// test's setUp.
  static Future<void> load() async {
    _program ??= await ui.FragmentProgram.fromAsset(assetKey);
  }

  /// A shader that draws [pass] over [source] for every pixel of a draw
  /// [source]'s size.
  ///
  /// ⚠️The caller owns the returned shader and must `dispose()` it after the
  /// draw that used it is recorded.
  static ui.FragmentShader shaderFor({
    required ui.Image source,
    required LineBoxPass pass,
  }) {
    final program = _program;
    if (program == null) {
      throw StateError(
        'DirectionalBlurShader.load() has not completed. A composite that '
        'reached a directional blur with no program would have to drop the '
        'effect, so the load is a prerequisite of offering it at all.',
      );
    }
    final first = _mapOf(pass, -(pass.taps - 1) / 2);
    final each = _mapOf(pass, 1);
    // ⛔Indices are declaration order, floats only — a sampler takes no
    // float slot.
    final shader = program.fragmentShader()
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
