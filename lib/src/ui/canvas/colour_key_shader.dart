import 'dart:ui' as ui;

import '../../services/cel_source_effect_pass.dart';
import 'loaded_fragment_program.dart';

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

  static final _program = LoadedFragmentProgram(
    'shaders/colour_key.frag',
    whyAwaited:
        'A composite that reached a colour key with no program would have '
        'to drop the effect, so the load is a prerequisite of offering the '
        'effect at all.',
  );

  /// Whether [shaderFor] can be called ([LoadedFragmentProgram.isReady]).
  static bool get isReady => _program.isReady;

  /// Loads the program ([LoadedFragmentProgram.load]).
  static Future<void> load() => _program.load();

  /// Releases the loaded program so a test can prove the unloaded path.
  static void debugUnload() => _program.debugUnload();

  /// A shader that reads [source] and answers [key] for every pixel of a
  /// draw [source]'s size, 1:1 at the identity ([applyEffectSteps]),
  /// [original] being its run's input — [source] itself for the run's first
  /// key ([CelColorKey.alphaFor]).
  ///
  /// ⚠️The caller owns the returned shader and must `dispose()` it after the
  /// draw that used it is recorded.
  static ui.FragmentShader shaderFor({
    required ui.Image source,
    required ui.Image original,
    required CelColorKey key,
  }) {
    // The button's 색 유지 edits bytes through its own kernel; no chain
    // holds a key that erases what its colour does not name.
    assert(key.operation != CelKeyOperation.eraseOthers);
    final shader = _program.shader();
    // ⛔Indices are declaration order, floats only — a sampler takes no float
    // slot. Getting this wrong does not throw; it silently keys on the wrong
    // numbers, which is why the proof sweeps values rather than trusting the
    // layout.
    shader.setFloat(0, source.width.toDouble());
    shader.setFloat(1, source.height.toDouble());
    shader.setFloat(2, key.red.toDouble());
    shader.setFloat(3, key.green.toDouble());
    shader.setFloat(4, key.blue.toDouble());
    shader.setFloat(5, key.tolerance.toDouble());
    shader.setFloat(6, key.amount);
    shader.setFloat(
      7,
      key.operation == CelKeyOperation.restoreMatches ? 1 : 0,
    );
    shader.setImageSampler(0, source);
    shader.setImageSampler(1, original);
    return shader;
  }
}
