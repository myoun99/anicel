import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';

/// PICK-2: the storage gate in front of the folder picker.
///
/// Android resolves the system tree back to a real path, and that probe
/// fails without the All-Files grant — so a pick made without it refuses
/// every folder and blames the folder. The gate raises the grant notice
/// instead, and it is the piece the round left uncovered: its only test
/// consumer was the in-app browser, which the same round deleted.
///
/// Both branches are unreachable from the Windows workstation this app is
/// written on, so the flow reads its OS through a seam.
void main() {
  late List<String?> picked;

  setUp(() {
    picked = [];
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
      picked.add(initialDirectory);
      return const FolderGrant.granted(path: '/picked/folder');
    };
  });

  tearDown(() {
    FolderPicker.debugFolderPicker = null;
    debugOperatingSystemOverride = null;
    AppStorage.debugAllFilesAccessOverride = null;
  });

  /// Runs the flow from a mounted context and returns what it answered.
  Future<String?> runFlow(WidgetTester tester) async {
    String? result;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await pickFolderForUser(context);
              done = true;
            },
            child: const Text('pick'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    // The notice is modal: dismiss it so the awaiting flow can finish.
    final close = find.byKey(const ValueKey<String>('storage-grant-cancel'));
    if (close.evaluate().isNotEmpty) {
      await tester.tap(close);
      await tester.pumpAndSettle();
    }
    expect(done, isTrue, reason: 'the flow answered rather than hanging');
    return result;
  }

  testWidgets('Android without the grant is told, and the picker never '
      'opens', (tester) async {
    debugOperatingSystemOverride = 'android';
    AppStorage.debugAllFilesAccessOverride = false;

    final result = await runFlow(tester);

    expect(result, isNull);
    expect(
      picked,
      isEmpty,
      reason: 'opening the picker first would refuse every folder and read '
          'as the folder being wrong',
    );
  });

  testWidgets('Android WITH the grant goes straight to the picker', (
    tester,
  ) async {
    debugOperatingSystemOverride = 'android';
    AppStorage.debugAllFilesAccessOverride = true;

    expect(await runFlow(tester), '/picked/folder');
    expect(picked, hasLength(1));
  });

  testWidgets('every other platform ignores the grant entirely', (
    tester,
  ) async {
    // The refused grant is the trap: a gate that forgot to check WHICH
    // platform it is on would stop a desktop pick dead, and desktop has no
    // grant to go and turn on.
    AppStorage.debugAllFilesAccessOverride = false;

    for (final os in const ['windows', 'macos', 'linux', 'ios']) {
      debugOperatingSystemOverride = os;
      picked.clear();
      expect(await runFlow(tester), '/picked/folder', reason: os);
      expect(picked, hasLength(1), reason: os);
    }
  });

  test('the gate is Android and nothing else', () {
    expect(folderPickNeedsStorageGrant('android'), isTrue);
    for (final os in const ['ios', 'macos', 'windows', 'linux', 'fuchsia']) {
      expect(folderPickNeedsStorageGrant(os), isFalse, reason: os);
    }
  });
}
