import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:sqlite3/sqlite3.dart';

import '../persistence/sqlite_bytes.dart';

/// The program a shortcut file was written by (I-107).
enum KeymapProgram { tvpaint, clipStudio }

/// A key as a shortcut file names it: the key, and the modifiers held with
/// it. [control] is the program's Ctrl — what a Mac presses as ⌘, as it
/// does a preset's.
@immutable
final class ProgramChord {
  const ProgramChord(
    this.key, {
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;

  @override
  bool operator ==(Object other) =>
      other is ProgramChord &&
      other.key == key &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(key, control, shift, alt);
}

/// What a program's shortcut file says (I-107).
///
/// ⚠️Not always every key the program has: CLIP STUDIO PAINT keeps its
/// menus' keys in a shortcut set (`.khc`) and its tools' in the tool
/// palette (`.todb`), so a command one file gives no key may have one in
/// the other.
final class ProgramKeymap {
  const ProgramKeymap({
    required this.program,
    required this.keys,
    required this.unread,
  });

  final KeymapProgram program;

  /// The keys the file puts on each command, in the file's order — a
  /// command it gives no key is not here.
  final Map<String, List<ProgramChord>> keys;

  /// How many keys the file names that are no key here — a mouse wheel, a
  /// key it spells in a way not known here. Counted, so they are said
  /// rather than dropped.
  final int unread;
}

/// TVPaint's shortcut files: its `config.ini`, a keymap `.cfg`, and the
/// `.txt` its shortcut window saves.
const List<String> _tvpaintExtensions = ['ini', 'cfg', 'txt'];

/// CLIP STUDIO PAINT's: a shortcut set (`.khc`), a tool palette (`.todb`).
const List<String> _clipStudioExtensions = ['khc', 'todb'];

/// What [readShortcutFile] reads. 🗣️I-107-Q2 (유저 2026-10-18): 「다섯 다」.
const List<String> shortcutFileExtensions = [
  ..._tvpaintExtensions,
  ..._clipStudioExtensions,
];

/// The keys in the shortcut file named [name], holding [bytes] — null for a
/// file no program's keys can be read out of.
///
/// By its extension, as every door tells a file: TVPaint writes text, CLIP
/// STUDIO PAINT SQLite.
ProgramKeymap? readShortcutFile(String name, List<int> bytes) {
  final extension = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
  if (_clipStudioExtensions.contains(extension)) {
    return readClipStudioShortcuts(bytes);
  }
  if (_tvpaintExtensions.contains(extension)) {
    return readTvpaintKeymap(utf8.decode(bytes, allowMalformed: true));
  }
  return null;
}

/// What TVPaint's shortcut window saves (`.txt`) names each command by:
/// the name it is shown by, in the interface's language. 🗣️I-107-Q2 (유저
/// 2026-10-18, 「다섯 다」): the Japanese names first — the file the user sent
/// (`tvp_shortcut_default.txt`, TVPaint 12) laid beside the same program's
/// `config.ini`, key by key. Only the commands a preset row names are here
/// (a test holds the two together); another language comes in when a file
/// saved in it does.
@visibleForTesting
const Map<String, String> tvpaintShownNames = {
  'LayerLeft': 'レイヤー: 左に移動',
  'LayerRight': 'レイヤー: 右に移動',
  'PrevInstance': 'レイヤー: エクスポージャー: 前',
  'NextInstance': 'レイヤー: エクスポージャー: 次',
  'LayerUp': 'レイヤー: 上に移動',
  'LayerDown': 'レイヤー: 下に移動',
  'ZoomRotateAdd15': 'ズーム: 回転 +15(反時計回り)',
  'ZoomRotateSub15': 'ズーム: 回転 -15(時計回り)',
  'ZoomIn': 'ズーム: ズームイン',
  'ZoomOut': 'ズーム: ズームアウト',
  'ZoomFlipX': 'ズーム: 水平に反転',
  'ZoomFlipY': 'ズーム: 垂直に反転',
  'ZoomRotateReset': 'ズーム: 回転リセット',
  'ShowPage': 'ズーム: 全ページを表示',
  'ZoomOneOne': 'ズーム: 1-1',
  'LayerTogglePelureMode': 'レイヤー: ライトテーブルモード',
  'PlayPreviewCurrentFrame': 'プレビュー: 現在の画像から再生 / 一時停止',
  'StoryboardDrawingHead': 'プロジェクト: クリップ: 最初の画像へ',
  'LayerFirstImage': 'レイヤー: 始めの画像',
  'Undo': 'アンドゥ: 最後のアクション',
  'MultiRedo': 'アンドゥ: 複数回のやり直し',
  'Cut': 'TVPaint Animation: 選択範囲をカット (アダプティブ)',
  'SelectDel': 'TVPaint Animation: 選択範囲をカット (設定で定義した)',
  'Copy': 'TVPaint Animation: 選択範囲をコピー',
  'Paste': 'TVPaint Animation: ペースト',
  'DeleteImageProject': 'プロジェクト: クリップ: 画像を削除',
  'Clear': 'レイヤー: クリア',
  'SaveImageToClipboard': 'クリップボード: 画像をコピーする',
  'LoadImageFromClipboard': 'クリップボード: 画像を貼り付ける',
  'ShapeApply': '形状: 適用',
  'ShapeAbort': '形状: キャンセル',
  'SelectClear': '形状選択: クリア',
  'NewProject': 'プロジェクト: 新規',
  'LoadProject': 'プロジェクト: 開く',
  'SaveProject': 'プロジェクト: 保存',
  'SaveAsProject': 'プロジェクト: 別名で保存',
  'SaveSequence': '書き出し: シークエンス',
  'OpenSettingsPanel': 'インターフェース: 設定パネルを開く',
  'ConfigureKeyboard': 'インターフェース: キーボード設定',
  'ShapeFreeHandLine': '形状: フリーハンド',
  'ShapeFlood': '形状: ペイント缶',
  'PicColor': '色: 色を拾う',
  'ToolText': 'ツール オプション: 文字',
  'ToggleCutBrush': 'ブラシ: ブラシ切り抜き・カットツール',
  'ShapeRectangle': '形状: 長方形',
  'ShapeRectangleFill': '形状: 塗りつぶし長方形',
  'ShapeLine': '形状: 直線',
  'Position': '形状変形: 変形',
  'Drawing Mode 1': '描画モード: 01 (色)',
  'Drawing Mode 2': '描画モード: 02 (背景)',
  'Drawing Mode 3': '描画モード: 03 (消去)',
  'Drawing Mode 6': '描画モード: 06 (暗くする)',
  'Drawing Mode 7': '描画モード: 07 (明るくする)',
  'UserAppendImageProject': 'プロジェクト: 今のフレームに画像を挿入',
  'ca31b5da-336f-5f4b-9b04-cd9003c43868': 'レイヤープリセット: Anim Layer',
  'DisplayAllLayer': 'レイヤー: 現在のレイヤーを見る / すべて',
};

final Map<String, String> _tvpaintCommandsByShownName = {
  for (final MapEntry(:key, :value) in tvpaintShownNames.entries) value: key,
};

/// [program]'s keymap out of what one of its files binds, in the file's
/// order: each command and the key it is on — null for a key not known
/// here, which is counted ([ProgramKeymap.unread]) rather than dropped. A
/// command is on a key once, however many times the file says so (a tool
/// palette's nodes of one kind each carry their kind's key).
///
/// ONE fold for the three files read: TVPaint's, and CLIP STUDIO PAINT's
/// shortcut set and tool palette.
ProgramKeymap _keymapOf(
  KeymapProgram program,
  Iterable<(String, ProgramChord?)> bound,
) {
  final keys = <String, List<ProgramChord>>{};
  var unread = 0;
  for (final (command, chord) in bound) {
    if (chord == null) {
      unread += 1;
      continue;
    }
    final held = keys.putIfAbsent(command, () => []);
    if (!held.contains(chord)) {
      held.add(chord);
    }
  }
  return ProgramKeymap(program: program, keys: keys, unread: unread);
}

/// Reads TVPaint's keymap out of [text]: the `[keyboard]` section of its
/// `config.ini` or of a keymap `.cfg`, or the text its shortcut window
/// saves. Null for text that is none of them — or a saved text whose
/// command names are none of [tvpaintShownNames], one in another language.
ProgramKeymap? readTvpaintKeymap(String text) {
  final lines = const LineSplitter().convert(text);
  final bound = _keyboardSection(lines) ?? _shownShortcuts(lines);
  if (bound == null) {
    return null;
  }
  return _keymapOf(KeymapProgram.tvpaint, [
    for (final (name, command) in bound) (command, _tvpaintChord(name)),
  ]);
}

/// Each `key=command` under `[keyboard]`, to the next section — the
/// config's lower-case names and a keymap's capitalised ones alike. A key
/// on `none` holds nothing.
List<(String, String)>? _keyboardSection(List<String> lines) {
  final start = lines.indexWhere(
    (line) => line.trim().toLowerCase() == '[keyboard]',
  );
  if (start < 0) {
    return null;
  }
  final bound = <(String, String)>[];
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('[')) {
      break;
    }
    // From the second character: a key named `=` is written `equal`, so
    // the first `=` past the key's first letter is the one before the
    // command. TVPaint's own config.ini ends the section on a blank line,
    // which has no second character.
    final at = line.isEmpty ? -1 : line.indexOf('=', 1);
    final command = at < 0 ? '' : line.substring(at + 1).trim();
    if (command.isNotEmpty && command != 'none') {
      bound.add((line.substring(0, at).trim(), command));
    }
  }
  return bound;
}

