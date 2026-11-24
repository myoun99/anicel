import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// a-keyboard-waking-restarts-the-app-on-the-galaxy-tab (H70, 유저
/// 2026-11-24: 「갤탭 키보드 절전상태?였다가 재인식되면 앱 튕기고
/// 재기동됨」): the activity takes every change of an input device itself,
/// so a keyboard coming and going tears nothing down — a change its
/// `configChanges` does not name has Android build the activity, and the
/// Flutter engine with it, again.
///
/// ⚠️A SOURCE PIN, because this suite runs no Android: it can say the list
/// names them; the app standing through a keyboard's sleep is the tablet's
/// to show.
void main() {
  test('the activity names every input device change it takes itself', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = manifest.indexOf('android:name=".MainActivity"');
    expect(activity, greaterThanOrEqualTo(0), reason: 'premise: declared');
    final said = RegExp(
      r'android:configChanges="([^"]*)"',
    ).firstMatch(manifest.substring(activity));
    expect(said, isNotNull, reason: 'premise: it names its changes');
    final names = said!.group(1)!.split('|').toSet();

    // Android's input device changes, all four: a Bluetooth keyboard
    // waking changes its navigation (its arrow keys) with its keyboard.
    for (final change in [
      'keyboard',
      'keyboardHidden',
      'navigation',
      'touchscreen',
    ]) {
      expect(names, contains(change));
    }
  });
}
