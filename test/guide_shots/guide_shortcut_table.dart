// The guide's shortcut page, written from the app's own shortcut list: its
// presets, and under each its groups, its names and the keys that preset
// ships with, in the order the shortcut window shows them.
//
// 유저 2026-10-03: 「단축키 바뀔경우 많을텐데 낡지않을구존가? 프로들하는거처럼?」
// — a page that copies keys by hand is wrong the day a default moves. Here
// the page names nothing by hand: re-making the guide re-writes the tables,
// the way a product's docs read its keymap.
//
// Each key goes in twice, as the app itself spells it on a PC and on a Mac or
// an iPad (`singleActivatorLabel` — Ctrl+Z / ⌘Z), and the page shows the
// reader's own. Only the part between the two markers is written; the rest of
// the page stays the guide's own text, edited by hand.
import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart'
    show editorActionLabel;
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

const _begin = '<!-- shortcuts:begin -->';
const _end = '<!-- shortcuts:end -->';

/// The guide's own words around the app's: the two table heads, and the
/// word between two keys of one action.
({String action, String key, String or}) _wordsOf(AppLanguage language) =>
    switch (language) {
      AppLanguage.ko => (action: '동작', key: '키', or: '또는'),
      AppLanguage.ja => (action: '操作', key: 'キー', or: 'または'),
      _ => (action: 'Action', key: 'Key', or: 'or'),
    };

/// Re-writes the generated part of `<language>/shortcuts.md` under
/// [guideRoot]. ⛔A page without both markers is an error, not a skip: a
/// table that silently stops being written is the stale page this exists
/// to end.
void writeShortcutTable(String guideRoot, AppLanguage language) {
  final page = File('$guideRoot/${language.name}/shortcuts.md');
  final text = page.readAsStringSync();
  final begin = text.indexOf(_begin);
  final end = text.indexOf(_end);
  if (begin < 0 || end < begin) {
    throw StateError('${page.path}: no $_begin … $_end to write between');
  }
  page.writeAsStringSync(
    '${text.substring(0, begin + _begin.length)}\n'
    '${shortcutTableMarkdown(language)}\n'
    '${text.substring(end)}',
  );
}

/// Every action that ships with a key, one table per group, under each
/// shortcut preset's name (I-63, 유저 2026-10-03: 「이를 가이드페이지에도 두
/// 프리셋별로 낡지않게 단축키 보여주도록」), in [language]. The keys are the
/// ones the shortcut window shows for that preset ([presetActivators]).
String shortcutTableMarkdown(AppLanguage language) {
  final before = AppText.settings.value;
  AppText.settings.value = AppLanguageSettings(
    programLanguage: language,
    notationLanguage: language,
  );
  try {
    final out = StringBuffer();
    for (final preset in ShortcutPreset.values) {
      final name = AppText.strings.shortcutPresetName(
        preset.name,
        preset.label,
      );
      out
        ..writeln()
        ..writeln('## ${_html(name)}');
      _writeGroups(out, preset, _wordsOf(language));
    }
    return out.toString();
  } finally {
    AppText.settings.value = before;
  }
}

/// [preset]'s tables, one per group that has a key in it.
void _writeGroups(
  StringBuffer out,
  ShortcutPreset preset,
  ({String action, String key, String or}) words,
) {
  final groups = <String, List<String>>{};
  for (final definition in editorActionDefinitions) {
    final keys = presetActivators(preset, definition).map(_key);
    if (keys.isNotEmpty) {
      (groups[definition.category] ??= []).add(
        '| ${_cell(editorActionLabel(definition.id))} '
        '| ${keys.join(' ${words.or} ')} |',
      );
    }
  }
  for (final MapEntry(key: category, value: rows) in groups.entries) {
    out
      ..writeln()
      ..writeln('### ${AppText.strings.shortcutCategory(category, category)}')
      ..writeln()
      ..writeln('| ${words.action} | ${words.key} |')
      ..writeln('|---|---|');
    rows.forEach(out.writeln);
  }
}

/// One key, as the app writes it on a PC and on a Mac or an iPad — one
/// `<kbd>` when the two agree, both (the page hides the other) when not.
String _key(SingleActivator activator) {
  final pc = _spelling(activator, TargetPlatform.windows);
  final mac = _spelling(activator, TargetPlatform.macOS);
  if (pc == mac) {
    return '<kbd>${_html(pc)}</kbd>';
  }
  return '<kbd class="k-pc">${_html(pc)}</kbd>'
      '<kbd class="k-mac">${_html(mac)}</kbd>';
}

String _spelling(SingleActivator activator, TargetPlatform platform) =>
    singleActivatorLabel(platformActivator(activator, platform), platform);

String _html(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _cell(String text) => _html(text).replaceAll('|', r'\|');
