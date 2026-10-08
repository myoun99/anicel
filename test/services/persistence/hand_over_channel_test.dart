import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';

/// The hand-over's own channel call (drive-folder-windows-Q1) — halves of a
/// contract whose native side nothing on this workstation can run: what
/// Dart sends, how it reads the answer, and that the runner which is asked
/// answers under the same names.
///
/// iOS's alone: Android hands over through the save window and the folder
/// window every other caller already asks (F-221 — the share sheet that had
/// a call of its own here is gone).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late Map<String, Object?> answer;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppStorage.channel, (call) async {
          calls.add(call);
          return answer;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppStorage.channel, null);
  });

  test('iOS: every output goes to ONE exportFiles call, and where they '
      'landed comes back as a grant', () async {
    answer = {
      'status': 'granted',
      'items': [
        {'path': '/Drive/a.png', 'bookmark': null},
        {'path': '/Drive/b.png', 'bookmark': null},
      ],
    };

    final grant = await FolderPicker.exportFiles(['/room/a.png', '/room/b']);

    expect(calls.single.method, 'exportFiles');
    expect(calls.single.arguments, {
      'sourcePaths': ['/room/a.png', '/room/b'],
    });
    expect(grant.isGranted, isTrue);
    expect(grant.path, '/Drive/a.png');

    answer = {'status': 'cancelled'};
    expect(
      (await FolderPicker.exportFiles(['/room/a.png'])).status,
      FolderPickStatus.cancelled,
    );
  });

  test('the runner that is asked answers under the names Dart asks by', () {
    final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(ios, contains('case "exportFiles":'));
    expect(ios, contains('arguments?["sourcePaths"] as? [String]'));
  });
}
