import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';

import '../../helpers/fake_pdf_document.dart';
import '../../helpers/fake_video_backend.dart';
import '../../helpers/placed_sound_conform.dart';
import '../../helpers/psd_fixture.dart';
import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// 🚨The import and placement window says each file's resolution (F-375,
/// 유저 2026-10-17: 「임포트/배치같은 창에 파일 해상도도 표시. 1920x1080
/// 이런 해상도」) — of every kind it lists, read after the rows are up.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-resolution');
  });

  tearDown(() {
    debugVideoDecodeBackend = null;
    PdfRenderService.debugResetForTests();
    deleteTempQuietly(tempDir);
  });

  String write(String name, List<int> bytes) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name')
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  Future<void> open(WidgetTester tester, List<String> paths) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
      audioConformStore: soundConformStore(),
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
  }

  String resolutionOf(WidgetTester tester, String path) => tester
      .widget<Text>(find.byKey(ValueKey<String>('import-resolution-$path')))
      .data!;

  /// Real IO runs in `runAsync`; its answers land on the pumps after —
  /// [tries] of them at most.
  Future<void> settle(
    WidgetTester tester, {
    required bool Function() until,
    int tries = 100,
  }) async {
    for (var i = 0; i < tries && !until(); i += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  testWidgets('every kind the window lists says its own — a picture its '
      'pixels, a Photoshop document its canvas, a movie its frame, a PDF '
      'its first page at 1:1 — and a sound a dash', (tester) async {
    debugVideoDecodeBackend = FakeVideoBackend(width: 1920, height: 1080);
    PdfRenderService.debugOpenerOverride = (source) async => FakePdfDocument(
      pageSizes: const [ui.Size(841.9, 595.3)],
    );
    final picture = (await tester.runAsync(
      () => writeSolidPng(tempDir, 'bg.png', width: 37, height: 23),
    ))!;
    final paths = [
      picture,
      write('layout.psd', buildPsd(width: 640, height: 480)),
      write('cut.mp4', const [0, 0, 0, 24]),
      write('conte.pdf', const [0x25, 0x50, 0x44, 0x46]),
      write('se.wav', const [0x52, 0x49, 0x46, 0x46]),
    ];
    await open(tester, paths);

    await settle(
      tester,
      until: () => paths.every((path) => resolutionOf(tester, path) != ''),
    );
    expect([for (final path in paths) resolutionOf(tester, path)], [
      '37×23',
      '640×480',
      '1920×1080',
      '842×595',
      '—',
    ]);
  });

  testWidgets('a file the window does not list is never read — a loose '
      'movie dropped with a folder is set aside, and its decoder never '
      'opened', (tester) async {
    final backend = FakeVideoBackend();
    debugVideoDecodeBackend = backend;
    final folder = Directory(
      '${tempDir.path}${Platform.pathSeparator}c001',
    )..createSync();
    final movie = write('cut.mp4', const [0, 0, 0, 24]);
    await open(tester, [folder.path, movie]);

    await settle(tester, until: () => false, tries: 10);
    expect(backend.openedAt, isEmpty);
  });

  testWidgets('🚨the sizes are read ONE AT A TIME, in the order the files '
      'are listed — a batch of large pictures is never held together, and '
      'a row waiting its turn says nothing yet', (tester) async {
    final held = Completer<void>();
    PdfRenderService.debugOpenerOverride = (source) async {
      await held.future;
      return FakePdfDocument(pageSizes: const [ui.Size(100, 50)]);
    };
    final picture = (await tester.runAsync(
      () => writeSolidPng(tempDir, 'bg.png', width: 37, height: 23),
    ))!;
    final pdf = write('conte.pdf', const [0x25, 0x50, 0x44, 0x46]);
    await open(tester, [pdf, picture]);

    // Long enough for the picture to have been read many times over, had
    // it not waited behind the PDF.
    await settle(tester, until: () => false, tries: 10);
    expect(resolutionOf(tester, pdf), '');
    expect(
      resolutionOf(tester, picture),
      '',
      reason: 'the picture waits its turn behind the PDF',
    );

    held.complete();
    await settle(
      tester,
      until: () => resolutionOf(tester, picture) != '',
    );
    expect(resolutionOf(tester, pdf), '100×50');
    expect(resolutionOf(tester, picture), '37×23');
  });
}
