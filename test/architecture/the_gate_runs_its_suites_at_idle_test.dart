@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🗣️유저 2026-09-24 「PC 굳히지 말 것」: every suite `affected_tests`
/// launches runs at Idle, however the tool itself was launched. 🔬2026-10-15:
/// two runs started straight from a shell, at Normal, starved the user's
/// release build of its AOT compile for five minutes.
///
/// The tool is launched at NORMAL here (`start /normal`) — launched from a
/// test run at Idle it would inherit Idle and prove nothing — with a
/// stand-in `flutter.bat` first on the PATH that writes down the class it
/// was launched at.
void main() {
  test('🚨launched at Normal, the tool runs its suites at Idle', () async {
    final stand = Directory.systemTemp.createTempSync('gate_idle_');
    addTearDown(() => stand.deleteSync(recursive: true));
    final said = File('${stand.path}\\class.txt');
    File('${stand.path}\\flutter.bat').writeAsStringSync(
      '@echo off\r\n'
      'powershell -NoProfile -NonInteractive -Command '
      '"(Get-Process -Id \$PID).PriorityClass" >> "${said.path}"\r\n'
      'echo 00:00 +1: All tests passed!\r\n',
    );

    final run = await Process.run(
      'cmd',
      [
        '/c',
        'start',
        '',
        '/normal',
        '/wait',
        '/b',
        'dart',
        'tool/affected_tests.dart',
        '--all',
      ],
      environment: {
        'PATH': '${stand.path};${Platform.environment['PATH']}',
      },
    );

    expect(said.existsSync(), isTrue, reason: '${run.stdout}${run.stderr}');
    final classes = said
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet();
    expect(classes, {'Idle'});
  }, timeout: const Timeout(Duration(minutes: 3)));
}
