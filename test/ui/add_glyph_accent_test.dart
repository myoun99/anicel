import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// EVERY `＋` IN THE APP WEARS THE ACCENT, AND THIS IS WHAT MAKES THAT TRUE.
///
/// 유저 확정 (2026-08-10): *"+의 강조색은 +라는 아이콘에만 있는건 좋다고
/// 생각해. ＋가있는 모든곳. 공통적으로."*
///
/// The 「모든 곳」 is the whole point, and it is the half that cannot be
/// checked by pumping a widget: a test that mounts the timeline bar proves
/// three plus signs and says nothing about the sixth one, in the media
/// browser, that a later round adds without ever reading this sentence. The
/// bar round shipped exactly that — three accented, six plain — and the gap
/// was invisible from inside any single panel's test.
///
/// So this is a CONTRACT over the source: a `＋` glyph must take its colour
/// from [AppColors.addGlyph], or argue for itself in [_allowed].
void main() {
  test('every ＋ glyph in the app takes its colour from AppColors.addGlyph', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      final source = file.readAsStringSync();
      for (final match in _plusGlyph.allMatches(source)) {
        // The colour is rarely on the same line as the glyph — it is an
        // argument two or three lines down — so the unit here is a window of
        // source, not a line.
        final window = source.substring(
          (match.start - _window).clamp(0, source.length),
          (match.end + _window).clamp(0, source.length),
        );
        if (window.contains('addGlyph') || window.contains('accent: true')) {
          continue;
        }
        if (_allowed.any(window.contains)) {
          continue;
        }
        final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('$path:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A ＋ was added without the accent. Colour the GLYPH with '
          'AppColors.addGlyph(enabled: ...) — never the border, never a '
          'caret, never the label beside it. If the plus is a row in a menu '
          'rather than a button, add it to _allowed with the reason.\n'
          '${offenders.join('\n')}',
    );
  });
}

/// `\b` keeps `Icons.add_box_outlined` and friends out: they are their own
/// glyphs, and the law is about the bare plus.
final RegExp _plusGlyph = RegExp(r'Icons\.add\b');

const int _window = 320;

/// Where a plus is NOT an add affordance wearing the accent.
///
/// Both entries are the same shape: a plus that is already inside something
/// that says what it does, where an accent would be shouting a second time.
const List<String> _allowed = [
  // A LEADING GLYPH IN A MENU ROW. The row's label is right there — "New
  // Cut", "Same as selected" — and accenting one row of a flyout picks a
  // winner among items that are peers.
  "keyValue: 'add-cut-new'",
  "keyValue: 'add-layer-kind-same'",
  // THE EMPTY GROUP'S PLACEHOLDER. Not a button that adds anything: it is
  // what a rail button shows when its group holds no panels yet, standing
  // in for the icon of the first tab that lands there.
  'tabs.isEmpty ? Icons.add',
];
