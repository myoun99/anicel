import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/dialogs/app_progress_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_file_table.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/drag_value_label.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/import_preview_probe.dart';
import '../../helpers/import_warnings.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/poll_until.dart';
import '../../helpers/psd_fixture.dart';
import '../../helpers/settle_async.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/staged_carry.dart';
import '../../helpers/stand_in_movie.dart';
import '../../helpers/temp_dir.dart';
import '../../helpers/wait_window.dart';
import '../../helpers/import_span.dart';

/// Empties [file], once nothing else holds it mapped.
///
/// ⚠️A file just written is read by the machine's virus scan, which maps
/// it: a write while the scan holds the map fails with
/// ERROR_USER_MAPPED_FILE (1224). 🔬2026-10-08: a cloud-wait test failed so
/// in a loaded run, then passed three times alone and in another lane's
/// run — and the window's own preview holding the file was measured and
/// ruled out (its viewer document open, the write went through). The
/// emptying is the fixture's, not what the test measures, so it waits —
/// by [waitPatience]. ↩️It gave up on its fiftieth try until 2026-10-19: a
/// count of rounds, which a busy machine runs out.
Future<void> emptyWhenFree(File file) async {
  final emptied = await pollUntil(
    () => _emptied(file),
    beat: const Duration(milliseconds: 100),
  );
  expect(emptied, isTrue, reason: 'still mapped: ${file.path}');
}

/// Whether [file] took the empty write — false while a map holds it.
Future<bool> _emptied(File file) async {
  try {
    await file.writeAsBytes(const <int>[]);
    return true;
  } on FileSystemException catch (error) {
    if (error.osError?.errorCode != 1224) {
      rethrow;
    }
    return false;
  }
}

