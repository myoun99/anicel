import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show Offset, TextureLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/ui/engine_screen_texture.dart';

import '../helpers/a_shown_surface.dart';

/// 🚨A FRAME THE GPU CANNOT FINISH LEAVES THE SCREEN AS IT STOOD, AND SAYS
/// SO BY NAME (관제 2026-11-08: 「멈춘 화면보다 이름 있는 실패」): paint goes
/// on, the layer shows the frame last shown and not the one that failed, and
/// the failure is reported as what it is.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const stillShown = 3;
  const failed = 4;
  final opener = debugOpenEngineScreen;
  final reportTo = FlutterError.onError;
  late GpuSurface surface;
  late EngineScreenTexture screen;
  final reported = <FlutterErrorDetails>[];

  setUp(() async {
    await openAppGpuEngine();
    reported.clear();
    FlutterError.onError = reported.add;
    debugOpenEngineScreen = (_, width, height) async {
      surface = shownSurfaceOf(width, height);
      return ScreenTexture.debugOnSurface(
        surface,
        id: stillShown,
        nextId: failed,
      );
    };
    screen = EngineScreenTexture(
      asks: () => true,
      opened: (_) {},
      letGo: () {},
      putUp: ({required behind}) {},
    )..wanted = (4, 4);
    await screen.open();
  });
  tearDown(() {
    FlutterError.onError = reportTo;
    debugOpenEngineScreen = opener;
    screen.stop();
    surface.free();
  });

  TextureLayer presented(void Function() draw) =>
      screen.presented(
            (_, _) => draw(),
            offset: Offset.zero,
            devicePixelRatio: 1,
          )
          as TextureLayer;

  test('a frame that failed is shown as the one before it, by name', () {
    final failure = StateError('the GPU did not finish within 30s');

    final layer = presented(() => throw failure);

    expect(layer.textureId, stillShown);
    expect(reported.map((details) => details.exception), [failure]);
  });

  test('a frame that finished is shown by its own texture', () {
    final layer = presented(() {});

    expect(layer.textureId, failed);
    expect(reported, isEmpty);
  });
}
