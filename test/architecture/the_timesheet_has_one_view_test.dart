import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🗣️유저 2026-10-08 (F-252-Q1): 「이어보기를 분명 삭제하라 했던거같은데.
/// 콘티너스보기? 말하는거지? 삭제. 잔재 싹 삭제」 — the timesheet is its
/// pages.
///
/// The continuous view — every row on one strip, beside the pages — went
/// with its toggle, its words, the layout's mode and the ink's second
/// geometry. ⛔A ratchet rather than a behaviour test, as for the alpha
/// preview (`one_transparency_checker_test`): what was deleted cannot be
/// driven, and 「분명 삭제하라 했던」 says it outlived an order once already.
void main() {
  /// [file]'s code, its `//` comments left out: a comment may tell the
  /// view's story all it likes.
  String codeOf(File file) => file
      .readAsLinesSync()
      .map((line) {
        final comment = line.indexOf('//');
        return comment < 0 ? line : line.substring(0, comment);
      })
      .join('\n');

  test('⛔the timesheet\'s code has no continuous view to switch to', () {
    final files = [
      ...dartFilesUnder('lib/src/ui/timesheet'),
      File('lib/src/ui/timesheet_tab_host.dart'),
    ];
    final spelled = [
      for (final file in files)
        if (RegExp('continuous', caseSensitive: false).hasMatch(codeOf(file)))
          libPath(file),
    ];
    expect(files.length, greaterThan(10), reason: 'the scan found the sheet');
    expect(spelled, isEmpty);
  });

  test('⛔nothing in the app spells the view\'s switch, its words or the '
      'state that kept it', () {
    const names = [
      'timesheet-page-mode-toggle-button',
      'sheetViewContinuous',
      'continuousLabel',
      'onContinuousChanged',
      '_timesheetContinuous',
    ];
    final spelled = <String>[];
    for (final file in dartFilesUnder('lib/src')) {
      final code = codeOf(file);
      for (final name in names) {
        if (code.contains(name)) {
          spelled.add('${libPath(file)}: $name');
        }
      }
    }
    expect(spelled, isEmpty);
  });
}
