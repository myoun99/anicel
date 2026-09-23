import 'dart:async';
import 'dart:io';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/persistence/app_save_settings.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/save_failure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/menu/editor_top_strip.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/temp_dir.dart';

/// 🚨★★★**A SAVE ITS FILE REFUSED SAYS SO THEN — WHY, AND WHERE THE WORK
/// IS, AND THAT IT GOES WHEN THE PROGRAM DOES.**
///
/// 🗣️유저 2026-09-23 (whole-write-temp-beside-the-file): 「저장에 실패하여
/// 앱컨테이너에 있다는걸 그 상황에 알려주기 … 왜 실패했는지(파일을
/// 잡고있어서)같은것들 정확하게 알기쉽게 명시」 · 「해당파일 지정해서
/// 백업할수있게」 · 「이 실패본은 프로그램 닫으면 사라진다고 안내」.
void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('anicel-refused-told');
    FolderPicker.debugOperatingSystem = 'windows';
  });

  tearDown(() {
    FolderPicker.debugOperatingSystem = null;
    FolderPicker.debugSaveDestinationPicker = null;
    deleteTempQuietly(folder);
  });

  /// A session and a context to ask things in.
  Future<({EditorSessionManager session, BuildContext context})> mounted(
    WidgetTester tester,
  ) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return (session: session, context: context);
  }

  /// A failed copy that is really there, recorded as [session]'s.
  String keptCopy(EditorSessionManager session, String projectName) {
    final copy = '${folder.path.replaceAll('\\', '/')}/room/$projectName';
    File(copy)
      ..createSync(recursive: true)
      ..writeAsStringSync('the work');
    session.failedSaveCopies.record(
      copy,
      '${folder.path.replaceAll('\\', '/')}/work/$projectName',
    );
    return copy;
  }

  bool live(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(ValueKey<String>(key))).enabled;

  testWidgets('🎯the notice says why, that the work is in the failed copy, '
      'that the copy goes when the program closes — and offers the backup', (
    tester,
  ) async {
    final (:session, :context) = await mounted(tester);
    final copy = keptCopy(session, 'take.anicel');
    final strings = AppText.strings;

    final message = saveFailureMessage(
      SaveFailure(
        cause: SaveFailureCause.fileInUse,
        error: const FileSystemException('refused'),
        failedCopy: copy,
      ),
    );
    expect(message, contains(strings.saveFailedFileInUse));
    expect(message, contains(strings.saveFailedCopyKept));
    expect(message, contains(strings.saveFailedRetry));

    unawaited(showSaveFailure(
      context,
      session,
      SaveFailure(
        cause: SaveFailureCause.fileInUse,
        error: const FileSystemException('refused'),
        failedCopy: copy,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('save-failure-notice')),
      findsOneWidget,
    );
    expect(find.text(strings.saveFailedTitle), findsOneWidget);
    expect(live(tester, 'save-failure-back-up'), isTrue);
  });

  testWidgets('when even the failed copy could not be written the notice '
      'says so — and the backup is there, greyed out', (tester) async {
    final (:session, :context) = await mounted(tester);
    final strings = AppText.strings;
    const failure = SaveFailure(
      cause: SaveFailureCause.diskFull,
      error: FileSystemException('full'),
      copyError: FileSystemException('full too'),
    );

    expect(saveFailureMessage(failure), contains(strings.saveFailedNoCopy));
    expect(
      saveFailureMessage(failure),
      isNot(contains(strings.saveFailedCopyKept)),
    );

    unawaited(showSaveFailure(context, session, failure));
    await tester.pumpAndSettle();

    expect(live(tester, 'save-failure-back-up'), isFalse);
  });

  testWidgets('every reason reads as its own sentence', (tester) async {
    final strings = AppText.strings;
    final sentences = {
      SaveFailureCause.fileInUse: strings.saveFailedFileInUse,
      SaveFailureCause.readOnly: strings.saveFailedReadOnly,
      SaveFailureCause.diskFull: strings.saveFailedDiskFull,
      SaveFailureCause.locationGone: strings.saveFailedLocationGone,
      SaveFailureCause.replaceRefused: strings.saveFailedReplaceRefused,
      SaveFailureCause.unknown: strings.saveFailedUnknown,
    };
    expect(sentences.keys, SaveFailureCause.values);
    for (final MapEntry(key: cause, value: sentence) in sentences.entries) {
      expect(
        saveFailureMessage(SaveFailure(cause: cause, error: 'x')),
        startsWith(sentence),
        reason: '$cause',
      );
    }
  });

  testWidgets('🚨the backup asks where under a name that is not the refused '
      'file\'s own, beside it', (tester) async {
    final (:session, :context) = await mounted(tester);
    final copy = keptCopy(session, 'take.anicel');
    final asked = <String>[];
    FolderPicker.debugSaveDestinationPicker = ({
      required String suggestedName,
      String? initialDirectory,
    }) async {
      asked.add('$initialDirectory|$suggestedName');
      return const FolderGrant.cancelled();
    };

    unawaited(showSaveFailure(
      context,
      session,
      SaveFailure(
        cause: SaveFailureCause.fileInUse,
        error: const FileSystemException('refused'),
        failedCopy: copy,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('save-failure-back-up')),
    );
    await tester.pumpAndSettle();

    expect(asked, hasLength(1));
    final (folderAsked, name) = (
      asked.single.split('|').first,
      asked.single.split('|').last,
    );
    expect(folderAsked, '${folder.path.replaceAll('\\', '/')}/work');
    expect(name, startsWith('take-'));
    expect(name, endsWith('.anicel'));
    expect(name, isNot('take.anicel'), reason: 'that is the refused file');
    expect(
      find.byKey(const ValueKey<String>('save-failure-notice')),
      findsNothing,
      reason: 'the notice gave way to the backup',
    );
  });

  testWidgets('🎯where a picker PLACES the file (iPad), the backup is the '
      'failed copy, staged, placed — and only then said to be backed up', (
    tester,
  ) async {
    FolderPicker.debugOperatingSystem = 'ios';
    addTearDown(() => FolderPicker.debugFileExporter = null);
    final placed = '${folder.path.replaceAll('\\', '/')}/placed.anicel';
    String? offeredAs;
    FolderPicker.debugFileExporter = ({
      required String sourcePath,
      String? suggestedName,
    }) async {
      offeredAs = suggestedName;
      // What the platform picker does with the staged file: puts it there.
      File(sourcePath).renameSync(placed);
      return FolderGrant.granted(path: placed, kind: GrantKind.file);
    };
    final (:session, :context) = await mounted(tester);
    final copy = keptCopy(session, 'take.anicel');
    const saidBackedUp = ValueKey<String>('failed-copy-backup-placed');

    var done = false;
    var said = false;
    // A real copy crosses into an isolate, which needs real time.
    await tester.runAsync(() async {
      unawaited(
        backUpFailedCopy(context, session, copy: copy).then((_) => done = true),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!done && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 16));
        said = said || find.byKey(saidBackedUp).evaluate().isNotEmpty;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    expect(done, isTrue, reason: 'the backup never came back');
    expect(File(placed).readAsStringSync(), 'the work');
    expect(offeredAs, startsWith('take-'));
    expect(said, isTrue, reason: 'placed, so now it says backed up');
  });

  testWidgets('the close question says the failed copy goes with the '
      'program', (tester) async {
    final (:session, :context) = await mounted(tester);
    session.projectFile
      ..markDirty()
      ..keptInFailedCopy(keptCopy(session, 'take.anicel'), asOf: 0);

    unawaited(ensureUnsavedWorkSettled(context, session));
    await tester.pumpAndSettle();

    expect(
      find.text(AppText.strings.closeProjectFailedCopyBody),
      findsOneWidget,
    );
  });

  testWidgets('「실패본 백업…」 is always in the Project list — off until '
      'there is a failed copy', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;

    Future<bool> backUpIsLive() async {
      await tester.tap(
        find.byKey(const ValueKey<String>('top-strip-project-button')),
      );
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<PanelFlyoutItem>>(
        find.byKey(const ValueKey<String>('menu-file-back-up-failed-copy')),
      );
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      return item.enabled;
    }

    expect(await backUpIsLive(), isFalse);
    keptCopy(session, 'take.anicel');
    expect(await backUpIsLive(), isTrue);
  });

  testWidgets('🚨the clock\'s save the file refuses is told at that moment '
      'too — the clock is what saves most of the time', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final refusing = '${folder.path.replaceAll('\\', '/')}/held.anicel';
    Directory(refusing).createSync();
    session.projectFile
      ..bindToOpenedFile(refusing, entryNames: const {}, unsaved: false)
      ..markDirty();
    addTearDown(() => AppSave.settings.value = const AppSaveSettings());
    AppSave.settings.value = const AppSaveSettings(periodicSnapshotMinutes: 1);

    await tester.pump(const Duration(minutes: 1));
    final notice = find.byKey(const ValueKey<String>('save-failure-notice'));
    // A real save crosses into an isolate, which needs real time.
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (notice.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    expect(notice, findsOneWidget);
    expect(session.projectFile.failedCopy, isNotNull);
  });
}
