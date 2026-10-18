import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../models/brush_blend_mode.dart';
import '../../models/canvas_shape_kind.dart';
import '../../models/layer_kind.dart';
import '../../services/shortcuts/program_keymap.dart';
import '../brush/brush_tool_state.dart' show CanvasTool;
import 'editor_action_registry.dart';
import 'shortcut_activator_codec.dart';

/// A keyboard layout the shortcut window starts from.
///
/// 🗣️I-63 (유저 2026-10-03): 「단축키 프리셋 기능 추가 … 지금까지 내가
/// 만든것들은 anicel으로서 등록」, and which presets there are (10-07,
/// I-63-Q1): 「tvp기반,클튜기반,anicel 이렇게 세개 두고싶음」. ↩️The first
/// words named a 「일반」 preset (「범용적으로 쓰기 쉬운 일반적인 프리셋」);
/// the two programs' layouts are what it became.
///
/// ★A PRESET HOLDS ONLY THE KEYS ITS PROGRAMS NAME ([presetRows]); an
/// action none of them names has no key under it (F-417-Q1), and only
/// [ShortcutPreset.anicel], which has no program, ships the registry's.
/// The rule for a key two actions would share is said once ([ProgramKeys]),
/// not listed per loser.
///
/// 🗣️I-88 (유저 2026-10-09): 「이런 키는 물론 클튜나 tvp 알아서 그거에맞춰서
/// 기록. 앞으로 단축키 관련은 그게 기본임. 내가 제안하는건 다 anicel용」 — a
/// key the user proposes is the registry's, anicel's; each program's table
/// takes that program's own key for the same command, from the program's
/// own references, or names none for it.
enum ShortcutPreset implements ShortcutLayout {
  /// The registry's own keys.
  anicel('Anicel'),

  /// CLIP STUDIO PAINT's default keys, then TVPaint's.
  clipStudio('Clip Studio based'),

  /// TVPaint Animation's default keys, then CLIP STUDIO PAINT's.
  tvpaint('TVPaint based');

  const ShortcutPreset(this.label);

  /// Its English name — the English row, as an action's label is
  /// (`AppStrings.shortcutPresetName` holds the other languages).
  final String label;

  @override
  String get id => name;

  @override
  ShortcutPreset get base => this;

  /// None: it is [base].
  @override
  Map<String, List<SingleActivator>> get ownKeys => const {};

  /// The preset a settings file names, or null for a name no build knows.
  static ShortcutPreset? named(Object? name) =>
      values.where((preset) => preset.name == name).firstOrNull;
}

/// A layout the keys can be put in: one of the presets the app ships, or
/// one of the user's own.
sealed class ShortcutLayout {
  /// What the settings file names it by.
  String get id;

  /// The preset the app ships that it stands on: what it holds for an
  /// action it has no keys of its own for.
  ShortcutPreset get base;

  /// The keys it holds of its own where they are not [base]'s, as this
  /// platform presses them.
  Map<String, List<SingleActivator>> get ownKeys;
}

/// A preset the user made (I-107): a name, and the keys it was made with
/// over the preset the app ships that it stands on.
///
/// 🗣️I-107-Q1 (유저 2026-10-18, 「기타」): 「프리셋 리스트 추가/삭제
/// 가능하게해서 사용자 입맛대로 추가해서 설정가능하고, 가져올땐 새
/// 프리셋으로서 등록」 — made from the list's ＋, out of the layout in use,
/// or out of a program's shortcut file.
/// ⚠️Not said by the user — asked on the board (I-107-Q3) and built as its
/// recommendation (a) while it waits: the three the app ships cannot be
/// deleted, a new one is the layout in use copied, and its name is given
/// once, when it is made.
///
/// ⚠️MY READING: what the user records while it is in use is a change to it
/// ([recorded]), as under a preset the app ships — so the window's reset
/// takes it back to the keys it was made with, not to its [base]'s.
final class UserShortcutPreset implements ShortcutLayout {
  UserShortcutPreset({
    required this.id,
    required this.name,
    required this.base,
    required Map<String, List<SingleActivator>> keys,
    Map<String, List<SingleActivator>>? recorded,
  }) : ownKeys = Map.unmodifiable(keys),
       recorded = recorded ?? {};

  @override
  final String id;

  final String name;

  @override
  final ShortcutPreset base;

  @override
  final Map<String, List<SingleActivator>> ownKeys;

  /// What the user recorded while it was in use, kept with it — so it goes
  /// when it does.
  final Map<String, List<SingleActivator>> recorded;
}

/// The preset the app ships that a program's shortcut file stands on: that
/// program's own. 🗣️I-107-Q1 (유저 2026-10-18): 「가져올땐 새 프리셋으로서
/// 등록」 — the file's keys make a preset of the user's over it. ↩️They were
/// put on the program's preset itself until that answer (추천 a, built while
/// the question waited).
ShortcutPreset presetOf(KeymapProgram program) => switch (program) {
  KeymapProgram.tvpaint => ShortcutPreset.tvpaint,
  KeymapProgram.clipStudio => ShortcutPreset.clipStudio,
};

