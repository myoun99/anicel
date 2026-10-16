import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/window_full_screen.dart';
import 'package:anicel/src/services/persistence/app_window_store.dart';
import 'package:anicel/src/services/persistence/versioned_settings_file.dart';

import '../helpers/temp_dir.dart';

/// 🗣️I-103-Q2 (유저 2026-10-16): 「데스크톱만 켜고 끄기, 모바일은 지금처럼
/// 늘 전체 화면 … 다음 실행 때도 기억한다」.
///
/// Here the channel is the runner, and says what a runner says; that each
/// runner does say it is `the_window_is_switched_one_way_test.dart`'s.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory folder;
  late AppWindowStore store;
  late List<bool> asked;
  late List<String> written;

  /// What a desktop runner says once its window went in or out.
  Future<void> runnerSays(bool on) => messenger.handlePlatformMessage(
    WindowFullScreen.channel.name,
    WindowFullScreen.channel.codec.encodeMethodCall(
      MethodCall(WindowFullScreen.changedMethod, on),
    ),
    (_) {},
  );

  /// A runner that hears the asking — and, [follows], does as asked and
  /// says so, as the three do when their OS lets them.
  void runner({required bool follows}) => messenger.setMockMethodCallHandler(
    WindowFullScreen.channel,
    (call) async {
      if (call.method != WindowFullScreen.setMethod) {
        throw MissingPluginException(call.method);
      }
      final on = call.arguments as bool;
      asked.add(on);
      if (follows) {
        await runnerSays(on);
      }
      return null;
    },
  );

  /// What the last run left on disk.
  void lastRunLeft(String text) => File(store.filePath).writeAsStringSync(text);

  setUp(() {
    folder = Directory.systemTemp.createTempSync('window');
    store = AppWindowStore(filePath: '${folder.path}/window.json');
    asked = [];
    written = [];
    debugSettingsFileWrite = (_, text) async => written.add(text);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() async {
    // The window as a run starts it, for the next test: [on] is the app's.
    // Only where it was heard — said to no one, the word would wait in the
    // channel's buffer for the next test's runner.
    if (WindowFullScreen.on.value) {
      await runnerSays(false);
    }
    messenger.setMockMethodCallHandler(WindowFullScreen.channel, null);
    debugDefaultTargetPlatformOverride = null;
    debugSettingsFileWrite = null;
    deleteTempQuietly(folder);
  });

  test('the switch is the three desktops\', and neither tablet\'s', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        WindowFullScreen.offered,
        const {
          TargetPlatform.windows,
          TargetPlatform.macOS,
          TargetPlatform.linux,
        }.contains(platform),
        reason: platform.name,
      );
    }
  });

  test('a run opens full screen when the last one left it so', () async {
    runner(follows: true);
    lastRunLeft('{"version":1,"fullScreen":true}');
    await WindowFullScreen.restore(store);
    expect(asked, [true]);
    expect(WindowFullScreen.on.value, isTrue);
  });

  test('…and asks the window nothing when it left it windowed, left '
      'nothing, or left what no run wrote', () async {
    runner(follows: true);
    for (final left in [
      '{"version":1,"fullScreen":false}',
      null,
      '{"version":1,"fullScreen":"yes"}',
      'not json',
    ]) {
      if (left == null) {
        File(store.filePath).deleteSync();
      } else {
        lastRunLeft(left);
      }
      await WindowFullScreen.restore(store);
      expect(asked, isEmpty, reason: '$left');
      expect(WindowFullScreen.on.value, isFalse, reason: '$left');
    }
  });

  test('⛔on the iPad and Android a run asks the window nothing — it stays '
      'full screen as it always was — even from a remembered switch', () async {
    runner(follows: true);
    lastRunLeft('{"version":1,"fullScreen":true}');
    for (final tablet in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = tablet;
      await WindowFullScreen.restore(store);
      expect(asked, isEmpty, reason: tablet.name);
    }
  });

  test('★the mark follows the window, never the asking', () async {
    runner(follows: false);
    await WindowFullScreen.restore(store);
    await WindowFullScreen.set(true);
    expect(asked, [true]);
    expect(
      WindowFullScreen.on.value,
      isFalse,
      reason: 'asked, and the window has not gone',
    );
    // The Mac's green button, a window manager's key: nobody asked.
    await runnerSays(true);
    expect(WindowFullScreen.on.value, isTrue);
    await runnerSays(false);
    expect(WindowFullScreen.on.value, isFalse);
  });

  test('what the window did is what the next run reads — the OS\'s own '
      'switch\'s too', () async {
    runner(follows: false);
    await WindowFullScreen.restore(store);
    for (final on in [true, false]) {
      await runnerSays(on);
      await pumpEventQueue();
      expect(written, isNotEmpty);
      lastRunLeft(written.last);
      expect(await store.loadFullScreen(), on);
    }
  });

  test('⛔a word the channel does not speak moves nothing', () async {
    await WindowFullScreen.restore(store);
    await messenger.handlePlatformMessage(
      WindowFullScreen.channel.name,
      WindowFullScreen.channel.codec.encodeMethodCall(
        const MethodCall('somethingElse', true),
      ),
      (_) {},
    );
    expect(WindowFullScreen.on.value, isFalse);
    expect(written, isEmpty);
  });

  test('⛔a desktop whose runner has no switch keeps its window and its '
      'mark', () async {
    await WindowFullScreen.restore(store);
    await WindowFullScreen.set(true);
    expect(WindowFullScreen.on.value, isFalse);
  });
}
