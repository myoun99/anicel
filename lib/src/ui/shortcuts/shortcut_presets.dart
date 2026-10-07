import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../models/brush_blend_mode.dart';
import 'editor_action_registry.dart';
import 'shortcut_activator_codec.dart';

/// A keyboard layout the shortcut window starts from.
///
/// 🗣️I-63 (유저 2026-10-03): 「단축키 프리셋 기능 추가 … 지금까지 내가
/// 만든것들은 anicel으로서 등록」, and which presets there are (10-07,
/// I-63-Q1): 「tvp기반,클튜기반,anicel 이렇게 세개 두고싶음」. ↩️The first
/// words named a 「일반」 preset (「범용적으로 쓰기 쉬운 일반적인 프리셋」);
/// the two programs' layouts are what it became.
/// ⚠️The TVPaint one is not here yet: that program publishes no default key
/// table, and whose keys to copy is asked on the board (I-63-Q2).
///
/// ★A PRESET HOLDS ONLY THE KEYS ITS PROGRAM NAMES ([_programKeys]). Every
/// other action keeps the registry's key, so a default that moves in the
/// registry moves in every preset that did not name it — and the rule for a
/// key two actions would share is said once ([presetActivators]), not listed
/// per loser.
enum ShortcutPreset {
  /// The registry's own keys.
  anicel('Anicel'),

  /// CLIP STUDIO PAINT's default keys.
  clipStudio('Clip Studio based');

  const ShortcutPreset(this.label);

  /// Its English name — the English row, as an action's label is
  /// (`AppStrings.shortcutPresetName` holds the other languages).
  final String label;

  /// The preset a settings file names, or null for a name no build knows.
  static ShortcutPreset? named(Object? name) =>
      values.where((preset) => preset.name == name).firstOrNull;
}

/// The keys [definition] ships with under [preset], written as the registry
/// writes its own (`control` is the platform's command key).
///
/// 🗣️I-63-Q3 (유저 2026-10-07), the answer picked for the mapping table:
/// 「초안대로 — 그 프로그램을 최대한 닮게」 = 「공식 키가 있는 줄은 그
/// 프로그램의 키로(「비슷한 명령」 줄 포함), 없는 줄은 anicel 의 키 그대로.
/// 키가 부딪히면 그 프로그램의 뜻을 따른다」. So an action the program names
/// takes the program's keys AND NO OTHER, and an action it does not name
/// keeps the registry's — less any key the program gave to something else.
List<SingleActivator> presetActivators(
  ShortcutPreset preset,
  EditorActionDefinition definition,
) {
  final named = _programKeys[preset]![definition.id];
  if (named != null) {
    return named;
  }
  final taken = _takenKeys[preset]!;
  return [
    for (final activator in definition.defaultActivators)
      if (!taken.contains(activatorKey(activator))) activator,
  ];
}

/// Every action id [preset] names a key for — what a test holds against the
/// registry, so an action renamed there cannot fall out of a preset unseen.
Iterable<String> presetNamedActionIds(ShortcutPreset preset) =>
    _programKeys[preset]!.keys;

final Map<ShortcutPreset, Map<String, List<SingleActivator>>> _programKeys = {
  ShortcutPreset.anicel: const {},
  ShortcutPreset.clipStudio: _clipStudioKeys,
};

/// The keys each preset's program holds, as [activatorKey] spells them.
final Map<ShortcutPreset, Set<String>> _takenKeys = {
  for (final MapEntry(key: preset, value: keys) in _programKeys.entries)
    preset: {
      for (final activators in keys.values)
        for (final activator in activators) activatorKey(activator),
    },
};