/// A row of a program's table: the program's commands an action is — the
/// same command, or the nearest one — and the keys the program ships them
/// with. A row with no keys names none: it is there for a shortcut file
/// that gives its commands some (I-107).
final class ProgramRow {
  const ProgramRow(this.commands, this.keys);

  /// As the program's own files name them (`ProgramKeymap.keys`).
  final List<String> commands;
  final List<SingleActivator> keys;
}

/// What each action holds under a program that puts [named] on actions.
///
/// ★THE ONE LAW OF A PROGRAM'S KEYS. 🗣️I-63-Q3 (유저 2026-10-07), the answer
/// picked for the mapping table: 「초안대로 — 그 프로그램을 최대한 닮게」 =
/// 「공식 키가 있는 줄은 그 프로그램의 키로(「비슷한 명령」 줄 포함), 없는
/// 줄은 anicel 의 키 그대로. 키가 부딪히면 그 프로그램의 뜻을 따른다」. So an
/// action the program names takes the program's keys AND NO OTHER, and an
/// action it does not name keeps what it would hold without the program —
/// less any key the program gave to something else.
/// A preset asks it with its own program's keys over the OTHER program's
/// ([presetActivators], F-417); a program's shortcut file with the file's
/// keys over what each action holds (I-107,
/// `EditorShortcutBindings.importShortcutFiles`).
final class ProgramKeys {
  ProgramKeys(this.named)
    : _taken = {
        for (final keys in named.values)
          for (final key in keys) activatorKey(key),
      };

  /// Each action the program names, with its keys.
  final Map<String, List<SingleActivator>> named;

  /// The keys [named] holds, as [activatorKey] spells them.
  final Set<String> _taken;

  /// What [actionId], whose own keys are [own], holds under the program.
  List<SingleActivator> of(String actionId, Iterable<SingleActivator> own) =>
      named[actionId] ??
      [
        for (final key in own)
          if (!_taken.contains(activatorKey(key))) key,
      ];
}

/// The keys [definition] ships with under [preset], written as the registry
/// writes its own (`control` is the platform's command key).
///
/// ↩️🗣️F-417 (유저 2026-10-20) turned the rows the program does not name:
/// 「A나 D로 플립하는건 내가 생각한 anicel기반임. 그러니 클튜기반에서
/// 그런식으로 클튜에서 확인안된것들은 tvp기반, tvp에서 확인안된건
/// 클튜기반으로 우선 그렇게 지정. anicel은 내가 혼자 쓰려고 생각한거라
/// 범용적이지 않기때문」. Such a row takes the OTHER program's keys, as that
/// program names them — they are what it holds without its own program.
///
/// 🗣️F-417-Q1 (유저 2026-10-21 「키 없이 둔다」): a row NEITHER program
/// names has no key — the registry's are anicel's own, not a general
/// layout. ↩️It kept the registry's (the old answer's tail) until then:
/// voice recording, the lasso tools, the blend F keys and the timesheet's
/// comma keys among the twenty rows that had one.
/// 🗣️F-417-Q2 (same day, 「키 없이 둔다」): a key the preset's own program
/// took leaves the other program's row with nothing in its place.
/// ↩️A row so emptied went on to anicel's keys until then (my reading):
/// under Clip Studio, whose hand holds Space, TVPaint's play had anicel's
/// Shift+X; it has no key now, nor do the new frame (I, the eyedropper's)
/// and the Color blend (F2, Cut's).
/// 🪦With nothing to fall to past the other program, the rows went from a
/// list of programs read in turn, each less the keys of those before, to
/// the two a preset is: a third program would only ever be read past the
/// second, and no preset has one.
List<SingleActivator> presetActivators(
  ShortcutPreset preset,
  EditorActionDefinition definition,
) {
  final programs = _programsOf[preset];
  if (programs == null) {
    return definition.defaultActivators;
  }
  return programs.own.of(
    definition.id,
    programs.other.named[definition.id] ?? const [],
  );
}

/// [preset]'s table, row by row — what a test holds against the registry,
/// so an action renamed there cannot fall out of a preset unseen, and
/// against what the program's files are read with.
Map<String, ProgramRow> presetRows(ShortcutPreset preset) => switch (preset) {
  ShortcutPreset.anicel => const {},
  ShortcutPreset.clipStudio => _clipStudioRows,
  ShortcutPreset.tvpaint => _tvpaintRows,
};

/// The program each preset is, and the one it takes the rows its own does
/// not name from (F-417); none for [ShortcutPreset.anicel], the registry.
final Map<ShortcutPreset, ({ProgramKeys own, ProgramKeys other})?>
_programsOf = {
  ShortcutPreset.anicel: null,
  ShortcutPreset.clipStudio: (own: _clipStudioShipped, other: _tvpaintShipped),
  ShortcutPreset.tvpaint: (own: _tvpaintShipped, other: _clipStudioShipped),
};

final ProgramKeys _clipStudioShipped = _shippedOf(_clipStudioRows);
final ProgramKeys _tvpaintShipped = _shippedOf(_tvpaintRows);

