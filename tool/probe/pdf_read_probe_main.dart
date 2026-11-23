// PDF READ PROBE — does the app's own PDF open tell how far PDFium read the
// file, and does a page range cut from one open?
//
//   flutter run -d windows -t tool/probe/pdf_read_probe_main.dart \
//     --dart-define=PDF_IN=<a.pdf> --dart-define=PDF_OUT=<report.txt>
//
// Then it opens the file ten times more, each with its time of day and a
// two-minute limit — a callback open once did not end within 600 s
// (1 of 9, 저장 11-24), and 관제 asked it be tried again, not closed.
//
// It runs in the REAL app process: flutter_tester never loads PDFium
// (PdfRenderService's test doctrine), so the reads PdfOpeningReads counts
// are only ever counted here (decoder-reads-skip-the-percent, 11-24).
//
// Measurement, not a feature: not wired into the app, no strings, no UI
// conventions apply.
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:anicel/src/models/kept_span.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const input = String.fromEnvironment('PDF_IN');
  const output = String.fromEnvironment('PDF_OUT');
  final out = File(output).openSync(mode: FileMode.write);
  void line(String words) {
    out.writeStringSync('${DateTime.now().toIso8601String()} $words\n');
    out.flushSync();
  }

  line('file=$input bytes=${File(input).lengthSync()}');
  try {
    final heard = <double>[];
    final watch = Stopwatch()..start();
    final document = await PdfRenderService.open(
      const MediaFileBytes(input),
      onRead: heard.add,
    );
    line(
      'open: ${watch.elapsedMilliseconds}ms pages=${document?.pageCount} '
      'told=${heard.length} first=${heard.firstOrNull} '
      'last=${heard.lastOrNull} rising=${_rising(heard)}',
    );
    final toldAtOpen = heard.length;
    final page = document!.pageSize(0);
    final image = await document.renderPage(
      0,
      width: 480,
      height: (480 * page.height / page.width).round(),
    );
    image.dispose();
    line('after a page: told=${heard.length} (open: $toldAtOpen)');
    await document.dispose();

    final cutHeard = <double>[];
    watch.reset();
    final piece = await PdfRenderService.pagesKept(
      input,
      (pages) => KeptSpan(length: pages, inFrame: 1, outFrame: 2),
      onRead: cutHeard.add,
    );
    line(
      'cut: ${watch.elapsedMilliseconds}ms kept=${piece?.kept.first}..'
      '${piece?.kept.last} bytes=${piece?.bytes.length} '
      'told=${cutHeard.length} last=${cutHeard.lastOrNull} '
      'rising=${_rising(cutHeard)}',
    );
    for (var again = 1; again <= 10; again += 1) {
      await _openAgain(again, input, line);
    }
  } on Object catch (error, stack) {
    line('FAILED: $error\n$stack');
  }
  out.closeSync();
  exit(0);
}

Future<void> _openAgain(
  int again,
  String input,
  void Function(String words) line,
) async {
  final told = <double>[];
  final watch = Stopwatch()..start();
  line('again $again: opening');
  try {
    final document = await PdfRenderService.open(
      MediaFileBytes(input),
      onRead: told.add,
    ).timeout(const Duration(minutes: 2));
    line(
      'again $again: open ${watch.elapsedMilliseconds}ms '
      'pages=${document?.pageCount} told=${told.length} '
      'last=${told.lastOrNull}',
    );
    await document?.dispose();
  } on Object catch (error) {
    line(
      'again $again: NOT OPEN after ${watch.elapsedMilliseconds}ms '
      'told=${told.length} last=${told.lastOrNull} — $error',
    );
  }
}

bool _rising(List<double> told) {
  for (var i = 1; i < told.length; i += 1) {
    if (told[i] < told[i - 1]) {
      return false;
    }
  }
  return true;
}
