import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';
import '../helpers/dart_sources.dart';

/// 🚨A TEST RUN'S `json` REPORT IS READ IN ONE PLACE — `readReport`
/// (tool/test_seconds.dart), card a-slow-test-cannot-creep, 2026-11-17.
/// What a file took and whether it was green, what a silent batch is still
/// running and which tests took a minute are views of the same events;
/// till then two of them read the report each for itself, and the minute
/// would have been a third.
///
/// ⛔A SOURCE SCAN, because two readers that agree today pass every
/// behaviour test, and part the day one of them learns an event the other
/// does not.
void main() {
  test("only test_seconds.dart reads a report's events", () {
    expect(
      [
        for (final file in dartFilesUnder('tool'))
          if (_readsTheEvents(file.readAsStringSync()))
            file.path.replaceAll(r'\', '/'),
      ],
      ['tool/test_seconds.dart'],
      reason: 'read it with `readReport` and take the view you need',
    );
  });

  test('the scan sees a planted reader, and not one in a comment', () {
    expect(_readsTheEvents("if (event['type'] == 'testStart') {}"), isTrue);
    expect(_readsTheEvents("// It once switched on 'testStart'."), isFalse);
  });
}

/// Whether [source] picks a report's events out by their type.
bool _readsTheEvents(String source) =>
    withoutComments(source).contains("'testStart'");
