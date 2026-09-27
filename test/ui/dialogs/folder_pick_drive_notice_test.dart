import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';

/// PICK-6: the one thing the app cannot see.
///
/// Google Drive gives no folder to any folder window: on Apple it greys out
/// Open in FOLDER mode, and a greyed-out button never calls the picker's
/// delegate; on Android it is not listed at all. Either way a person who
/// went looking for it arrives at exactly the same place as someone who
/// changed their mind. This notice is the only moment left to say it, which
/// is why it is pinned rather than left to read well.
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
        expect(
          find.textContaining('iCloud Drive'),
          findsOneWidget,
          reason: 'where a folder CAN come from on Apple (실측 08-13)',
        );
      });
    }

    testWidgets('🎯android: Drive is not even LISTED in the folder window — a '
        'cancel may be someone who looked for it, and they are told where a '
        'folder can come from there (유저 2026-09-27: 「폴더 고르는창은 '
        '드라이브 어쩔수없나?」)', (tester) async {
      debugOperatingSystemOverride = 'android';
      await pumpAndPickFolder(tester);
      expect(find.byKey(notice), findsOneWidget);
      expect(
        find.textContaining('iCloud Drive'),
        findsNothing,
        reason: 'there is no iCloud Drive on Android to send anyone to',
      );
      expect(find.textContaining('Autosync'), findsOneWidget);
    });
  });

  group('where it cannot', () {
    // Windows and Linux have no Drive provider in a folder window at all —
    // Drive for desktop is a drive letter, and it hands over folders.
    for (final os in const ['windows', 'linux']) {
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
    //
    // F-10: it is a MODAL window now rather than a bottom-of-screen strip, so
    // the second pick has to happen after the first one is dismissed — which
    // is also the only way to tell "said once" from "said twice, on top of
    // itself".
    debugOperatingSystemOverride = 'ios';
    await pumpAndPickFolder(tester);
    expect(find.byKey(notice), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('app-notice-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(notice), findsNothing);

    for (var i = 0; i < 2; i += 1) {
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(notice),
        findsNothing,
        reason: 'pick ${i + 2} must say nothing',
      );
    }
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
                  pickFileGrantsForUser(context, supportedExtensions: const []),
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
    // Pinned so a future edit to a predicate that names some of the same
    // platforms for another reason does not quietly move this one.
    expect(folderPickCancelMayBeDrive('ios'), isTrue);
    expect(folderPickCancelMayBeDrive('macos'), isTrue);
    expect(folderPickCancelMayBeDrive('android'), isTrue);
    for (final os in const ['windows', 'linux', 'fuchsia']) {
      expect(folderPickCancelMayBeDrive(os), isFalse, reason: os);
    }
  });
}
