import 'dart:io';

import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★유저 규칙: **툴 설정은 툴 설정 패널에 넣는다. 그 툴 전용 패널을
/// 새로 만들지 않는다.**
///
/// > 「**너가 멋대로 보완하지 마**」 (유저, when the rule was set)
///
/// One tool wanting a knob is never a reason for one more panel. Every
/// tool's knobs live in `ToolSettingsPanel`, which switches on the ACTIVE
/// tool — so the user learns one place, the panel keeps one scroll
/// position per tool, and the rail does not grow a button per tool.
///
/// ⛔THIS IS A CENSUS, NOT A WALL (the shape `no_explanatory_copy`,
/// `selection_is_colour_only` and `the_slot_is_reserved` set). The panels
/// standing today stay; the list may only get SHORTER. A new one has to
/// argue itself into the ledger below, in the same commit that adds it —
/// which is the whole point, because a panel always arrives as "just this
/// one tool" and nobody is ever asked.
///
/// **When this goes red, there are two ways forward and only two:**
///  1. Move the setting into `lib/src/ui/brush/tool_settings_panel.dart` —
///     a new `CanvasTool.x => _XSettings(...)` arm, beside the other nine.
///     This is the answer unless the user said otherwise.
///  2. If the user decided this one is an exception, add it to the ledger
///     HERE with their words and the date, exactly as `tool-size` carries
///     theirs. ⛔Not a comment in the widget: the number is what holds.
///
/// ⚠️No scan can read intent, so this reads the two spellings the rule
/// actually fails in: a SECOND place where the active tool picks a
/// settings widget, and a NEW panel in the workspace registry.
void main() {
  Iterable<({String path, int line, String text})> sourceLines() sync* {
    for (final file in Directory('lib/src/ui').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final relative = file.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src/ui'));
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index += 1) {
        yield (path: key, line: index + 1, text: lines[index]);
      }
    }
  }

  /// The one panel. Everything below is measured against this path.
  const panel = 'lib/src/ui/brush/tool_settings_panel.dart';

  /// `CanvasTool.fill => _FillSettings(` — the active tool choosing the
  /// widget that shows its knobs. There may be exactly one file doing it.
  /// ⚠️`const` is in the pattern because the planted violation that proved
  /// this test red wrote `=> const _LassoSettings()` and the first spelling
  /// of the scan walked straight past it.
  final dispatch = RegExp(
    r'CanvasTool\.\w+\s*(?:\|\|\s*CanvasTool\.\w+\s*)*=>\s*(?:const\s+)?'
    r'_?[A-Z]\w*Settings',
  );

  /// A widget whose name ends in `Settings` (or `SettingsPanel`) — the
  /// repo's name for a surface of knobs. ⚠️The app-wide settings dialog's
  /// pieces end in `SettingsSection` and are deliberately NOT this: they
  /// are the settings ROOM, which is a different rule and a different test.
  final declaration = RegExp(
    r'^class (_?[A-Z]\w*Settings(?:Panel)?) extends State(?:less|ful)Widget',
  );

  test('the premise: it read the real tree', () {
    expect(sourceLines().length, greaterThan(20000));
  });

  test('🚨the active tool picks its settings in ONE file', () {
    final arms = [
      for (final line in sourceLines())
        if (dispatch.hasMatch(line.text) &&
            !line.text.trimLeft().startsWith('//'))
          line,
    ];

    // A scan that matches nothing passes everything. The arms are counted
    // first so a reformat that breaks the regex fails LOUD instead of
    // going quietly green.
    expect(
      arms.length,
      greaterThanOrEqualTo(_knownToolArms),
      reason:
          'the tool→settings arms stopped matching, or one left the panel. '
          'If a tool genuinely went away, lower _knownToolArms to '
          '${arms.length}; if the panel was reformatted so the arm no '
          'longer fits on one line, fix the scan — as written it now '
          'measures nothing.',
    );

    expect(
      arms.map((line) => line.path).toSet(),
      {panel},
      reason:
          'a second place decides what a tool\'s settings look like. The '
          'rule is one panel: move the arm into $panel — the user\'s words '
          'were 「너가 멋대로 보완하지 마」 — or, if they granted an '
          'exception, put it in this file\'s ledger with their words.\n'
          '${arms.map((line) => '${line.path}:${line.line}  ${line.text.trim()}').join('\n')}',
    );
  });

  test('⛔a settings widget is a SECTION of that panel, not a panel', () {
    final declared = <String, String>{};
    for (final line in sourceLines()) {
      final match = declaration.firstMatch(line.text);
      if (match != null) {
        declared[match.group(1)!] = line.path;
      }
    }

    expect(
      declared,
      hasLength(greaterThanOrEqualTo(_knownSettingsWidgets)),
      reason:
          'the settings widgets stopped matching — the scan measures '
          'nothing. Either the naming changed (a knob surface is named '
          '`…Settings`) or one went away; if the latter, lower '
          '_knownSettingsWidgets to ${declared.length}.',
    );

    final host = File(panel).readAsStringSync();
    final orphans = <String>[
      for (final entry in declared.entries)
        if (entry.value != panel && !host.contains('${entry.key}('))
          '${entry.value}  ${entry.key}',
    ];

    expect(
      orphans,
      isEmpty,
      reason:
          'a settings surface that the tool settings panel does not mount. '
          'It lives in its own file — fine, the panel is long — but it has '
          'to be a SECTION of it: $panel builds it from a `CanvasTool` arm '
          '(that is what `BrushSettingsPanel` and `GuideSettings` are). A '
          'settings widget nobody mounts there is the tool-specific panel '
          'the rule forbids.\n${orphans.join('\n')}',
    );
  });

  test('⛔the workspace grows no panel for one tool', () {
    expect(
      EditorWorkspace.debugAllTabIds.toSet(),
      _thePanelsStandingToday,
      reason:
          'the panel list changed. If the new one is a TOOL\'s settings, '
          'it does not get a panel: add a `CanvasTool.x => _XSettings(...)` '
          'arm to $panel instead. If it is not tool settings at all, add '
          'its id to _thePanelsStandingToday in this commit and say in one '
          'line what it is — and if it IS a tool panel the user asked for, '
          'quote them, the way `tool-size` quotes 「새 패널로 만든다 — '
          '이번은 예외」.',
    );
  });
}

