import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/import/import_file_table.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/psd_fixture.dart';

/// The import/placement window: the interpretation table shows the parse
/// (dropped files included), the settings answer with filled defaults,
/// and Import runs the session verbs.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-import-ui');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on Object {
      // Windows keeps handles briefly.
    }
  });

  Future<String> writePngFilled(String name, int fill) async {
    final pixels = Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, fill);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      8,
      8,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file.path;
  }

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
    // test font's glyphs are wide), so the cell is brought into view first.
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey<String>('import-option-$column-$option')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a dropped cut folder shows the interpretation (layers, '
      'pictures, exclusions) and Import builds the cut through the '
      'session', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final folderPath = await tester.runAsync(() async {
      const root = 'upn_02_063_lo';
      final sep = Platform.pathSeparator;
      await writePng('$root${sep}A1.png');
      await writePng('$root${sep}A2.png');
      await writePng('$root${sep}_BG.png');
      await File('${tempDir.path}$sep$root${sep}memo.txt').writeAsString('메모');
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

    expect(
      find.byKey(const ValueKey<String>('import-interpretation-table')),
      findsOneWidget,
    );
    expect(find.textContaining('063'), findsWidgets, reason: 'cut number');
    expect(find.textContaining('2 cels'), findsOneWidget, reason: 'layer A');
    expect(find.text('BG'), findsWidgets, reason: 'picture row');
    expect(
      find.textContaining('memo.txt'),
      findsOneWidget,
      reason: 'exclusions are listed, never silent',
    );
    expect(
      find.byKey(const ValueKey<String>('import-rasterize-toggle')),
      findsNothing,
      reason: 'folder imports ALWAYS bake (§6-z22) — no toggle to mislead',
    );
    expect(
      find.byKey(const ValueKey<String>('import-media-reference')),
      findsOneWidget,
      reason:
          'a folder still REGISTERS its references (the 참고영상 among '
          'them), so copy-or-reference has something to decide',
    );
    expect(
      find.textContaining('always bake'),
      findsOneWidget,
      reason: 'and the window says so',
    );

    final cutsBefore = s.repository.requireProject().tracks.first.cuts.length;
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    // Real IO completes inside runAsync, but the await CONTINUATIONS are
    // fake-zone microtasks that only pump() drains — interleave the two.
    for (var tries = 0; tries < 100; tries += 1) {
      if (s.repository.requireProject().tracks.first.cuts.length > cutsBefore) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final track = s.repository.requireProject().tracks.first;
    expect(track.cuts.length, cutsBefore + 1);
    final cut = track.cuts.firstWhere((cut) => cut.name == '063');
    expect(cut.layers.any((l) => l.kind == LayerKind.image), isTrue);
    expect(cut.layers.any((l) => l.name == 'A'), isTrue);
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
      find.byKey(const ValueKey<String>('import-place-timeline')),
      findsOneWidget,
    );
    expect(
      find.text(AppText.strings.imIntoNewLayer),
      findsOneWidget,
      reason: 'the row is already answered: into the cut you are in',
    );
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    for (var tries = 0; tries < 100; tries += 1) {
      if (s.requireActiveCut.layers.length > layersBefore) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(s.requireActiveCut.layers.length, layersBefore + 1);
    expect(
      s.requireActiveCut.layers.any(
        (l) => l.kind == LayerKind.image && l.mediaReference != null,
      ),
      isTrue,
      reason: 'the default is reference mode',
    );
  });

  /// The media pool's ＋ became a destination in this window rather
  /// than a picker of its own, which is what makes the two import
  /// entrances one. The browser accepted movies and the window refused
  /// them; now the window does both, and which one it does is the
  /// destination's business.
  group('the media pool is a destination', () {
    Future<String> writeMovie() async {
      final file = File('${tempDir.path}${Platform.pathSeparator}ref.mp4');
      await file.writeAsBytes(const [0, 0, 0, 24]);
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
        find.textContaining('placement not available'),
        findsNothing,
        reason: 'nothing is being placed, so nothing can be unplaceable',
      );
      expect(
        find.byKey(const ValueKey<String>('import-rasterize-toggle')),
        findsNothing,
        reason: 'rasterize is a question about a placed layer',
      );

      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      await tester.pumpAndSettle();

      expect(s.mediaPool.mediaAssets.single.path, path.replaceAll('\\', '/'));
      expect(s.mediaPool.mediaAssets.single.kind, MediaAssetKind.video);
    });

    testWidgets('the browser pins the pool — the other door is shown, not '
        'offered', (tester) async {
      final path = await tester.runAsync(writeMovie);
      await pumpWindow(tester, path!, poolOnly: true);

      await tester.tap(
        find.byKey(const ValueKey<String>('import-place-timeline')),
      );
      await tester.pump();
      expect(
        find.textContaining('placement not available'),
        findsNothing,
        reason: 'the chip is disabled: pressing it changes nothing',
      );
    });

    testWidgets('placed from anywhere else, the same movie is refused BY '
        'NAME', (tester) async {
      final path = await tester.runAsync(writeMovie);
      final s = await pumpWindow(tester, path!, poolOnly: false);

      await tester.tap(
        find.byKey(const ValueKey<String>('import-place-timeline')),
      );
      await tester.pump();
      expect(find.textContaining('placement not available'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('placement is not available'), findsOneWidget);
      expect(s.mediaPool.mediaAssets, isEmpty);
    });

    testWidgets('every other entrance still starts on a placement', (
      tester,
    ) async {
      final path = await tester.runAsync(() => writePng('drop.png'));
      await pumpWindow(tester, path!, poolOnly: false);

      expect(
        find.byKey(const ValueKey<String>('import-place-timeline')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('import-place-pool')),
        findsOneWidget,
        reason: 'the pool is on offer from here too — one window',
      );
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

    Future<void> runImport(WidgetTester tester, EditorSessionManager s) async {
      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      for (var tries = 0; tries < 100; tries += 1) {
        if (s.mediaPool.mediaAssets.isNotEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('it starts on Keep inside, on every platform', (tester) async {
      // It used to start on Reference everywhere but Apple, where a
      // recorded path dies at the next launch without a grant. Two things
      // moved since: the project carries its own media, so carrying costs
      // bytes inside a ZIP rather than a second file on disk, and video
      // DEFAULTS to Reference (mediaKindCarriedByDefault — a default only
      // since 2026-08-14, no longer a ceiling), so the 3GB-movie accident
      // that made Reference the blanket default answers itself per kind.
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
    PdfRenderService.debugOpenerOverride = (path) async => FakePdfDocument(
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
    for (var tries = 0; tries < 100; tries += 1) {
      if (s.repository.requireProject().tracks.first.cuts.length > cutsBefore) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final track = s.repository.requireProject().tracks.first;
    expect(track.cuts.length, cutsBefore + 1);
    expect(track.cuts.last.duration, 2, reason: '1 page = 1 frame');
    expect(s.mediaPool.mediaAssets.single.pageCount, 2);
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
    for (var tries = 0; tries < 100; tries += 1) {
      final status = tester.widgetList<Text>(
        find.byKey(const ValueKey<String>('import-status')),
      );
      if (status.isNotEmpty &&
          (status.first.data ?? '').contains('no PDF renderer')) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(
      find.textContaining('no PDF renderer'),
      findsOneWidget,
      reason: 'the absence is a stated condition, not a decode failure',
    );
    expect(s.mediaPool.mediaAssets, isEmpty);
  });

  // --- The size warning (A-2) ---------------------------------------------
  //
  // Keep inside is the default and the chips are one click apart, so the
  // cost of an accident is a project that quietly doubled. The window is
  // where the choice is made and where changing it is cheap; the save is
  // already too late, and a modal there is the shape this round has spent
  // its whole length avoiding.

  /// A file of [bytes] that costs no time to make — the length is what is
  /// being tested, never the contents.
  Future<String> writeBigFile(String name, int bytes) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.parent.create(recursive: true);
    final handle = file.openSync(mode: FileMode.write);
    handle.truncateSync(bytes);
    handle.closeSync();
    return file.path;
  }

  testWidgets('a large file bound for the project file says so — total, '
      'name and the way out', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(
      () => writeBigFile('마스터.wav', 120 * 1024 * 1024),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [path!]),
        ),
      ),
    );
    await tester.pump();

    final note = find.byKey(const ValueKey<String>('import-large-carry-note'));
    expect(note, findsOneWidget, reason: 'Keep inside is the default');
    final text = tester.widget<Text>(note).data!;
    expect(text, contains('120 MB'), reason: 'the number being decided');
    expect(text, contains('마스터'), reason: 'and what the answer acts on');
    expect(
      text,
      contains(AppText.strings.imModeReference),
      reason: 'the way out is named',
    );
  });

  testWidgets('choosing Reference takes the warning away', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(
      () => writeBigFile('마스터.wav', 120 * 1024 * 1024),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [path!]),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('import-large-carry-note')),
      findsOneWidget,
    );

    await pickCell(tester, column: 'file', path: path, option: 'reference');

    expect(
      find.byKey(const ValueKey<String>('import-large-carry-note')),
      findsNothing,
      reason: 'nothing large is going inside any more',
    );
  });

  testWidgets('a large MOVIE never warns — the kind keeps it outside '
      'whatever the chips say', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(
      () => writeBigFile('참고영상.mp4', 900 * 1024 * 1024),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [path!]),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('import-large-carry-note')),
      findsNothing,
      reason:
          'a warning about a file that was always staying outside is '
          'the noise that teaches people to ignore the real one',
    );
  });

  testWidgets('an ordinary file does not warn', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(() => writePng('보통.png'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [path!]),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('import-large-carry-note')),
      findsNothing,
    );
  });

  /// The table itself: one row per file, one column per question, and a
  /// press that speaks for exactly the rows it should.
  group('the file table', () {
    Future<String> writeMovie(String name) async {
      final file = File('${tempDir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(const [0, 0, 0, 24]);
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
      await tester.pump();
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
      await tester.tap(
        find.byKey(const ValueKey<String>('import-column-file')),
      );
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

    testWidgets('a movie starts as a reference and can be carried anyway', (
      tester,
    ) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      final movie = await tester.runAsync(() => writeMovie('ref.mp4'));
      await pump(tester, [png!, movie!]);

      expect(
        cellText(tester, 'file', movie),
        'Link',
        reason: 'three gigabytes should not land in a project by accident',
      );
      expect(cellText(tester, 'file', png), 'Keep');

      await pickCell(tester, column: 'file', path: movie, option: 'keepInside');

      expect(
        cellText(tester, 'file', movie),
        'Keep',
        reason: 'the kind decides the DEFAULT, and the user decides this',
      );
    });

    testWidgets('🚨a sound REGISTERS rather than places, and it still counts '
        'as imported — a batch of nothing but sound must not report '
        '"Nothing imported."', (tester) async {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      final wav = await tester.runAsync(() async {
        final file = File('${tempDir.path}${Platform.pathSeparator}take.wav');
        await file.writeAsBytes(const [0x52, 0x49, 0x46, 0x46]);
        return file.path;
      });
      // A PLACEMENT run (a destination is chosen), not the pool: this is
      // the branch where audio takes the batch door on its own.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(session: session, initialPaths: [wav!]),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
      for (var tries = 0; tries < 100; tries += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (!tester.any(find.text('Importing…'))) {
          break;
        }
      }
      await tester.pumpAndSettle();

      expect(
        session.repository.requireProject().mediaAssets,
        isNotEmpty,
        reason: 'the sound registered',
      );
      expect(
        find.text('Nothing imported.'),
        findsNothing,
        reason: 'a registration IS an import — the batch counted it',
      );
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

      await tester.tap(
        find.byKey(const ValueKey<String>('import-column-bake')),
      );
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

    testWidgets('expanding a PSD locks its BAKE on — one of them baked means '
        'all of them are — and leaves how the file is kept alone', (
      tester,
    ) async {
      final psd = await tester.runAsync(() => writePsd('BG.psd'));
      await pump(tester, [psd!]);

      expect(cellText(tester, 'psd', psd), 'Merge');
      expect(cellText(tester, 'bake', psd), AppText.strings.commonOff);
      expect(cellText(tester, 'file', psd), 'Keep');

      await pickCell(tester, column: 'psd', path: psd, option: 'expand');

      expect(cellText(tester, 'bake', psd), AppText.strings.commonOn);
      expect(cellText(tester, 'file', psd), 'Keep');
    });

    testWidgets('🚨the pool asks nothing about placement — the questions a '
        'placement asks are not there at all (유저 2026-09-11: 「플레이스가 '
        '풀이면 넣을곳 맞춤 PSD 열 삭제」)', (tester) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      await pump(tester, [png!], poolOnly: true);

      for (final id in ['bake', 'into', 'fit', 'psd']) {
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
    testWidgets('a still shows no IN/OUT — a range that cannot act is a '
        'control that lies', (tester) async {
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
        find.byKey(const ValueKey<String>('transport-in')),
        findsNothing,
        reason: 'one frame has no span to choose',
      );
      expect(
        find.byKey(const ValueKey<String>('transport-play')),
        findsOneWidget,
        reason: 'the bar itself stays, inert, rather than blinking in and out',
      );
    });

    testWidgets('registering into the pool shows no IN/OUT either — trimming '
        'what is only registered would have to write the trimmed bytes', (
      tester,
    ) async {
      final s = EditorSessionManager(initialProject: createDefaultProject());
      addTearDown(s.dispose);
      final png = await tester.runAsync(() => writePng('a.png'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImportDialog(
              session: s,
              initialPaths: [png!],
              poolOnly: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey<String>('transport-in')), findsNothing);
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
    PdfRenderService.debugOpenerOverride = (path) async => fake;
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
    await pickCell(tester, column: 'into', path: pdfPath, option: 'newCut');

    // Pages three and four of five: IN and OUT are one-based on screen.
    await tester.tap(find.byKey(const ValueKey<String>('transport-in')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('transport-in-input')),
      '3',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('transport-out')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('transport-out-input')),
      '4',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    // The CUT lands before its pages are drawn — the structure is
    // committed first and the bakes follow — so waiting for the cut alone
    // would read the render log half-written.
    for (var tries = 0; tries < 200; tries += 1) {
      if (s.repository.requireProject().tracks.first.cuts.length > cutsBefore &&
          fake.renderRequests.length >= 3) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final cut = s.repository.requireProject().tracks.first.cuts.firstWhere(
      (cut) => cut.name == 'conte.pdf',
    );
    final layer = cut.layers.firstWhere((l) => l.name == 'conte.pdf');
    expect(layer.frames, hasLength(2), reason: 'two pages, not five');
    final pages = [for (final request in fake.renderRequests) request.$1];
    expect(
      pages,
      containsAll(<int>[2, 3]),
      reason: 'the pages the user chose, zero-based against the document',
    );
    expect(pages, isNot(contains(1)), reason: 'page two was outside IN');
    expect(pages, isNot(contains(4)), reason: 'page five was outside OUT');
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
      find.byKey(const ValueKey<String>('import-browse-files-button')),
      findsNothing,
      reason: 'the source is what the row already decided',
    );
    expect(
      find.byKey(const ValueKey<String>('import-file-table')),
      findsOneWidget,
      reason: 'and every other answer is still the row\'s to give',
    );
    expect(
      find.byKey(const ValueKey<String>('import-place-timeline')),
      findsOneWidget,
    );
  });

  testWidgets('an already-registered asset placed again does not register '
      'twice', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(() => writePng('bg.png'));
    s.mediaPool.importMediaFiles([path!], copyIntoProject: true);
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
    for (var tries = 0; tries < 100; tries += 1) {
      if (s.requireActiveCut.layers.length > layersBefore) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(s.requireActiveCut.layers.length, layersBefore + 1);
    expect(
      s.mediaPool.mediaAssets,
      hasLength(1),
      reason: 'the pool already knew this file',
    );
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
    await tester.runAsync(() => File(path).writeAsBytes(const <int>[]));
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));

    // It waits rather than failing, and the line names the cloud.
    var waited = false;
    for (var tries = 0; tries < 40 && !waited; tries += 1) {
      // Real time for the file probes, and the FAKE clock moved forward
      // for the wait's own pacing — a bare pump leaves it where it was,
      // the 250ms step never elapses, and the test measures nothing.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      waited = find.textContaining(cloudLine).evaluate().isNotEmpty;
    }
    expect(
      waited,
      isTrue,
      reason: 'the import said it was waiting on the cloud, not failing',
    );
    expect(s.requireActiveCut.layers.length, layersBefore);

    // And the wait can be let go of — Cancel is live again while the
    // import is waiting on bytes that are not its own.
    await tester.tap(
      find.byKey(const ValueKey<String>('import-cancel-button')),
    );
    for (var tries = 0; tries < 40; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      if (find.textContaining(cloudLine).evaluate().isEmpty) {
        break;
      }
    }
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
      for (var tries = 0; tries < 100; tries += 1) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (!tester.any(find.text('Importing…'))) {
          break;
        }
      }
      await tester.pumpAndSettle();
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
  });

  /// THE INTERPRETATION TABLE SAYS WHAT WILL HAPPEN, in the reader's own
  /// language and with the rows it will leave alone drawn as such.
  ///
  /// 감사 2026-09-09: nothing measured it. The kind label could be swapped
  /// for another kind's word and the dim rule dropped, and the suite stayed
  /// green — while the table printed `video` (a stored key) at a Japanese
  /// user and drew a refused row like an ordinary one.
  group('the interpretation table', () {
    Future<String> writeMovie(WidgetTester tester) async =>
        (await tester.runAsync(() async {
          final file = File('${tempDir.path}${Platform.pathSeparator}ref.mp4');
          await file.writeAsBytes(const [0, 0, 0, 24]);
          return file.path;
        }))!;

    Future<void> pumpOn(WidgetTester tester, List<String> paths) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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
      // A loose file is PROBED (identity, size) before the table can say
      // what it is; the real IO runs in runAsync and its awaits are
      // fake-zone microtasks that only pump() drains.
      for (var i = 0; i < 8; i += 1) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
    }


    testWidgets('with nothing picked it says so', (tester) async {
      await pumpOn(tester, const []);
      expect(find.text(AppText.strings.imPickToSee), findsOneWidget);
    });

    testWidgets('loose files go to the file TABLE — this table is not built '
        'for them at all', (tester) async {
      // 감사 2026-09-09: the table carried a loose-file branch that could
      // not run, because the only place that builds it is the arm where
      // `_files` is empty. It was still being kept in step with the kinds.
      await pumpOn(tester, [await writeMovie(tester)]);
      expect(
        find.byKey(const ValueKey<String>('import-interpretation-table')),
        findsNothing,
      );
      expect(find.byType(ImportFileTable), findsOneWidget);
    });

    testWidgets('a movie in a placing batch is refused in the reader\'s '
        'language, and the note names it', (tester) async {
      final movie = await writeMovie(tester);
      await pumpOn(tester, [movie]);

      final note = tester.widget<Text>(
        find.byKey(const ValueKey<String>('import-unplaceable-note')),
      );
      expect(note.data, contains(AppText.strings.imRegisterInstead));
      expect(note.data, contains('ref'));
    });
  });
}
