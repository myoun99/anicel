// The guide's shortcut page, written from the app's own shortcut list: its
// groups, its names and its default keys, in the order the shortcut window
// shows them.
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

/// Every action that ships with a key, one table per group, in [language].
String shortcutTableMarkdown(AppLanguage language) {
  final before = AppText.settings.value;
  AppText.settings.value = AppLanguageSettings(
    programLanguage: language,
    notationLanguage: language,
  );
  try {
    final words = _wordsOf(language);
    final groups = <String, List<EditorActionDefinition>>{};
    for (final definition in editorActionDefinitions) {
      if (definition.defaultActivators.isNotEmpty) {
        (groups[definition.category] ??= []).add(definition);
      }
    }
    final out = StringBuffer();
    for (final MapEntry(key: category, value: actions) in groups.entries) {
      out
        ..writeln()
        ..writeln('## ${AppText.strings.shortcutCategory(category, category)}')
        ..writeln()
        ..writeln('| ${words.action} | ${words.key} |')
        ..writeln('|---|---|');
      for (final action in actions) {
        final keys = [
          for (final activator in action.defaultActivators) _key(activator),
        ];
        out.writeln(
          '| ${_cell(editorActionLabel(action.id))} '
          '| ${keys.join(' ${words.or} ')} |',
        );
      }
    }
    return out.toString();
  } finally {
    AppText.settings.value = before;
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