/// The keys a program ships its rows with: a row with none names none.
ProgramKeys _shippedOf(Map<String, ProgramRow> rows) => ProgramKeys({
  for (final MapEntry(key: actionId, value: row) in rows.entries)
    if (row.keys.isNotEmpty) actionId: row.keys,
});

/// The keys [files] give each action of their program's table: every key on
/// the row's commands, once, in the files' order and then the row's — and
/// an action whose commands they give none is not here.
Map<String, List<SingleActivator>> fileKeysOf(Iterable<ProgramKeymap> files) {
  final chordsByAction = <String, Set<ProgramChord>>{};
  for (final file in files) {
    for (final MapEntry(key: actionId, value: row)
        in presetRows(presetOf(file.program)).entries) {
      chordsByAction.putIfAbsent(actionId, () => {}).addAll([
        for (final command in row.commands) ...?file.keys[command],
      ]);
    }
  }
  return {
    for (final MapEntry(key: actionId, value: chords)
        in chordsByAction.entries)
      if (chords.isNotEmpty)
        actionId: [
          for (final chord in chords)
            SingleActivator(
              chord.key,
              control: chord.control,
              shift: chord.shift,
              alt: chord.alt,
            ),
        ],
  };
}

/// How many of [files]' keys an action takes, and how many none does: a key
/// on a command the app has no action for, or one that is no key here.
({int taken, int skipped}) countFileKeys(Iterable<ProgramKeymap> files) {
  var taken = 0;
  var skipped = 0;
  for (final file in files) {
    final rows = presetRows(presetOf(file.program)).values;
    final commands = {for (final row in rows) ...row.commands};
    skipped += file.unread;
    for (final MapEntry(key: command, value: chords) in file.keys.entries) {
      if (commands.contains(command)) {
        taken += chords.length;
      } else {
        skipped += chords.length;
      }
    }
  }
  return (taken: taken, skipped: skipped);
}