/// The import/placement window: the table shows what each source becomes,
/// its cells answer with filled defaults, and Import runs the session
/// verbs. A cut folder's rows have a file of their own
/// (`a_cut_folder_comes_in_as_rows_of_the_import_window_test`).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-import-ui');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  // ⚠️[fill] is ONE BYTE repeated into every channel, alpha included — these
  // tests vary it only to tell two fixtures apart, so the shared writer is
  // handed the same repeated byte rather than an opaque colour.
  Future<String> writePngFilled(String name, int fill) => writeSolidPng(
    tempDir,
    name,
    rgba: (fill << 24) | (fill << 16) | (fill << 8) | fill,
  );

  Future<String> writePng(String name) => writePngFilled(name, 0xAA);

  /// Answers one question for one FILE: press its cell in [column] (the
  /// column's id) and pick [option] (the answer's key) from the popup that
  /// column opens.
  ///
  /// This is the window's shape now — the settings that were chips over a
  /// whole batch are cells on the row they belong to — so the tests drive
  /// it the way a hand does.
  Future<void> pickCell(
    WidgetTester tester, {
    required String column,
    required String path,
    required String option,
  }) async {
    final cell = find.byKey(ValueKey<String>('import-cell-$column-$path'));
    // The table scrolls sideways when its columns outgrow the window (the
    // test font's glyphs are wide), so the cell is brought into view first
    // — and the preview's page lands, or its spinner never lets it settle.
    await tester.ensureVisible(cell);
    await settleLoadedPages(tester);
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey<String>('import-option-$column-$option')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('🎯a cut folder counts its scans into the run\'s % (F-282-Q1)', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final folderPath = await tester.runAsync(() async {
      const root = 'upn_02_064_lo';
      final sep = Platform.pathSeparator;
      for (final scan in ['A1', 'A2', 'A3']) {
        await writePng('$root$sep$scan.png');
      }
      return '${tempDir.path}$sep$root';
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [folderPath!]),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await tester.pump();
    await tester.pump();
    final window = find.byType(AppProgressDialog);
    expect(window, findsOneWidget);
    final progress = tester.widget<AppProgressDialog>(window).progress;
    final counted = <double>[];
    progress.addListener(() {
      if (progress.value.fraction case final fraction?) {
        counted.add(fraction);
      }
    });
    await pumpPastTheWaitWindow(tester);

    expect(
      counted.where((fraction) => fraction > 0 && fraction < 1),
      isNotEmpty,
      reason: 'its scans were counted on the way, not only its end',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🗣️F-494: the window\'s line names what a file is going '
      'through — a carried file\'s bytes held — and lets go once it is '
      'through (「하고있는 과정을 투명하게」)', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(() => writePng('ref.png'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [path!]),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    final lines = watchTheLine(tester);
    await pumpPastTheWaitWindow(tester);

    expect(
      lines,
      ['', AppText.strings.imStepCarrying, ''],
      reason: 'a row carries its file at first (seedImportSettings), so the '
          'one long thing this file goes through is its bytes being held',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('single files import with destination/fit defaults filled — '
      'the simple case is one press', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(() => writePng('ref.png'));
    final layersBefore = s.requireActiveCut.layers.length;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [path!]),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('import-column-into')),
      findsOneWidget,
    );
    expect(
      find.text(AppText.strings.imIntoNewLayer),
      findsOneWidget,
      reason: 'the row is already answered: into the cut you are in',
    );
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await settleAsync(
      tester,
      () => s.requireActiveCut.layers.length > layersBefore,
    );
    await tester.pumpAndSettle();

    expect(s.requireActiveCut.layers.length, layersBefore + 1);
    expect(
      s.requireActiveCut.layers.any(
        (l) => l.kind == LayerKind.image && l.mediaReference != null,
      ),
      isTrue,
      reason: 'the default is reference mode',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯F-405: one press of Import is ONE undo — every file it '
      'placed goes back together', (tester) async {
    // 🗣️유저 2026-10-19: 「여러파일 임포트/배치시 레이어 하나당 한번언두인데
    // 임포트한거 한번에 언두하도록」.
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final a = await tester.runAsync(() => writePng('a.png'));
    final b = await tester.runAsync(() => writePng('b.png'));
    final layersBefore = s.requireActiveCut.layers.length;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [a!, b!]),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await settleAsync(
      tester,
      () => s.requireActiveCut.layers.length == layersBefore + 2,
    );
    await tester.pumpAndSettle();
    expect(
      s.requireActiveCut.layers.length,
      layersBefore + 2,
      reason: 'CONTROL: a layer each',
    );

    s.undo();

    expect(
      s.requireActiveCut.layers.length,
      layersBefore,
      reason: 'both go with the one undo',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  /// The media pool's ＋ became a destination in this window rather
  /// than a picker of its own, which is what makes the two import
  /// entrances one. The browser accepted movies and the window refused
  /// them; now the window does both, and which one it does is the
  /// destination's business.
  group('the media pool is a destination', () {
    Future<String> writeMovie() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}ref.mp4');
      await file.writeAsBytes(standInMovieBytes);
      return file.path;
    }

    Future<EditorSessionManager> pumpWindow(
      WidgetTester tester,
      String path, {
      required bool poolOnly,
    }) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(
              session: s,
              initialPaths: [path],
              poolOnly: poolOnly,
            ),
          ),
        ),
      );
      await tester.pump();
      return s;
    }

    testWidgets('opened from the browser it starts on the pool, and a movie '
        'registers there', (tester) async {
      final path = await tester.runAsync(writeMovie);
      final s = await pumpWindow(tester, path!, poolOnly: true);

      expect(
        find.byKey(const ValueKey<String>('import-rasterize-toggle')),
        findsNothing,
        reason: 'rasterize is a question about a placed layer',
      );

      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      await pumpPastTheWaitWindow(tester);
      await tester.pumpAndSettle();

      expect(s.mediaPool.mediaAssets.single.path, path.replaceAll('\\', '/'));
      expect(s.mediaPool.mediaAssets.single.kind, MediaAssetKind.video);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('the browser pins the pool — every row\'s 넣을 곳 says it, and '
        'opens nothing', (tester) async {
      final path = await tester.runAsync(writeMovie);
      await pumpWindow(tester, path!, poolOnly: true);
      final into = find.byKey(ValueKey<String>('import-cell-into-$path'));

      expect(
        find.descendant(of: into, matching: find.text(AppText.strings.panelMedia)),
        findsOneWidget,
      );
      await tester.tap(into, warnIfMissed: false);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('import-option-into-newLayer')),
        findsNothing,
        reason: 'the door answered: no placement is offered',
      );
      expect(
        find.byKey(const ValueKey<String>('import-column-bake')),
        findsNothing,
        reason: 'and a placement would have asked the movie whether it bakes',
      );
    });

    testWidgets('every other entrance still starts on a placement — and '
        'offers the pool on the row', (tester) async {
      final path = await tester.runAsync(() => writePng('drop.png'));
      await pumpWindow(tester, path!, poolOnly: false);
      await settleLoadedPages(tester);
      final into = find.byKey(ValueKey<String>('import-cell-into-$path'));

      expect(
        find.descendant(
          of: into,
          matching: find.text(AppText.strings.imIntoNewLayer),
        ),
        findsOneWidget,
      );
      // The table scrolls sideways in a window too narrow for it.
      await tester.ensureVisible(into);
      await tester.pumpAndSettle();
      await tester.tap(into);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('import-option-into-pool')),
        findsOneWidget,
        reason: 'the pool is on offer from here too — one window',
      );
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('import-column-file')),
        findsOneWidget,
        reason: 'and how a new file is kept is that file\'s own answer',
      );
    });
  });

  /// Copy-or-reference, end to end through the window.
  ///
  /// The session verb is pinned in `audio_import_media_copy_test.dart`;
  /// what fails apart from it is the WIRING — a window whose chips do not
  /// reach `copyIntoProject`, or whose default silently flipped, leaves
  /// those tests green while every import copies again. So this drives the
  /// real chips and reads the path the project ended up with.
  group('the import window decides carry or reference', () {
    /// A png beside a SAVED project — saved, so that a `.assets` sibling
    /// COULD be created here. That is the whole assertion of the carry
    /// test: there is somewhere for a copy to land and none appears.
    Future<(EditorSessionManager, String)> savedProjectWithPng(
      WidgetTester tester,
    ) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final path = await tester.runAsync(() async {
        final png = await writePng('ref.png');
        await s.projectDoor.saveProjectToFile(
          asked: SaveAsked.byAPerson,
          '${tempDir.path}${Platform.pathSeparator}scene.anicel',
        );
        return png;
      });
      return (s, path!);
    }

    /// Imports what the window holds. It waits out the wait window, so it
    /// ends by stopping playback's warmer (`pumpPastTheWaitWindow`) — for
    /// every test that imports through it.
    Future<void> runImport(WidgetTester tester, EditorSessionManager s) async {
      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      await pumpPastTheWaitWindow(tester);
      await settleAsync(tester, () => s.mediaPool.mediaAssets.isNotEmpty);
      await tester.pumpAndSettle();
      s.playbackRig.prerenderScheduler.cancel();
    }

    testWidgets('it starts on Keep inside, on every platform', (tester) async {
      // It used to start on Reference everywhere but Apple, where a
      // recorded path dies at the next launch without a grant. Two things
      // moved since: the project carries its own media, so carrying costs
      // bytes inside a ZIP rather than a second file on disk, and the
      // 3GB-movie accident that made Reference the blanket default was
      // answered per kind (video defaulted to Reference from 2026-08-14)
      // until 2026-09-16, when the user made every file, at any size, the
      // person's own call.
      //
      // What is left is which failure someone meets by not choosing, and a
      // link that breaks when the original moves is the worse one.
      final (s, path) = await savedProjectWithPng(tester);
      for (final os in const ['ios', 'macos', 'windows', 'linux']) {
        FolderPicker.debugOperatingSystem = os;
        addTearDown(() => FolderPicker.debugOperatingSystem = null);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ImportDialog(
                key: ValueKey<String>(os),
                session: s,
                initialPaths: [path],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text('Keep'),
          findsWidgets,
          reason: '$os starts on Keep inside',
        );
        expect(find.text('Link'), findsNothing);
      }
    });

    testWidgets('Reference is still a choice, and it still costs nothing', (
      tester,
    ) async {
      // The toggle has to keep meaning something: an original shared with
      // another tool should stay where the other tool expects it. That is
      // a deliberate answer now rather than the one you get by not
      // answering.
      final (s, path) = await savedProjectWithPng(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(session: s, initialPaths: [path]),
          ),
        ),
      );
      await tester.pump();
      await pickCell(tester, column: 'file', path: path, option: 'reference');
      expect(
        find.text('Link'),
        findsOneWidget,
        reason: 'the row says which of the two it is on',
      );

      await runImport(tester, s);

      expect(s.mediaPool.mediaAssets.single.path, path.replaceAll('\\', '/'));
      expect(
        s.mediaPool.mediaAssets.single.carried,
        isFalse,
        reason: 'and the project will not pack it at the next save',
      );
      expect(
        Directory(
          '${tempDir.path}${Platform.pathSeparator}scene.assets',
        ).existsSync(),
        isFalse,
        reason: 'a reference costs zero bytes — the point of it',
      );
    });

    testWidgets('Keep inside is the default, and it duplicates nothing', (
      tester,
    ) async {
      final (s, path) = await savedProjectWithPng(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(session: s, initialPaths: [path]),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('Keep'),
        findsWidgets,
        reason: 'the row starts answered, and answered with carry',
      );

      await runImport(tester, s);

      expect(
        s.mediaPool.mediaAssets.single.path,
        path.replaceAll('\\', '/'),
        reason: 'the project records the file where the user keeps it',
      );
      expect(
        s.mediaPool.mediaAssets.single.carried,
        isTrue,
        reason: 'and the next save packs it into the .anicel',
      );
      expect(
        Directory(
          '${tempDir.path}${Platform.pathSeparator}scene.assets',
        ).existsSync(),
        isFalse,
        reason:
            'carrying is a fact about the SAVE — there was somewhere '
            'for a copy to land and none was made',
      );
    });
  });

  testWidgets('a PDF places through the window (R4): the fake renderer '
      'lands its pages as a new cut', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    addTearDown(PdfRenderService.debugResetForTests);
    PdfRenderService.debugOpenerOverride = (_) async => FakePdfDocument(
      pageSizes: const [ui.Size(595, 842), ui.Size(595, 842)],
    );
    final pdfPath = await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}conte.pdf');
      await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      return file.path;
    });
    final cutsBefore = s.repository.requireProject().tracks.first.cuts.length;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [pdfPath!]),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining('placement not available'),
      findsNothing,
      reason: 'PDF left the unplaceable set in R4',
    );

    await pickCell(tester, column: 'into', path: pdfPath, option: 'newCut');
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await settleAsync(
      tester,
      () =>
          s.repository.requireProject().tracks.first.cuts.length > cutsBefore,
    );
    await tester.pumpAndSettle();

    final track = s.repository.requireProject().tracks.first;
    expect(track.cuts.length, cutsBefore + 1);
    expect(track.cuts.last.duration, 2, reason: '1 page = 1 frame');
    expect(s.mediaPool.mediaAssets.single.pageCount, 2);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯a PDF counts its pages into the run\'s % (F-282-Q1)', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    addTearDown(PdfRenderService.debugResetForTests);
    PdfRenderService.debugOpenerOverride = (_) async => FakePdfDocument(
      pageSizes: List.filled(4, const ui.Size(595, 842)),
    );
    final pdfPath = await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}pages.pdf');
      await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      return file.path;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [pdfPath!]),
        ),
      ),
    );
    await tester.pump();
    await pickCell(tester, column: 'into', path: pdfPath, option: 'newCut');

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    final counted = watchTheBar(tester);
    final lines = watchTheLine(tester);
    await tester.pump();
    await tester.pump();
    expect(find.byType(AppProgressDialog), findsOneWidget);
    await pumpPastTheWaitWindow(tester);

    expect(
      counted.where((fraction) => fraction > 0 && fraction < 1),
      isNotEmpty,
      reason: 'its pages were counted on the way, not only its end',
    );
    // 🗣️F-494: what it went through, in the order its door does it, each
    // an even share of the file's: its bytes held, then its four pages.
    expect(lines, [
      '',
      AppText.strings.imStepCarrying,
      AppText.strings.imStepRasterizing,
      '',
    ]);
    expectOneBar(counted, [0.5, 0.625, 0.75, 0.875, 1]);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a PDF with NO renderer warns honestly instead of failing '
      'as a decode', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    addTearDown(PdfRenderService.debugResetForTests);
    // No override: flutter_tester's probe reports absent.
    final pdfPath = await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}none.pdf');
      await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      return file.path;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [pdfPath!]),
        ),
      ),
    );
    await tester.pump();
    await pickCell(tester, column: 'into', path: pdfPath, option: 'newCut');
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await settleAsync(
      tester,
      () => importWarningsButton.evaluate().isNotEmpty,
    );
    await tester.pumpAndSettle();
    final notice = await openImportWarnings(tester);

    expect(
      find.descendant(
        of: notice,
        matching: find.text('No PDF renderer in this build. (1)'),
      ),
      findsOneWidget,
      reason: 'the absence is a stated condition, not a decode failure',
    );
    expect(
      find.descendant(of: notice, matching: find.text('none.pdf')),
      findsOneWidget,
    );
    expect(s.mediaPool.mediaAssets, isEmpty);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a large file bound for the project file is kept like any '
      'other, and nothing under the table second-guesses it (유저 '
      '2026-09-16: 「파일 크기 어떻든 품기/참조가능으로 바꿨으니 기본값이든 '
      '경고줄이든 싹 다 삭제 잔존제거」)', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}마스터.wav');
      final handle = file.openSync(mode: FileMode.write);
      handle.truncateSync(120 * 1024 * 1024);
      handle.closeSync();
      return file.path;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [path!]),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('import-status')))
          .data,
      isEmpty,
      reason: 'the footer is the status line, and nothing is running',
    );
    expect(importWarningsButton, findsNothing);
  });

  /// The table itself: one row per file, one column per question, and a
  /// press that speaks for exactly the rows it should.
  group('the file table', () {
    Future<String> writeMovie(String name) async {
      final file = File('${tempDir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(standInMovieBytes);
      return file.path;
    }

    Future<String> writePsd(String name) async {
      final file = File('${tempDir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(
        buildPsd(
          width: 4,
          height: 4,
          layers: [
            PsdTestLayer(
              name: 'art',
              left: 0,
              top: 0,
              right: 4,
              bottom: 4,
              planes: psdSolidPlanes(4, 4, [10, 20, 30]),
            ),
          ],
          compositePlanes: [Uint8List(16), Uint8List(16), Uint8List(16)],
        ),
      );
      return file.path;
    }

    Future<EditorSessionManager> pump(
      WidgetTester tester,
      List<String> paths, {
      bool poolOnly = false,
    }) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(
              session: s,
              initialPaths: paths,
              poolOnly: poolOnly,
            ),
          ),
        ),
      );
      await settleLoadedPages(tester);
      return s;
    }

    /// What a cell READS — the answer this file will give, whether the
    /// cell is a button or the dash that says the question does not apply.
    String cellText(WidgetTester tester, String column, String path) {
      final cell = find.byKey(ValueKey<String>('import-cell-$column-$path'));
      final widget = tester.widget(cell);
      if (widget is Text) {
        return widget.data!;
      }
      return tester
          .widget<Text>(find.descendant(of: cell, matching: find.byType(Text)))
          .data!;
    }

    testWidgets('a column header answers for every row at once', (
      tester,
    ) async {
      final a = await tester.runAsync(() => writePng('a.png'));
      final b = await tester.runAsync(() => writePng('b.png'));
      await pump(tester, [a!, b!]);

      expect(cellText(tester, 'file', a), 'Keep');
      final header = find.byKey(const ValueKey<String>('import-column-file'));
      await tester.ensureVisible(header);
      await tester.pumpAndSettle();
      await tester.tap(header);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('import-option-file-reference')),
      );
      await tester.pumpAndSettle();

      expect(cellText(tester, 'file', a), 'Link');
      expect(cellText(tester, 'file', b), 'Link');
    });

    testWidgets('a cell speaks for the SELECTION when its row is in one', (
      tester,
    ) async {
      final a = await tester.runAsync(() => writePng('a.png'));
      final b = await tester.runAsync(() => writePng('b.png'));
      final c = await tester.runAsync(() => writePng('c.png'));
      await pump(tester, [a!, b!, c!]);

      // The NAME, not the row's centre: the centre is a cell, and pressing
      // a cell answers its question instead of selecting the row.
      Future<void> selectRow(String name) async {
        final rect = tester.getRect(
          find.byKey(ValueKey<String>('import-row-$name')),
        );
        await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
        await tester.pump();
      }

      await selectRow('a.png');
      await selectRow('b.png');
      await pickCell(tester, column: 'file', path: a, option: 'reference');

      expect(cellText(tester, 'file', a), 'Link');
      expect(cellText(tester, 'file', b), 'Link');
      expect(
        cellText(tester, 'file', c),
        'Keep',
        reason: 'the row nobody selected keeps its own answer',
      );
    });

    testWidgets('a movie starts on Keep like the picture beside it, and can '
        'be linked', (tester) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      final movie = await tester.runAsync(() => writeMovie('ref.mp4'));
      await pump(tester, [png!, movie!]);

      expect(
        cellText(tester, 'file', movie),
        'Keep',
        reason: 'every file starts where the settings start (유저 2026-09-16)',
      );
      expect(cellText(tester, 'file', png), 'Keep');

      await pickCell(tester, column: 'file', path: movie, option: 'reference');

      expect(cellText(tester, 'file', movie), 'Link');
    });

    testWidgets('🚨a sound PLACES on the SE rows (유저 2026-09-11: 「소리파일: '
        '추천대로 통일」), and it counts as imported — a batch of nothing but '
        'sound must not report "Nothing imported."', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
        audioConformStore: soundConformStore(),
      );
      addTearDown(session.dispose);
      final wav = await tester.runAsync(() async {
        final file = File('${tempDir.path}${Platform.pathSeparator}take.wav');
        await file.writeAsBytes(const [0x52, 0x49, 0x46, 0x46]);
        return file.path;
      });
      // A PLACEMENT run (a destination is chosen), not the pool: a sound
      // goes through its own door onto the SE rows.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(session: session, initialPaths: [wav!]),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      final lines = watchTheLine(tester);
      await pumpPastTheWaitWindow(tester);
      // Waits for what landed, as every run here does. ↩️It waited for
      // 「Importing…」 to go, which a run that imported never does: it ends
      // in a pop, the window is no route in this test, and the line is left
      // as it was — sixty seconds of patience run out every time (10-19).
      Object? onSe1() => session.activeTrack.seLayers.first
          .timeline[session.activeCutGlobalStartFrame];
      await settleAsync(tester, () => onSe1() != null);
      await tester.pumpAndSettle();

      expect(
        session.repository.requireProject().mediaAssets,
        isNotEmpty,
        reason: 'the sound registered as it placed',
      );
      expect(onSe1(), isNotNull, reason: 'it landed on SE1 from the cut start');
      expect(
        find.text('Nothing imported.'),
        findsNothing,
        reason: 'a placement IS an import — the batch counted it',
      );
      expect(
        lines,
        ['', AppText.strings.imStepCarrying, ''],
        reason: '🗣️F-494: carried as it placed, by its own door',
      );
      session.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('an answer the KIND refuses still does not stick — a sound '
        'has no pixels to bake, so its bake cell stays a dash', (
      tester,
    ) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      final wav = await tester.runAsync(() async {
        final file = File('${tempDir.path}${Platform.pathSeparator}se.wav');
        await file.writeAsBytes(const [0x52, 0x49, 0x46, 0x46]);
        return file.path;
      });
      await pump(tester, [png!, wav!]);

      final header = find.byKey(const ValueKey<String>('import-column-bake'));
      await tester.ensureVisible(header);
      await tester.pumpAndSettle();
      await tester.tap(header);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('import-option-bake-true')),
      );
      await tester.pumpAndSettle();

      expect(cellText(tester, 'bake', png), AppText.strings.commonOn);
      expect(
        cellText(tester, 'bake', wav),
        '—',
        reason: 'the header asked, and a sound has no pixels to bake',
      );
      expect(
        cellText(tester, 'file', wav),
        'Keep',
        reason: 'and the pool\'s question was never touched by the layer\'s',
      );
    });

    testWidgets('an expanded PSD locks its BAKE on — one of them baked means '
        'all of them are — so its file stays out of the pool and is not '
        'asked how it is kept; merged, the bake is its own question again, '
        'and so is the file', (tester) async {
      final psd = await tester.runAsync(() => writePsd('BG.psd'));
      await pump(tester, [psd!]);
      // The preview reads a Photoshop file whole, through an awaited read
      // that holds it open between turns — and one this test ended in the
      // middle of held it open for the rest of the run, so its folder could
      // not be removed (2026-10-08). Shown, it has been read and let go.
      expect(
        await settleAsync(tester, () => tester.importPreviewImage != null),
        isTrue,
        reason: 'the preview shows the file it read',
      );

      expect(
        cellText(tester, 'option', psd),
        'Keep layers',
        reason: 'a PSD comes in as its layers (F-306-Q1)',
      );
      expect(cellText(tester, 'bake', psd), AppText.strings.commonOn);
      expect(
        cellText(tester, 'file', psd),
        '—',
        reason: 'baked, it keeps no entry (F-282-Q6, 유저 2026-10-09: 「구우면 '
            '풀에 안 남긴다」)',
      );

      await pickCell(tester, column: 'option', path: psd, option: 'merge');

      expect(cellText(tester, 'bake', psd), AppText.strings.commonOff);
      expect(cellText(tester, 'file', psd), 'Keep');
    });

    // ↩️The 넣을 곳 column went with them (09-11); it stands now, 「미디어」
    // locked — the window mock the user started this from (2026-10-09: 「미디어
    // 패널의 경우엔 굽기 맞춤 옵션안넣어도되 … 그거만 해서 시작해도되」), and
    // pinned beside the browser's door above.
    testWidgets('🚨the pool asks nothing about placement — the questions a '
        'placement asks are not there at all (유저 2026-09-11: 「플레이스가 '
        '풀이면 넣을곳 맞춤 PSD 열 삭제」)', (tester) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      await pump(tester, [png!], poolOnly: true);

      for (final id in ['bake', 'fit', 'option']) {
        expect(
          find.byKey(ValueKey<String>('import-column-$id')),
          findsNothing,
          reason: id,
        );
      }
      expect(
        cellText(tester, 'file', png),
        'Keep',
        reason: 'what the project holds is still a question here',
      );
    });
  });

  /// The preview zone, and the rule that keeps its range honest.
  group('the preview', () {
    /// Whether the transport's IN readout takes a hand — the row is always
    /// there (the window trims), and off where a span would act on nothing.
    bool rangeIsOn(WidgetTester tester) => tester
        .widget<DragValueLabel>(
          find.ancestor(
            of: find.byKey(const ValueKey<String>('transport-in')),
            matching: find.byType(DragValueLabel),
          ),
        )
        .enabled;

    testWidgets('a still keeps its IN/OUT row, off — a range that cannot '
        'act is a control that lies', (tester) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final png = await tester.runAsync(() => writePng('a.png'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(session: s, initialPaths: [png!]),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('import-preview')),
        findsOneWidget,
      );
      expect(
        rangeIsOn(tester),
        isFalse,
        reason: 'one frame has no span to choose',
      );
      expect(
        find.byKey(const ValueKey<String>('transport-play')),
        findsOneWidget,
        reason: 'the bar itself stays, inert, rather than blinking in and out',
      );
    });

    /// A five-page document whose preview opens — what shows the ends.
    Future<String> fivePages(WidgetTester tester) async {
      addTearDown(PdfRenderService.debugResetForTests);
      PdfRenderService.debugOpenerOverride = (_) async => FakePdfDocument(
        pageSizes: List.filled(5, const ui.Size(595, 842)),
      );
      return (await tester.runAsync(() async {
        final file = File('${tempDir.path}${Platform.pathSeparator}conte.pdf');
        await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
        return file.path;
      }))!;
    }

    Future<void> openOnThePool(
      WidgetTester tester,
      EditorSessionManager s,
      String path,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(session: s, initialPaths: [path], poolOnly: true),
          ),
        ),
      );
      // IN/OUT is a span of the file's pages, said once the file is open.
      await settleLoadedPages(tester);
    }

    testWidgets('🚨registering into the pool shows IN/OUT where there is a '
        'span to keep — a trimmed registration comes in as its piece', (
      tester,
    ) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final pdf = await fivePages(tester);

      await openOnThePool(tester, s, pdf);

      expect(rangeIsOn(tester), isTrue);
    });

    testWidgets('⛔but not on a file the pool already holds — registering it '
        'again adds nothing, so a span there would act on nothing', (
      tester,
    ) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final pdf = await fivePages(tester);
      await tester.runAsync(
        () => s.mediaPool.importMediaFiles([pdf], copyIntoProject: false),
      );

      await openOnThePool(tester, s, pdf);

      expect(rangeIsOn(tester), isFalse);
      expect(
        find.byKey(const ValueKey<String>('transport-play')),
        findsOneWidget,
        reason: 'the bar itself stays, inert',
      );
    });
  });

  /// IN/OUT over a document's PAGES: a hundred-page conte comes in for the
  /// span someone is drawing, not for all of it.
  testWidgets('a PDF placed with a range lands only those pages, and the '
      'RIGHT ones', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    addTearDown(PdfRenderService.debugResetForTests);
    final fake = FakePdfDocument(
      pageSizes: const [
        ui.Size(595, 842),
        ui.Size(595, 842),
        ui.Size(595, 842),
        ui.Size(595, 842),
        ui.Size(595, 842),
      ],
    );
    // The piece the chosen pages are cut into: two pages of its own.
    final piece = FakePdfDocument(
      pageSizes: const [ui.Size(595, 842), ui.Size(595, 842)],
    );
    final pdfPath = await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}conte.pdf');
      await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      // In the pool's spelling — the one the opener is handed.
      return normalizedMediaPath(file.path);
    });
    PdfRenderService.debugOpenerOverride = (source) async =>
        source.wholeFilePath == pdfPath ? fake : piece;
    final cutFrom = <(String, int, int)>[];
    PdfRenderService.debugPageSpanOverride = (path, first, count) async {
      cutFrom.add((path, first, count));
      return Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]);
    };
    final cutsBefore = s.repository.requireProject().tracks.first.cuts.length;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [pdfPath!]),
        ),
      ),
    );
    await tester.pump();
    await pickCell(tester, column: 'into', path: pdfPath, option: 'newCut');

    // Pages three and four of five.
    await keepImportSpan(tester, 3, 4);

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    final lines = watchTheLine(tester);
    await pumpPastTheWaitWindow(tester);
    // 🗣️F-494: the cut named from its start — a page range's says nothing
    // until it is done — then the piece's door, as a whole file's.
    expect(lines, [
      '',
      AppText.strings.imStepWritingSpan,
      AppText.strings.imStepCarrying,
      AppText.strings.imStepRasterizing,
      '',
    ]);
    // The CUT lands before its pages are drawn — the structure is
    // committed first and the bakes follow — so waiting for the cut alone
    // would read the render log half-written.
    await settleAsync(
      tester,
      () =>
          s.repository.requireProject().tracks.first.cuts.length > cutsBefore &&
          piece.renderRequests.length >= 2,
    );
    await tester.pumpAndSettle();

    final cut = s.repository.requireProject().tracks.first.cuts.firstWhere(
      (cut) => cut.name == 'conte_3-4',
    );
    final layer = cut.layers.firstWhere((l) => l.name == 'conte_3-4');
    expect(layer.frames, hasLength(2), reason: 'two pages, not five');
    expect(
      cutFrom,
      [(pdfPath, 2, 2)],
      reason: 'the pages the user chose, zero-based against the document — '
          'cut out of the ORIGINAL into the piece the project carries '
          '(유저 2026-09-23: 자른 구간만 품는다)',
    );
    final pages = [for (final request in piece.renderRequests) request.$1];
    expect(
      pages,
      containsAll(<int>[0, 1]),
      reason: 'the cels are the piece, whole — its two pages ARE the ones '
          'the user chose',
    );
    final pool = s.repository.requireProject().mediaAssets;
    expect(
      [for (final asset in pool) (mediaFileName(asset.path), asset.sourcePath)],
      [('conte_3-4.pdf', pdfPath)],
      reason: 'the pool names the piece; the original is where it came from',
    );
    final piecePath = pool.single.path;
    // The piece is let go of once its door returns — after the last page
    // has baked, which is later than the renders being asked for. Its bytes
    // were held before it landed, so THAT is no sign the door is done.
    await settleAsync(tester, () => !File(piecePath).existsSync());
    expect(
      stagedCopyIn(s, piecePath),
      isNotNull,
      reason: 'carried from the moment it landed (「품은 순간 데이터를 가지고」)',
    );
    expect(
      File(piecePath).existsSync(),
      isFalse,
      reason: 'the file the door read is gone — the staged copy is the only one',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯BAKED, a PDF placed with a range is drawn from the file '
      'itself — no piece is cut for an entry it will not keep (F-282-Q6)', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    addTearDown(PdfRenderService.debugResetForTests);
    final fake = FakePdfDocument(
      pageSizes: List.filled(5, const ui.Size(595, 842)),
    );
    final pdfPath = await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}conte.pdf');
      await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      return normalizedMediaPath(file.path);
    });
    PdfRenderService.debugOpenerOverride = (_) async => fake;
    final cutFrom = <(String, int, int)>[];
    PdfRenderService.debugPageSpanOverride = (path, first, count) async {
      cutFrom.add((path, first, count));
      return Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]);
    };
    final cutsBefore = s.repository.requireProject().tracks.first.cuts.length;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [pdfPath!]),
        ),
      ),
    );
    await tester.pump();
    await pickCell(tester, column: 'into', path: pdfPath, option: 'newCut');
    await keepImportSpan(tester, 3, 4);
    final bake = find.byKey(ValueKey<String>('import-cell-bake-$pdfPath'));
    await tester.ensureVisible(bake);
    await tester.pumpAndSettle();
    await tester.tap(bake);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    int cutCount() => s.repository.requireProject().tracks.first.cuts.length;
    await settleAsync(tester, () => cutCount() != cutsBefore);
    await tester.pumpAndSettle();

    // Named for the file: no piece was cut to lend it a span's name.
    final cut = s.repository.requireProject().tracks.first.cuts.last;
    final layer = cut.layers.firstWhere((layer) => layer.name == 'conte');
    expect(layer.mediaReference, isNull, reason: 'CONTROL: baked');
    expect(layer.frames, hasLength(2), reason: 'two pages, not five');
    expect(
      cutFrom,
      isEmpty,
      reason: 'a piece is a pool entry\'s to be, and a baked placement keeps '
          'none — its span is drawn from the file through the door\'s IN/OUT',
    );
    expect(
      s.repository.requireProject().mediaAssets,
      isEmpty,
      reason: 'baked, it keeps no entry (유저 2026-10-09: 「구우면 풀에 안 '
          '남긴다」)',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯a PDF REGISTERED with a range comes in as a piece of those '
      'pages — the same step a placement takes', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    addTearDown(PdfRenderService.debugResetForTests);
    final fake = FakePdfDocument(
      pageSizes: List.filled(5, const ui.Size(595, 842)),
    );
    final pdfPath = await tester.runAsync(() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}conte.pdf');
      await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
      return file.path;
    });
    PdfRenderService.debugOpenerOverride = (_) async => fake;
    final cutFrom = <(String, int, int)>[];
    PdfRenderService.debugPageSpanOverride = (path, first, count) async {
      cutFrom.add((path, first, count));
      return Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]);
    };
    final cutsBefore = s.repository.requireProject().tracks.first.cuts.length;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(
            session: s,
            initialPaths: [pdfPath!],
            poolOnly: true,
          ),
        ),
      ),
    );
    await tester.pump();

    // Pages two and three of five.
    await keepImportSpan(tester, 2, 3);

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    final lines = watchTheLine(tester);
    final counted = watchTheBar(tester);
    await pumpPastTheWaitWindow(tester);
    List<MediaAsset> pool() => s.repository.requireProject().mediaAssets;
    await settleAsync(tester, () => pool().isNotEmpty);
    await tester.pumpAndSettle();

    // 🗣️F-494: the cut is named from its start — a page range's says
    // nothing until it is done — and then the piece's holding.
    expect(lines, [
      '',
      AppText.strings.imStepWritingSpan,
      '',
      AppText.strings.imStepCarrying,
      '',
    ]);
    // Each an even share of the file's: the cut the first half, the
    // holding the second — the piece read twice, its first read a half
    // of the holding (`mediaBlobReadsAtMost`).
    expectOneBar(counted, [0, 0.75, 1]);

    expect(cutFrom, [(pdfPath, 1, 2)], reason: 'cut out of the original');
    expect(
      [for (final asset in pool()) (mediaFileName(asset.path), asset.sourcePath)],
      [('conte_2-3.pdf', pdfPath)],
      reason: 'the pool names the piece; the original is where it came from',
    );
    final piecePath = pool().single.path;
    expect(pool().single.carried, isTrue);
    expect(
      stagedCopyIn(s, piecePath),
      isNotNull,
      reason: 'held the moment it was registered',
    );
    expect(
      File(piecePath).existsSync(),
      isFalse,
      reason: 'the file the pool was handed is gone — the held copy is the '
          'only one',
    );
    expect(
      s.repository.requireProject().tracks.first.cuts.length,
      cutsBefore,
      reason: 'registered, not placed',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  /// PLACE: the pool row's way onto the timeline. The same window, minus
  /// the question it has already answered — which file.
  testWidgets('place mode drops the source bar and says what it is doing', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(() => writePng('bg.png'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(
            session: s,
            initialPaths: [path!],
            placeOnly: true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Place — bg.png'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('import-source-line')),
      findsNothing,
      reason: 'the source is what the row already decided — the title says '
          'it',
    );
    expect(
      find.byKey(const ValueKey<String>('import-file-table')),
      findsOneWidget,
      reason: 'and every other answer is still the row\'s to give',
    );
    expect(
      find.byKey(const ValueKey<String>('import-column-into')),
      findsOneWidget,
    );
  });

  testWidgets('an already-registered asset placed again does not register '
      'twice', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(() => writePng('bg.png'));
    await s.mediaPool.importMediaFiles([path!], copyIntoProject: true);
    expect(s.mediaPool.mediaAssets, hasLength(1));
    final layersBefore = s.requireActiveCut.layers.length;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [path], placeOnly: true),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    await settleAsync(
      tester,
      () => s.requireActiveCut.layers.length > layersBefore,
    );
    await tester.pumpAndSettle();

    expect(s.requireActiveCut.layers.length, layersBefore + 1);
    expect(
      s.mediaPool.mediaAssets,
      hasLength(1),
      reason: 'the pool already knew this file',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯the run stands behind the app\'s wait window from its first '
      'frame — counting from 0%, its Cancel standing throughout and grey '
      'with no wait to stop — and leaves on its check (F-282-Q1)', (
    tester,
  ) async {
    // 유저 2026-10-08: 「굽기 · 저장과 같은 기다림 창에」.
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final first = await tester.runAsync(() => writePng('first.png'));
    final second = await tester.runAsync(() => writePng('second.png'));
    final layersBefore = s.requireActiveCut.layers.length;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [first!, second!]),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await tester.pump();
    await tester.pump();

    final window = find.byKey(const ValueKey<String>('import-progress-dialog'));
    expect(window, findsOneWidget);
    expect(
      find.descendant(
        of: window,
        matching: find.byKey(const ValueKey<String>('app-progress-percent')),
      ),
      findsOneWidget,
      reason: 'it counts the files from the first one',
    );
    final cancel = find.descendant(
      of: window,
      matching: find.byKey(const ValueKey<String>('app-progress-cancel')),
    );
    expect(cancel, findsOneWidget, reason: 'the stop stands throughout');

    final checked = await settleAsync(
      tester,
      () => find
          .byKey(const ValueKey<String>('app-progress-done'))
          .evaluate()
          .isNotEmpty,
      step: const Duration(milliseconds: 20),
    );
    expect(checked, isTrue, reason: 'it says it is over');
    expect(cancel, findsOneWidget, reason: 'still standing — not gone');
    expect(
      tester.widget<TextButton>(cancel).onPressed,
      isNull,
      reason: 'nothing is being waited for: there is nothing to stop',
    );
    await pumpPastTheWaitWindow(tester);
    expect(s.requireActiveCut.layers.length, layersBefore + 2);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯a stop gives up the ONE file it was said to — the next '
      'file\'s wait is its own, and it lands when its bytes come', (
    tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final first = await tester.runAsync(() => writePng('cloud-a.png'));
    final second = await tester.runAsync(() => writePng('cloud-b.png'));
    final secondBytes = await tester.runAsync(
      () => File(second!).readAsBytes(),
    );
    final layersBefore = s.requireActiveCut.layers.length;
    final cloudLine = AppText.strings.openWaitingCloudTemplate
        .split('{sec}')
        .first;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [first!, second!]),
        ),
      ),
    );
    await tester.pump();
    // Both turn into placeholders only now — see the test below for why.
    await tester.runAsync(() async {
      await emptyWhenFree(File(first));
      await emptyWhenFree(File(second));
    });
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));

    final waitWindow = find.byKey(
      const ValueKey<String>('import-progress-dialog'),
    );
    final lineThere = find.descendant(
      of: waitWindow,
      matching: find.textContaining(cloudLine),
    );
    Future<bool> pumpUntil(bool Function() done) =>
        settleAsync(tester, done, step: const Duration(milliseconds: 300));

    expect(
      await pumpUntil(() => lineThere.evaluate().isNotEmpty),
      isTrue,
      reason: 'the first file is waited for',
    );
    await tester.tap(
      find.descendant(
        of: waitWindow,
        matching: find.byKey(const ValueKey<String>('app-progress-cancel')),
      ),
    );
    // The first is given up — its line goes — and the second's wait is a
    // wait of its own, its line coming up again.
    expect(
      await pumpUntil(() => lineThere.evaluate().isEmpty),
      isTrue,
      reason: 'the first file\'s wait ended',
    );
    expect(
      await pumpUntil(
        () =>
            waitWindow.evaluate().isEmpty || lineThere.evaluate().isNotEmpty,
      ),
      isTrue,
    );
    expect(
      lineThere,
      findsOneWidget,
      reason: 'the stop said to the first file did not give up the second',
    );
    await tester.runAsync(() => File(second).writeAsBytes(secondBytes!));
    await pumpPastTheWaitWindow(tester);

    expect(s.requireActiveCut.layers.length, layersBefore + 1);
    final notice = await openImportWarnings(tester);
    expect(
      find.descendant(of: notice, matching: find.text('cloud-a.png')),
      findsOneWidget,
      reason: 'the one given up is named',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🚨 a placement WAITS for a file that has not arrived, says '
      'whose work the wait is, and can be stopped', (tester) async {
    // The same law the two open doors go through, applied where an
    // import actually READS. A cloud pick arrives as a placeholder and
    // used to fail here as if the file were corrupt.
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(() => writePng('cloudy.png'));
    final layersBefore = s.requireActiveCut.layers.length;
    // Built from the string itself, and only the part before the count:
    // the suite runs in whatever locale the app defaults to, so a literal
    // Korean line here would pass or fail on the language rather than on
    // the behaviour.
    final cloudLine = AppText.strings.openWaitingCloudTemplate
        .split('{sec}')
        .first;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [path!]),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text(AppText.strings.imIntoNewLayer),
      findsOneWidget,
      reason: 'the placement branch is the one under test',
    );
    // ⚠️Emptied only NOW, after the window has read it to fill its
    // defaults. A file that is a placeholder from the start never gets a
    // placement destination at all, and the test would be measuring the
    // setup rather than the import: what a cloud pick actually does is
    // answer the window and then not read at the moment of import.
    await tester.runAsync(() => emptyWhenFree(File(path)));
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));

    // It waits rather than failing, and the line names the cloud — on the
    // wait window the run stands behind (F-282-Q1: 「클라우드 파일을
    // 기다리는 줄과 「그만」도 이 창으로 옮긴다」).
    final waitWindow = find.byKey(
      const ValueKey<String>('import-progress-dialog'),
    );
    final lineThere = find.descendant(
      of: waitWindow,
      matching: find.textContaining(cloudLine),
    );
    // Real time for the file probes, and the FAKE clock moved forward for
    // the wait's own pacing — a bare pump leaves it where it was, the 250ms
    // step never elapses, and the test measures nothing.
    final waited = await settleAsync(
      tester,
      () => lineThere.evaluate().isNotEmpty,
      step: const Duration(milliseconds: 300),
    );
    expect(
      waited,
      isTrue,
      reason: 'the import said it was waiting on the cloud, not failing',
    );
    expect(s.requireActiveCut.layers.length, layersBefore);

    // And the wait can be let go of — the wait window's Cancel is live
    // while the import waits on bytes that are not its own.
    await tester.tap(
      find.descendant(
        of: waitWindow,
        matching: find.byKey(const ValueKey<String>('app-progress-cancel')),
      ),
    );
    await pumpPastTheWaitWindow(tester);
    expect(
      find.textContaining(cloudLine),
      findsNothing,
      reason: 'stopping the wait ends it',
    );
    expect(
      s.requireActiveCut.layers.length,
      layersBefore,
      reason: 'nothing was placed from a file that never arrived',
    );
    final notice = await openImportWarnings(tester);
    expect(
      find.descendant(of: notice, matching: find.text('cloudy.png')),
      findsOneWidget,
      reason: 'the file given up is named in the import window\'s warnings',
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  /// 🚨WHAT SUCCEEDED LEAVES THE LIST.
  ///
  /// A mixed batch is the normal case — one file is corrupt, the rest are
  /// fine — and the window stays open so the warning can be read. Pressing
  /// Import again then has to import ONLY what is left: the rule was
  /// written in a comment and nothing checked it, so mutating the removal
  /// away left the whole suite green (2026-09-05).
  group('the tally after a mixed batch', () {
    Future<String> writeBrokenPng(String name) async {
      final file = File('${tempDir.path}${Platform.pathSeparator}$name');
      // A .png that is not a PNG: the kind is image, the file reads, and
      // the decode is what fails — the per-file failure this window has
      // to survive.
      await file.writeAsBytes(const [1, 2, 3, 4, 5, 6, 7, 8]);
      return file.path;
    }

    /// Imports [paths] into a fresh session, and answers it. It waits out
    /// the wait window, so it ends by stopping playback's warmer
    /// (`pumpPastTheWaitWindow`) — for every test that imports through it.
    Future<EditorSessionManager> runImport(
      WidgetTester tester,
      List<String> paths,
    ) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(session: session, initialPaths: paths),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      await pumpPastTheWaitWindow(tester);
      await settleAsync(tester, () => !tester.any(find.text('Importing…')));
      // The file left on the list is previewed again, and its spinner never
      // lets the frames settle until the page lands. ↩️A bare
      // `pumpAndSettle` held only while the wait before it happened to lend
      // the real clock once more after the run — 20ms the preview's read
      // needed, and got by luck.
      await settleLoadedPages(tester);
      session.playbackRig.prerenderScheduler.cancel();
      return session;
    }

    testWidgets('🚨the file that LANDED is gone from the list and the one '
        'that failed is still there — pressing Import again must not '
        'import the good one twice', (tester) async {
      final good = await tester.runAsync(() => writePng('lands.png'));
      final bad = await tester.runAsync(() => writeBrokenPng('breaks.png'));
      await runImport(tester, [good!, bad!]);

      expect(
        find.byKey(ValueKey<String>('import-name-$bad')),
        findsOneWidget,
        reason: 'the failure is still on the list to retry',
      );
      expect(
        find.byKey(ValueKey<String>('import-name-$good')),
        findsNothing,
        reason: 'it already landed — importing it again would duplicate it',
      );
      // The row names its file without the extension and shows the extension
      // on its own — the split the media pool shares (mediaFileNameParts).
      expect(
        tester
            .widget<Text>(find.byKey(ValueKey<String>('import-name-$bad')))
            .data,
        'breaks',
      );
      expect(find.text('.png'), findsOneWidget);
    });

    testWidgets('🚨a WARNING holds the window open — the whole point of the '
        'list surviving is that there is something to read and retry', (
      tester,
    ) async {
      final good = await tester.runAsync(() => writePng('lands.png'));
      final bad = await tester.runAsync(() => writeBrokenPng('breaks.png'));
      await runImport(tester, [good!, bad!]);

      expect(
        find.byKey(const ValueKey<String>('import-run-button')),
        findsOneWidget,
        reason: 'the window did not close on a batch that half-failed',
      );
      expect(
        find.text('Nothing imported.'),
        findsNothing,
        reason: 'one of the two DID land',
      );
    });

    testWidgets('and the good file really did land — the removal is not the '
        'window quietly dropping it', (tester) async {
      final good = await tester.runAsync(() => writePng('lands.png'));
      final bad = await tester.runAsync(() => writeBrokenPng('breaks.png'));
      final session = await runImport(tester, [good!, bad!]);

      expect(
        session.requireActiveCut.layers.any(
          (layer) => layer.kind == LayerKind.image,
        ),
        isTrue,
      );
    });

    testWidgets('🎯F-370-Q1: what the run could not do is the status line\'s '
        '「N warnings」, and it opens the Open door\'s notice — each reason '
        'once, over every file it was said of', (tester) async {
      final good = await tester.runAsync(() => writePng('lands.png'));
      final first = await tester.runAsync(() => writeBrokenPng('breaks.png'));
      final second = await tester.runAsync(() => writeBrokenPng('snaps.png'));
      await runImport(tester, [good!, first!, second!]);

      expect(
        find.descendant(
          of: importWarningsButton,
          matching: find.text('2 warnings'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('import-status')),
        findsNothing,
        reason: 'the line is the button, not the warnings one after another',
      );
      final notice = await openImportWarnings(tester);
      Finder inNotice(String text) =>
          find.descendant(of: notice, matching: find.text(text));
      expect(inNotice(AppText.strings.imLeftBehind), findsOneWidget);
      expect(
        inNotice('Could not be imported. (2)'),
        findsOneWidget,
        reason: 'the reason said once, not once a file',
      );
      expect(
        [
          for (final name in ['breaks.png', 'snaps.png'])
            if (inNotice(name).evaluate().length != 1) name,
        ],
        isEmpty,
        reason: 'every file, a line of its own',
      );
    });

    /// Runs the window on [paths] and answers the notice its warnings open,
    /// once the run has left them on the status line — a picture the window
    /// [previews] shown first: a Photoshop file is read whole for it, and
    /// held while it is (the file table's PSD pins) — and what the rows are
    /// [asked] answered before Import is pressed; the pool's window when
    /// it is [poolOnly].
    Future<Finder> warningsAfterImporting(
      WidgetTester tester,
      List<String> paths, {
      bool previews = false,
      Future<void> Function()? asked,
      bool poolOnly = false,
    }) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(
              session: session,
              initialPaths: paths,
              poolOnly: poolOnly,
            ),
          ),
        ),
      );
      await tester.pump();
      if (previews) {
        expect(
          await settleAsync(tester, () => tester.importPreviewImage != null),
          isTrue,
        );
      }
      await asked?.call();
      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      await pumpPastTheWaitWindow(tester);
      await settleAsync(
        tester,
        () => importWarningsButton.evaluate().isNotEmpty,
      );
      session.playbackRig.prerenderScheduler.cancel();
      // 🚨A run that landed some of the files and not others leaves the
      // preview opening the next: its spinner never settles until that
      // page lands. ↩️The wait window's loop lent real time after its last
      // frame, and that slice opened it — or did not, on a busy machine.
      await settleLoadedPages(tester);
      return openImportWarnings(tester);
    }

    testWidgets('F-370-Q1: what a door says of a layer is listed under it in '
        'the same notice — a Photoshop file\'s, as the Open door lists a '
        'converted file\'s', (tester) async {
      final psd = await tester.runAsync(() async {
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}locked.psd',
        );
        await file.writeAsBytes(
          buildPsd(
            width: 4,
            height: 4,
            layers: [
              for (final name in ['ink', 'shade'])
                PsdTestLayer(
                  name: name,
                  left: 0,
                  top: 0,
                  right: 4,
                  bottom: 4,
                  planes: psdSolidPlanes(4, 4, [10, 20, 30]),
                  protection: 0x80000000,
                ),
            ],
            compositePlanes: [Uint8List(16), Uint8List(16), Uint8List(16)],
          ),
        );
        return file.path;
      });
      final notice = await warningsAfterImporting(tester, [
        psd!,
      ], previews: true);
      Finder inNotice(String text) =>
          find.descendant(of: notice, matching: find.text(text));

      expect(inNotice('Came in unlocked. (2)'), findsOneWidget);
      expect(
        [
          for (final layer in ['ink', 'shade'])
            if (inNotice(layer).evaluate().length != 1) layer,
        ],
        isEmpty,
        reason: 'each layer a line of its own, under what was said of it',
      );
    });

    testWidgets('F-370-Q1: what a cut folder\'s import said of no one file is '
        'a line of the notice\'s own sentence', (tester) async {
      final folder = await tester.runAsync(() async {
        final sep = Platform.pathSeparator;
        await writePng('scans${sep}A1.png');
        return '${tempDir.path}${sep}scans';
      });
      final notice = await warningsAfterImporting(tester, [folder!]);

      expect(
        find.descendant(
          of: notice,
          matching: find.text(
            [
              AppText.strings.imLeftBehind,
              'No cut number found in the folder name.',
            ].join('\n'),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('F-370-Q1: a Photoshop file with no layers to keep is named '
        'under what was said of it', (tester) async {
      final flat = await tester.runAsync(() async {
        final file = File('${tempDir.path}${Platform.pathSeparator}flat.psd');
        await file.writeAsBytes(
          buildPsd(
            width: 4,
            height: 4,
            compositePlanes: [Uint8List(16), Uint8List(16), Uint8List(16)],
          ),
        );
        return file.path;
      });
      final notice = await warningsAfterImporting(tester, [
        flat!,
      ], previews: true);
      Finder inNotice(String text) =>
          find.descendant(of: notice, matching: find.text(text));

      expect(
        inNotice('No layers to expand — import it merged instead. (1)'),
        findsOneWidget,
      );
      expect(inNotice('flat.psd'), findsWidgets);
    });

    testWidgets('F-370-Q1: a PDF whose pages did not all render is named '
        'under how many did not', (tester) async {
      addTearDown(PdfRenderService.debugResetForTests);
      PdfRenderService.debugOpenerOverride = (_) async => FakePdfDocument(
        pageSizes: List.filled(3, const ui.Size(595, 842)),
        unrenderable: const {1, 2},
      );
      final pdf = await tester.runAsync(() async {
        final file = File('${tempDir.path}${Platform.pathSeparator}conte.pdf');
        await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
        return file.path;
      });
      final notice = await warningsAfterImporting(
        tester,
        [pdf!],
        asked: () =>
            pickCell(tester, column: 'into', path: pdf, option: 'newCut'),
      );
      Finder inNotice(String text) =>
          find.descendant(of: notice, matching: find.text(text));

      expect(
        inNotice('2 page(s) failed to render — their cels stay empty. (1)'),
        findsOneWidget,
      );
      // By the name the pool gave it as it came in (F-376) — the flat
      // Photoshop file above never came in, so it keeps its file's name.
      expect(inNotice('conte'), findsOneWidget);
    });

    testWidgets('F-370-Q1: a cut folder gone before Import is said as a line '
        'of the notice\'s own sentence', (tester) async {
      final folder = await tester.runAsync(() async {
        final sep = Platform.pathSeparator;
        await writePng('gone_01_002_lo${sep}A1.png');
        return '${tempDir.path}${sep}gone_01_002_lo';
      });
      final notice = await warningsAfterImporting(
        tester,
        [folder!],
        // Moved away rather than deleted: a recursive delete in test/ sits
        // in one of the two seats (a_temp_dir_cleans_itself_up_in_one_place)
        // and the folder is gone from where it was picked all the same.
        asked: () => tester.runAsync(
          () => Directory(folder).rename('$folder-moved'),
        ),
      );

      expect(
        find.descendant(
          of: notice,
          matching: find.text(
            [
              AppText.strings.imLeftBehind,
              'Could not read that folder.',
            ].join('\n'),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('F-370-Q1: a file its door could not open is named under '
        'corrupt or locked', (tester) async {
      addTearDown(PdfRenderService.debugResetForTests);
      // A PDF that will not open — locked, say: its renderer throws.
      PdfRenderService.debugOpenerOverride = (_) async =>
          throw const FormatException('a password is needed');
      final pdf = await tester.runAsync(() async {
        final file = File('${tempDir.path}${Platform.pathSeparator}locked.pdf');
        await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
        return file.path;
      });
      final notice = await warningsAfterImporting(
        tester,
        [pdf!],
        asked: () =>
            pickCell(tester, column: 'into', path: pdf, option: 'newCut'),
      );
      Finder inNotice(String text) =>
          find.descendant(of: notice, matching: find.text(text));

      expect(
        inNotice('Could not be opened — corrupt or password-locked. (1)'),
        findsOneWidget,
      );
      expect(inNotice('locked.pdf'), findsOneWidget);
    });

    testWidgets('F-370-Q1: a PDF registered as the pages it keeps, whose '
        'pages could not be cut out, is named — and nothing registers in '
        'their stead', (tester) async {
      addTearDown(PdfRenderService.debugResetForTests);
      PdfRenderService.debugOpenerOverride = (_) async => FakePdfDocument(
        pageSizes: List.filled(5, const ui.Size(595, 842)),
      );
      // The renderer could not write those pages out as a file of their own.
      PdfRenderService.debugPageSpanOverride = (path, first, count) async =>
          null;
      final pdf = await tester.runAsync(() async {
        final file = File('${tempDir.path}${Platform.pathSeparator}conte.pdf');
        await file.writeAsBytes(const [0x25, 0x50, 0x44, 0x46]);
        return file.path;
      });
      final notice = await warningsAfterImporting(
        tester,
        [pdf!],
        poolOnly: true,
        asked: () => keepImportSpan(tester, 2, 3),
      );
      Finder inNotice(String text) =>
          find.descendant(of: notice, matching: find.text(text));

      expect(inNotice('Could not be imported. (1)'), findsOneWidget);
      expect(inNotice('conte.pdf'), findsOneWidget);
      expect(
        tester
            .widget<ImportDialog>(find.byType(ImportDialog))
            .session
            .repository
            .requireProject()
            .mediaAssets,
        isEmpty,
        reason: 'not the piece, and not the whole file in its place',
      );
    });

    testWidgets('F-370-Q1: what threw part-way through a run is a line of '
        'the notice\'s own sentence — and what landed before it stays '
        'landed', (tester) async {
      final good = await tester.runAsync(() => writePng('lands.png'));
      final cloudy = await tester.runAsync(() => writePng('cloudy.png'));
      final notice = await warningsAfterImporting(
        tester,
        [good!, cloudy!],
        asked: () async {
          // A file that has not arrived, whose provider is asked for it and
          // fails as a platform can: no file the run read, so said of none.
          FolderPicker.debugDownloadRequester = (_) async =>
              throw PlatformException(
                code: 'offline',
                message: 'the provider let go',
              );
          await tester.runAsync(() => emptyWhenFree(File(cloudy)));
        },
      );

      expect(
        find.descendant(
          of: notice,
          matching: find.textContaining('the provider let go'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('import-name-$good')),
        findsNothing,
        reason: 'it landed before the throw, and is not imported again',
      );
      expect(
        find.byKey(ValueKey<String>('import-name-$cloudy')),
        findsOneWidget,
        reason: 'what threw is still on the list to retry',
      );
    });

    testWidgets('F-370-Q1: the status line keeps its place — as tall before '
        'anything is said as the button it turns into', (tester) async {
      final bad = await tester.runAsync(() => writeBrokenPng('breaks.png'));
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(session: session, initialPaths: [bad!]),
          ),
        ),
      );
      await tester.pump();
      final line = find.byKey(const ValueKey<String>('import-status-line'));
      final run = find.byKey(const ValueKey<String>('import-run-button'));
      final lineBefore = tester.getRect(line);
      final runBefore = tester.getRect(run);
      expect(
        importWarningsButton,
        findsNothing,
        reason: 'with nothing to warn of, there is no button to press',
      );
      // Held, not shown: the button keeps the line as tall as it, and is
      // there for nothing else.
      final held = find.byKey(const ValueKey<String>('import-warnings-button'));
      expect(
        tester.widget<ButtonStyleButton>(held).onPressed,
        isNull,
        reason: 'no key reaches a button that is not there to see',
      );
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(of: held, matching: find.byType(Opacity)),
            )
            .opacity,
        0,
        reason: 'its place shows nothing',
      );

      await tester.tap(run);
      await pumpPastTheWaitWindow(tester);
      await settleAsync(
        tester,
        () => importWarningsButton.evaluate().isNotEmpty,
      );
      session.playbackRig.prerenderScheduler.cancel();

      expect(
        find.descendant(
          of: importWarningsButton,
          matching: find.text('1 warning'),
        ),
        findsOneWidget,
      );
      expect(tester.getRect(line), lineBefore);
      expect(tester.getRect(run), runBefore, reason: 'nothing under it moved');
    });
  });

  /// ⛔없다가 생기는 UI 금지: the table and the preview stand whatever is
  /// listed. ↩️With nothing picked the window swapped them for a line saying
  /// to pick something, and a cut folder for a list reading its parse out.
  testWidgets('with nothing picked the table stands, empty', (tester) async {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ImportDialog(session: session))),
    );
    await tester.pump();

    expect(
      tester.widget<ImportFileTable>(find.byType(ImportFileTable)).rows,
      isEmpty,
    );
  });

  testWidgets('one bar for the whole press: the files the pool takes fill '
      'their share of it, then each file placed its own — the second '
      'starting where the first\'s ends', (tester) async {
    final (kept, linked, first, second) = (await tester.runAsync(
      () async => (
        await writePng('kept.png'),
        await writePng('linked.png'),
        await writePng('first.png'),
        await writePng('second.png'),
      ),
    ))!;
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(
            session: session,
            initialPaths: [kept, linked, first, second],
          ),
        ),
      ),
    );
    // The preview's page spins until it lands, so no frame settles before.
    await settleLoadedPages(tester);
    Future<void> pick(String column, String path, String option) async {
      final cell = find.byKey(ValueKey<String>('import-cell-$column-$path'));
      await tester.ensureVisible(cell);
      await tester.pump();
      await tester.tap(cell);
      await settleLoadedPages(tester);
      await tester.tap(
        find.byKey(ValueKey<String>('import-option-$column-$option')),
      );
      await settleLoadedPages(tester);
    }

    await pick('into', kept, 'pool');
    await pick('into', linked, 'pool');
    await pick('file', linked, 'reference');

    final told = watchTheBar(tester);
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    session.playbackRig.prerenderScheduler.cancel();

    // Four files, a quarter each: the pool's two — the kept one carried
    // before the linked one registers — then the placed two, from half the
    // bar.
    expectOneBar(told, [0.25, 0.5, 0.75, 1]);
  });

  testWidgets('a kept file the pool already holds still fills its share — '
      'said outright, as its holding holds nothing — before the linked one '
      'registers (F-282-Q1)', (tester) async {
    final (held, linked) = (await tester.runAsync(
      () async => (await writePng('held.png'), await writePng('linked.png')),
    ))!;
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    await tester.runAsync(
      () => session.mediaPool.importMediaFiles([held], copyIntoProject: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(
            session: session,
            initialPaths: [held, linked],
            poolOnly: true,
          ),
        ),
      ),
    );
    await settleLoadedPages(tester);
    await pickCell(tester, column: 'file', path: linked, option: 'reference');

    final told = watchTheBar(tester);
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    await pumpPastTheWaitWindow(tester);
    session.playbackRig.prerenderScheduler.cancel();

    expectOneBar(told, [0, 0.5, 1]);
    expect(
      told.where((fraction) => fraction > 0 && fraction < 0.5),
      isEmpty,
      reason: 'the held file holds nothing again: $told',
    );
  });
}
