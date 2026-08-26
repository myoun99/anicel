import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// THE CHANNEL HAS NO COMPILER, SO THIS IS ITS TYPE CHECK.
///
/// `FolderPicker.decodeChannelAnswer` accepts exactly one shape for a
/// success — `{status: granted, items: [{path, bookmark}]}` — and treats
/// anything else as UNAVAILABLE, deliberately: a native that grows a case
/// Dart has not learned yet should be loud rather than look like a user
/// who changed their mind.
///
/// 🚨That loudness has one blind spot, and it shipped: the two coordinated
/// file helpers on iOS and macOS answered `{status: granted, path: …}`,
/// the single-item dialect. Dart read every one of those as unavailable,
/// so `replaceFileCoordinated` and `readFileCoordinated` returned false no
/// matter what the platform actually did. The provider-refusal save wrote
/// its archive, handed it to NSFileCoordinator, watched the replace
/// SUCCEED, and then told the user 「the location refused both a direct
/// write and a coordinated replace」 (실기 08-27, iPhone). Nothing failed
/// except the sentence Dart and Swift use to agree.
///
/// So: every native payload that says `granted` must carry `items`.
void main() {
  test('every native "granted" payload speaks the ITEMS dialect', () {
    final offenders = <String>[];
    for (final path in const [
      'ios/Runner/AppDelegate.swift',
      'macos/Runner/MainFlutterWindow.swift',
      'android/app/src/main/kotlin/com/myoun/anicel/MainActivity.kt',
    ]) {
      final file = File(path);
      if (!file.existsSync()) {
        fail('$path is missing — this test guards a channel it cannot find');
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        // Swift spells it `"status": "granted"`, Kotlin `"status" to
        // "granted"`; both put the pair on one line.
        if (!line.contains('"granted"')) {
          continue;
        }
        // Prose about the word is not a payload — and the runners
        // explain this vocabulary at length, on purpose.
        final code = line.trimLeft();
        if (code.startsWith('//') || code.startsWith('*')) {
          continue;
        }
        // The Kotlin builder spans lines, so the item key is allowed to
        // arrive on the NEXT one.
        final window = [
          line,
          if (i + 1 < lines.length) lines[i + 1],
        ].join('\n');
        if (!window.contains('items')) {
          offenders.add('$path:${i + 1}  ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A granted payload without `items` decodes as UNAVAILABLE in '
          'Dart, which reads as "the platform refused" for an operation '
          'that succeeded.\n${offenders.join('\n')}',
    );
  });
}