/// Each `"key" = none<name>` under `Shortcuts`: the text TVPaint's shortcut
/// window saves, every command by the name it is shown by. Null where none
/// of those names is known here.
List<(String, String)>? _shownShortcuts(List<String> lines) {
  final start = lines.indexWhere((line) => line.trim() == 'Shortcuts');
  if (start < 0) {
    return null;
  }
  final shortcut = RegExp(r'^"(.*)" = none(.*)$');
  final bound = [
    for (final line in lines.skip(start + 1))
      if (shortcut.firstMatch(line.trimRight()) case final match?
          when match[2]!.isNotEmpty)
        (match[1]!, _tvpaintCommandsByShownName[match[2]!] ?? match[2]!),
  ];
  final known = bound.any((pair) => tvpaintShownNames.containsKey(pair.$2));
  return known ? bound : null;
}

/// TVPaint's name of a key as one chord: its modifiers first, a word each
/// (`ctrl shift page up`, `Ctrl Pad 0`). Null for a name that is no key
/// here — a mouse wheel, a character no key types.
ProgramChord? _tvpaintChord(String name) {
  final words = name.toLowerCase().split(' ');
  var at = 0;
  while (at < words.length - 1 && _tvpaintModifiers.contains(words[at])) {
    at += 1;
  }
  final held = words.take(at).toSet();
  final key = _tvpaintKey(words.skip(at).join(' '));
  return key == null
      ? null
      : ProgramChord(
          key,
          control: held.contains('ctrl'),
          shift: held.contains('shift'),
          alt: held.contains('alt'),
        );
}

