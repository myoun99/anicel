import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨★★★THE APP HAS ONE BOOLEAN — the ring, dotted when on
/// (`lib/src/ui/widgets/boolean_dot.dart`).
///
/// 유저 (guide-sym ⑥⑧, 2026-08-31): 「이 on off 버튼, 공용화시켜서
/// 다른곳에도 쓸수있게. 앞으로 이런 불리언값 바꾸는 버튼은 이걸 공통적으로
/// 사용」 — and then 「좀 더 적용범위 넓혀서 진짜 불리언값 모든곳에 적용 …
/// 동일한 on off 버튼 전수조사해서 적용」.
///
/// ⛔SO THIS SCANS SOURCE. 「앞으로」 is the part no behaviour test can
/// hold: a new row that reaches for Material's `Switch` passes every test it
/// brings along. When this landed (2026-09-23) the settings rows, the
/// compact export/import switches, the hand-written `SwitchListTile`s, the
/// tablet-service radio pair, the timesheet's box chips, the flyout's toggle
/// check, the fx lane's check box and the guide row's hand-drawn ring all
/// became this one control.
void main() {
  test('no Material or Cupertino boolean control anywhere in lib', () {
    final hits = [
      for (final file in dartFilesUnder('lib'))
        ..._hits(libPath(file), file.readAsStringSync(), _materialBoolean),
    ];
    expect(
      hits,
      isEmpty,
      reason:
          'a boolean here is the app\'s ring: `SettingsSwitchRow` for a '
          'labelled row, `BooleanDotButton` for a control of its own, '
          '`BooleanDot` where the surrounding row keeps the press. '
          '(Material\'s `Switch` also wraps itself in an `Opacity`, which '
          'keeps its whole panel from ever baking.)\n${hits.join('\n')}',
    );
  });

  test('the ring is drawn in one file', () {
    final drawers = {
      for (final file in dartFilesUnder('lib'))
        if (_hits(libPath(file), file.readAsStringSync(), _ringGlyph)
            .isNotEmpty)
          libPath(file),
    };
    expect(
      drawers,
      {'lib/src/ui/widgets/boolean_dot.dart'},
      reason:
          'a file that draws the ring itself is a second boolean — the '
          'guide row had one, and its colours had already drifted from the '
          'rule 유저 gave',
    );
  });

  test('a check mark is a verb, never a state', () {
    final wearers = {
      for (final file in dartFilesUnder('lib'))
        if (_hits(libPath(file), file.readAsStringSync(), _checkGlyph)
            .isNotEmpty)
          libPath(file),
    };
    expect(
      wearers,
      _checkMarkVerbs.keys.toSet(),
      reason:
          'a check that says 「on」 is the mark 「선택 표시는 색상만」 names — '
          'use the ring. A button whose job is to APPLY may wear one; add a '
          'line to _checkMarkVerbs saying which',
    );
    for (final entry in _checkMarkVerbs.entries) {
      expect(
        entry.value.length,
        greaterThan(20),
        reason: '${entry.key} needs a reason, not a slot',
      );
    }
  });

  test('the scan sees a planted control, and not the app\'s own names or a '
      'comment', () {
    // ⛔A WALL THAT FINDS NOTHING PROVES NOTHING until it has found
    // something: the three walls above are green on an empty scan too.
    const planted = '''
Widget a() => Switch(value: true, onChanged: null);
Widget b() => RadioGroup<int>(groupValue: 1, onChanged: (_) {}, child: c);
// ↩️It was a SwitchListTile( once.
Widget d() => SettingsSwitchRow(label: 'x', value: true, onChanged: null);
Widget e() => Icon(on ? Icons.check_box : Icons.check_box_outline_blank);
Widget f() => Icon(Icons.indeterminate_check_box_outlined);
''';
    List<String> lines(RegExp pattern) => [
      for (final hit in _hits('planted.dart', planted, pattern))
        hit.split('  ').first,
    ];
    expect(lines(_materialBoolean), ['planted.dart:1', 'planted.dart:2']);
    expect(lines(_checkGlyph), ['planted.dart:5']);
  });
}

/// The app's ring glyphs — the pair [BooleanDot] draws.
final _ringGlyph = RegExp(r'Icons\.radio_button_(un)?checked\b');

/// A check that could stand for 「on」. `indeterminate_check_box` is not
/// one: it is the SUBTRACT selection mode's picture.
final _checkGlyph = RegExp(
  r'Icons\.(check|check_box\w*|check_circle\w*|done\w*|task_alt|'
  r'toggle_on|toggle_off)\b',
);

final _materialBoolean = RegExp(
  r'\b(Switch|SwitchListTile|CupertinoSwitch|Checkbox|CheckboxListTile|'
  'CupertinoCheckbox|Radio|RadioListTile|RadioGroup|CupertinoRadio|'
  'FilterChip|ChoiceChip|CheckboxMenuButton|RadioMenuButton|'
  r'CheckedPopupMenuItem)(\.adaptive)?(<[^>()]*>)?\(',
);

/// 🚨THE LEDGER. Measured 2026-09-23: one file wears a check, and it is a
/// verb.
const _checkMarkVerbs = <String, String>{
  'lib/src/ui/canvas/canvas_selection_layer.dart':
      'the APPLY button of a move/transform session — it commits, and shows '
      'no state of its own',
};

/// Every line of [source] (named [path]) where [pattern] matches CODE — a
/// `//` comment is cut off first, so a history note may name what it
/// replaced.
List<String> _hits(String path, String source, RegExp pattern) => [
  for (final (index, line) in source.split('\n').indexed)
    if (pattern.hasMatch(_code(line))) '$path:${index + 1}  ${line.trim()}',
];

String _code(String line) {
  final comment = line.indexOf('//');
  return comment < 0 ? line : line.substring(0, comment);
}
