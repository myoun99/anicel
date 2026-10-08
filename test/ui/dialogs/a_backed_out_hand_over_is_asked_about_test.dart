import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/services/persistence/app_documents.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/services/persistence/move_into_folder.dart';
import 'package:anicel/src/ui/dialogs/folder_pick_flow.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/temp_dir.dart';

/// BACKING OUT OF THE WINDOW A FINISHED OUTPUT IS HANDED OVER THROUGH LETS
/// NOTHING GO (F-221-Q6, 유저 2026-10-07: 「취소하면 바로 묻는다 — [다시
/// 고르기] · [버리기]」 — 「고르거나 버릴 때까지 그 확인 창이 떠 있다」).
///
/// Where a place can only be asked of what is already made, the window
/// comes after the whole run — and backing out of it used to throw the run
/// away (F-221-Q2: 「지금 코드는 그 창을 취소하면 결과물을 버린다(다시
/// 내보내야 한다)」). It is asked about now: the same window again, or let
/// it go, and nothing but 「버리기」 lets it go.
///
/// The law itself, on every road that hands over (`placedOrLetGo`). Which
/// window each road opens is `finished_outputs_take_the_road_their_os_has_
/// test`'s; what the export window does around it is `finished_outputs_are_
/// handed_over_test`'s; what 「stays until answered」 means for a question
/// is the confirm door's own (`asking_a_yes_no_question_test`).
void main() {
  const question = ValueKey<String>('hand-over-pending-dialog');
  const pickAgain = ValueKey<String>('hand-over-pending-pick-again');
  const discard = ValueKey<String>('hand-over-pending-discard');
  const everyTime = 1 << 30;

  late Directory temp;
  late Directory picked;
  late String file;
  late String folder;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('qa-hand-over-asked');
    picked = Directory('${temp.path}/picked')..createSync();
    file = (File('${temp.path}/frame_0001.png')..writeAsStringSync('a')).path;
    folder = (Directory('${temp.path}/CUT001')..createSync()).path;
    File('$folder/0001.png').writeAsStringSync('b');
  });

  tearDown(() {
    debugOperatingSystemOverride = null;
    debugDriveNoticeShown = false;
    AppStorage.debugAllFilesAccessOverride = null;
    FolderPicker.debugFolderPicker = null;
    FolderPicker.debugFileExporter = null;
    FolderPicker.debugFilesExporter = null;
    deleteTempQuietly(temp);
  });

  Future<void> press(WidgetTester tester, ValueKey<String> key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  /// Whether the caller of [start] has been taken off the tree — the app,
  /// and any window standing over it, stay.
  late ValueNotifier<bool> callerGone;

  setUp(() => callerGone = ValueNotifier<bool>(false));
  tearDown(() => callerGone.dispose());

  /// Runs [flow] from a mounted context, as far as the first window that
  /// waits for an answer.
  Future<void> start(
    WidgetTester tester,
    Future<void> Function(BuildContext context) flow,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: callerGone,
            builder: (context, gone, _) => gone
                ? const SizedBox.shrink()
                : Builder(
                    builder: (context) => TextButton(
                      onPressed: () => flow(context),
                      child: const Text('go'),
                    ),
                  ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  /// Takes the caller away while a window of its flow is still open.
  Future<void> callerLeaves(WidgetTester tester) async {
    callerGone.value = true;
    await tester.pumpAndSettle();
  }

  test('the question is written in every language the app speaks', () {
    // A key one table lacks is read from the English one, and nothing
    // says so: the sentence and its two answers are checked by what they
    // SAY in each language.
    final english = AppStrings.of(AppLanguage.en);
    for (final language in AppLanguage.values) {
      if (language == AppLanguage.en) {
        continue;
      }
      final strings = AppStrings.of(language);
      for (final (word, inEnglish) in [
        (strings.exHandOverPending, english.exHandOverPending),
        (strings.exHandOverPickAgain, english.exHandOverPickAgain),
        (strings.exHandOverDiscard, english.exHandOverDiscard),
      ]) {
        expect(word, isNot(inEnglish), reason: 'in ${language.name}');
      }
    }
  });

  group('outputs handed over once they are made', () {
    /// What the hand-over answered, once it has.
    HandOver? handed;

    setUp(() => handed = null);

    Future<void> handOver(WidgetTester tester, List<String> paths) => start(
      tester,
      (context) async =>
          handed = await handOverFilesForUser(context, paths: paths),
    );

    /// The iOS export picker, backed out of [backedOut] times and placing
    /// what it is handed after that — with what it was handed each time.
    List<List<String>> iosPicker({required int backedOut}) {
      debugOperatingSystemOverride = 'ios';
      final asked = <List<String>>[];
      FolderPicker.debugFilesExporter = (sourcePaths) async {
        asked.add([...sourcePaths]);
        if (asked.length <= backedOut) {
          return const FolderGrant.cancelled();
        }
        for (final source in sourcePaths) {
          moveIntoFolder(source, picked.path);
        }
        return FolderGrant.granted(path: picked.path);
      };
      return asked;
    }

    testWidgets('🎯backing out of the window is not letting go: it is ASKED '
        'about, and the outputs stand where they were made while it is', (
      tester,
    ) async {
      final asked = iosPicker(backedOut: everyTime);

      await handOver(tester, [file, folder]);

      expect(find.byKey(question), findsOneWidget);
      expect(find.text(AppText.strings.exHandOverPending), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(pickAgain),
          matching: find.text(AppText.strings.exHandOverPickAgain),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(discard),
          matching: find.text(AppText.strings.exHandOverDiscard),
        ),
        findsOneWidget,
      );
      // 버리기 throws a whole run away, and is inked as what does.
      expect(
        tester
            .widget<TextButton>(find.byKey(discard))
            .style
            ?.foregroundColor
            ?.resolve({}),
        Theme.of(tester.element(find.byKey(discard))).colorScheme.error,
      );
      expect(handed, isNull, reason: 'nothing is answered until the user is');
      expect(File(file).existsSync(), isTrue);
      expect(File('$folder/0001.png').existsSync(), isTrue);
      expect(asked, hasLength(1));
      await press(tester, discard);
    });

    testWidgets('🎯다시 고르기 opens the SAME window again with the SAME '
        'outputs — and what it places is placed', (tester) async {
      final asked = iosPicker(backedOut: 1);

      await handOver(tester, [file, folder]);
      await press(tester, pickAgain);

      expect(find.byKey(question), findsNothing);
      expect(handed, HandOver.placed);
      expect(asked, [
        [file, folder],
        [file, folder],
      ]);
      expect(File('${picked.path}/frame_0001.png').readAsStringSync(), 'a');
      expect(File('${picked.path}/CUT001/0001.png').readAsStringSync(), 'b');
    });

    testWidgets('버리기 declines — the window is not opened again, and what '
        'was made is the caller\'s to let go', (tester) async {
      final asked = iosPicker(backedOut: everyTime);

      await handOver(tester, [file, folder]);
      await press(tester, discard);

      expect(find.byKey(question), findsNothing);
      expect(handed, HandOver.declined);
      expect(asked, hasLength(1));
      expect(File(file).existsSync(), isTrue, reason: 'the caller clears it');
      expect(picked.listSync(), isEmpty);
    });

    testWidgets('it is asked EVERY time the window is backed out of — not '
        'once, with the second backing out taken for an answer', (
      tester,
    ) async {
      final asked = iosPicker(backedOut: 2);

      await handOver(tester, [file]);
      await press(tester, pickAgain);

      expect(find.byKey(question), findsOneWidget);
      expect(handed, isNull);
      expect(File(file).existsSync(), isTrue);
      await press(tester, pickAgain);

      expect(handed, HandOver.placed);
      expect(asked, hasLength(3));
    });

    testWidgets('the question STANDS until one of its two is pressed: a tap '
        'beside it answers nothing', (tester) async {
      final asked = iosPicker(backedOut: everyTime);

      await handOver(tester, [file]);
      await tester.tapAt(const Offset(3, 3));
      await tester.pumpAndSettle();

      expect(find.byKey(question), findsOneWidget);
      expect(handed, isNull);
      expect(asked, hasLength(1));
      await press(tester, discard);
    });

    testWidgets('🚨taken down from OUTSIDE it answered nothing — the window '
        'opens again, and nothing is let go', (tester) async {
      // A pop meant for some other route lands on whatever is on top. Only
      // 「버리기」 lets the outputs go.
      final asked = iosPicker(backedOut: 1);

      await handOver(tester, [file]);
      Navigator.of(tester.element(find.byKey(question))).pop();
      await tester.pumpAndSettle();

      expect(asked, hasLength(2));
      expect(handed, HandOver.placed);
      expect(File('${picked.path}/frame_0001.png').readAsStringSync(), 'a');
    });

    testWidgets('a caller that went away while its WINDOW was open is asked '
        'nothing — what it made goes with it', (tester) async {
      debugOperatingSystemOverride = 'ios';
      final backedOut = Completer<FolderGrant>();
      FolderPicker.debugFilesExporter = (sourcePaths) => backedOut.future;

      await handOver(tester, [file]);
      await callerLeaves(tester);
      backedOut.complete(const FolderGrant.cancelled());
      await tester.pumpAndSettle();

      expect(find.byKey(question), findsNothing);
      expect(handed, HandOver.declined);
    });

    testWidgets('a caller that went away while it was ASKED opens no window '
        'again, whatever is pressed', (tester) async {
      final asked = iosPicker(backedOut: everyTime);

      await handOver(tester, [file]);
      await callerLeaves(tester);
      await press(tester, pickAgain);

      expect(asked, hasLength(1));
      expect(handed, HandOver.declined);
    });

    testWidgets('Android, ONE file: the save window backed out of is asked '
        'about, and 다시 고르기 opens the save window again', (tester) async {
      debugOperatingSystemOverride = 'android';
      final saved = <String>[];
      FolderPicker.debugFileExporter = ({
        required String sourcePath,
        String? suggestedName,
      }) async {
        saved.add(sourcePath);
        return saved.length == 1
            ? const FolderGrant.cancelled()
            : FolderGrant.granted(path: sourcePath, kind: GrantKind.file);
      };

      await handOver(tester, [file]);
      expect(find.byKey(question), findsOneWidget);
      await press(tester, pickAgain);

      expect(saved, [file, file]);
      expect(handed, HandOver.placed);
    });

    testWidgets('🎯Android, SEVERAL: a grant refused is asked about like any '
        'backing out — given, 다시 고르기 opens the folder window and the '
        'outputs are moved', (tester) async {
      // What the answered card promised: 「설정에 가서 「모든 파일 접근」을
      // 켜고 돌아와 [다시 고르기]를 누르는 것은 된다」.
      debugOperatingSystemOverride = 'android';
      AppStorage.debugAllFilesAccessOverride = false;
      var askedFolder = 0;
      FolderPicker.debugFolderPicker = ({String? initialDirectory}) async {
        askedFolder += 1;
        return FolderGrant.granted(path: picked.path);
      };

      await handOver(tester, [file, folder]);
      await press(tester, const ValueKey<String>('storage-grant-cancel'));

      expect(find.byKey(question), findsOneWidget);
      expect(askedFolder, 0, reason: 'no grant, no window');
      expect(File(file).existsSync(), isTrue);

      AppStorage.debugAllFilesAccessOverride = true;
      await press(tester, pickAgain);

      expect(askedFolder, 1);
      expect(handed, HandOver.placed);
      expect(File('${picked.path}/frame_0001.png').readAsStringSync(), 'a');
      expect(File('${picked.path}/CUT001/0001.png').readAsStringSync(), 'b');
    });

    group('🗣️a hand-over that FAILS half way is asked the same (F-221-Q7, '
        '유저 2026-10-08: 「오류 때도 같은 질문 — 남은 것만 [다시 고르기] · '
        '[버리기]」)', () {
      const failure = FileSystemException('the disk filled');

      /// The iOS export picker, which moves the FIRST of what it is handed
      /// and then fails, [failing] times — and moves all of it after that.
      List<List<String>> failingPicker({int failing = 1}) {
        debugOperatingSystemOverride = 'ios';
        final asked = <List<String>>[];
        FolderPicker.debugFilesExporter = (sourcePaths) async {
          asked.add([...sourcePaths]);
          moveIntoFolder(sourcePaths.first, picked.path);
          if (asked.length <= failing) {
            throw failure;
          }
          for (final source in sourcePaths.skip(1)) {
            moveIntoFolder(source, picked.path);
          }
          return FolderGrant.granted(path: picked.path);
        };
        return asked;
      }

      testWidgets('🎯it says why, and 다시 고르기 opens the window for what is '
          'still here — what made it stays where it was put', (tester) async {
        final asked = failingPicker();

        await handOver(tester, [file, folder]);

        expect(find.byKey(question), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(question),
            matching: find.textContaining(AppText.strings.exFailed(failure)),
          ),
          findsOneWidget,
          reason: 'the error is said, above the question',
        );
        await press(tester, pickAgain);

        expect(asked, [
          [file, folder],
          [folder],
        ], reason: 'the second window is handed what the first left');
        expect(handed, HandOver.placed);
        expect(File('${picked.path}/frame_0001.png').readAsStringSync(), 'a');
        expect(File('${picked.path}/CUT001/0001.png').readAsStringSync(), 'b');
      });

      testWidgets('버리기 lets go of what is left — what made it stays', (
        tester,
      ) async {
        failingPicker(failing: everyTime);

        await handOver(tester, [file, folder]);
        await press(tester, discard);

        expect(handed, HandOver.declined);
        expect(File('${picked.path}/frame_0001.png').existsSync(), isTrue);
        expect(Directory(folder).existsSync(), isTrue, reason: 'the caller '
            'lets go of what is left (HandOver.declined)');
      });

      testWidgets('a backing out is asked about without a failure said', (
        tester,
      ) async {
        iosPicker(backedOut: 1);

        await handOver(tester, [file]);

        expect(
          find.descendant(
            of: find.byKey(question),
            matching: find.text(AppText.strings.exHandOverPending),
          ),
          findsOneWidget,
          reason: 'the question alone — nothing failed',
        );
        await press(tester, pickAgain);
        expect(handed, HandOver.placed);
      });

      testWidgets('a failure that left NOTHING to place is the caller\'s to '
          'say: there is nothing to ask about', (tester) async {
        failingPicker();
        Object? thrown;

        await start(tester, (context) async {
          try {
            await handOverFilesForUser(context, paths: [file]);
          } on FileSystemException catch (error) {
            thrown = error;
          }
        });

        expect(thrown, failure);
        expect(find.byKey(question), findsNothing);
      });
    });
  });

  group('a written file placed where the OS says', () {
    /// Where the staged file stood each time the window was opened on it,
    /// and what it held.
    late List<({String path, String holds})> opened;

    setUp(() {
      opened = [];
      // A platform whose file is made first; which one is not this law's.
      debugOperatingSystemOverride = 'ios';
    });

    /// The save window of a scoped platform, backed out of [backedOut]
    /// times and answering a place after that.
    void saveWindow({required int backedOut}) {
      FolderPicker.debugFileExporter = ({
        required String sourcePath,
        String? suggestedName,
      }) async {
        opened.add((
          path: sourcePath,
          holds: File(sourcePath).readAsStringSync(),
        ));
        return opened.length <= backedOut
            ? const FolderGrant.cancelled()
            : FolderGrant.granted(
                path: '${picked.path}/$suggestedName',
                kind: GrantKind.file,
              );
      };
    }

    Future<bool> writeTake(String path) async {
      File(path).writeAsStringSync('the take');
      return true;
    }

    testWidgets('🎯an EXPORT backed out of its window is asked about — and '
        '다시 고르기 hands the SAME written file to the window again, not a '
        'second one', (tester) async {
      saveWindow(backedOut: 1);
      FolderGrant? placed;

      await start(tester, (context) async {
        placed = await placeStagedFileForUser(
          context,
          suggestedName: 'take.wav',
          write: writeTake,
        );
      });

      expect(find.byKey(question), findsOneWidget);
      expect(placed, isNull);
      expect(File(opened.single.path).existsSync(), isTrue);
      await press(tester, pickAgain);

      expect(opened, hasLength(2));
      expect(opened.last, opened.first);
      expect(placed?.path, '${picked.path}/take.wav');
    });

    testWidgets('🗣️an export whose window FAILS is asked about too, the '
        'written file still in hand (F-221-Q7) — 다시 고르기 hands it to the '
        'window again', (tester) async {
      FolderPicker.debugFileExporter = ({
        required String sourcePath,
        String? suggestedName,
      }) async {
        opened.add((
          path: sourcePath,
          holds: File(sourcePath).readAsStringSync(),
        ));
        if (opened.length == 1) {
          throw const FileSystemException('the picker lost it');
        }
        return FolderGrant.granted(
          path: '${picked.path}/$suggestedName',
          kind: GrantKind.file,
        );
      };
      FolderGrant? placed;

      await start(tester, (context) async {
        placed = await placeStagedFileForUser(
          context,
          suggestedName: 'take.wav',
          write: writeTake,
        );
      });

      expect(find.byKey(question), findsOneWidget);
      await press(tester, pickAgain);

      expect(opened, hasLength(2));
      expect(opened.last, opened.first, reason: 'the same written file');
      expect(placed?.path, '${picked.path}/take.wav');
    });

    testWidgets('버리기 answers nothing placed, and the written file goes '
        'with its staging folder', (tester) async {
      saveWindow(backedOut: everyTime);
      FolderGrant? placed;
      var answered = false;

      await start(tester, (context) async {
        placed = await placeStagedFileForUser(
          context,
          suggestedName: 'take.wav',
          write: writeTake,
        );
        answered = true;
      });
      await press(tester, discard);

      expect(answered, isTrue);
      expect(placed, isNull);
      expect(opened, hasLength(1));
      expect(File(opened.single.path).parent.existsSync(), isFalse);
    });

    testWidgets('SAVE AS backs out to a project that is still open: it is '
        'asked nothing', (tester) async {
      saveWindow(backedOut: everyTime);
      FolderGrant? placed;
      var answered = false;

      await start(tester, (context) async {
        placed = await placeStagedFileForUser(
          context,
          suggestedName: 'Cut.anicel',
          write: writeTake,
          keepsSavingThere: true,
        );
        answered = true;
      });

      expect(find.byKey(question), findsNothing);
      expect(answered, isTrue);
      expect(placed, isNull);
      expect(opened, hasLength(1));
      expect(File(opened.single.path).parent.existsSync(), isFalse);
    });
  });
}
