import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/services/persistence/folder_grant.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';

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

  /// Answers one question for one FILE: press its cell in [column] and pick
  /// [option] from the popup that column opens.
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
    await tester.tap(
      find.byKey(ValueKey<String>('import-cell-$column-$path')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>('import-option-$option')));
    await tester.pumpAndSettle();
  }

  /// A fully transparent PNG — what 「빈 사진 포함」 writes for an instance
  /// with no pixels (a quarter of the files in a real export).
  Future<String> writeBlankPng(String name) => writePngFilled(name, 0x00);

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
      await File('${tempDir.path}$sep$root${sep}memo.txt')
          .writeAsString('메모');
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
      reason: 'a folder still REGISTERS its references (the 참고영상 among '
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
      if (s.repository.requireProject().tracks.first.cuts.length >
          cutsBefore) {
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
      find.text('Layer'),
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

  /// The media browser's ＋ became a destination in this window rather
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

      await tester.tap(
        find.byKey(const ValueKey<String>('import-run-button')),
      );
      await tester.pumpAndSettle();

      expect(s.mediaAssets.single.path, path.replaceAll('\\', '/'));
      expect(s.mediaAssets.single.kind, MediaAssetKind.video);
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

      await tester.tap(
        find.byKey(const ValueKey<String>('import-run-button')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('placement is not available'), findsOneWidget);
      expect(s.mediaAssets, isEmpty);
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
        find.byKey(const ValueKey<String>('import-column-File')),
        findsOneWidget,
        reason: 'and whether a file is absorbed is that file\'s own answer',
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
        await s.saveProjectToFile(
          '${tempDir.path}${Platform.pathSeparator}scene.anicel',
        );
        return png;
      });
      return (s, path!);
    }

    Future<void> runImport(WidgetTester tester, EditorSessionManager s) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('import-run-button')),
      );
      for (var tries = 0; tries < 100; tries += 1) {
        if (s.mediaAssets.isNotEmpty) {
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
      // bytes inside a ZIP rather than a second file on disk, and the KIND
      // rule stops a 3GB movie from being carried at all — which was the
      // reason Reference had to be the default in the first place.
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
        expect(find.text('Ref'), findsNothing);
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
          home: Scaffold(body: ImportDialog(session: s, initialPaths: [path])),
        ),
      );
      await tester.pump();
      await pickCell(tester, column: 'File', path: path, option: 'Ref');
      expect(
        find.text('Ref'),
        findsOneWidget,
        reason: 'the row says which of the three it is on',
      );

      await runImport(tester, s);

      expect(s.mediaAssets.single.path, path.replaceAll('\\', '/'));
      expect(
        s.mediaAssets.single.carried,
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
          home: Scaffold(body: ImportDialog(session: s, initialPaths: [path])),
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
        s.mediaAssets.single.path,
        path.replaceAll('\\', '/'),
        reason: 'the project records the file where the user keeps it',
      );
      expect(
        s.mediaAssets.single.carried,
        isTrue,
        reason: 'and the next save packs it into the .anicel',
      );
      expect(
        Directory(
          '${tempDir.path}${Platform.pathSeparator}scene.assets',
        ).existsSync(),
        isFalse,
        reason: 'carrying is a fact about the SAVE — there was somewhere '
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

    await pickCell(tester, column: 'Into', path: pdfPath, option: 'New cut');
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    for (var tries = 0; tries < 100; tries += 1) {
      if (s.repository.requireProject().tracks.first.cuts.length >
          cutsBefore) {
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
    expect(s.mediaAssets.single.pageCount, 2);
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
    await pickCell(tester, column: 'Into', path: pdfPath, option: 'New cut');
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
    expect(s.mediaAssets, isEmpty);
  });

  testWidgets('a dropped TVPaint JSON export becomes the source outright, '
      'and Import lands the clip as one cut — exposure, hold edge and '
      'blank-instance labels included', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final jsonPath = await tester.runAsync(() async {
      // Forward slashes on purpose: that is how the export writes its
      // relative paths, whichever platform wrote it.
      await writePng('[001] A/[0001] A.png');
      await writePng('[001] A/[0004] A.png');
      await writeBlankPng('[002] SE/[0001] SE.png');
      // Layer A: two drawings three commas apart, then a hold edge.
      // Layer SE: one instance with no pixels, carrying only its label —
      // the shape 「빈 사진 포함」 produces.
      const json = '''
{"version":{"major":5,"minor":1},
 "project":{"camera":{"width":8,"height":8},
 "clip":{"name":"C001","width":8,"height":8,"framerate":24.0,
  "image-count":8,"bg":{"red":255,"green":255,"blue":255},
  "markin":{"status":false,"value":0},"markout":{"status":false,"value":0},
  "camera":{"points":[],"positions":[]},
  "layers":[
   {"name":"SE","position":1,"visible":true,"opacity":255,"start":0,"end":5,
    "pre-behavior":0,"post-behavior":0,"blending-mode":"Color",
    "link":[{"instance-index":0,"instance-name":"arisu,\\u304a\\u306f\\u3088",
      "file":"[002] SE/[0001] SE.png","images":[0]}],"repeat":[]},
   {"name":"A","position":2,"visible":true,"opacity":255,"start":0,"end":5,
    "pre-behavior":0,"post-behavior":3,"blending-mode":"Color",
    "link":[{"instance-index":0,"instance-name":"1",
      "file":"[001] A/[0001] A.png","images":[0]},
     {"instance-index":3,"instance-name":"2",
      "file":"[001] A/[0004] A.png","images":[3]}],"repeat":[]}
  ]}}}''';
      final file = File('${tempDir.path}/C001.json');
      await file.writeAsString(json);
      // The CSV that names the cels, exported beside the JSON and found
      // by stem — the JSON's own `instance-name` is TVPaint's counting
      // and is never read as a name. Layer A is named `1`/`2` here, and
      // SE's blank instance carries the label that IS its whole content.
      await File('${tempDir.path}/C001.csv').writeAsString(
        'UTF-8, TVPaint, "CSV 1.1"\n'
        'Project Name, Width, Height, Frame Count, Layer Count\n'
        '"C001", 8, 8, 8, 2\n'
        '\n'
        '#Layers,"SE","A"\n'
        '#00001, "[001][00001] arisu,おはよ.png", "[002][00001] 1.png"\n'
        '#00004, "[002][00004] 2.png"\n',
      );
      return file.path;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [jsonPath!]),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('C001'), findsWidgets, reason: 'clip row');
    expect(
      find.textContaining('2 drawing(s), 2 exposure(s)'),
      findsOneWidget,
      reason: 'layer A, read top-first like the layer panel',
    );
    expect(find.textContaining('post hold'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('import-rasterize-toggle')),
      findsNothing,
      reason: 'an export lands a whole cut — nothing to place',
    );
    expect(find.textContaining('빈 사진 포함'), findsOneWidget,
        reason: 'the window names the export setting it depends on');

    final cutsBefore = s.repository.requireProject().tracks.first.cuts.length;
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    // The cels bake AFTER the command lands the cut, so waiting on the
    // cut count alone would sample the store mid-flight — wait for the
    // pixels themselves.
    for (var tries = 0; tries < 200; tries += 1) {
      final cuts = s.repository.requireProject().tracks.first.cuts;
      final landed = cuts.where((cut) => cut.name == 'C001');
      if (landed.isNotEmpty) {
        final cut = landed.first;
        final layer = cut.layers.firstWhere((layer) => layer.name == 'A');
        if (layer.frames.isNotEmpty &&
            s.brushFrameStore.bakedSurfaceOrNull(
                  s.brushFrameKeyForCut(cut, layer.id, layer.frames.first.id),
                ) !=
                null) {
          break;
        }
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final track = s.repository.requireProject().tracks.first;
    expect(track.cuts.length, cutsBefore + 1);
    final cut = track.cuts.firstWhere((cut) => cut.name == 'C001');
    expect(cut.duration, 8, reason: 'image-count is the cut length');
    expect(cut.canvasSize.width, 8);

    final a = cut.layers.firstWhere((layer) => layer.name == 'A');
    expect(a.frames, hasLength(2));
    expect(a.frames.map((frame) => frame.name), ['1', '2']);
    expect(a.runBehaviors.single.mode, TimelineRunEdgeMode.hold);
    // The two AUTHORED blocks, and then the hold's ghost carrying the
    // last drawing to the cut end. The behaviour used to arrive recorded
    // and unapplied — the property tag printed H over empty cells — so
    // the third key IS the fix showing through.
    expect(a.timeline.keys, [0, 3, 6]);
    expect(a.timeline.values.map((entry) => entry.length), [3, 3, 2]);
    expect(a.timeline.values.map((entry) => entry.ghost), [false, false, true]);
    expect(
      a.timeline[6]!.frameId,
      a.frames.last.id,
      reason: 'a hold repeats the run\'s last drawing',
    );

    final se = cut.layers.firstWhere((layer) => layer.name == 'SE');
    expect(
      se.frames.single.name,
      'arisu,おはよ',
      reason: 'a blank instance is a LABEL, not nothing',
    );

    // A is opaque and must have baked; SE is transparent and must not
    // have donated an empty surface into the store.
    expect(
      s.brushFrameStore.bakedSurfaceOrNull(
        s.brushFrameKeyForCut(cut,a.id, a.frames.first.id),
      ),
      isNotNull,
    );
    expect(
      s.brushFrameStore.bakedSurfaceOrNull(
        s.brushFrameKeyForCut(cut, se.id, se.frames.single.id),
      ),
      isNull,
      reason: 'blank instances carry no pixels into the save',
    );
  });

  testWidgets('a dropped TVPaint export FOLDER is read as the export, not '
      'as a cut folder — and the knobs that have nothing to decide are '
      'gone', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    await tester.runAsync(() async {
      await writePng('[001] A/[0001] A.png');
      await File('${tempDir.path}/notes.json').writeAsString('{"a":1}');
      await File('${tempDir.path}/C002.json').writeAsString(
        '{"version":{"major":5,"minor":1},"project":{"camera":{"width":8,'
        '"height":8},"clip":{"name":"C002","width":8,"height":8,'
        '"framerate":24.0,"image-count":4,'
        '"camera":{"points":[],"positions":[]},"layers":['
        '{"name":"A","position":1,"visible":true,"opacity":255,"start":0,'
        '"end":3,"pre-behavior":0,"post-behavior":0,'
        '"blending-mode":"Color","link":[{"instance-index":0,'
        '"instance-name":"1","file":"[001] A/[0001] A.png","images":[0]}],'
        '"repeat":[]}]}}}',
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportDialog(session: s, initialPaths: [tempDir.path]),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('C002'),
      findsWidgets,
      reason: 'the folder was read as the TVPaint export it holds',
    );
    expect(
      find.textContaining('drawing(s)'),
      findsWidgets,
      reason: 'the TVPaint interpretation table rendered',
    );
    expect(
      find.textContaining('Cut folders always bake'),
      findsNothing,
      reason: 'the cut-folder branch must not have run on it',
    );
    expect(
      find.textContaining('notes.json'),
      findsOneWidget,
      reason: 'the .json that was not the export is named, not dropped',
    );
    expect(
      find.byKey(const ValueKey<String>('import-fit-contain')),
      findsNothing,
      reason: 'the cut is born at the clip size and the images ARE that '
          'size — all three fit modes compute the same rect',
    );
    expect(
      find.byKey(const ValueKey<String>('import-destination-cut')),
      findsOneWidget,
      reason: 'one destination today, shown so the row can grow later',
    );

    final cutsBefore = s.repository.requireProject().tracks.first.cuts.length;
    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    for (var tries = 0; tries < 200; tries += 1) {
      if (s.repository.requireProject().tracks.first.cuts
          .any((cut) => cut.name == 'C002')) {
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
    expect(track.cuts.firstWhere((cut) => cut.name == 'C002').duration, 4);
  });

  testWidgets('a .json that is not a TVPaint export is refused by name and '
      'leaves the file list — never a decode failure later', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);

    final path = await tester.runAsync(() async {
      final file = File('${tempDir.path}/notes.json');
      await file.writeAsString('{"hello":"world"}');
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
      find.textContaining('not a TVPaint JSON export'),
      findsOneWidget,
      reason: 'the window names what the file is, not what failed to decode',
    );
    expect(
      find.textContaining('Ignored'),
      findsOneWidget,
      reason: 'and it is listed rather than dropped',
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey<String>('import-run-button')),
          )
          .onPressed,
      isNull,
      reason: 'there is nothing left to import',
    );
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
        home: Scaffold(body: ImportDialog(session: s, initialPaths: [path!])),
      ),
    );
    await tester.pump();

    final note = find.byKey(const ValueKey<String>('import-large-carry-note'));
    expect(note, findsOneWidget, reason: 'Keep inside is the default');
    final text = tester.widget<Text>(note).data!;
    expect(text, contains('120 MB'), reason: 'the number being decided');
    expect(text, contains('마스터'), reason: 'and what the answer acts on');
    expect(text, contains('Reference'), reason: 'the way out is named');
  });

  testWidgets('choosing Reference takes the warning away', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(
      () => writeBigFile('마스터.wav', 120 * 1024 * 1024),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImportDialog(session: s, initialPaths: [path!])),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('import-large-carry-note')),
      findsOneWidget,
    );

    await pickCell(tester, column: 'File', path: path, option: 'Ref');

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
        home: Scaffold(body: ImportDialog(session: s, initialPaths: [path!])),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('import-large-carry-note')),
      findsNothing,
      reason: 'a warning about a file that was always staying outside is '
          'the noise that teaches people to ignore the real one',
    );
  });

  testWidgets('an ordinary file does not warn', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final path = await tester.runAsync(() => writePng('보통.png'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ImportDialog(session: s, initialPaths: [path!])),
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
          .widget<Text>(
            find.descendant(of: cell, matching: find.byType(Text)),
          )
          .data!;
    }

    testWidgets('a column header answers for every row at once',
        (tester) async {
      final a = await tester.runAsync(() => writePng('a.png'));
      final b = await tester.runAsync(() => writePng('b.png'));
      await pump(tester, [a!, b!]);

      expect(cellText(tester, 'File', a), 'Keep');
      await tester.tap(
        find.byKey(const ValueKey<String>('import-column-File')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('import-option-Ref')));
      await tester.pumpAndSettle();

      expect(cellText(tester, 'File', a), 'Ref');
      expect(cellText(tester, 'File', b), 'Ref');
    });

    testWidgets('a cell speaks for the SELECTION when its row is in one',
        (tester) async {
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
      await pickCell(tester, column: 'File', path: a, option: 'Ref');

      expect(cellText(tester, 'File', a), 'Ref');
      expect(cellText(tester, 'File', b), 'Ref');
      expect(
        cellText(tester, 'File', c),
        'Keep',
        reason: 'the row nobody selected keeps its own answer',
      );
    });

    testWidgets('an answer the KIND refuses does not stick', (tester) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      final movie = await tester.runAsync(() => writeMovie('ref.mp4'));
      await pump(tester, [png!, movie!]);

      expect(
        cellText(tester, 'File', movie),
        'Ref',
        reason: 'a movie is never carried, whatever the default says',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('import-column-File')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('import-option-Keep')),
      );
      await tester.pumpAndSettle();

      expect(cellText(tester, 'File', png), 'Keep');
      expect(
        cellText(tester, 'File', movie),
        'Ref',
        reason: 'the header asked, and this file still cannot',
      );
    });

    testWidgets('expanding a PSD locks its File answer to the pixels',
        (tester) async {
      final psd = await tester.runAsync(() => writePsd('BG.psd'));
      await pump(tester, [psd!]);

      expect(cellText(tester, 'PSD', psd), 'Merge');
      expect(cellText(tester, 'File', psd), 'Keep');

      await pickCell(tester, column: 'PSD', path: psd, option: 'Expand');

      expect(
        cellText(tester, 'File', psd),
        'Raster',
        reason: 'one of them baked means all of them are',
      );
    });

    testWidgets('the pool asks nothing about placement', (tester) async {
      final png = await tester.runAsync(() => writePng('a.png'));
      await pump(tester, [png!], poolOnly: true);

      expect(cellText(tester, 'Into', png), '—');
      expect(cellText(tester, 'Fit', png), '—');
      expect(
        cellText(tester, 'File', png),
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
          home: Scaffold(body: ImportDialog(session: s, initialPaths: [png!])),
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
        'what is only registered would have to write the trimmed bytes',
        (tester) async {
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
}
