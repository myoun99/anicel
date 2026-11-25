import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/screen_texture.dart';

/// [ScreenTexture.path]: the way a screen opened reaches Flutter's — the
/// engine's own words ([GpuEngine.screenSaid]) — and, where it could not
/// open, the refusal's (card the-galaxy-tab-canvas-went-slow-on-build-1095
/// ⓑ: why not, read off the device).
void main() {
  tearDown(() => ScreenTexture.debugPathIs(''));

  test('a screen refused says the way and the refusal\'s own words, and '
      'stands for none', () async {
    final said = appGpuEngine.screenSaid;
    expect(said, isNotEmpty, reason: '⛔premise: the engine says its way');

    final opening = ScreenTexture.open(appGpuEngine, 0, 0);

    final refused = await opening.then<GpuRefused?>(
      (_) => null,
      onError: (Object error) => error as GpuRefused,
    );
    expect(refused, isNotNull, reason: 'no 0 × 0 screen is made');
    expect(ScreenTexture.path, '$said  refused: ${refused!.message}');
    expect(ScreenTexture.engineOfThePath, same(appGpuEngine));
  });
}
