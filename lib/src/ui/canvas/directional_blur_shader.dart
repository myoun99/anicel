import 'dart:ui' as ui;

import '../../services/directional_blur_passes.dart';

/// The fragment program one pass of a directional blur runs
/// (`shaders/directional_blur.frag`) — a raster of its own at the identity,
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

  /// A shader that draws [pass] over [source] for every pixel of a [width]
  /// x [height] draw.
  ///
  /// ⚠️The caller owns the returned shader and must `dispose()` it after the
  /// draw that used it is recorded.
  static ui.FragmentShader shaderFor({
    required ui.Image source,
    required LineBoxPass pass,
    required double width,
    required double height,
  }) {
    final program = _program;
    if (program == null) {
      throw StateError(
        'DirectionalBlurShader.load() has not completed. A composite that '
        'reached a directional blur with no program would have to drop the '
        'effect, so the load is a prerequisite of offering it at all.',
      );
    }
    // ⛔Indices are declaration order, floats only — a sampler takes no
    // float slot.
    return program.fragmentShader()
      ..setFloat(0, width)
      ..setFloat(1, height)
      ..setFloat(2, pass.stepX)
      ..setFloat(3, pass.stepY)
      ..setFloat(4, pass.taps.toDouble())
      // Between texels, as a tap a fraction of a pixel along the line
      // lands: a step under one pixel weighs the two it falls between.
      ..setImageSampler(0, source, filterQuality: ui.FilterQuality.low);
  }
}
