import 'dart:io';

import 'package:anicel/src/services/diagnostics/memory_black_box.dart';
import 'package:flutter_test/flutter_test.dart';

/// The instrument that survives a kill.
///
/// 🚨A memory termination leaves nothing: no exception, no crash report,
/// and nothing in App Store Connect — memory kills are not collected
/// there. 실기 08-27: an iPhone died three times saving a file an iPad
/// saved fine, and afterwards there was not one line of evidence on the
/// device or the server. So the app writes its own, before the fact, and
/// the ONLY thing that matters is that an interrupted entry survives to
/// be read at the next launch.
void main() {
  setUp(() {
    MemoryBlackBox.reset();
    MemoryBlackBox.debugReading = () => (
      footprint: 1234 * 1024 * 1024,
      available: 512 * 1024 * 1024,
    );
  });

  tearDown(() {
    MemoryBlackBox.debugReading = null;
    MemoryBlackBox.reset();
  });

  test('work that finished leaves nothing to report', () {
    MemoryBlackBox.begin('save');
    MemoryBlackBox.end('save');
    expect(MemoryBlackBox.unfinishedEntry(), isNull);
  });

  test('🚨 work that never ended is what the next launch reads — with the '
      'size it had grown to', () {
    // Exactly the shape of a kill: the BEGIN was flushed, the END never
    // came, and the process is gone. Nothing else in this app leaves an
    // unclosed entry.
    MemoryBlackBox.begin('save');

    final report = MemoryBlackBox.unfinishedEntry();
    expect(report, isNotNull);
    expect(report, contains('save'));
    expect(
      report,
      contains('1234MB'),
      reason: 'the footprint at the moment it stopped is the number that '
          'says whether it was memory — a report without it only says '
          'that something happened',
    );
    expect(report, contains('512MB'), reason: 'and what was left to take');
  });

  test('the newest answer wins: a finished run after a killed one reports '
      'nothing', () {
    MemoryBlackBox.begin('save');
    // Next launch, and this time it lands.
    MemoryBlackBox.begin('save');
    MemoryBlackBox.end('save');
    expect(
      MemoryBlackBox.unfinishedEntry(),
      isNull,
      reason: 'a kill is reported once, not at every launch after it',
    );
  });

  test('the log is written where the app can always write, and flushed as '
      'it goes', () {
    MemoryBlackBox.begin('tvpp-import');
    final file = File(MemoryBlackBox.logPath());
    expect(
      file.existsSync(),
      isTrue,
      reason: 'a diagnostic still queued when the process dies records '
          'nothing, which is the one outcome this must not have',
    );
    expect(file.readAsStringSync(), contains('BEGIN tvpp-import'));
  });

  test('a platform that will not answer says so instead of guessing', () {
    MemoryBlackBox.debugReading = () => (footprint: null, available: null);
    MemoryBlackBox.begin('save');
    final report = MemoryBlackBox.unfinishedEntry();
    expect(report, contains('footprint=?'));
    expect(
      report,
      isNot(contains('MB')),
      reason: 'the device\'s RAM is a different question, and standing it '
          'in here is how the cel budget came to be twice what the '
          'process is allowed',
    );
  });
}
