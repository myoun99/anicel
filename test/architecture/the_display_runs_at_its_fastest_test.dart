import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_body.dart';

/// 🗣️every-screen-at-its-own-refresh-rate (유저 2026-10-16): 「144fps모니터에서
/// 봐도 60으로보인다던가 … 최대 프레임 주사율에 맞춰서 하고싶은데」.
///
/// Android's engine follows whatever rate the display runs and asks for none
/// of its own, so the app asks: the window takes the display's fastest mode
/// at the size it already has.
///
/// ⚠️A SOURCE PIN, because no machine this suite runs on is an Android
/// device: it can say the app asks; the rate the device then runs at is the
/// device's to show (the frame stats overlay reads it).
void main() {
  const activity =
      'android/app/src/main/kotlin/com/myoun/anicel/MainActivity.kt';
  const mode =
      'android/app/src/main/kotlin/com/myoun/anicel/FastestDisplayMode.kt';

  test('the activity asks for it from its creation', () {
    final create = sourceBodyOf(
      File(activity).readAsStringSync(),
      'override fun onCreate(',
    );
    expect(create, contains('super.onCreate(savedInstanceState)'));
    expect(create, contains('preferTheFastestDisplayMode()'));
  });

  test('it is the fastest of the modes at the size the display has — never '
      'another resolution — and the window is handed it back', () {
    final ask = sourceBodyOf(
      File(mode).readAsStringSync(),
      'internal fun Activity.preferTheFastestDisplayMode(',
    );
    expect(ask, contains('it.physicalWidth == now.physicalWidth'));
    expect(ask, contains('it.physicalHeight == now.physicalHeight'));
    expect(ask, contains('.maxByOrNull { it.refreshRate }'));
    expect(ask, contains('attributes.preferredDisplayModeId = fastest.modeId'));
    expect(
      ask,
      contains('window.attributes = attributes'),
      reason: 'a window reads a changed attribute only when it is set again',
    );
  });
}
