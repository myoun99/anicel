import 'dart:ui' as ui;

import '../../services/cel_source_effect_pass.dart';

/// 🚨★★★ONE COLOUR KEY, TWO PROCESSORS.
///
/// The BUTTON edits cel bytes, where the pixels are Dart's and the answer has
/// to survive an undo that replays positionally — that is [CelColorKey], on
/// the CPU. The FX keys a COMPOSITED picture, where the pixels only ever
/// exist on the GPU: reading them back to key them in Dart would be an async
/// round trip per frame.
///
/// So there are two implementations, and the contract is that they agree BIT
/// FOR BIT on the same input. `shaders/colour_key.frag` mirrors
/// [CelColorKey.matches], [CelColorKey.erases] and [CelColorKey.alphaFor]
/// line for line, and `test/ui/canvas/one_colour_key_two_processors_test.dart`
/// sweeps the whole decision domain rather than sampling it.
///
/// ⛔NOT a fallback pair. This is not "GPU when available, CPU otherwise" —
/// each runs where its pixels are, and neither is the other's stand-in.
class ColourKeyShader {
  ColourKeyShader._();

  static const String assetKey = 'shaders/colour_key.frag';

  static ui.FragmentProgram? _program;

  /// Whether [shaderFor] can be called. False until [load] completes.
  ///
  /// ⚠️`FragmentProgram.fromAsset` is async and a paint is not, so the
  /// program has to be in hand before the first frame that needs it. A
  /// composite that reached a colour key with no program would have to drop
  /// the effect, and a dropped effect is the screen lying about the file.
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

  /// A shader that reads [source] and answers [key] for every pixel of a
  /// [width] x [height] draw.
  ///
  /// ⚠️The caller owns the returned shader and must `dispose()` it after the
  /// draw that used it is recorded.
  static ui.FragmentShader shaderFor({
    required ui.Image source,
    required CelColorKey key,
    required double width,
    required double height,
  }) {
    final program = _program;
    if (program == null) {
      throw StateError(
        'ColourKeyShader.load() has not completed. A composite that reached a '
        'colour key with no program would have to drop the effect, so the '
        'load is a prerequisite of offering the effect at all.',
      );
    }
    final shader = program.fragmentShader();
    // ⛔Indices are declaration order, floats only — a sampler takes no float
    // slot. Getting this wrong does not throw; it silently keys on the wrong
    // numbers, which is why the proof sweeps values rather than trusting the
    // layout.
    shader.setFloat(0, width);
    shader.setFloat(1, height);
    shader.setFloat(2, key.red.toDouble());
    shader.setFloat(3, key.green.toDouble());
    shader.setFloat(4, key.blue.toDouble());
    shader.setFloat(5, key.tolerance.toDouble());
    shader.setFloat(6, key.amount);
    shader.setFloat(7, key.keepsMatches ? 1 : 0);
    shader.setImageSampler(0, source);
    return shader;
  }
}
