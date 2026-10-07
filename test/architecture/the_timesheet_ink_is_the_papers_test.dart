import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🗣️유저 2026-10-01 (F-252): 「잉크는 용지에 귀속됨. 더이상 칸에
/// 귀속되지않음」, and 10-08 (F-252-Q1): 「잔재 싹 삭제」 — the timesheet's
/// ink is one surface per page.
///
/// The frame-anchored plane over the column grid went with its keys, its
/// store, its windows and the band arithmetic that stretched them over the
/// 3-second sheet. ⛔A ratchet rather than a behaviour test: what was
/// deleted cannot be driven, and the plane would come back looking like a
/// feature (the conte's paper plane went the same way, H44).
void main() {
  /// [file]'s code, its `//` comments left out: a comment may tell the
  /// plane's story all it likes.
  String codeOf(File file) => file
      .readAsLinesSync()
      .map((line) {
        final comment = line.indexOf('//');
        return comment < 0 ? line : line.substring(0, comment);
      })
      .join('\n');

  test('⛔nothing in the app spells the frame-anchored plane: its keys, its '
      'store, its windows or its band arithmetic', () {
    const names = [
      'TimesheetInkPlane',
      'timesheetInkStrip',
      'timesheetInkPageStore',
      'timesheetInkBandFrames',
      'timesheetInkRuns',
      "'sheet-strip",
      'stripBandSurfaceSize',
    ];
    final files = dartFilesUnder('lib/src').toList();
    final spelled = <String>[];
    for (final file in files) {
      final code = codeOf(file);
      for (final name in names) {
        if (code.contains(name)) {
          spelled.add('${libPath(file)}: $name');
        }
      }
    }
    expect(files.length, greaterThan(100), reason: 'the scan found the app');
    expect(spelled, isEmpty);
    expect(
      File('lib/src/ui/timesheet/timesheet_ink_bands.dart').existsSync(),
      isFalse,
    );
  });
}
