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
/// 🚨THE INSTRUMENT WAS THE HOLE (2026-08-31). This scanned `Text('…')` and
/// nothing else, so it went green while the autosave section's six section
/// headings shouted `label: 'Autosave'` at a Japanese user — and
/// `autosaveTitle` sat in the table, translated five ways, read by nobody,
/// **the exact bug the paragraph above was written about, surviving the
/// test written to stop it.** 유저 caught it by eye: 「Autosave가 아니라
/// 그부분도 자동저장이라고 번역」.
///
/// So the scan follows the STRING TO THE SCREEN, not one widget's name: a
/// `Text(…)` and every argument that a widget renders — `label`, `help`,
/// `title`, `tooltip`, `hintText`, `message`, `labelText`, `semanticLabel`.
/// ⚠️It reads the file WHOLE rather than line by line, because `help:` and
/// its string sit on different lines and a per-line scan cannot see across
/// the break — which is how six of them hid.
///
/// ⛔SCOPED TO THE DIALOGS, and the number says why. A scan of the whole of
/// `lib/src/ui` on 2026-08-31 found **205** hardcoded strings — 39 in the
/// shortcut registry, 21 in the import dialog, 19 in the top strip. Those
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

  /// Every shape in which a literal reaches the screen from these files.
  ///
  /// ⚠️`[^'$]` keeps interpolations out: `'${size.width}×${size.height}'`
  /// is arithmetic wearing quotes, not a sentence anyone translates.
  final onScreen = <RegExp>[
    RegExp(r"""Text\(\s*(?:const\s+)?'([^'$]*)'"""),
    RegExp(
      r"""(?:label|help|title|tooltip|hintText|message|labelText"""
      r"""|semanticLabel):\s*(?:const\s+)?'([^'$]*)'""",
    ),
  ];

  test('a settings dialog reads its words from AppStrings', () {
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
      final source = file.readAsStringSync();
      for (final pattern in onScreen) {
        for (final match in pattern.allMatches(source)) {
          final text = match.group(1)!;
          // A '×' or a bare number is not English — it is punctuation, and
          // it reads the same to everyone.
          if (!hasLetter.hasMatch(text) || universal.contains(text)) {
            continue;
          }
          final line =
              '\n'.allMatches(source.substring(0, match.start)).length + 1;
          offenders.add('$relative:$line  "$text"');
        }
      }
    }
    // ⚠️A scan that finds nothing because its regex broke would pass this
    // test silently. The corpus is known to contain translated calls, so
    // prove the reader reached the files at all.
    expect(
      File(
        'lib/src/ui/dialogs/autosave_settings_section.dart',
      ).readAsStringSync(),
      contains('AppText.strings.autosaveTitle'),
      reason: 'the scanned corpus is not what this test thinks it is',
    );
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
