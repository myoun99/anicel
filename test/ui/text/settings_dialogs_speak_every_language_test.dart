import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨F-37 — the settings dialogs do not hardcode English.
///
/// 유저 2026-08-28: 「로컬라이즈 잔여 — **특히 환경설정 저장 쪽**」. The save
/// section had four: `Every`, `Default` twice, and `Empty now` — and
/// `autosaveDefault` was already sitting in the table, **translated into
/// all five languages and read by nobody**. A key nothing uses is the same
/// bug as a key that does not exist, and harder to see.
///
/// ⛔SCOPED TO THE DIALOGS, and the number says why. A scan of the whole of
/// `lib/src/ui` on 2026-08-29 found **32** hardcoded strings — eight in the
/// tool settings panel, six on the canvas, five in the import table. Those
/// are real and they are the rest of F-37; turning them all red today would
/// make this a wall rather than a ratchet, and the user's emphasis was the
/// settings.
void main() {
  /// Literals that are the SAME in every language, so a key would buy
  /// nothing but indirection.
  ///
  /// ⛔Each is a symbol or a unit, not a word. If a translator would ever
  /// change it, it does not belong here.
  const universal = <String>{
    'ms', // the unit, written 'ms' in every language this app ships
  };

  test('a settings dialog reads its words from AppStrings', () {
    final literal = RegExp(r"""Text\(\s*(?:const\s+)?'([^'$]*)'""");
    final hasLetter = RegExp(r'[A-Za-z]');
    final offenders = <String>[];
    for (final file in Directory(
      'lib/src/ui/dialogs',
    ).listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) {
          continue;
        }
        final match = literal.firstMatch(lines[i]);
        if (match == null) {
          continue;
        }
        final text = match.group(1)!;
        // A '×' or a bare number is not English — it is punctuation, and it
        // reads the same to everyone.
        if (!hasLetter.hasMatch(text) || universal.contains(text)) {
          continue;
        }
        offenders.add('$relative:${i + 1}  "$text"');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'add a key to AppStrings (all five languages) and read it here — '
          'a dialog that speaks English to a Japanese user is the one place '
          'the fallback table cannot help, because nothing is missing',
    );
  });
}
