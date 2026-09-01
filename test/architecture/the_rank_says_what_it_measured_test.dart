@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★THE RANKING IS THE AUDIT'S WORKLIST, SO ITS COLUMNS MUST NOT LIE.
///
/// `tool/audit_rank.dart` decides where the whole-codebase audit spends its
/// time. Two of its columns are easy to read as 「is this tested」 and neither
/// is: `reach` says a test COULD arrive here, `direct` says test code NAMES
/// this file. A file can be named by ten tests and asserted about by none.
///
/// ⛔This drives the real tool over the real tree rather than re-implementing
/// its arithmetic. A test that recomputes what the tool computes agrees with
/// the tool by construction and catches nothing — and the numbers here are
/// the ones the audit acts on, so what matters is that THE TOOL says them.
///
/// ⚠️`test/architecture/` and not `test/tool/`, for the reason given in
/// `the_code_map_counts_what_is_there_test.dart`.
void main() {
  late Map<String, dynamic> report;
  late List<Map<String, dynamic>> rows;

  setUpAll(() {
    final run = Process.runSync(
      'dart',
      ['run', 'tool/audit_rank.dart', '--json'],
      // ⚠️`dart run` prints build-hook chatter to stdout on this toolchain,
      // so the JSON is found rather than assumed to start at byte zero.
      runInShell: true,
    );
    final out = run.stdout as String;
    final start = out.indexOf('{');
    expect(
      start,
      isNonNegative,
      reason: 'audit_rank produced no JSON at all:\n$out\n${run.stderr}',
    );
    report = jsonDecode(out.substring(start)) as Map<String, dynamic>;
    rows = (report['rows'] as List).cast<Map<String, dynamic>>();
  });

  group('the premise', () {
    test('it read the real tree, not an empty one', () {
      // ⛔Without this every 「no row claims X」 assertion below would pass on
      // an empty list, which is the failure this repo keeps meeting.
      expect(rows.length, greaterThan(700),
          reason: 'lib/ has hundreds of files; a short list means the walk '
              'did not happen');
      expect(report['testFiles'] as int, greaterThan(500));
      expect(
        rows.map((r) => r['path'] as String),
        contains('lib/main.dart'),
      );
    });

    test('every row carries every column', () {
      for (final r in rows) {
        for (final key in ['path', 'layer', 'lines', 'fanIn', 'reach',
          'direct', 'worstComplexity']) {
          expect(r.containsKey(key), isTrue,
              reason: '${r['path']} has no $key');
        }
      }
    });
  });

  group('what the columns mean', () {
    test('`direct` never exceeds `reach` — naming implies reaching', () {
      // 🚨A row where `direct > reach` would mean test code names a file the
      // graph says no test can arrive at, which can only be a bug in one of
      // the two walks. ⚠️They are computed from the same graph but by
      // different code paths, so this is a real cross-check and not a
      // tautology.
      //
      // ⚠️The one legitimate gap: `reach` counts only `_test.dart` suites
      // while `direct` counts all of `test/`, so a file named ONLY by a
      // helper no suite uses could break this. There is no such file today
      // and if one appears this assertion is where you will hear about it.
      final broken = rows
          .where((r) => (r['direct'] as int) > (r['reach'] as int))
          .map((r) => '${r['path']} direct=${r['direct']} reach=${r['reach']}')
          .toList();
      expect(broken, isEmpty);
    });

    test('a file no test reaches is also named by no test', () {
      for (final r in rows.where((r) => (r['reach'] as int) == 0)) {
        expect(r['direct'], 0, reason: '${r['path']} is named but unreachable');
      }
    });

    test('the tree is connected, so `reach` alone ranks nothing', () {
      // 🧪This is the measurement that made `direct` exist, pinned so the
      // conclusion cannot quietly stop being true. If a refactor ever makes
      // `reach` discriminating again, this fails and the header comment in
      // `audit_rank.dart` needs rewriting with it.
      final unreached = rows.where((r) => (r['reach'] as int) == 0).length;
      expect(unreached, lessThan(rows.length ~/ 20),
          reason: 'reach was saturated when this was written — 1 of 809');
    });

    test('`direct` is the column that discriminates', () {
      final unnamed = rows.where((r) => (r['direct'] as int) == 0).length;
      expect(unnamed, greaterThan(10),
          reason: 'a column that flags nothing is not a worklist');
      expect(unnamed, lessThan(rows.length ~/ 2),
          reason: 'a column that flags half the tree is not a worklist '
              'either — it would mean the walk missed the test edges');
    });
  });

  group('the layers are the ones the dependency rule names', () {
    test('every row lands in a known layer', () {
      const known = {
        'core', 'models', 'services', 'controllers', 'ui', 'native', 'other',
      };
      for (final r in rows) {
        expect(known, contains(r['layer']), reason: '${r['path']}');
      }
    });
  });
}
