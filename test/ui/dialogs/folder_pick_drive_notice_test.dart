import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';

/// PICK-6: the one thing the app cannot see.
///
/// Google Drive greys out Open in FOLDER mode, and a greyed-out button never
/// calls the picker's delegate — so a user who walked into Drive and found
/// Open dead arrives at exactly the same place as someone who changed their
/// mind. This notice is the only moment left to say it, which is why it is
/// pinned rather than left to read well.
void main() {
  const notice = ValueKey<String>('folder-pick-drive-notice');

  setUp(() {
    FolderPicker.debugFolderPicker =
        ({String? initialDirectory}) async => const FolderGrant.cancelled();
  });
  tearDown(() {
    FolderPicker.debugFolderPicker = null;
    FolderPicker.debugFilePicker = null;
    debugOperatingSystemOverride = null;
    debugDriveNoticeShown = false;
  });

  Future<void> pumpAndPickFolder(WidgetTester tester, {int times = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => pickFolderForUser(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < times; i++) {
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }
  }

  group('where it can happen', () {
    for (final os in const ['ios', 'macos']) {
      testWidgets('$os: a cancelled folder pick says why it might not be one', (
        tester,
      ) async {
        debugOperatingSystemOverride = os;
        await pumpAndPickFolder(tester);
        expect(find.byKey(notice), findsOneWidget);
      });
    }
  });

  group('where it cannot', () {
    // Android reaches Drive too, but its tree resolves to `noFilesystemPath`
    // and raises its OWN notice — a second one here would be two answers to
    // one question. Windows and Linux have no Drive provider at all.
    for (final os in const ['android', 'windows', 'linux']) {
      testWidgets('$os: a cancel stays a cancel', (tester) async {
        debugOperatingSystemOverride = os;
        await pumpAndPickFolder(tester);
        expect(find.byKey(notice), findsNothing);
      });
    }
  });

  testWidgets('it is said once per session, not once per pick', (tester) async {
    // A real cancel costs the user one line they can ignore. Repeating it on
    // every backed-out pick would turn "the thing you could not have known"
    // into noise, and noise is how a notice stops being read.
    debugOperatingSystemOverride = 'ios';
    await pumpAndPickFolder(tester, times: 3);
    expect(find.byKey(notice), findsOneWidget);
  });

  testWidgets('a granted pick says nothing', (tester) async {
    debugOperatingSystemOverride = 'ios';
    FolderPicker.debugFolderPicker = ({String? initialDirectory}) async =>
        const FolderGrant.granted(path: '/work');
    await pumpAndPickFolder(tester);
    expect(find.byKey(notice), findsNothing);
  });

  testWidgets('a cancelled FILE pick says nothing', (tester) async {
    // File mode reaches Drive fine — that is the whole point of PICK-6. A
    // notice here would name a limitation that does not apply.
    debugOperatingSystemOverride = 'ios';
    FolderPicker.debugFilePicker =
        ({
          required List<dynamic> acceptedTypeGroups,
          required bool allowMultiple,
        }) async => const [FolderGrant.cancelled()];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  pickFilesForUser(context, acceptedTypeGroups: const []),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byKey(notice), findsNothing);
  });

  test('the predicate is its own, not borrowed', () {
    // It happens to name the same two platforms as
    // `referencesExpireForPlatform`, for a DIFFERENT reason (that one is the
    // sandbox; this one is that Android has its own notice and Apple's
    // button is simply dead). Pinned so a future edit to either does not
    // quietly move the other.
    expect(folderPickCancelMayBeDrive('ios'), isTrue);
    expect(folderPickCancelMayBeDrive('macos'), isTrue);
    for (final os in const ['android', 'windows', 'linux', 'fuchsia']) {
      expect(folderPickCancelMayBeDrive(os), isFalse, reason: os);
    }
  });
}
