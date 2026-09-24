@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨★★★NOBODY BUILDS A SCROLLBAR BY HAND.
///
/// `AppScrollBehavior.buildScrollbar` already hands every desktop scrollable
/// in the app a [PanelScrollbar]. Its own header says why it exists: the app
/// had 「two species living side by side and nobody had counted them」 — some
/// thirty surfaces wearing Flutter's bar while the rails and panbars wore the
/// app's, diverging in the one way a hand notices (our thumb is 4px in every
/// state; the framework's grew to 6 under the pointer).
///
/// So a framework `Scrollbar` written in `lib/` is not a second species any
/// more. It is a SECOND BAR, drawn over the one the behaviour already put
/// there.
///
/// 🧪Baseline the day this was written: TWO, both in dialogs, and both were
/// doubled bars nobody had counted —
/// `app_confirm_dialog.dart` (the affected-files disclosure) and
/// `autosave_settings_section.dart` (the recovery snapshot list). The second
/// was also the app's one AUTO-HIDING bar, because the framework's default
/// fades the thumb when the list stops and CLAUDE.md forbids exactly that:
/// 「⛔스크롤바를 자동으로 숨기지 않는다」. A rule broken by writing nothing.
///
/// Both are deleted, so this starts from zero and every hit it ever reports
/// is new. 유저 answered ARCH-audit-Q2 「unify」, and this is what unifying
/// turned out to mean: not swapping the widget, but removing the one that
/// was doubled.
///
/// ⚠️Two surfaces the behaviour provably cannot reach — `DropdownButton`'s
/// menu and `MenuAnchor`'s panel — build their own inside the FRAMEWORK, not
/// here, and `ScrollbarThemeData` in `buildAppTheme` is their styling. They
/// are not `lib/` files, so this scan does not see them and does not need to.
///
/// ⚠️`test/architecture/` and not `test/tool/`: the pre-push hook treats
/// `test/tool/` as board-only and pushes it to master without a PR.
void main() {
  test('nothing in lib/ builds a framework scrollbar', () {
    final offenders = <String>[];
    for (final entity in dartFilesUnder('lib')) {
      final path = entity.path.replaceAll(r'\', '/');
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        // ⛔COMMENTS FIRST. Several files now explain in prose what they
        // used to draw, and a check that cannot tell 「this builds one」 from
        // 「this comment says it used to」 reports the history as the crime.
        final slash = lines[i].indexOf('//');
        final code = slash < 0 ? lines[i] : lines[i].substring(0, slash);
        if (_construction.hasMatch(code)) {
          offenders.add('$path:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A scrollable in this app already has a bar — `AppScrollBehavior` '
          'gives every one of them `PanelScrollbar`. Building a framework '
          '`Scrollbar` here draws a second one over it, and the framework\'s '
          'fades out, which CLAUDE.md forbids. If a surface genuinely needs '
          'a bar of its own shape, `AppScrollbar` is the app\'s and it takes '
          'a lane, a seat and a press mode.\n${offenders.join('\n')}',
    );
  });

  test('the behaviour that replaces them is still the one wiring them up', () {
    // ⛔THE PREMISE. The test above passes just as well in an app that has
    // no scrollbars at all — which is what deleting `buildScrollbar` would
    // produce, silently. 🧪It is the same shape as the enum case in
    // `a_mutation_changes_what_the_code_does_test`: an assertion that
    // cannot fail is a comment wearing a test's clothes.
    final source =
        File('lib/src/ui/theme/app_scroll_behavior.dart').readAsStringSync();
    expect(source, contains('Widget buildScrollbar('));
    expect(
      source,
      contains('return PanelScrollbar('),
      reason: 'the app-wide bar is what makes the rule above affordable',
    );
  });
}

/// A framework scrollbar being built.
///
/// ⚠️Anchored with a lookbehind so `AppScrollbar(`, `PanelScrollbar(` and
/// `CanvasViewportVerticalScrollbar(` are not hits — they are the app's own
/// and none of them can fade.
final _construction = RegExp(r'(?<![A-Za-z0-9_])(Raw)?Scrollbar\(');
