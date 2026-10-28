import 'dart:ui' as ui;

/// A fragment program a composite draws with, in hand before the first frame
/// that needs it: `FragmentProgram.fromAsset` is async and a paint is not,
/// and a composite that reached its effect with no program would have to
/// drop it or draw it some other way — the screen lying about the file. So
/// the app awaits [load] before its first frame, and a test before its
/// first pump.
///
/// ⛔ONE LOADER. The colour key's, the advanced blends' and the directional
/// blur's each wrote these lines out again; `LayerBlendShader` said a third
/// would merge them (the rule of three), and the third came without it.
/// Merged as the camera lens blur brought two more.
class LoadedFragmentProgram {
  LoadedFragmentProgram(this.assetKey, {required this.whyAwaited});

  /// The program's path under pubspec's `shaders:`.
  final String assetKey;

  /// What a composite would have to do without it — the error's word to a
  /// route that drew before the load.
  final String whyAwaited;

  ui.FragmentProgram? _program;

  /// Whether [shader] can be called. False until [load] completes.
  bool get isReady => _program != null;

  /// Loads the program. Idempotent; safe to call from app start and from a
  /// test's setUp.
  Future<void> load() async {
    _program ??= await ui.FragmentProgram.fromAsset(assetKey);
  }

  /// Releases the loaded program so a test can prove the unloaded path.
  void debugUnload() {
    _program = null;
  }

  /// A fresh shader of the program.
  ///
  /// ⚠️The caller owns it and must `dispose()` it after the draw that used
  /// it is recorded.
  ui.FragmentShader shader() {
    final program = _program;
    if (program == null) {
      throw StateError('$assetKey has not loaded. $whyAwaited');
    }
    return program.fragmentShader();
  }
}
