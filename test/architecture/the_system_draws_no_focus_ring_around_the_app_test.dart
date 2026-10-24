import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🗣️F-438 (유저 2026-10-22, a Galaxy Tab with a Bluetooth keyboard): 「키
/// 누르면 앱 제일 외곽이 초록색 외곽선생김 … 아이패드로는 문제없었음 …
/// 애초에 왜 외곽선이 생기는건지 궁금」.
///
/// Android 8+ draws a default highlight around the view that holds the
/// keyboard's focus once a key takes the device out of touch mode, and the
/// whole app is ONE view — the one Flutter draws in. The app's own focus
/// looks cannot be what changed on a key: the highlight strategy is fixed
/// (`applyFocusHighlightPolicy`, always traditional), and the iPad, where
/// the system draws no such ring, showed nothing.
///
/// So the window's theme turns the system's ring off, in the light and the
/// dark theme alike — the one the window wears while Flutter runs.
///
/// ⚠️A SOURCE PIN, because no machine this suite runs on is a tablet with a
/// keyboard: it can say the theme asks; the tablet shows what it does.
void main() {
  for (final path in const [
    'android/app/src/main/res/values/styles.xml',
    'android/app/src/main/res/values-night/styles.xml',
  ]) {
    test('$path: the running theme draws no focus ring of the system\'s', () {
      final styles = File(path).readAsStringSync();
      final normal = RegExp(
        r'<style name="NormalTheme"[^>]*>([\s\S]*?)</style>',
      ).firstMatch(styles);
      expect(normal, isNotNull, reason: 'the theme Flutter runs under');
      expect(
        normal!.group(1),
        contains(
          '<item name="android:defaultFocusHighlightEnabled" '
          'tools:targetApi="o">false</item>',
        ),
      );
    });
  }
}
