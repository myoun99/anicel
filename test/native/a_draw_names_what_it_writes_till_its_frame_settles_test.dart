import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/screen_texture.dart';

import '../helpers/a_shown_surface.dart';

/// What a frame's draws wrote of a target is the box round all of them,
/// kept on the target ([GpuSurface.debugChanged]) till it is settled
/// ([GpuSurface.settle]) — and a screen settles each frame it draws, before
/// its done. Where Flutter shows another texture than the one drawn on
/// (an Android device whose AHardwareBuffer images take no stores) that
/// box is what is copied across: a box too small leaves a stale strip on
/// screen, one never cleared copies the whole of every frame since
/// (card the-galaxy-tab-canvas-went-slow-on-build-1095-Q9, 유저
/// 2026-11-23: 「그 기기만 바뀐 곳을 한 번 옮겨 보여 준다」).
void main() {
  late GpuSurface surface;
  late GpuGridLay lay;

  setUp(() {
    surface = shownSurfaceOf(16, 8);
    lay = GpuGridLay(appGpuEngine);
  });
  tearDown(() {
    lay.free();
    surface.free();
  });

  test('a draw names the rect it writes; draws grow the box round them', () {
    expect(surface.debugChanged, isNull, reason: 'nothing drawn yet');

    lay.lay(surface, (2, 1, 5, 3), const []);
    expect(surface.debugChanged, (2, 1, 5, 3));

    lay.lay(surface, (9, 4, 12, 7), const []);
    expect(surface.debugChanged, (2, 1, 12, 7));

    lay.lay(surface, (0, 2, 3, 5), const []);
    expect(surface.debugChanged, (0, 1, 12, 7));
  });

  test('a draw of the whole names the whole', () {
    surface.fill(3);
    expect(surface.debugChanged, (0, 0, 16, 8));
  });

  test('a settle hands the box over and starts the next from none', () {
    lay.lay(surface, (2, 1, 5, 3), const []);
    surface.settle();
    expect(surface.debugChanged, isNull);

    lay.lay(surface, (9, 4, 12, 7), const []);
    expect(surface.debugChanged, (9, 4, 12, 7), reason: 'not the one before');
  });

  test('a screen settles the frame it draws', () {
    final screen = ScreenTexture.debugOnSurface(surface);
    GpuSurface? drawnOn;
    screen.present((next) {
      drawnOn = next;
      lay.lay(next, (2, 1, 5, 3), const []);
    });
    expect(drawnOn, same(surface), reason: '⛔premise: drawn on the surface');
    expect(surface.debugChanged, isNull);
  });
}
