import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A licence the app ships a binary under is SHOWN with it — the About ▸
/// licenses screen registers each text in `assets/licenses/` (THIRD_PARTY.md:
/// 「a component whose license requires a notice in shipped binaries must
/// also appear in the app's about/licenses screen」). A text put in the
/// folder and never registered ships unread.
void main() {
  test('every licence text in assets/licenses is registered at launch', () {
    final main = File('lib/main.dart').readAsStringSync();
    final texts = [
      for (final file in Directory('assets/licenses').listSync())
        if (file is File) file.uri.pathSegments.last,
    ];
    expect(texts, contains('LICENSE-Wasmtime.txt'));
    for (final text in texts) {
      expect(
        main,
        contains("'assets/licenses/$text'"),
        reason: '$text is bundled but not shown',
      );
    }
  });
}
