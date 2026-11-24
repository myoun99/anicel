import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_body.dart';

/// 🗣️H69 (유저 2026-11-24, 갤탭): 「앱 기동후 선긋고 언두 키보드로하면
/// 안먹어. b같은거 누르면 되. … 근데 그상황에서 언두 버튼은작동해.」
///
/// An Android window comes up in touch mode with no view focused, and a
/// key reaches a view only through focus. Flutter's view takes every touch
/// itself and never asks for focus, so until a key that types something
/// took the window out of touch mode, Ctrl+Z went to a window with nothing
/// focused (measured on the emulator 11-24). The activity gives Flutter's
/// view the focus whenever the window is in front with none.
///
/// ⚠️A SOURCE PIN, because no machine this suite runs on is an Android
/// device: it can say the activity hands its focus over; that a key then
/// reaches the framework is the device's to show.
void main() {
  test('a window in front with no view focused gives Flutter\'s view the '
      'focus', () {
    final focused = sourceBodyOf(
      File(
        'android/app/src/main/kotlin/com/myoun/anicel/MainActivity.kt',
      ).readAsStringSync(),
      'override fun onWindowFocusChanged(',
    );
    expect(focused, contains('super.onWindowFocusChanged(hasFocus)'));
    expect(focused, contains('hasFocus && currentFocus == null'));
    expect(
      focused,
      contains(
        'findViewById<View>(FlutterActivity.FLUTTER_VIEW_ID)?.requestFocus()',
      ),
      reason: 'the view the keys go to is the one Flutter draws in',
    );
  });
}
