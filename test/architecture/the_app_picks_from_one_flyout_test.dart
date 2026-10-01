@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨★★★EVERY LIST THE APP PICKS FROM IS THE ONE FLYOUT.
///
/// 🗣️F-230 (유저 2026-09-29): 「오디오의 출력 선택이나 트랜지션레이어의 ol선택등
/// 선택하는 ui가 구식 ui 쓰는곳있는데, 앵커팝오버? 공용화된 ui 통일적용.
/// 다른곳도 확인해서」.
///
/// The shared list is `showPanelFlyout`, opened by `PanelFlyoutButton` or
/// `PanelFlyoutTrigger`. A framework menu draws its own rows, its own row
/// height and its own mark for the current value — the 「구식 UI」 the user
/// saw beside the app's.
///
/// 🧪Baseline the day this was written: NINE — every `DropdownButton` and
/// `DropdownButtonFormField` in lib/ (the audio devices, offset unit and
/// input channel; the input settings' touch slots and canvas mappings; the
/// languages; the linked cut's target; the instruction's kind, which is the
/// transition row's O.L). R6 had already pulled every raw `PopupMenuButton`
/// into the shell. All are gone, so every hit this ever reports is new.
void main() {
  test('nothing in lib/ builds a framework menu', () {
    final offenders = <String>[];
    for (final entity in dartFilesUnder('lib')) {
      final path = entity.path.replaceAll(r'\', '/');
      // The shell itself: the one place the menu route is opened.
      if (path.endsWith('lib/src/ui/widgets/panel_flyout.dart')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        // Comments first: a file explaining what it used to build is
        // history, not a menu.
        final slash = lines[i].indexOf('//');
        final code = slash < 0 ? lines[i] : lines[i].substring(0, slash);
        if (_frameworkMenu.hasMatch(code)) {
          offenders.add('$path:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A list to pick from is the shared flyout: PanelFlyoutButton with '
          'asFlyoutChoices (an enum) or asFlyoutValueChoices (any value), or '
          'PanelFlyoutTrigger over a glyph.\n${offenders.join('\n')}',
    );
  });

  test('the flyout that replaces them is still the one they open', () {
    // ⛔THE PREMISE: the scan above passes as well in an app with no picker
    // at all.
    final source = File(
      'lib/src/ui/widgets/panel_flyout.dart',
    ).readAsStringSync();
    expect(source, contains('class PanelFlyoutButton '));
    expect(source, contains('List<PanelFlyoutEntry> asFlyoutValueChoices('));
    expect(source, contains('showMenu<PanelFlyoutItem>('));
  });
}

/// A framework menu being built — or opened.
final _frameworkMenu = RegExp(
  '(?<![A-Za-z0-9_])(DropdownButton|DropdownButtonFormField|DropdownMenu|'
  r'PopupMenuButton|MenuAnchor|showMenu)(<[^>(]*>)?\(',
);
