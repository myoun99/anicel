// A batch starts the Flutter tool past its .bat when the SDK has what the
// .bat would have called — and through the .bat when it has not.
//
// 🆕2026-11-20 (card the-wide-check-takes-five-hours): the .bat takes one
// lock for the whole machine on every call and goes through cmd.exe, whose
// 8191 characters cut the wide check into batches of about a hundred
// files ([flutterLaunch] says it all).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart'
    show flutterLaunch, kBatArgBudget, kDirectArgBudget;

void main() {
  const root = r'C:\sdk\flutter';
  final files = {
    r'C:\sdk\flutter\bin\cache\dart-sdk\bin\dart.exe',
    r'C:\sdk\flutter\bin\cache\flutter_tools.snapshot',
    r'C:\sdk\flutter\packages\flutter_tools\.dart_tool\package_config.json',
  };

  test("with the SDK's dart, the tool's snapshot and its packages, the "
      'tool is started directly, told where Flutter is, with the longer '
      'line', () {
    final launch = flutterLaunch(
      const {'FLUTTER_ROOT': root},
      windows: true,
      exists: files.contains,
    );
    expect(
      launch.executable,
      r'C:\sdk\flutter\bin\cache\dart-sdk\bin\dart.exe',
    );
    expect(launch.leading, [
      r'--packages=C:\sdk\flutter\packages\flutter_tools\.dart_tool'
          r'\package_config.json',
      r'C:\sdk\flutter\bin\cache\flutter_tools.snapshot',
    ]);
    expect(launch.environment, {'FLUTTER_ROOT': root});
    expect(launch.shell, isFalse);
    expect(launch.argBudget, kDirectArgBudget);
  });

  test('any of the three missing, it goes through the .bat as before', () {
    for (final gone in files) {
      final launch = flutterLaunch(
        const {'FLUTTER_ROOT': root},
        windows: true,
        exists: (path) => path != gone && files.contains(path),
      );
      expect(launch.executable, 'flutter.bat', reason: gone);
      expect(launch.leading, isEmpty, reason: gone);
      expect(launch.environment, isEmpty, reason: gone);
      expect(launch.shell, isTrue, reason: gone);
      expect(launch.argBudget, kBatArgBudget, reason: gone);
    }
  });

  test('off Windows there is no .bat to pass: `flutter` as it was', () {
    final launch = flutterLaunch(
      const {'FLUTTER_ROOT': root},
      windows: false,
      exists: (_) => true,
    );
    expect(launch.executable, 'flutter');
    expect(launch.leading, isEmpty);
    expect(launch.shell, isTrue);
  });

  test('the longer line is the reason: it is more than three times the '
      'one cmd.exe allows, and still inside what CreateProcess takes', () {
    expect(kDirectArgBudget, greaterThan(3 * kBatArgBudget));
    expect(kDirectArgBudget, lessThan(32767));
  });

  test('every batch is started the way the launch says, and cut to its '
      'line', () {
    final source = File('tool/affected_tests.dart').readAsStringSync();
    expect(source, contains('final launch = _launch;'));
    expect(source, contains('launch.executable,'));
    expect(source, contains('...launch.leading,'));
    expect(
      source,
      contains('environment: temp.environment..addAll(launch.environment),'),
    );
    expect(source, contains('runInShell: launch.shell,'));
    expect(source, contains('_launch.argBudget;'));
    expect(source, isNot(contains("Platform.isWindows ? 'flutter.bat'")));
  });

  test('on a Windows machine with Flutter, its SDK has the three files — a '
      'Flutter that moved them would send every batch back through the '
      '.bat, and this says so', () {
    if (!Platform.isWindows) return;
    final launch = flutterLaunch(Platform.environment, windows: true);
    expect(launch.executable, endsWith(r'\bin\cache\dart-sdk\bin\dart.exe'));
    expect(launch.shell, isFalse);
  });
}
