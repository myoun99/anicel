@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★A SCROLLBAR IN THIS APP DOES NOT HIDE ITSELF.
///
/// CLAUDE.md, under UI 컨벤션: 「⛔**스크롤바를 자동으로 숨기지 않는다.** 레인
/// 16px, 썸 최소 32px」.
///
/// Material's `Scrollbar` defaults to the opposite — the thumb appears while
/// the list is moving and fades when it stops — so the rule is broken by
/// writing NOTHING, which no behaviour test is going to notice. A widget test
/// that scrolls and looks would find a thumb there; the fade happens later,
/// off the end of the test.
///
/// 🧪Baseline the day this was written: ONE offender,
/// `lib/src/ui/dialogs/autosave_settings_section.dart`, whose list of
/// autosave rows faded its bar out. Fixed in the same change, so this starts
/// from zero and every hit it ever reports is new.
///
/// ⚠️It does not ask which scrollbar WIDGET is used. Whether the two dialogs
/// that still build Material's should build [AppScrollbar] like the rest of
/// the app is a real question about how they look, and it is on the board
/// rather than decided here — this file is about the one thing CLAUDE.md
/// states outright.
void main() {
  test('every scrollbar in lib/ keeps its thumb on screen', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      final source = entity.readAsStringSync();
      for (final match in _construction.allMatches(source)) {
        // The constructor's arguments run to its closing paren. Reading to
        // the next `);` at the same nesting would need a parser; the
        // argument list of a scrollbar is short, and 400 characters covers
        // every one in this tree with room to spare.
        final from = match.start;
        final to = (from + 400).clamp(0, source.length);
        final window = source.substring(from, to);
        if (window.contains('thumbVisibility: true')) continue;
        final line = '\n'.allMatches(source.substring(0, from)).length + 1;
        offenders.add('$path:$line  ${match.group(0)}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Material\'s Scrollbar fades its thumb out when the list stops '
          'moving, and CLAUDE.md forbids that: 「스크롤바를 자동으로 숨기지 '
          '않는다」. Pass `thumbVisibility: true`, or build the app\'s own '
          '`AppScrollbar`, which is always visible by construction.\n'
          '${offenders.join('\n')}',
    );
  });
}

/// A Material scrollbar being built. ⚠️Anchored so `AppScrollbar(`,
/// `PanelScrollbar(` and `CanvasViewportVerticalScrollbar(` are not hits:
/// they are the app's own, and none of them can fade.
final _construction = RegExp(r'(?<![A-Za-z0-9_])(Raw)?Scrollbar\(');
