import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_body.dart';

/// 🗣️I-104 (유저 2026-10-15): 「아이패드같은거 조작안하면 화면 꺼지는데
/// 모든플랫폼? 그런거 없이 안꺼지도록?」 — and I-104-Q1 (2026-10-16): on the
/// iPad and Android, always while the app is in front; the desktops keep
/// their OS's own display settings.
///
/// Each OS keeps the switch to the app in front by itself — Android's flag
/// is the activity window's, iOS's idle timer answers only for the app in
/// front — so it is thrown where the app starts and never undone.
///
/// ⚠️A SOURCE PIN, because no machine this suite runs on is a tablet: it
/// can say the app asks; what the tablet does with it is the device's to
/// show.
void main() {
  test("Android: the activity's window keeps the screen on from its "
      'creation', () {
    final create = sourceBodyOf(
      File(
        'android/app/src/main/kotlin/com/myoun/anicel/MainActivity.kt',
      ).readAsStringSync(),
      'override fun onCreate(',
    );
    expect(create, contains('super.onCreate(savedInstanceState)'));
    expect(
      create,
      contains(
        'window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)',
      ),
    );
  });

  test('iOS: the idle timer is off from launch, and is said off again each '
      'time the app becomes active', () {
    final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(
      sourceBodyOf(ios, 'didFinishLaunchingWithOptions launchOptions'),
      contains('keepTheScreenOn(application)'),
    );
    final keep = sourceBodyOf(ios, 'private func keepTheScreenOn(');
    expect(keep, contains('application.isIdleTimerDisabled = true'));
    expect(
      keep,
      contains('forName: UIApplication.didBecomeActiveNotification'),
    );
    expect(
      keep,
      contains('UIApplication.shared.isIdleTimerDisabled = true'),
      reason: 'and the observer says it again — one that only listened '
          'would read the same above',
    );
  });
}
