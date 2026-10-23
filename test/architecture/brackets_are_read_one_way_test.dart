import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// 🚨NO SCAN COUNTS BRACKETS BY HAND — where one closes is asked of the one
/// reading, `tool/source_brackets.dart` (2026-10-18,
/// source-scans-count-brackets-by-hand).
///
/// 🔬Measured the day this was written: eleven scans under `test/` and two
/// tools under `tool/` each counted brackets their own way — a body by its
/// braces (four, with a shared reader beside them), a call by its
/// parentheses (six), a class by the first line that was a lone `}` (two),
/// a lexer of its own (the class API snapshot) — and every one but the
/// reading's first owner counted the brackets inside strings and comments
/// too.
///
/// ⛔A behaviour test cannot hold this: a copy that agrees with the reading
/// today passes every test the reading passes, and drifts the day one of
/// them is fixed. This reads the source.
void main() {
  test('premise: the scan sees every form a count by hand took', () {
    for (final line in const [
      "if (source[i] == '{') {",
      "} else if (char == ')') {",
      "if (c == '(' || c == '[' || c == '{') depth++;",
      "} else if ('([{'.contains(char)) {",
      "case '{':",
      "'(' => depth + 1,",
      'if (unit == 0x7B) {',
      "for (var i = 1; i < lines.length && lines[i] != '}'; i += 1) {",
    ]) {
      expect(_handCount.hasMatch(line), isTrue, reason: line);
    }
    for (final line in const [
      r"final head = RegExp(r'\bmain\s*\([^)]*\)\s*\{');",
      "final open = source.indexOf('{', start);",
      'const bytes = [0xf0, 0x28, 0x8c];',
    ]) {
      expect(_handCount.hasMatch(line), isFalse, reason: line);
    }
  });

  test('no source scan or tool counts brackets but through the one '
      'reading', () {
    final scanned = <String>[];
    final counts = <String, List<String>>{};
    for (final file in [...dartFilesUnder('test'), ...dartFilesUnder('tool')]) {
      final path = file.path.replaceAll(r'\', '/');
      scanned.add(path);
      if (path.endsWith(_seat) || path.endsWith(_itself)) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (!lines[i].trimLeft().startsWith('//') &&
            _handCount.hasMatch(lines[i])) {
          (counts[path] ??= []).add('${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      scanned,
      containsAll([
        endsWith('tool/refactor/extract_method.dart'),
        endsWith('test/helpers/source_body.dart'),
      ]),
      reason: 'premise: the walk reaches both trees',
    );
    // Exact paths, not suffixes: a ledgered file that was deleted is paid off.
    expectCountsMatchLedger(
      {
        for (final MapEntry(key: path, value: lines) in counts.entries)
          path: lines.length,
      },
      {for (final entry in _ledger.entries) entry.key: entry.value.lines},
      grew:
          'where a bracket closes is `tool/source_brackets.dart`\'s to say — '
          'matchingClose, callArguments, namedArgument, bodyOf (and '
          'sourceBodyOf over it in a test). A count by hand reads a bracket '
          'in a string or a comment as one',
      paidOff:
          'A line in the ledger that is gone: take it out (and one that '
          'reads fewer brackets: lower its count)',
      hits: counts,
    );
  });
}

const _seat = 'tool/source_brackets.dart';
const _itself = 'test/architecture/brackets_are_read_one_way_test.dart';

/// A line that reads a bracket by hand: a character — or a code unit —
/// compared with one, a case or a switch arm on one, or a string of them
/// asked whether it holds one.
final _handCount = RegExp(
  r"(==|!=)\s*'[(){}\[\]]'"
  r"|'[(){}\[\]]'\s*(==|!=|=>)"
  r"|\bcase\s+'[(){}\[\]]'"
  r"|'[(){}\[\]]{2,6}'\.contains\("
  r'|(==|!=)\s*0x(28|29|5[bBdD]|7[bBdD])\b',
);

/// The lines that compare with a bracket and read none — with why.
const _ledger = <String, ({int lines, String why})>{
  'tool/class_api_snapshot.dart': (
    lines: 6,
    why:
        'cuts a class into its members in one pass by the brace and paren '
        'depth it walks — a member that ends at its `;` has no bracket of '
        'its own to close, and a `{` opens a body only outside the '
        'parentheses. What is code there is the reading\'s (pastNonCode)',
  ),
  'tool/refactor/apply_spec.dart': (
    lines: 1,
    why:
        'a whole LINE compared with a lone `}`: a removal that leaves a '
        'blank line above a closing brace takes the blank line too — it '
        'tidies text, it does not ask where a bracket closes',
  ),
};