/// CLIP STUDIO PAINT's default key for each action it has one for — the
/// 클립 스튜디오 column of the table the user answered (I-63-Q3), row for
/// row. Source: the Celsys User Guide's 「Shortcut list」 chapter, Ver. 5.0
/// (Tool · Menu · Optional pages); nothing here is from a third-party list.
/// Each row names its commands as the program's own files do (I-107): a
/// menu's by the name its shortcut set (`.khc`) writes, a tool's by its
/// kind's number in the tool palette ([clipStudioTool]).
///
/// ⚠️Its ANIMATION commands have no default key at all — the official list
/// has no animation section — so the moves along the film, the playback and
/// the timeline's verbs are not named here: they take TVPaint's (F-417).
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
///
/// ➕Read against the same pages again on 2026-10-10 (유저 10-09: 「클튜
/// 단축키 제대로 한거 맞는지? … 다시한번 확인하고싶음」): every row below
/// matched, and what the first pass left out is in — Erase's two Ctrl keys,
/// and the rows for actions the app has gained since: New · Open ·
/// Preferences · Shortcut Settings · Fit to Screen (the same commands), and
/// 100% · Reset display · New Raster Layer · Create folder (similar ones).
///
/// ➕The rows with no key (I-107, 2026-10-18) are commands the program
/// ships without one, for a shortcut file that gives them some — the
/// animation's among them. ⚠️MY READINGS, each the same command or the
/// nearest, not the user's: the table they answered held only keys.
final Map<String, ProgramRow> _clipStudioRows = {
  // Change Selected Layer > Layer Above / Layer Below.
  EditorActionIds.layerUp: const ProgramRow(
    ['layerselectupperlayer'],
    [SingleActivator(LogicalKeyboardKey.bracketRight, alt: true)],
  ),
  EditorActionIds.layerDown: const ProgramRow(
    ['layerselectlowerlayer'],
    [SingleActivator(LogicalKeyboardKey.bracketLeft, alt: true)],
  ),
  // The hand, held on Space — and the view's turn on Shift+Space (I-88:
  // 「Shortcuts usable during operation」, Rotate = Shift + Space + drag).
  // No shortcut file holds these: the program keeps them in its modifier
  // key settings, which nothing reads.
  EditorActionIds.canvasPanHold: const ProgramRow(
    [],
    [SingleActivator(LogicalKeyboardKey.space)],
  ),
  EditorActionIds.canvasRotateHold: const ProgramRow(
    [],
    [SingleActivator(LogicalKeyboardKey.space, shift: true)],
  ),
  // Rotate/Invert > Rotate Left / Rotate right.
  EditorActionIds.canvasRotateCcw: const ProgramRow(
    ['viewrotateleft'],
    [SingleActivator(LogicalKeyboardKey.minus)],
  ),
  EditorActionIds.canvasRotateCw: const ProgramRow(
    ['viewrotateright'],
    [SingleActivator(LogicalKeyboardKey.caret)],
  ),
  EditorActionIds.canvasZoomIn: const ProgramRow(
    ['viewzoomin'],
    [
      SingleActivator(LogicalKeyboardKey.numpadAdd, control: true),
      SingleActivator(LogicalKeyboardKey.semicolon, control: true),
    ],
  ),
  EditorActionIds.canvasZoomOut: const ProgramRow(
    ['viewzoomout'],
    [
      SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true),
      SingleActivator(LogicalKeyboardKey.minus, control: true),
    ],
  ),
  EditorActionIds.undo: const ProgramRow(
    ['undo'],
    [SingleActivator(LogicalKeyboardKey.keyZ, control: true)],
  ),
  EditorActionIds.redo: const ProgramRow(
    ['redo'],
    [
      SingleActivator(LogicalKeyboardKey.keyY, control: true),
      SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true),
    ],
  ),
  EditorActionIds.editCut: const ProgramRow(
    ['cut'],
    [
      SingleActivator(LogicalKeyboardKey.keyX, control: true),
      SingleActivator(LogicalKeyboardKey.f2),
    ],
  ),
  EditorActionIds.editCopy: const ProgramRow(
    ['copy'],
    [
      SingleActivator(LogicalKeyboardKey.keyC, control: true),
      SingleActivator(LogicalKeyboardKey.f3),
    ],
  ),
  // The program's one Paste — a similar command: it is the paste an ordinary
  // program's Ctrl+V does, which is the independent one here (F-156).
  EditorActionIds.editPasteIndependent: const ProgramRow(
    ['paste'],
    [
      SingleActivator(LogicalKeyboardKey.keyV, control: true),
      SingleActivator(LogicalKeyboardKey.f4),
    ],
  ),
  // Erase.
  EditorActionIds.editClearPixels: const ProgramRow(
    ['clear'],
    [
      SingleActivator(LogicalKeyboardKey.delete),
      SingleActivator(LogicalKeyboardKey.backspace),
      SingleActivator(LogicalKeyboardKey.delete, control: true),
      SingleActivator(LogicalKeyboardKey.backspace, control: true),
    ],
  ),
  EditorActionIds.selectionDeselect: const ProgramRow(
    ['selectdeselect'],
    [SingleActivator(LogicalKeyboardKey.keyD, control: true)],
  ),
  // Invert selected area — the Select tool's 선택 반전, an action since
  // I-40's tool settings round (2026-10-11).
  EditorActionIds.selectionInvert: const ProgramRow(
    ['selectinvert'],
    [
      SingleActivator(LogicalKeyboardKey.keyI, control: true, shift: true),
      SingleActivator(LogicalKeyboardKey.f7, shift: true),
    ],
  ),
  EditorActionIds.fileNew: const ProgramRow(
    ['filenew'],
    [SingleActivator(LogicalKeyboardKey.keyN, control: true)],
  ),
  EditorActionIds.fileOpen: const ProgramRow(
    ['fileopen'],
    [SingleActivator(LogicalKeyboardKey.keyO, control: true)],
  ),
  EditorActionIds.fileSave: const ProgramRow(
    ['filesave'],
    [SingleActivator(LogicalKeyboardKey.keyS, control: true)],
  ),
  EditorActionIds.fileSaveAs: const ProgramRow(
    ['filesaveas'],
    [
      SingleActivator(LogicalKeyboardKey.keyS, shift: true, alt: true),
      SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true),
      SingleActivator(LogicalKeyboardKey.keyS, control: true, alt: true),
    ],
  ),
  EditorActionIds.preferences: const ProgramRow(
    ['applicationpreference'],
    [SingleActivator(LogicalKeyboardKey.keyK, control: true)],
  ),
  EditorActionIds.keyboardShortcuts: const ProgramRow(
    ['applicationshortcutsetting'],
    [
      SingleActivator(
        LogicalKeyboardKey.keyK,
        control: true,
        shift: true,
        alt: true,
      ),
    ],
  ),
  // View > Fit to Screen; > 100% and > Reset display — similar commands:
  // the view at 100%, and the view's turn put back (as is Rotate/Invert >
  // Reset rotation/inversion, which ships with no key).
  EditorActionIds.canvasFit: const ProgramRow(
    ['viewwholesize'],
    [SingleActivator(LogicalKeyboardKey.digit0, control: true)],
  ),
  EditorActionIds.canvasResetView: const ProgramRow(
    ['viewpixelsize'],
    [SingleActivator(LogicalKeyboardKey.digit0, control: true, alt: true)],
  ),
  EditorActionIds.canvasStraighten: const ProgramRow(
    ['viewreset', 'viewangleandreversereset'],
    [SingleActivator(LogicalKeyboardKey.at, control: true)],
  ),
  // Layer > New Raster Layer, and > Create folder and insert layer — similar
  // commands: the layer pill's ＋, and a folder row (as are New Layer >
  // Raster Layer and > Folder, which ship with no key).
  EditorActionIds.layerAdd: const ProgramRow(
    ['layernew', 'layerrasternew'],
    [SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true)],
  ),
  addLayerKindActionId(LayerKind.folder): const ProgramRow(
    ['layerfoldernewandinsert', 'layerfoldernew'],
    [SingleActivator(LogicalKeyboardKey.keyG, control: true)],
  ),
  // Brush · Pen — and the Pencil and the Airbrush, which share their keys.
  EditorActionIds.toolBrush: ProgramRow(
    [
      clipStudioTool(22),
      clipStudioTool(20),
      clipStudioTool(21),
      clipStudioTool(23),
    ],
    const [
      SingleActivator(LogicalKeyboardKey.keyB),
      SingleActivator(LogicalKeyboardKey.keyP),
    ],
  ),
  EditorActionIds.toolEraser: ProgramRow(
    [clipStudioTool(25)],
    const [SingleActivator(LogicalKeyboardKey.keyE)],
  ),
  EditorActionIds.toolEyedropper: ProgramRow(
    [clipStudioTool(16)],
    const [SingleActivator(LogicalKeyboardKey.keyI)],
  ),
  // Fill.
  EditorActionIds.toolFill: ProgramRow(
    [clipStudioTool(30)],
    const [SingleActivator(LogicalKeyboardKey.keyG)],
  ),
  EditorActionIds.toolText: ProgramRow(
    [clipStudioTool(35)],
    const [SingleActivator(LogicalKeyboardKey.keyT)],
  ),
  // Figure. ↩️U stood on the guide tool until the shape tool came (I-69,
  // 2026-10-07) — Ruler, a similar command, which shares the key in the
  // program; the same command comes before a similar one, so the guide
  // tool has no key of this table's now.
  EditorActionIds.toolShape: ProgramRow(
    [clipStudioTool(32)],
    const [SingleActivator(LogicalKeyboardKey.keyU)],
  ),
  // Selection area.
  EditorActionIds.toolSelect: ProgramRow(
    [clipStudioTool(14)],
    const [SingleActivator(LogicalKeyboardKey.keyM)],
  ),
  // Transform > Scale/Rotate, and > Free Transform.
  EditorActionIds.toolTransformNormal: const ProgramRow(
    ['transformstretch'],
    [SingleActivator(LogicalKeyboardKey.keyT, control: true)],
  ),
  EditorActionIds.toolTransformFree: const ProgramRow(
    ['transformfree'],
    [SingleActivator(LogicalKeyboardKey.keyT, control: true, shift: true)],
  ),
  // 「Switch drawing color and transparent color」 — a similar command:
  // drawing in the transparent colour is what the erase blend does.
  blendModeActionId(BrushBlendMode.erase): const ProgramRow(
    ['applicationchangecolortransparent'],
    [SingleActivator(LogicalKeyboardKey.keyC)],
  ),
  // View > Rotate/Invert > Flip horizontal / Flip vertical.
  EditorActionIds.canvasFlipHorizontal: const ProgramRow(
    ['viewreversehorz'],
    [],
  ),
  EditorActionIds.canvasFlipVertical: const ProgramRow(
    ['viewreversevert'],
    [],
  ),
  // Animation > Playback: Play/Stop, Loop playback; Move to first frame ·
  // previous frame · next frame; Select previous cel / next cel — similar
  // commands, the drawing before and after.
  EditorActionIds.playbackToggle: const ProgramRow(['animationplaystop'], []),
  EditorActionIds.playbackLoopToggle: const ProgramRow(
    ['animationplaytypeloop'],
    [],
  ),
  EditorActionIds.playbackToStart: const ProgramRow(
    ['animationmovetostartframe'],
    [],
  ),
  EditorActionIds.framePrevious: const ProgramRow(
    ['animationmovetopreviousframe'],
    [],
  ),
  EditorActionIds.frameNext: const ProgramRow(
    ['animationmovetonextframe'],
    [],
  ),
  EditorActionIds.drawingPrevious: const ProgramRow(
    ['animationselectpreviousanimationcel'],
    [],
  ),
  EditorActionIds.drawingNext: const ProgramRow(
    ['animationselectnextanimationcel'],
    [],
  ),
  // Enable onion skin; New animation cel — a similar command: a drawing
  // at the current frame; New animation folder — a similar one: an
  // animation layer; New cut.
  EditorActionIds.onionSkinToggle: const ProgramRow(
    ['animationenableonionskin'],
    [],
  ),
  EditorActionIds.frameNewDrawing: const ProgramRow(['animationcelnew'], []),
  addLayerKindActionId(LayerKind.animation): const ProgramRow(
    ['animationnewanimationfolder'],
    [],
  ),
  EditorActionIds.cutNew: const ProgramRow(['animationnewcut'], []),
  // Layer > Duplicate layer · Rasterize.
  EditorActionIds.layerDuplicate: const ProgramRow(['layercopy'], []),
  EditorActionIds.layerRasterize: const ProgramRow(['layerrasterize'], []),
  // Transform > Mesh transformation · Flip horizontal · Flip vertical ·
  // Confirm transformation — the confirm here — · Cancel transformation.
  EditorActionIds.toolTransformMesh: const ProgramRow(['transformmesh'], []),
  EditorActionIds.transformFlipHorizontal: const ProgramRow(
    ['transformreversehorz'],
    [],
  ),
  EditorActionIds.transformFlipVertical: const ProgramRow(
    ['transformreversevert'],
    [],
  ),
  EditorActionIds.confirm: const ProgramRow(['transformfix'], []),
  EditorActionIds.selectionTransformCancel: const ProgramRow(
    ['transformcancel'],
    [],
  ),
  // Edit > Change canvas size — a similar command: the cut's. File >
  // Export animation > Image sequence · Movie, and File > Import > Image ·
  // Movie · Audio — similar ones: the export, and the media pool's import.
  EditorActionIds.cutCanvasSize: const ProgramRow(
    ['pagechangecanvassize'],
    [],
  ),
  EditorActionIds.fileExport: const ProgramRow(
    ['exportimageseries', 'exportmovie'],
    [],
  ),
  EditorActionIds.mediaPoolImport: const ProgramRow(
    ['fileimportimage', 'animationimportmovie', 'fileimportaudio'],
    [],
  ),
  EditorActionIds.about: const ProgramRow(['applicationabout'], []),
};