const Set<String> _tvpaintModifiers = {'ctrl', 'shift', 'alt'};

LogicalKeyboardKey? _tvpaintKey(String name) =>
    _tvpaintNamedKeys[name] ??
    (name.startsWith('pad ') ? _numpadDigit(name.substring(4)) : null) ??
    _functionKey(name) ??
    _typedKey(name);

/// The keys TVPaint names in words. `braquet` and `equal` are its config's
/// names for `[` and `=` — the two characters an INI line cannot start a
/// key with.
const Map<String, LogicalKeyboardKey> _tvpaintNamedKeys = {
  'braquet': LogicalKeyboardKey.bracketLeft,
  'equal': LogicalKeyboardKey.equal,
  'space': LogicalKeyboardKey.space,
  'tab': LogicalKeyboardKey.tab,
  'enter': LogicalKeyboardKey.enter,
  'escape': LogicalKeyboardKey.escape,
  'backspace': LogicalKeyboardKey.backspace,
  'del': LogicalKeyboardKey.delete,
  'insert': LogicalKeyboardKey.insert,
  'home': LogicalKeyboardKey.home,
  'end': LogicalKeyboardKey.end,
  'page up': LogicalKeyboardKey.pageUp,
  'page down': LogicalKeyboardKey.pageDown,
  'up': LogicalKeyboardKey.arrowUp,
  'down': LogicalKeyboardKey.arrowDown,
  'left': LogicalKeyboardKey.arrowLeft,
  'right': LogicalKeyboardKey.arrowRight,
};

/// The command of CLIP STUDIO's tool kind [identifier] — Pen 20, Brush 22.
/// A tool is named by the number the program gives its kind
/// (`NodeDefaultIdentifier`, the same in every language's palette, where
/// its name is not); a menu command by its own name.
String clipStudioTool(int identifier) => 'tool:$identifier';

/// Reads CLIP STUDIO PAINT's keys out of [bytes]: a shortcut set (`.khc` —
/// `shortcutmenu`, its menus' keys) or a tool palette (`.todb` — `Node`, a
/// key per tool). Null for bytes that are neither.
ProgramKeymap? readClipStudioShortcuts(List<int> bytes) {
  try {
    return readSqliteBytes(bytes, (database) {
      final tables = {
        for (final row in database.select(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ))
          row['name'],
      };
      if (tables.contains('shortcutmenu')) {
        return _clipStudioMenus(database);
      }
      return tables.contains('Node') ? _clipStudioTools(database) : null;
    });
  } on SqliteException {
    return null;
  }
}

