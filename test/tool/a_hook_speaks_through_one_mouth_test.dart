import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨A HOOK'S VERDICT IS WRITTEN BY ONE FUNCTION, NEVER BY HAND.
///
/// Every session hook answers Claude Code with a JSON object, and every one
/// used to spell it out itself: a literal with `\n` typed into it and a
/// variable dropped in the middle. 2026-10-07 (found on the Surface,
/// reproduced on the first machine): the board gate dropped the checker's
/// complaint — several lines, quotes in them — into its `block`, and the
/// result was not JSON. Claude Code reads output it cannot parse as plain
/// text, so the gate stopped nothing exactly when the board had something
/// to say, and nothing said so. Eleven more places had the same shape.
///
/// ⚠️The suite spawns no process (tests_do_not_race_the_code_test), so what
/// the scripts PRINT is pinned by the shell tests beside them, run by hand:
/// `hook_says_test.sh` (the escaper, byte for byte), `board_gate_test.sh`
/// (the gate on a stage, its PR half answered from files) and
/// `autorun_test.sh`. What is pinned here is the thing that made twelve
/// copies possible: that there is one mouth, and no script grows a second.
void main() {
  // The keys only a verdict has. ⚠️`"decision":` with its colon — the gate
  // also prints the SHAPE of a decision card, where the word is a value.
  const verdictKeys = [
    '"decision":',
    'hookSpecificOutput',
    'permissionDecision',
  ];
  const mouth = 'hook_says.sh';

  String nameOf(File file) => file.uri.pathSegments.last;
  final hooks = [
    for (final file in Directory('tool/session_hooks').listSync())
      if (file is File &&
          file.path.endsWith('.sh') &&
          !file.path.endsWith('_test.sh'))
        file,
  ];

  /// A script's lines that are code: a comment explains, and may quote.
  Iterable<(int, String)> codeOf(File file) sync* {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('#')) continue;
      yield (i + 1, lines[i]);
    }
  }

  test('⛔fixture premise: the hooks are found, the mouth among them, and '
      'it does spell the verdicts', () {
    expect(hooks.length, greaterThan(5));
    final speaker = hooks.singleWhere((file) => nameOf(file) == mouth);
    final spelled = codeOf(speaker).map((line) => line.$2).join('\n');
    for (final key in verdictKeys) {
      expect(spelled, contains(key), reason: key);
    }
  });

  test('no other hook spells a verdict itself', () {
    for (final file in hooks) {
      if (nameOf(file) == mouth) continue;
      for (final (number, line) in codeOf(file)) {
        for (final key in verdictKeys) {
          expect(
            line.contains(key),
            isFalse,
            reason:
                '${nameOf(file)}:$number writes $key by hand — hand the plain '
                'text to say_block / say_context / say_deny ($mouth)',
          );
        }
      }
    }
  });

  test('a hook that says anything reads the mouth in', () {
    final says = RegExp(r'\bsay_(block|context|deny)\b');
    var speakers = 0;
    for (final file in hooks) {
      if (nameOf(file) == mouth) continue;
      final code = codeOf(file).map((line) => line.$2).join('\n');
      if (!says.hasMatch(code)) continue;
      speakers++;
      expect(code, contains('/$mouth"'), reason: nameOf(file));
    }
    expect(speakers, greaterThan(5), reason: 'the scan reached no speaker');
  });

  // 2026-10-07, read in the gate: 「$reasonCI가 빨간 PR…」. A shell name
  // runs on through ASCII letters, so that asked for a variable called
  // `reasonCI`, and under `set -u` an unset name ends the script — the
  // red-PR half died on that line every time it had something to say.
  test('⛔the gate never lets its reason run into the next word', () {
    final gate = hooks.singleWhere(
      (file) => nameOf(file) == 'board_gate.sh',
    );
    final runsOn = RegExp(r'\$reason[A-Za-z0-9_]');
    expect(
      [
        for (final (number, line) in codeOf(gate))
          if (runsOn.hasMatch(line)) number,
      ],
      isEmpty,
      reason: r'write ${reason} with its braces',
    );
  });
}
