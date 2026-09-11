import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/ui/canvas/paper_background.dart'
    show AlphaCheckerboardPainter;
import 'package:anicel/src/ui/import/import_preview.dart';

/// 🚨Open alpha in the import window reads as the app's ONE checker — the
/// export preview's own (유저 2026-09-11: 「임포트의 미리보기에서 배경이
/// 투명한파일은 출력창의 미리보기에서 쓰는 투명한 배경에서 격자무늬 쓰는거
/// 그대로 공용화해서 재사용하도록」). It used to draw the file straight onto
/// the dark well, where open alpha and a dark picture look the same.
void main() {
  testWidgets('a transparent file is shown over the shared checker', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('anicel-preview'),
    );
    addTearDown(() async {
      try {
        await dir!.delete(recursive: true);
      } on Object {
        // Windows keeps handles briefly.
      }
    });
    final path = await tester.runAsync(() async {
      // Every pixel fully transparent: nothing but the checker should show.
      final pixels = Uint8List(4 * 4 * 4);
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        4,
        4,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('${dir!.path}${Platform.pathSeparator}open.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      return file.path;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: ImportPreview(
              path: path,
              inFrame: 0,
              outFrame: null,
              rangeEditable: false,
              onRangeChanged: (start, end) {},
              soundPeaks: (_) async => null,
              frameRate: ProjectFrameRate.fps24,
            ),
          ),
        ),
      ),
    );
    final checker = find.byKey(const ValueKey<String>('import-preview-checker'));
    for (var tries = 0; tries < 50 && checker.evaluate().isEmpty; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(checker, findsOneWidget);
    expect(
      tester.widget<CustomPaint>(checker).painter,
      isA<AlphaCheckerboardPainter>(),
      reason: 'the one checker the canvas and the export preview paint',
    );
  });
}