/// Each of the set's keys, in its order. A command left without one reads
/// `NULL` — written out, not left empty.
ProgramKeymap _clipStudioMenus(Database database) =>
    _keymapOf(KeymapProgram.clipStudio, [
      for (final row in database.select(
        'SELECT menucommand, shortcut, modifier FROM shortcutmenu '
        'ORDER BY _PW_ID',
      ))
        if ((row['menucommand'], row['shortcut'])
            case (final String command, final String name)
            when name != 'NULL')
          (
            command,
            _clipStudioChord(name, switch (row['modifier']) {
              final int bits => bits,
              _ => 0,
            }),
          ),
    ]);

/// The set's modifier bits, read off the program's own keys: Save As is on
/// Shift+Alt+S · Ctrl+Shift+S · Ctrl+Alt+S, which the set writes 3 · 6 · 5,
/// and Fill on Alt+Delete is 1.
const int _clipStudioAlt = 1;
const int _clipStudioShift = 2;
const int _clipStudioControl = 4;

ProgramChord? _clipStudioChord(String name, int modifiers) {
  const known = _clipStudioAlt | _clipStudioShift | _clipStudioControl;
  final key = switch (name) {
    'DELETE' => LogicalKeyboardKey.delete,
    'BACKSPACE' => LogicalKeyboardKey.backspace,
    _ => _functionKey(name.toLowerCase()) ?? _typedKey(name.toLowerCase()),
  };
  return key == null || modifiers & ~known != 0
      ? null
      : ProgramChord(
          key,
          control: modifiers & _clipStudioControl != 0,
          shift: modifiers & _clipStudioShift != 0,
          alt: modifiers & _clipStudioAlt != 0,
        );
}

/// Each kind of tool the palette holds, with the keys of its nodes. A node
/// of no kind of its own (`0`) is no command here.
ProgramKeymap _clipStudioTools(Database database) =>
    _keymapOf(KeymapProgram.clipStudio, [
      for (final row in database.select(
        'SELECT NodeDefaultIdentifier, NodeShortCutKey FROM Node '
        'WHERE NodeDefaultIdentifier > 0 AND NodeShortCutKey > 0 '
        'ORDER BY _PW_ID',
      ))
        (
          clipStudioTool(row['NodeDefaultIdentifier'] as int),
          switch (_clipStudioToolKey(row['NodeShortCutKey'] as int)) {
            final key? => ProgramChord(key),
            null => null,
          },
        ),
    ]);

/// A tool's key as the palette numbers it: A to Z are 1 to 26, read off the
/// program's own palettes (Gradient G is 7, the shipped Pen's P 16); `/`,
/// the Zoom tool's, is 90. Any other number is a key not known here.
LogicalKeyboardKey? _clipStudioToolKey(int code) {
  if (code >= 1 && code <= 26) {
    return _typedKey(String.fromCharCode(0x60 + code));
  }
  return code == 90 ? LogicalKeyboardKey.slash : null;
}

/// `f1` … `f24`.
LogicalKeyboardKey? _functionKey(String name) {
  final number = name.startsWith('f') ? int.tryParse(name.substring(1)) : null;
  return number == null || number < 1 || number > _functionKeys.length
      ? null
      : _functionKeys[number - 1];
}

/// The key that types the one character [name] is — a letter, a digit, a
/// sign. Null for a longer name, or a character no key here types.
LogicalKeyboardKey? _typedKey(String name) => name.runes.length == 1
    ? LogicalKeyboardKey.findKeyByKeyId(name.runes.single)
    : null;

LogicalKeyboardKey? _numpadDigit(String digit) {
  final value = digit.length == 1 ? int.tryParse(digit) : null;
  return value == null ? null : _numpadDigits[value];
}

const List<LogicalKeyboardKey> _numpadDigits = [
  LogicalKeyboardKey.numpad0,
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];

const List<LogicalKeyboardKey> _functionKeys = [
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
  LogicalKeyboardKey.f13,
  LogicalKeyboardKey.f14,
  LogicalKeyboardKey.f15,
  LogicalKeyboardKey.f16,
  LogicalKeyboardKey.f17,
  LogicalKeyboardKey.f18,
  LogicalKeyboardKey.f19,
  LogicalKeyboardKey.f20,
  LogicalKeyboardKey.f21,
  LogicalKeyboardKey.f22,
  LogicalKeyboardKey.f23,
  LogicalKeyboardKey.f24,
];
