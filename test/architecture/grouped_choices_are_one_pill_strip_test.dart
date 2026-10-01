import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨THE APP HAS ONE GROUPED CHOICE — `PillStrip` (유저 2026-09-09:
/// 「여러개중 하나 선택한다거나 아무튼 그룹중에 선택한다거나 복수선택한다거나
/// 그룹으로 묶여있는 선택은 이 ui 사용하도록 공용화」, board
/// `pill-group-everywhere`). The framework's own grouped choices — a
/// segmented button, toggle buttons, choice and filter chips — each draw
/// that one question their own way, so none of them is written under lib/.
///
/// ⛔A behaviour test cannot hold this: it passes with a segmented button
/// and a pill strip side by side, answering alike today.
void main() {
  test('no framework grouped-choice control is written under lib/', () {
    final control = RegExp(
      '(^|[^A-Za-z])(SegmentedButton|ToggleButtons|ChoiceChip|FilterChip)'
      r'(<[^>(]*>)?\(',
    );
    final files = dartFilesUnder('lib').toList();
    expect(files, isNotEmpty, reason: 'the scan read nothing');
    final offenders = <String>[];
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) {
          continue;
        }
        if (control.hasMatch(line)) {
          offenders.add('${libPath(file)}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
