import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';

import '../../helpers/fake_pdf_document.dart';

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

  Future<String> writePng(String name) async {
    final pixels = Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 0xAA);
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
      find.byKey(const ValueKey<String>('import-destination-layer')),
      findsOneWidget,
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

    await tester.tap(find.byKey(const ValueKey<String>('import-destination-cut')));
    await tester.pump();
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
    await tester.tap(find.byKey(const ValueKey<String>('import-destination-cut')));
    await tester.pump();
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
}
