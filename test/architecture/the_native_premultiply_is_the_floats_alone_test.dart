import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/project_scratch_folder.dart';
import '../helpers/source_ledger.dart';

/// 🧭관제 2026-11-11 18:47 (gpu-export-path 1b ②): 「뷰어 · 컷 조각 미리보기 ·
/// 브러시 팁은 … 작업자 아이솔레이트의 Dart 로 간다」 · 「플로트는 캔버스
/// 베이스 패널 몫이다」. A straight picture goes up to the display
/// premultiplied by the app's one premultiply in Dart, on a worker
/// (`decodeStraightRgbaImageOnAWorker`); the native pass
/// (`decodeStraightRgbaImage` — the C `premultipliedStampCopy` under
/// `premultipliedStraightRgba`) is asked by the ledger's alone, until its
/// owner moves it and the ledger is empty.
///
/// A scan, because no picture tells the two roads apart: the C and the
/// Dart premultiply give the same bytes (`straight_rgba_image_test`).
void main() {
  const home = 'lib/src/services/straight_rgba_image.dart';

  const ledger = <String, ({int count, String why})>{
    'lib/src/ui/canvas/float_warp.dart': (
      count: 1,
      why:
          'the float a warp lands, 캔버스 베이스 패널\'s (관제 2026-11-11 '
          '18:47) — it moves to the worker when its owner moves it',
    ),
  };

  /// The native pass asked by name: not the worker's door, whose name
  /// begins the same.
  final ask = RegExp(
    r'(?<![A-Za-z0-9_])(decodeStraightRgbaImage|premultipliedStraightRgba)\(',
  );

  /// Where under [root] the native pass is asked, and how often, comments
  /// apart — each file with the lines that ask it.
  (Map<String, int>, Map<String, List<int>>) asksUnder(String root) {
    final found = <String, int>{};
    final hits = <String, List<int>>{};
    for (final file in dartFilesUnder(root)) {
      final path = file.path.replaceAll(r'\', '/');
      final lines = codeOfLines(file.readAsStringSync()).split('\n');
      for (final (at, line) in lines.indexed) {
        final count = ask.allMatches(line).length;
        if (count > 0) {
          found[path] = (found[path] ?? 0) + count;
          (hits[path] ??= []).add(at + 1);
        }
      }
    }
    return (found, hits);
  }

  test('only the ledger asks the native premultiply', () {
    final (found, hits) = asksUnder('lib');
    found.remove(home);

    expectCountsMatchLedger(
      found,
      {for (final entry in ledger.entries) entry.key: entry.value.count},
      grew:
          'a straight picture goes up premultiplied on a worker '
          '(`decodeStraightRgbaImageOnAWorker`), not by the native pass',
      paidOff:
          'these ask the native pass fewer times than the ledger says — '
          'lower the count, or take the line out',
      hits: hits,
    );
    expectEveryEntrySaysWhy({
      for (final entry in ledger.entries) entry.key: entry.value.why,
    });
  });

  test('🚨the scan sees the native pass asked when it is', () {
    final planted = Directory.systemTemp.createTempSync('anicel-premul');
    deleteAfterSessionEnds(planted);
    File('${planted.path}/a_page.dart').writeAsStringSync(
      'Future<Object> page(List<int> rgba) async {\n'
      '  // decodeStraightRgbaImage(rgba: rgba) would ask the C\n'
      '  await decodeStraightRgbaImageOnAWorker(rgba: rgba);\n'
      '  premultipliedStraightRgba(rgba);\n'
      '  return decodeStraightRgbaImage(rgba: rgba, width: 1, height: 1);\n'
      '}\n',
    );
    File('${planted.path}/clean.dart').writeAsStringSync(
      'Future<Object> page(List<int> rgba) =>\n'
      '    decodeStraightRgbaImageOnAWorker(rgba: rgba);\n',
    );

    final (found, hits) = asksUnder(planted.path);
    final page = '${planted.path.replaceAll(r'\', '/')}/a_page.dart';
    expect(found, {page: 2});
    expect(hits, {
      page: [4, 5],
    });
  });
}