/// The nine arms of `ToolSettingsPanel.build` when this gate landed
/// (2026-09-08): brush/eraser, fill, fillShape, eyedropper, select, cut,
/// cutStamp, move, guide. Adding a tenth is the rule being OBEYED — the
/// count only guards against the scan going blind.
const int _knownToolArms = 9;

/// The ten widgets named `…Settings`/`…SettingsPanel` standing at the same
/// date: `ToolSettingsPanel` plus its seven private sections, and the two
/// it mounts from their own files (`BrushSettingsPanel`, `GuideSettings`).
const int _knownSettingsWidgets = 10;

/// **THE LEDGER — every panel the workspace can build, and what it is.**
///
///  * `brush-settings` — ★THE tool settings panel (the id is historical;
///    the label is 툴 설정). Every tool's knobs belong in it.
///  * `tool-size` — 🚨THE ONE EXCEPTION, and it is the user's own:
///    유저 결정 2026-08-25 「**새 패널로 만든다 — 이번은 예외**」. A rack of
///    sizes is not a setting, it is a value you point at while drawing, so
///    it has to be visible at the same time as the canvas — the one thing
///    the settings panel cannot be. ⛔NOT A HOLE TO WIDEN: it was granted
///    for a rack of values, not for "my tool needs its own space".
///  * `tools` — the tool PICKER, and `brushes` — the tool LIBRARY (the set
///    you pick one out of). Neither is a knob.
///  * `canvas` — the drawing surface itself.
///  * `color-wheel`, `color-rgb`, `color-palette` — the colour pickers. The
///    colour is not a tool's setting; it belongs to all of them (R26 #11
///    took the swatches OUT of the brush settings for exactly this).
///  * `onion-skin` — a viewing aid's own knobs. Not a tool.
///  * `media`, `media-viewer`, `media-viewer-sub` — the pool and the two
///    reference viewers.
///  * `timeline`, `storyboard`, `conte`, `envelope`, `timesheet` — the
///    production surfaces.
///
/// ⚠️`camera` is a dead constant with no builder, deliberately absent from
/// the registry — see `EditorWorkspace.debugAllTabIds`.
const Set<String> _thePanelsStandingToday = <String>{
  'tools',
  'canvas',
  'brushes',
  'brush-settings',
  'color-wheel',
  'color-rgb',
  'color-palette',
  'onion-skin',
  'tool-size',
  'media',
  'media-viewer',
  'media-viewer-sub',
  'timeline',
  'storyboard',
  'conte',
  'envelope',
  'timesheet',
};