/// CLIP STUDIO PAINT's default key for each action it has one for — the
/// 클립 스튜디오 column of the table the user answered (I-63-Q3), row for
/// row. Source: the Celsys User Guide's 「Shortcut list」 chapter, Ver. 5.0
/// (Tool · Menu · Optional pages); nothing here is from a third-party list.
///
/// ⚠️Its ANIMATION commands have no default key at all — the official list
/// has no animation section — so the moves along the film, the playback and
/// the timeline's verbs are not named here and keep the registry's.
///
/// ⚠️`-` · `^` · `;` are where a JAPANESE keyboard has them; the program
/// prints the same three in every language's edition. Another layout reaches
/// `^` as the character it types (`pressableForms`).
///
/// 🚨WHERE ONE PROGRAM KEY STOOD ON SEVERAL ROWS OF THE TABLE it is on ONE
/// here — a preset ships with no two actions on a key:
/// · `M` · `G` · `U` — 「한 키로 여러 도구를 도는 `M` · `U` · `G` 를 도구 버튼
///   하나에만 준다」 (the answer's own words): the rail tool, never its
///   tiles. For `U` that is the guide tool — ⚠️MY READING, not said: the
///   three rows it stood on were two fill tiles (the program's Figure) and
///   the guide tool (its Ruler), and the guide is the only rail tool of them.
/// · `Ctrl+T` — the program's command is Scale/Rotate, which is the normal
///   transform; the transform tool's own row keeps no key, as in the
///   registry.
/// · `Delete` — the program's 「Erase」 is 픽셀 비우기 outright (the same
///   command) and only resembles the pill's 삭제, so the first has it and the
///   second is left without a key (⚠️my reading of 「그 프로그램의 뜻을
///   따른다」: the same command before a similar one).
final Map<String, List<SingleActivator>> _clipStudioKeys = {
  // Change Selected Layer > Layer Above / Layer Below.
  EditorActionIds.layerUp: const [
    SingleActivator(LogicalKeyboardKey.bracketRight, alt: true),
  ],
  EditorActionIds.layerDown: const [
    SingleActivator(LogicalKeyboardKey.bracketLeft, alt: true),
  ],
  // The hand, held on Space.
  EditorActionIds.canvasPanHold: const [
    SingleActivator(LogicalKeyboardKey.space),
  ],
  // Rotate/Invert > Rotate Left / Rotate right.
  EditorActionIds.canvasRotateCcw: const [
    SingleActivator(LogicalKeyboardKey.minus),
  ],
  EditorActionIds.canvasRotateCw: const [
    SingleActivator(LogicalKeyboardKey.caret),
  ],
  EditorActionIds.canvasZoomIn: const [
    SingleActivator(LogicalKeyboardKey.numpadAdd, control: true),
    SingleActivator(LogicalKeyboardKey.semicolon, control: true),
  ],
  EditorActionIds.canvasZoomOut: const [
    SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true),
    SingleActivator(LogicalKeyboardKey.minus, control: true),
  ],
  EditorActionIds.undo: const [
    SingleActivator(LogicalKeyboardKey.keyZ, control: true),
  ],
  EditorActionIds.redo: const [
    SingleActivator(LogicalKeyboardKey.keyY, control: true),
    SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true),
  ],
  EditorActionIds.editCut: const [
    SingleActivator(LogicalKeyboardKey.keyX, control: true),
    SingleActivator(LogicalKeyboardKey.f2),
  ],
  EditorActionIds.editCopy: const [
    SingleActivator(LogicalKeyboardKey.keyC, control: true),
    SingleActivator(LogicalKeyboardKey.f3),
  ],
  // The program's one Paste — a similar command: it is the paste an ordinary
  // program's Ctrl+V does, which is the independent one here (F-156).
  EditorActionIds.editPasteIndependent: const [
    SingleActivator(LogicalKeyboardKey.keyV, control: true),
    SingleActivator(LogicalKeyboardKey.f4),
  ],
  // Erase.
  EditorActionIds.editClearPixels: const [
    SingleActivator(LogicalKeyboardKey.delete),
    SingleActivator(LogicalKeyboardKey.backspace),
  ],
  EditorActionIds.selectionDeselect: const [
    SingleActivator(LogicalKeyboardKey.keyD, control: true),
  ],
  EditorActionIds.fileSave: const [
    SingleActivator(LogicalKeyboardKey.keyS, control: true),
  ],
  EditorActionIds.fileSaveAs: const [
    SingleActivator(LogicalKeyboardKey.keyS, shift: true, alt: true),
    SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true),
    SingleActivator(LogicalKeyboardKey.keyS, control: true, alt: true),
  ],
  // Brush · Pen.
  EditorActionIds.toolBrush: const [
    SingleActivator(LogicalKeyboardKey.keyB),
    SingleActivator(LogicalKeyboardKey.keyP),
  ],
  EditorActionIds.toolEraser: const [SingleActivator(LogicalKeyboardKey.keyE)],
  EditorActionIds.toolEyedropper: const [
    SingleActivator(LogicalKeyboardKey.keyI),
  ],
  EditorActionIds.toolFill: const [SingleActivator(LogicalKeyboardKey.keyG)],
  EditorActionIds.toolText: const [SingleActivator(LogicalKeyboardKey.keyT)],
  // Ruler — a similar command.
  EditorActionIds.toolGuide: const [SingleActivator(LogicalKeyboardKey.keyU)],
  EditorActionIds.toolSelect: const [SingleActivator(LogicalKeyboardKey.keyM)],
  // Transform > Scale/Rotate, and > Free Transform.
  EditorActionIds.toolTransformNormal: const [
    SingleActivator(LogicalKeyboardKey.keyT, control: true),
  ],
  EditorActionIds.toolTransformFree: const [
    SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true),
  ],
  // 「Switch drawing color and transparent color」 — a similar command:
  // drawing in the transparent colour is what the erase blend does.
  blendModeActionId(BrushBlendMode.erase): const [
    SingleActivator(LogicalKeyboardKey.keyC),
  ],
};
