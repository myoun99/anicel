// The guide's shortcut page, written from the app's own shortcut list: its
// groups and its names, in the order the shortcut window shows them, and
// beside the language folders `keys.json`, the keys every preset ships with.
//
// 유저 2026-10-03: 「단축키 바뀔경우 많을텐데 낡지않을구존가? 프로들하는거처럼?」
// — a page that copies keys by hand is wrong the day a default moves. Here
// the page names nothing by hand: re-making the guide re-writes the tables
// and the keymap, the way a product's docs read its keymap.
//
// A page names an action, never its key (`<span data-k="edit-undo">`); the
// guide fills it from `keys.json` for the preset the reader picked, as the
// app itself spells it on a PC and on a Mac or an iPad
// (`singleActivatorLabel` — Ctrl+Z / ⌘Z). Only the part between the two
// markers is written; the rest of the page stays the guide's own text,
// edited by hand.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart'
    show editorActionLabel;
import 'package:anicel/src/ui/shortcuts/shortcut_activator_codec.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_presets.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_shelf.dart';
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

/// The keys every preset ships, as `keys.json` beside the language folders:
/// what each page's `<span data-k="<action id>">` is filled from, for the
/// preset the reader picks, as a language is picked (유저 2026-10-28:
/// 「한국어/일본어 고르듯이 단축키도 프리셋 3종 변환해서 보이게 … 3종마다
/// 페이지 만드는게아니라 연결해서 그 단축키만 자동으로 바뀌도록」). It opens on
/// the preset an install opens on — asked of the app, not written here.
///
/// Each key is a pair, as a PC and as a Mac or an iPad spell it.
void writeShortcutKeymap(String guideRoot) {
  final keys = <String, Map<String, List<List<String>>>>{};
  for (final definition in editorActionDefinitions) {
    for (final preset in ShortcutPreset.values) {
      final pairs = [
        for (final activator in presetActivators(preset, definition))
          [
            _spelling(activator, TargetPlatform.windows),
            _spelling(activator, TargetPlatform.macOS),
          ],
      ];
      if (pairs.isNotEmpty) {
        (keys[definition.id] ??= {})[preset.name] = pairs;
      }
    }
  }
  final before = AppText.settings.value;
  final names = <String, Map<String, String>>{};
  final or = <String, String>{};
  try {
    for (final language in _guideLanguages) {
      AppText.settings.value = AppLanguageSettings(
        programLanguage: language,
        notationLanguage: language,
      );
      names[language.name] = {
        for (final preset in ShortcutPreset.values)
          preset.name: AppText.strings.shortcutPresetName(
            preset.name,
            preset.label,
          ),
      };
      or[language.name] = _wordsOf(language).or;
    }
  } finally {
    AppText.settings.value = before;
  }
  File('$guideRoot/keys.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'default': EditorShortcutBindings().preset.base.name,
      'presets': [for (final preset in ShortcutPreset.values) preset.name],
      'names': names,
      'or': or,
      'keys': keys,
    }),
  );
}

/// The languages the guide is written in — one folder each.
const _guideLanguages = [AppLanguage.ko, AppLanguage.ja, AppLanguage.en];

/// Every action that ships with a key in any preset, one table per shelf,
/// in [language] (I-63, 유저 2026-10-03: 「이를 가이드페이지에도 두
/// 프리셋별로 낡지않게 단축키 보여주도록」). The key column names the action
/// ([writeShortcutKeymap]): the page shows the keys of the preset picked.
String shortcutTableMarkdown(AppLanguage language) {
  final before = AppText.settings.value;
  AppText.settings.value = AppLanguageSettings(
    programLanguage: language,
    notationLanguage: language,
  );
  try {
    final out = StringBuffer();
    _writeGroups(out, _wordsOf(language));
    return out.toString();
  } finally {
    AppText.settings.value = before;
  }
}

/// The tables, one per shelf that has a key in it in some preset, headed by
/// the shelves from its place down — 「캔버스 › 도구」, as the window nests
/// them.
void _writeGroups(
  StringBuffer out,
  ({String action, String key, String or}) words,
) {
  final groups = <ShortcutShelf, List<String>>{};
  for (final definition in editorActionDefinitions) {
    final shipped = ShortcutPreset.values.any(
      (preset) => presetActivators(preset, definition).isNotEmpty,
    );
    if (shipped) {
      (groups[definition.shelf] ??= []).add(
        '| ${_cell(editorActionLabel(definition.id))} '
        '| <span data-k="${_html(definition.id)}"></span> |',
      );
    }
  }
  for (final shelf in ShortcutShelf.values) {
    final rows = groups[shelf];
    if (rows == null) {
      continue;
    }
    final heading = [
      for (final each in shelf.path)
        AppText.strings.shortcutShelfName(each.name, each.label),
    ].join(' › ');
    out
      ..writeln()
      ..writeln('### ${_html(heading)}')
      ..writeln()
      ..writeln('| ${words.action} | ${words.key} |')
      ..writeln('|---|---|');
    rows.forEach(out.writeln);
  }
}

/// One key as the app writes it on [platform] (`singleActivatorLabel` —
/// Ctrl+Z / ⌘Z).
String _spelling(SingleActivator activator, TargetPlatform platform) =>
    singleActivatorLabel(platformActivator(activator, platform), platform);

String _html(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _cell(String text) => _html(text).replaceAll('|', r'\|');
