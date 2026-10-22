import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/window_place.dart';
import 'package:anicel/src/services/persistence/app_window_store.dart';
import 'package:anicel/src/services/persistence/versioned_settings_file.dart';

import '../helpers/temp_dir.dart';

/// 🗣️I-116 (유저 2026-10-21): 「닫고 열때 마지막크기/위치로 열고싶음」.
///
/// Here the channel is the runner, and says what a runner says; that each
/// runner does say it is `the_window_keeps_its_place_test.dart`'s.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory folder;
  late AppWindowStore store;
  late List<Object?> handed;
  late List<String> written;

  const frame = {
    'left': 120.0,
    'top': 80.0,
    'width': 1500.0,
    'height': 900.0,
    'maximized': false,
  };

  /// What a desktop runner says once its window has settled.
  Future<void> runnerSays(Object? place) => messenger.handlePlatformMessage(
    WindowPlace.channel.name,
    WindowPlace.channel.codec.encodeMethodCall(
      MethodCall(WindowPlace.changedMethod, place),
    ),
    (_) {},
  );

  void lastRunLeft(String text) => File(store.filePath).writeAsStringSync(text);

  setUp(() {
    folder = Directory.systemTemp.createTempSync('window_place');
    store = AppWindowStore(filePath: '${folder.path}/window.json');
    handed = [];
    written = [];
    debugSettingsFileWrite = (_, text) async => written.add(text);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    messenger.setMockMethodCallHandler(WindowPlace.channel, (call) async {
      if (call.method != WindowPlace.setMethod) {
        throw MissingPluginException(call.method);
      }
      handed.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(WindowPlace.channel, null);
    debugDefaultTargetPlatformOverride = null;
    debugSettingsFileWrite = null;
    deleteTempQuietly(folder);
  });

  test('a run hands its runner the frame the last run left', () async {
    lastRunLeft(jsonEncode({'version': 1, 'frame': frame}));
    await WindowPlace.restore(store);
    expect(handed, [frame]);
  });

  test('…and hands nothing when the last run left none, or left what no '
      'run wrote', () async {
    for (final left in [
      null,
      '{"version":1,"fullScreen":true}',
      '{"version":1,"frame":{"left":0,"top":0,"width":0,"height":900,'
          '"maximized":false}}',
      '{"version":1,"frame":{"left":0,"top":0,"width":800}}',
      'not json',
    ]) {
      if (left == null) {
        if (File(store.filePath).existsSync()) {
          File(store.filePath).deleteSync();
        }
      } else {
        lastRunLeft(left);
      }
      await WindowPlace.restore(store);
      expect(handed, isEmpty, reason: '$left');
    }
  });

  test('⛔on the iPad and Android a run hands nothing — the window is the '
      'screen', () async {
    lastRunLeft(jsonEncode({'version': 1, 'frame': frame}));
    for (final tablet in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = tablet;
      await WindowPlace.restore(store);
      expect(handed, isEmpty, reason: tablet.name);
    }
  });

  test('where the window settled is what the next run is handed', () async {
    await WindowPlace.restore(store);
    final moved = {...frame, 'left': 300.0, 'maximized': true};
    await runnerSays(moved);
    await pumpEventQueue();
    expect(written, hasLength(1));
    lastRunLeft(written.last);
    expect(await store.loadFrame(), windowFrameFromJson(moved));
  });

  test('a word that moves nothing writes nothing, and a word that is no '
      'frame neither', () async {
    lastRunLeft(jsonEncode({'version': 1, 'frame': frame}));
    await WindowPlace.restore(store);
    await runnerSays(frame);
    await runnerSays({...frame, 'width': -1.0});
    await runnerSays('somewhere');
    await pumpEventQueue();
    expect(written, isEmpty);
  });

  test('★the frame and the full screen share one file, and a save of one '
      'keeps the other', () async {
    lastRunLeft(jsonEncode({'version': 1, 'fullScreen': true}));
    await WindowPlace.restore(store);
    await runnerSays(frame);
    await pumpEventQueue();
    lastRunLeft(written.last);
    expect(await store.loadFullScreen(), isTrue);
    await store.saveFullScreen(false);
    lastRunLeft(written.last);
    expect(await store.loadFrame(), windowFrameFromJson(frame));
    expect(await store.loadFullScreen(), isFalse);
  });
}
