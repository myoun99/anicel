import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// F-2 — **no explanatory copy under a control.**
///
/// 유저 2026-08-24: 「텍스트가 쓸데없이 설명적인 부분이 너무 많음. 특히
/// 환경설정은 텍스트가 너무 심함. 최대한 간략하게 심플하게 하고싶음. 쓸데없는
/// 텍스트 싹 다 삭제하고 그 중에서 필요해보이는건 툴팁으로 넣도록」.
/// It restates a standing rule ("텍스트 설명많은거 버릇이야"), which is why it
/// gets a gate this time instead of another sweep.
///
/// ⚠️This scans SOURCE, which is the only thing that can see a caption nobody
/// wrote a test for. A widget test can only check the screens it happens to
/// build, and the copy grows on the screens nobody opened.
///
/// The ledger below is the whole exception list. Adding to it is allowed and
/// is meant to cost a sentence: say what the subtitle SHOWS, and if the answer
/// is "what the control does", it belongs in a tooltip instead.
/// A line that only TALKS about the pattern. This file talks about it a lot,
/// and so does the widget that exists to prevent it.
bool isComment(String line) => line.trimLeft().startsWith('//');

void main() {
  /// Every `subtitle:` that is legitimately not explanatory copy.
  ///
  /// A subtitle that shows a VALUE is a second line of data, not a caption —
  /// removing it would delete information the window is there to give.
  const allowed = <String, String>{
    'lib/src/ui/brush/guide_panels.dart':
        'the vanishing point row: the subtitle is its COORDINATES (or '
            '"parallel"), which is the row\'s content, not a description of it',
  };

  test('no `subtitle:` caption outside the ledger', () {
    final offenders = <String>[];
    final unusedLedger = allowed.keys.toSet();

    for (final entry in Directory('lib/src/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final relative = entry.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src/ui'));
      final lines = entry.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (isComment(lines[i]) || !lines[i].contains('subtitle:')) {
          continue;
        }
        if (allowed.containsKey(key)) {
          unusedLedger.remove(key);
          continue;
        }
        offenders.add('$key:${i + 1}  ${lines[i].trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'a caption under a control is the habit this rule exists for. '
          'Put the words in a tooltip — SettingsSwitchRow / '
          'SettingsSectionHeading / settingsHelpTooltip take `help` and have '
          'nowhere else to put it. If the subtitle really is DATA, add the '
          'file to the ledger in this test with a sentence saying what it '
          'shows.',
    );

    expect(
      unusedLedger,
      isEmpty,
      reason: 'a ledger entry whose file no longer has a subtitle is a stale '
          'exception — delete it, or the next caption there passes for free',
    );
  });

  /// The other half: a string NAMED as help must not be rendered as visible
  /// copy. The sweep moved every one of these into a tooltip, and the naming
  /// convention is what makes the rule checkable at all.
  test('no `*Help` / `*Note` string is rendered as a bare Text', () {
    final offenders = <String>[];
    final pattern = RegExp(
      r'''Text\(\s*(?:AppText\.)?strings?\.\w*(?:Help|Note)\b''',
    );

    for (final entry in Directory('lib/src/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final relative = entry.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src/ui'));
      final lines = entry.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (!isComment(lines[i]) && pattern.hasMatch(lines[i])) {
          offenders.add('$key:${i + 1}  ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these read as `Text(strings.somethingHelp)` — a caption. '
          'Tooltip them.',
    );
  });
}
