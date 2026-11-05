import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A licence the app ships a binary under is SHOWN with it — the About ▸
/// licenses screen registers each text in `assets/licenses/`, and each font's
/// OFL text beside it in `assets/fonts/` (THIRD_PARTY.md: 「a component whose
/// license requires a notice in shipped binaries must also appear in the
/// app's about/licenses screen」). A text put in a folder and never
/// registered ships unread.
void main() {
  test('every licence text the app bundles is registered at launch', () {
    final main = File('lib/main.dart').readAsStringSync();
    final texts = [
      for (final folder in [
        Directory('assets/licenses'),
        Directory('assets/fonts'),
      ])
        for (final file in folder.listSync())
          if (file is File && file.path.endsWith('.txt'))
            "'${folder.path}/${file.uri.pathSegments.last}'",
    ];
    expect(texts, contains("'assets/licenses/LICENSE-Wasmtime.txt'"));
    expect(texts, contains("'assets/fonts/OFL-NotoSansSC.txt'"));
    for (final text in texts) {
      expect(main, contains(text), reason: '$text is bundled but not shown');
    }
  });
}
