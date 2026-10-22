@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/test_queue.dart';
import '../helpers/temp_dir.dart';

/// 🗣️유저 2026-10-21, tests-crowd-the-machine-Q15 「실행 전체가 자리를
/// 지킨다」: the run, not the batch, stands in the machine's line — at its
/// next batch it has waited since its ticket was asked, so a run that asked
/// after it does not go first. ↩️From 10-20 every batch counted its wait
/// from naught and stood behind every run waiting.
///
/// Through [standInLine] and [Turn] alone, so the same file runs against
/// the line from before this rule (the mutant is the rule taken out).
void main() {
  late Directory line;
  setUp(() => line = Directory.systemTemp.createTempSync('queue_place'));
  tearDown(() => deleteTempQuietly(line));

  String nameOf(File file) => file.uri.pathSegments.last;

  /// A settled ticket another run took at [microseconds], telling [told].
  File standing(int microseconds, Map<String, Object> told) {
    final file = File('${line.path}/${ticketName(microseconds, 1)}')
      ..writeAsStringSync('1\n')
      ..setLastModifiedSync(DateTime(2020));
    File('${file.path}.json').writeAsStringSync(jsonEncode(told));
    return file;
  }

  test('🚨at its next batch a run stands ahead of a long run that asked '
      'after it', () async {
    final running = standing(1, {'state': 'running', 'suites': 5});
    File? later;
    var looks = 0;
    final events = <String>[];
    await standInLine(
      'a run',
      (turn) async {
        events.add('batch at ${await turn.take(files: 40, work: 2400)}');
        turn.putDown();
        // As long a run, asked while the first batch ran.
        later = standing(DateTime.now().microsecondsSinceEpoch, {
          'state': 'waiting',
          'files': 40,
          'work': 2400,
          'takesWhatIsLeft': true,
        });
        events.add('batch at ${await turn.take(files: 40, work: 2400)}');
        turn.putDown();
      },
      line: line,
      room: () async => true,
      say: (_) => events.add('waits'),
      lookAgain: Duration.zero,
      // The running run is given back on its third look after the later one
      // asked — so a run sent behind it waits, and then still runs.
      ended: (file) =>
          later != null && nameOf(file) == nameOf(running) && ++looks > 2,
    );
    expect(events, [
      'batch at 5', //
      // Its own half again at once — the later run takes what is left
      // after it, which here is none.
      'batch at 5',
    ]);
  });
}
