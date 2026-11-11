import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/screen_texture.dart';
import 'package:anicel/src/ui/engine_screen_texture.dart';

import '../helpers/a_shown_surface.dart';
import '../helpers/the_apps_engine_let_go.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — what stands on a screen of what
/// the app's engine made is told that the engine was let go, and of the
/// next one opened ([StandsOnTheAppsEngine]: one seam, 관제 2026-11-11
/// 22:35), and the texture a box is shown through goes and comes back by
/// it ([EngineScreenTexture]).
///
/// On the app's own engine, which each test loses: the one after it finds
/// the next.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what stands on the app\'s engine', () {
    test('is told that the engine was let go, and of the next one opened '
        '— and of neither once it hears no more', () async {
      await openAppGpuEngine();
      final heard = <Object>[];
      final stands = StandsOnTheAppsEngine(
        letGo: () => heard.add('let go'),
        opened: heard.add,
      )..start();
      addTearDown(stands.stop);

      final gone = theAppsEngineLostAndLetGo();
      expect(heard, ['let go']);
      final next = await openAppGpuEngine();
      expect(identical(next, gone), isFalse, reason: '⛔premise');
      expect(heard, ['let go', next]);

      stands.stop();
      theAppsEngineLostAndLetGo();
      await openAppGpuEngine();
      expect(heard, ['let go', next]);
    });

    test('is told of the letting go of an engine no one said was open', () {
      theAppsEngineLostAndLetGo();
      // Opened by the first that asks, with no word of it.
      appGpuEngine;
      expect(appGpuEngineOpen.value, isNull, reason: '⛔premise');
      var letGo = 0;
      final stands = StandsOnTheAppsEngine(letGo: () => letGo += 1)..start();
      addTearDown(stands.stop);

      theAppsEngineLostAndLetGo();

      expect(letGo, 1);
    });
  });

  group('the texture a box is shown through', () {
    /// A texture of the size asked, on a surface freed as the test ends.
    ScreenTexture aTexture(int id) {
      final surface = shownSurfaceOf(4, 4);
      addTearDown(surface.free);
      return ScreenTexture.debugOnSurface(surface, id: id);
    }

    test('goes with the engine it was opened on — the box told — and is '
        'opened again on the next, at the size it held', () async {
      await openAppGpuEngine();
      final told = <Object>[];
      final screen = EngineScreenTexture(
        asks: () => true,
        opened: told.add,
        letGo: () => told.add('let go'),
      )..wanted = (4, 4);
      screen.start();
      addTearDown(screen.stop);
      await screen.open();
      final first = screen.texture;
      expect(first, isNotNull, reason: '⛔premise: one is open');
      expect(screen.holdsWhatIsWanted, isTrue, reason: '⛔premise');
      told.clear();
      final live = ScreenTexture.liveBytes;

      theAppsEngineLostAndLetGo();

      expect(screen.texture, isNull);
      expect(screen.holdsWhatIsWanted, isFalse);
      expect(told, ['let go']);
      expect(ScreenTexture.liveBytes, lessThan(live), reason: 'freed');

      final next = await openAppGpuEngine();
      await pumpEventQueue();
      expect(screen.texture, isNotNull);
      expect(identical(screen.texture, first), isFalse);
      expect(screen.holdsWhatIsWanted, isTrue);
      expect(told, ['let go', next]);
    });

    test('one being opened on the engine let go is not the box\'s: the '
        'next engine\'s is, asked for at the same size', () async {
      await openAppGpuEngine();
      final opening = <Completer<ScreenTexture>>[];
      final opener = debugOpenEngineScreen;
      addTearDown(() => debugOpenEngineScreen = opener);
      debugOpenEngineScreen = (_, _, _) {
        opening.add(Completer<ScreenTexture>());
        return opening.last.future;
      };
      final screen = EngineScreenTexture(
        asks: () => true,
        opened: (_) {},
        letGo: () {},
      )..wanted = (4, 4);
      screen.start();
      addTearDown(screen.stop);
      unawaited(screen.open());
      expect(opening, hasLength(1), reason: '⛔premise: one is on its way');

      theAppsEngineLostAndLetGo();
      await openAppGpuEngine();
      expect(opening, hasLength(2), reason: 'asked of the next engine');

      // The one of the engine let go comes first.
      final ofTheLast = aTexture(1);
      final ofTheNext = aTexture(2);
      opening.first.complete(ofTheLast);
      await pumpEventQueue();
      expect(screen.texture, isNull);

      opening.last.complete(ofTheNext);
      await pumpEventQueue();
      expect(screen.texture, same(ofTheNext));
    });
  });
}