/// TVPaint Animation's default key for each action it has one for.
/// 🗣️I-63-Q2 (유저 2026-10-09): 「쓰시는 TVPaint 의 단축키를 보내 주신다 —
/// 그대로 옮긴다」 — sent as TVPaint 12's own default keymap file
/// (`tvp_shortcut_default.txt`, its Japanese interface), whose command names
/// are quoted beside each row. The rule is the table's (I-63-Q3, 「그
/// 프로그램을 최대한 닮게」): the same command, or the nearest one. Each row
/// names its commands by the ids the program's keymaps write (I-107 —
/// `config.ini`'s `[keyboard]`), laid beside those names key by key.
///
/// ⚠️Where the program's key names a command the app has no action for —
/// `A` shakes the view, `G` `H` `V` `J` `K` are selection modes, `1`…`9`
/// scroll the view, `+` `-` size the brush — the action that held the key
/// here keeps it: only a key the program gives to one of OUR actions leaves
/// another ([ProgramKeys]).
/// ⚠️`Space` plays (「再生 / 一時停止」), so the pan held on it has no key
/// under this preset. The program pans on Alt and turns the view on
/// Ctrl+Alt, each held while dragging (its 「Rotate, pan, zoom」 page) — a
/// modifier alone, which no key binding can hold — so the turn takes
/// CLIP STUDIO PAINT's Shift+Space here (F-417), anicel's too (I-88).
/// ⚠️MY READINGS, each the nearest command, not one the user named: `Del`
/// is the program's second Cut (「選択範囲をカット (設定で定義した)」, the
/// timeline's, as Ctrl+X is), so it cuts here rather than clearing pixels;
/// `F` is the bucket itself, so the bucket's tile takes it and the fill
/// button keeps no key; `B` (the CutBrush) is the cut tool AND its stamp
/// here, and the rail tool takes it (the rule `M` · `U` · `G` follow in the
/// CLIP STUDIO table).
final Map<String, ProgramRow> _tvpaintRows = {
  // レイヤー: 左に移動 / 右に移動.
  EditorActionIds.framePrevious: const ProgramRow(
    ['LayerLeft'],
    [SingleActivator(LogicalKeyboardKey.arrowLeft)],
  ),
  EditorActionIds.frameNext: const ProgramRow(
    ['LayerRight'],
    [SingleActivator(LogicalKeyboardKey.arrowRight)],
  ),
  // レイヤー: エクスポージャー: 前 / 次.
  EditorActionIds.drawingPrevious: const ProgramRow(
    ['PrevInstance'],
    [SingleActivator(LogicalKeyboardKey.arrowLeft, control: true)],
  ),
  EditorActionIds.drawingNext: const ProgramRow(
    ['NextInstance'],
    [SingleActivator(LogicalKeyboardKey.arrowRight, control: true)],
  ),
  // レイヤー: 上に移動 / 下に移動.
  EditorActionIds.layerUp: const ProgramRow(
    ['LayerUp'],
    [SingleActivator(LogicalKeyboardKey.arrowUp)],
  ),
  EditorActionIds.layerDown: const ProgramRow(
    ['LayerDown'],
    [SingleActivator(LogicalKeyboardKey.arrowDown)],
  ),
  // ズーム: 回転 +15(反時計回り) / -15(時計回り).
  EditorActionIds.canvasRotateCcw: const ProgramRow(
    ['ZoomRotateAdd15'],
    [SingleActivator(LogicalKeyboardKey.pageUp, shift: true)],
  ),
  EditorActionIds.canvasRotateCw: const ProgramRow(
    ['ZoomRotateSub15'],
    [SingleActivator(LogicalKeyboardKey.pageDown, shift: true)],
  ),
  // ズーム: ズームイン / ズームアウト.
  EditorActionIds.canvasZoomIn: const ProgramRow(
    ['ZoomIn'],
    [SingleActivator(LogicalKeyboardKey.greater)],
  ),
  EditorActionIds.canvasZoomOut: const ProgramRow(
    ['ZoomOut'],
    [SingleActivator(LogicalKeyboardKey.less)],
  ),
  // ズーム: 水平に反転 / 垂直に反転.
  EditorActionIds.canvasFlipHorizontal: const ProgramRow(
    ['ZoomFlipX'],
    [SingleActivator(LogicalKeyboardKey.bracketLeft)],
  ),
  EditorActionIds.canvasFlipVertical: const ProgramRow(
    ['ZoomFlipY'],
    [SingleActivator(LogicalKeyboardKey.bracketRight)],
  ),
  // ズーム: 回転リセット.
  EditorActionIds.canvasStraighten: const ProgramRow(
    ['ZoomRotateReset'],
    [SingleActivator(LogicalKeyboardKey.insert)],
  ),
  // ズーム: 全ページを表示.
  EditorActionIds.canvasFit: const ProgramRow(
    ['ShowPage'],
    [
      SingleActivator(LogicalKeyboardKey.keyV, shift: true),
      SingleActivator(LogicalKeyboardKey.f11, shift: true),
    ],
  ),
  // ズーム: 1-1.
  EditorActionIds.canvasResetView: const ProgramRow(
    ['ZoomOneOne'],
    [SingleActivator(LogicalKeyboardKey.numpad0, control: true)],
  ),
  // レイヤー: ライトテーブルモード — a similar command: the light table is
  // the program's onion skin.
  EditorActionIds.onionSkinToggle: const ProgramRow(
    ['LayerTogglePelureMode'],
    [SingleActivator(LogicalKeyboardKey.keyL, control: true)],
  ),
  // プレビュー: 現在の画像から再生 / 一時停止.
  EditorActionIds.playbackToggle: const ProgramRow(
    ['PlayPreviewCurrentFrame'],
    [SingleActivator(LogicalKeyboardKey.space)],
  ),
  // プロジェクト: クリップ: 最初の画像へ; レイヤー: 始めの画像 — a similar
  // command.
  EditorActionIds.playbackToStart: const ProgramRow(
    ['StoryboardDrawingHead', 'LayerFirstImage'],
    [
      SingleActivator(LogicalKeyboardKey.home, shift: true),
      SingleActivator(LogicalKeyboardKey.home),
    ],
  ),
  // アンドゥ: 最後のアクション / 複数回のやり直し.
  EditorActionIds.undo: const ProgramRow(
    ['Undo'],
    [
      SingleActivator(LogicalKeyboardKey.keyZ, control: true),
      SingleActivator(LogicalKeyboardKey.keyU),
    ],
  ),
  EditorActionIds.redo: const ProgramRow(
    ['MultiRedo'],
    [
      SingleActivator(LogicalKeyboardKey.keyY, control: true),
      SingleActivator(LogicalKeyboardKey.keyU, shift: true),
    ],
  ),
  // 選択範囲をカット (アダプティブ) and (設定で定義した); 選択範囲をコピー;
  // ペースト — the ordinary paste, the independent one here (F-156).
  EditorActionIds.editCut: const ProgramRow(
    ['Cut', 'SelectDel'],
    [
      SingleActivator(LogicalKeyboardKey.keyX, control: true),
      SingleActivator(LogicalKeyboardKey.delete),
    ],
  ),
  EditorActionIds.editCopy: const ProgramRow(
    ['Copy'],
    [SingleActivator(LogicalKeyboardKey.keyC, control: true)],
  ),
  EditorActionIds.editPasteIndependent: const ProgramRow(
    ['Paste'],
    [SingleActivator(LogicalKeyboardKey.keyV, control: true)],
  ),
  // プロジェクト: クリップ: 画像を削除 — a similar command.
  EditorActionIds.editDelete: const ProgramRow(
    ['DeleteImageProject'],
    [SingleActivator(LogicalKeyboardKey.f5, shift: true)],
  ),
  // レイヤー: クリア, on two keys.
  EditorActionIds.editClearPixels: const ProgramRow(
    ['Clear'],
    [
      SingleActivator(LogicalKeyboardKey.backspace),
      SingleActivator(LogicalKeyboardKey.keyK, shift: true),
    ],
  ),
  // クリップボード: 画像をコピーする / 画像を貼り付ける — similar commands.
  EditorActionIds.editCopyPixels: const ProgramRow(
    ['SaveImageToClipboard'],
    [SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true)],
  ),
  EditorActionIds.editPastePixelsAbove: const ProgramRow(
    ['LoadImageFromClipboard'],
    [SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true)],
  ),
  // 形状: 適用 / キャンセル.
  EditorActionIds.confirm: const ProgramRow(
    ['ShapeApply'],
    [SingleActivator(LogicalKeyboardKey.enter)],
  ),
  EditorActionIds.selectionTransformCancel: const ProgramRow(
    ['ShapeAbort'],
    [SingleActivator(LogicalKeyboardKey.escape)],
  ),
  // 形状選択: クリア.
  EditorActionIds.selectionDeselect: const ProgramRow(
    ['SelectClear'],
    [SingleActivator(LogicalKeyboardKey.keyD, control: true)],
  ),
  // プロジェクト: 新規 · 開く · 保存 · 別名で保存; 書き出し: シークエンス — a
  // similar command.
  EditorActionIds.fileNew: const ProgramRow(
    ['NewProject'],
    [SingleActivator(LogicalKeyboardKey.keyN, shift: true)],
  ),
  EditorActionIds.fileOpen: const ProgramRow(
    ['LoadProject'],
    [
      SingleActivator(LogicalKeyboardKey.keyO, control: true),
      SingleActivator(LogicalKeyboardKey.keyL, shift: true),
    ],
  ),
  EditorActionIds.fileSave: const ProgramRow(
    ['SaveProject'],
    [
      SingleActivator(LogicalKeyboardKey.keyS, control: true),
      SingleActivator(LogicalKeyboardKey.keyS, shift: true),
    ],
  ),
  EditorActionIds.fileSaveAs: const ProgramRow(
    ['SaveAsProject'],
    [SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true)],
  ),
  EditorActionIds.fileExport: const ProgramRow(
    ['SaveSequence'],
    [SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true)],
  ),
  // インターフェース: 設定パネルを開く (the program's Preferences) ·
  // キーボード設定.
  EditorActionIds.preferences: const ProgramRow(
    ['OpenSettingsPanel'],
    [SingleActivator(LogicalKeyboardKey.keyD, shift: true)],
  ),
  EditorActionIds.keyboardShortcuts: const ProgramRow(
    ['ConfigureKeyboard'],
    [SingleActivator(LogicalKeyboardKey.keyK, control: true)],
  ),
  // 形状: フリーハンド — a similar command: drawing freehand is the brush.
  EditorActionIds.toolBrush: const ProgramRow(
    ['ShapeFreeHandLine'],
    [SingleActivator(LogicalKeyboardKey.keyD)],
  ),
  // 形状: ペイント缶.
  EditorActionIds.toolFillBucket: const ProgramRow(
    ['ShapeFlood'],
    [SingleActivator(LogicalKeyboardKey.keyF)],
  ),
  // 色: 色を拾う · ツール オプション: 文字 · ブラシ: ブラシ切り抜き・カット
  // ツール.
  EditorActionIds.toolEyedropper: const ProgramRow(
    ['PicColor'],
    [SingleActivator(LogicalKeyboardKey.semicolon)],
  ),
  EditorActionIds.toolText: const ProgramRow(
    ['ToolText'],
    [SingleActivator(LogicalKeyboardKey.keyT)],
  ),
  EditorActionIds.toolCut: const ProgramRow(
    ['ToggleCutBrush'],
    [SingleActivator(LogicalKeyboardKey.keyB)],
  ),
  // 形状: 長方形 · 塗りつぶし長方形 · 直線.
  shapeTileActionId(CanvasTool.shape, CanvasShapeKind.rect): const ProgramRow(
    ['ShapeRectangle'],
    [SingleActivator(LogicalKeyboardKey.keyR)],
  ),
  shapeTileActionId(CanvasTool.fillShape, CanvasShapeKind.rect):
      const ProgramRow(
        ['ShapeRectangleFill'],
        [SingleActivator(LogicalKeyboardKey.keyR, shift: true)],
      ),
  shapeTileActionId(CanvasTool.shape, CanvasShapeKind.line): const ProgramRow(
    ['ShapeLine'],
    [SingleActivator(LogicalKeyboardKey.keyL)],
  ),
  // 形状変形: 変形.
  EditorActionIds.toolTransformNormal: const ProgramRow(
    ['Position'],
    [SingleActivator(LogicalKeyboardKey.keyT, control: true)],
  ),
  // 描画モード: 01 (色) · 02 (背景) · 03 (消去) · 06 (暗くする) · 07 (明る
  // くする). 04 · 05 · 08 have no blend here.
  blendModeActionId(BrushBlendMode.color): const ProgramRow(
    ['Drawing Mode 1'],
    [SingleActivator(LogicalKeyboardKey.f2)],
  ),
  blendModeActionId(BrushBlendMode.behind): const ProgramRow(
    ['Drawing Mode 2'],
    [SingleActivator(LogicalKeyboardKey.f3)],
  ),
  blendModeActionId(BrushBlendMode.erase): const ProgramRow(
    ['Drawing Mode 3'],
    [SingleActivator(LogicalKeyboardKey.f4)],
  ),
  blendModeActionId(BrushBlendMode.darken): const ProgramRow(
    ['Drawing Mode 6'],
    [SingleActivator(LogicalKeyboardKey.f7)],
  ),
  blendModeActionId(BrushBlendMode.lighten): const ProgramRow(
    ['Drawing Mode 7'],
    [SingleActivator(LogicalKeyboardKey.f8)],
  ),
  // プロジェクト: 今のフレームに画像を挿入 — 프레임 추가 makes its drawing
  // at the current frame too. レイヤープリセット: Anim Layer — a similar
  // command: the layer pill's ＋, a preset the program names by a number of
  // its own. 🗣️I-63-Q4 (유저 2026-10-09): 「알아서 클튜/tvp기반으로 해당
  // 프리셋에 넣어주고」.
  EditorActionIds.frameNewDrawing: const ProgramRow(
    ['UserAppendImageProject'],
    [SingleActivator(LogicalKeyboardKey.keyI)],
  ),
  EditorActionIds.layerAdd: const ProgramRow(
    ['ca31b5da-336f-5f4b-9b04-cd9003c43868'],
    [SingleActivator(LogicalKeyboardKey.keyN, control: true)],
  ),
  // レイヤー: 現在のレイヤーを見る / すべて.
  EditorActionIds.layerVisibilitySolo: const ProgramRow(
    ['DisplayAllLayer'],
    [SingleActivator(LogicalKeyboardKey.equal)],
  ),
};
