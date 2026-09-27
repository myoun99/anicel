import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';

/// The hand-over's two channel calls (drive-folder-windows-Q1) — halves of
/// a contract whose native side nothing on this workstation can run: what
/// Dart sends, how it reads the answer, and that the runner which is asked
/// answers under the same names.
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

  test('Android: shareFiles sends the paths, and only a sheet that came up '
      'reads as shared', () async {
    answer = {
      'status': 'granted',
      'items': [
        {'path': '/room/a.png', 'bookmark': null},
      ],
    };

    expect(await FolderPicker.shareFiles(['/room/a.png']), isTrue);
    expect(calls.single.method, 'shareFiles');
    expect(calls.single.arguments, {
      'paths': ['/room/a.png'],
    });

    for (final status in const ['unavailable', 'cancelled']) {
      answer = {'status': status};
      expect(
        await FolderPicker.shareFiles(['/room/a.png']),
        isFalse,
        reason: status,
      );
    }
  });

  test('the runner that is asked answers under the names Dart asks by', () {
    final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(ios, contains('case "exportFiles":'));
    expect(ios, contains('arguments?["sourcePaths"] as? [String]'));

    final android = File(
      'android/app/src/main/kotlin/com/myoun/anicel/MainActivity.kt',
    ).readAsStringSync();
    expect(android, contains('"shareFiles" ->'));
    expect(android, contains('call.argument<List<String>>("paths")'));

    // The provider the share hands out URIs through answers at the
    // authority the share builds them with.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(
      manifest,
      contains(r'android:authorities="${applicationId}.outbox"'),
    );
    expect(android, contains(r'"$packageName.outbox"'));
  });
}
