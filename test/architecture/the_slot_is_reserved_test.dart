import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨★★★유저 규칙: **없다가 갑자기 생기는 UI 금지 — 자리는 항상 예약하고
/// 내용만 바꾼다.**
///
/// > 「없다가 갑자기 생기는 ui를 내가 좋아하겠니? 지금까지 경험에서?」
/// > (2026-08-15)
///
/// A widget that appears does two things at once: it takes the eye, and it
/// PUSHES its neighbours — under a hand that is already on the button it
/// moved. 「필요할 때만 보인다」 is tidy for the person building it and is
/// the screen rearranging itself for the person using it.
///
/// ⚠️This cannot census the whole law: a row that belongs to a mode the
/// user just chose is not the same thing as a badge blinking in beside a
/// button, and no scan can tell those apart. What it CAN close is the
/// literal idiom for it — Flutter's `Visibility`, whose default
/// `maintainSize: false` removes the child from layout and lets its
/// neighbours close up. That is the rule's failure, spelled as a widget.
///
/// ⛔`Offstage` keeps its three sites and no more. They are TAB HOSTS: the
/// whole panel swaps, so nothing beside the hidden subtree moves, and
/// keeping it mounted is what preserves its scroll position and its state
/// (the same investment `location.reload()` was banned for throwing away).
void main() {
  Iterable<({String path, int line, String text})> sourceLines() sync* {
    for (final file in dartFilesUnder('lib/src/ui')) {
      final relative = file.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src/ui'));
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        yield (path: key, line: index + 1, text: lines[index]);
      }
    }
  }

  test('the premise: it read the real tree', () {
    expect(sourceLines().length, greaterThan(20000));
  });

  test('🚨nothing hides a widget by taking its SLOT away', () {
    final offenders = [
      for (final line in sourceLines())
        if (RegExp(r'(?<![A-Za-z_])Visibility\s*\(').hasMatch(line.text) &&
            !line.text.trimLeft().startsWith('//'))
          '${line.path}:${line.line}  ${line.text.trim()}',
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Visibility drops the child out of layout, so its neighbours '
          'close up and the control beside it moves. Reserve the slot and '
          'change the CONTENT — an inert widget, an empty string in a '
          'fixed-width box, a dimmed control with a null callback.',
    );
  });

  test('⛔Offstage stays at the three tab hosts', () {
    final sites = {
      for (final line in sourceLines())
        if (RegExp(r'(?<![A-Za-z_])Offstage\s*\(').hasMatch(line.text) &&
            !line.text.trimLeft().startsWith('//'))
          line.path,
    };

    expect(sites, {
      'lib/src/ui/panels/editor_panel_tabs.dart',
      'lib/src/ui/storyboard_tab_host.dart',
      'lib/src/ui/timeline/timeline_panel.dart',
    }, reason: 'a new Offstage is a widget disappearing — say why here');
  });
}
