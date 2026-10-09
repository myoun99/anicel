import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../models/brush_blend_mode.dart';
import '../../models/canvas_shape_kind.dart';
import '../../models/layer_kind.dart';
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
/// ★A PRESET HOLDS ONLY THE KEYS ITS PROGRAM NAMES ([_programKeys]). Every
/// other action keeps the registry's key, so a default that moves in the
/// registry moves in every preset that did not name it — and the rule for a
/// key two actions would share is said once ([presetActivators]), not listed
/// per loser.
///
/// 🗣️I-88 (유저 2026-10-09): 「이런 키는 물론 클튜나 tvp 알아서 그거에맞춰서
/// 기록. 앞으로 단축키 관련은 그게 기본임. 내가 제안하는건 다 anicel용」 — a
/// key the user proposes is the registry's, anicel's; each program's table
/// takes that program's own key for the same command, from the program's
/// own references, or names none for it.
enum ShortcutPreset {
  /// The registry's own keys.
  anicel('Anicel'),

  /// CLIP STUDIO PAINT's default keys.
  clipStudio('Clip Studio based'),

  /// TVPaint Animation's default keys.
  tvpaint('TVPaint based');

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
  ShortcutPreset.tvpaint: _tvpaintKeys,
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
///
/// ➕Read against the same pages again on 2026-10-10 (유저 10-09: 「클튜
/// 단축키 제대로 한거 맞는지? … 다시한번 확인하고싶음」): every row below
/// matched, and what the first pass left out is in — Erase's two Ctrl keys,
/// and the rows for actions the app has gained since: New · Open ·
/// Preferences · Shortcut Settings · Fit to Screen (the same commands), and
/// 100% · Reset display · New Raster Layer · Create folder (similar ones).
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
    SingleActivator(LogicalKeyboardKey.delete, control: true),
    SingleActivator(LogicalKeyboardKey.backspace, control: true),
  ],
  EditorActionIds.selectionDeselect: const [
    SingleActivator(LogicalKeyboardKey.keyD, control: true),
  ],
  EditorActionIds.fileNew: const [
    SingleActivator(LogicalKeyboardKey.keyN, control: true),
  ],
  EditorActionIds.fileOpen: const [
    SingleActivator(LogicalKeyboardKey.keyO, control: true),
  ],
  EditorActionIds.fileSave: const [
    SingleActivator(LogicalKeyboardKey.keyS, control: true),
  ],
  EditorActionIds.fileSaveAs: const [
    SingleActivator(LogicalKeyboardKey.keyS, shift: true, alt: true),
    SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true),
    SingleActivator(LogicalKeyboardKey.keyS, control: true, alt: true),
  ],
  EditorActionIds.preferences: const [
    SingleActivator(LogicalKeyboardKey.keyK, control: true),
  ],
  EditorActionIds.keyboardShortcuts: const [
    SingleActivator(
      LogicalKeyboardKey.keyK,
      control: true,
      shift: true,
      alt: true,
    ),
  ],
  // View > Fit to Screen; > 100% and > Reset display — similar commands:
  // the view at 100%, and the view's turn put back.
  EditorActionIds.canvasFit: const [
    SingleActivator(LogicalKeyboardKey.digit0, control: true),
  ],
  EditorActionIds.canvasResetView: const [
    SingleActivator(LogicalKeyboardKey.digit0, control: true, alt: true),
  ],
  EditorActionIds.canvasStraighten: const [
    SingleActivator(LogicalKeyboardKey.at, control: true),
  ],
  // Layer > New Raster Layer, and > Create folder and insert layer — similar
  // commands: the layer pill's ＋, and a folder row.
  EditorActionIds.layerAdd: const [
    SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true),
  ],
  addLayerKindActionId(LayerKind.folder): const [
    SingleActivator(LogicalKeyboardKey.keyG, control: true),
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
  // Figure. ↩️U stood on the guide tool until the shape tool came (I-69,
  // 2026-10-07) — Ruler, a similar command, which shares the key in the
  // program; the same command comes before a similar one, so the guide
  // tool has no key of this table's now.
  EditorActionIds.toolShape: const [SingleActivator(LogicalKeyboardKey.keyU)],
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

/// TVPaint Animation's default key for each action it has one for.
/// 🗣️I-63-Q2 (유저 2026-10-09): 「쓰시는 TVPaint 의 단축키를 보내 주신다 —
/// 그대로 옮긴다」 — sent as TVPaint 12's own default keymap file
/// (`tvp_shortcut_default.txt`, its Japanese interface), whose command names
/// are quoted beside each row. The rule is the table's (I-63-Q3, 「그
/// 프로그램을 최대한 닮게」): the same command, or the nearest one.
///
/// ⚠️Where the program's key names a command the app has no action for —
/// `A` shakes the view, `G` `H` `V` `J` `K` are selection modes, `1`…`9`
/// scroll the view, `+` `-` size the brush — the action that held the key
/// here keeps it: only a key the program gives to one of OUR actions leaves
/// another ([presetActivators]).
/// ⚠️`Space` plays (「再生 / 一時停止」), so the pan held on it has no key
/// under this preset.
/// ⚠️MY READINGS, each the nearest command, not one the user named: `Del`
/// is the program's second Cut (「選択範囲をカット (設定で定義した)」, the
/// timeline's, as Ctrl+X is), so it cuts here rather than clearing pixels;
/// `F` is the bucket itself, so the bucket's tile takes it and the fill
/// button keeps no key; `B` (the CutBrush) is the cut tool AND its stamp
/// here, and the rail tool takes it (the rule `M` · `U` · `G` follow in the
/// CLIP STUDIO table).
final Map<String, List<SingleActivator>> _tvpaintKeys = {
  // レイヤー: 左に移動 / 右に移動.
  EditorActionIds.framePrevious: const [
    SingleActivator(LogicalKeyboardKey.arrowLeft),
  ],
  EditorActionIds.frameNext: const [
    SingleActivator(LogicalKeyboardKey.arrowRight),
  ],
  // レイヤー: エクスポージャー: 前 / 次.
  EditorActionIds.drawingPrevious: const [
    SingleActivator(LogicalKeyboardKey.arrowLeft, control: true),
  ],
  EditorActionIds.drawingNext: const [
    SingleActivator(LogicalKeyboardKey.arrowRight, control: true),
  ],
  // レイヤー: 上に移動 / 下に移動.
  EditorActionIds.layerUp: const [SingleActivator(LogicalKeyboardKey.arrowUp)],
  EditorActionIds.layerDown: const [
    SingleActivator(LogicalKeyboardKey.arrowDown),
  ],
  // ズーム: 回転 +15(反時計回り) / -15(時計回り).
  EditorActionIds.canvasRotateCcw: const [
    SingleActivator(LogicalKeyboardKey.pageUp, shift: true),
  ],
  EditorActionIds.canvasRotateCw: const [
    SingleActivator(LogicalKeyboardKey.pageDown, shift: true),
  ],
  // ズーム: ズームイン / ズームアウト.
  EditorActionIds.canvasZoomIn: const [
    SingleActivator(LogicalKeyboardKey.greater),
  ],
  EditorActionIds.canvasZoomOut: const [
    SingleActivator(LogicalKeyboardKey.less),
  ],
  // ズーム: 水平に反転 / 垂直に反転.
  EditorActionIds.canvasFlipHorizontal: const [
    SingleActivator(LogicalKeyboardKey.bracketLeft),
  ],
  EditorActionIds.canvasFlipVertical: const [
    SingleActivator(LogicalKeyboardKey.bracketRight),
  ],
  // ズーム: 回転リセット.
  EditorActionIds.canvasStraighten: const [
    SingleActivator(LogicalKeyboardKey.insert),
  ],
  // ズーム: 全ページを表示.
  EditorActionIds.canvasFit: const [
    SingleActivator(LogicalKeyboardKey.keyV, shift: true),
    SingleActivator(LogicalKeyboardKey.f11, shift: true),
  ],
  // ズーム: 1-1.
  EditorActionIds.canvasResetView: const [
    SingleActivator(LogicalKeyboardKey.numpad0, control: true),
  ],
  // レイヤー: ライトテーブルモード — a similar command: the light table is
  // the program's onion skin.
  EditorActionIds.onionSkinToggle: const [
    SingleActivator(LogicalKeyboardKey.keyL, control: true),
  ],
  // プレビュー: 現在の画像から再生 / 一時停止.
  EditorActionIds.playbackToggle: const [
    SingleActivator(LogicalKeyboardKey.space),
  ],
  // プロジェクト: クリップ: 最初の画像へ; レイヤー: 始めの画像 — a similar
  // command.
  EditorActionIds.playbackToStart: const [
    SingleActivator(LogicalKeyboardKey.home, shift: true),
    SingleActivator(LogicalKeyboardKey.home),
  ],
  // アンドゥ: 最後のアクション / 複数回のやり直し.
  EditorActionIds.undo: const [
    SingleActivator(LogicalKeyboardKey.keyZ, control: true),
    SingleActivator(LogicalKeyboardKey.keyU),
  ],
  EditorActionIds.redo: const [
    SingleActivator(LogicalKeyboardKey.keyY, control: true),
    SingleActivator(LogicalKeyboardKey.keyU, shift: true),
  ],
  // 選択範囲をカット (アダプティブ) and (設定で定義した); 選択範囲をコピー;
  // ペースト — the ordinary paste, the independent one here (F-156).
  EditorActionIds.editCut: const [
    SingleActivator(LogicalKeyboardKey.keyX, control: true),
    SingleActivator(LogicalKeyboardKey.delete),
  ],
  EditorActionIds.editCopy: const [
    SingleActivator(LogicalKeyboardKey.keyC, control: true),
  ],
  EditorActionIds.editPasteIndependent: const [
    SingleActivator(LogicalKeyboardKey.keyV, control: true),
  ],
  // プロジェクト: クリップ: 画像を削除 — a similar command.
  EditorActionIds.editDelete: const [
    SingleActivator(LogicalKeyboardKey.f5, shift: true),
  ],
  // レイヤー: クリア, on two keys.
  EditorActionIds.editClearPixels: const [
    SingleActivator(LogicalKeyboardKey.backspace),
    SingleActivator(LogicalKeyboardKey.keyK, shift: true),
  ],
  // クリップボード: 画像をコピーする / 画像を貼り付ける — similar commands.
  EditorActionIds.editCopyPixels: const [
    SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true),
  ],
  EditorActionIds.editPastePixelsAbove: const [
    SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true),
  ],
  // 形状: 適用 / キャンセル.
  EditorActionIds.confirm: const [SingleActivator(LogicalKeyboardKey.enter)],
  EditorActionIds.selectionTransformCancel: const [
    SingleActivator(LogicalKeyboardKey.escape),
  ],
  // 形状選択: クリア.
  EditorActionIds.selectionDeselect: const [
    SingleActivator(LogicalKeyboardKey.keyD, control: true),
  ],
  // プロジェクト: 新規 · 開く · 保存 · 別名で保存; 書き出し: シークエンス — a
  // similar command.
  EditorActionIds.fileNew: const [
    SingleActivator(LogicalKeyboardKey.keyN, shift: true),
  ],
  EditorActionIds.fileOpen: const [
    SingleActivator(LogicalKeyboardKey.keyO, control: true),
    SingleActivator(LogicalKeyboardKey.keyL, shift: true),
  ],
  EditorActionIds.fileSave: const [
    SingleActivator(LogicalKeyboardKey.keyS, control: true),
    SingleActivator(LogicalKeyboardKey.keyS, shift: true),
  ],
  EditorActionIds.fileSaveAs: const [
    SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true),
  ],
  EditorActionIds.fileExport: const [
    SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true),
  ],
  // インターフェース: 設定パネルを開く (the program's Preferences) ·
  // キーボード設定.
  EditorActionIds.preferences: const [
    SingleActivator(LogicalKeyboardKey.keyD, shift: true),
  ],
  EditorActionIds.keyboardShortcuts: const [
    SingleActivator(LogicalKeyboardKey.keyK, control: true),
  ],
  // 形状: フリーハンド — a similar command: drawing freehand is the brush.
  EditorActionIds.toolBrush: const [SingleActivator(LogicalKeyboardKey.keyD)],
  // 形状: ペイント缶.
  EditorActionIds.toolFillBucket: const [
    SingleActivator(LogicalKeyboardKey.keyF),
  ],
  // 色: 色を拾う · ツール オプション: 文字 · ブラシ: ブラシ切り抜き・カット
  // ツール.
  EditorActionIds.toolEyedropper: const [
    SingleActivator(LogicalKeyboardKey.semicolon),
  ],
  EditorActionIds.toolText: const [SingleActivator(LogicalKeyboardKey.keyT)],
  EditorActionIds.toolCut: const [SingleActivator(LogicalKeyboardKey.keyB)],
  // 形状: 長方形 · 塗りつぶし長方形 · 直線.
  shapeTileActionId(CanvasTool.shape, CanvasShapeKind.rect): const [
    SingleActivator(LogicalKeyboardKey.keyR),
  ],
  shapeTileActionId(CanvasTool.fillShape, CanvasShapeKind.rect): const [
    SingleActivator(LogicalKeyboardKey.keyR, shift: true),
  ],
  shapeTileActionId(CanvasTool.shape, CanvasShapeKind.line): const [
    SingleActivator(LogicalKeyboardKey.keyL),
  ],
  // 形状変形: 変形.
  EditorActionIds.toolTransformNormal: const [
    SingleActivator(LogicalKeyboardKey.keyT, control: true),
  ],
  // 描画モード: 01 (色) · 02 (背景) · 03 (消去) · 06 (暗くする) · 07 (明る
  // くする). 04 · 05 · 08 have no blend here.
  blendModeActionId(BrushBlendMode.color): const [
    SingleActivator(LogicalKeyboardKey.f2),
  ],
  blendModeActionId(BrushBlendMode.behind): const [
    SingleActivator(LogicalKeyboardKey.f3),
  ],
  blendModeActionId(BrushBlendMode.erase): const [
    SingleActivator(LogicalKeyboardKey.f4),
  ],
  blendModeActionId(BrushBlendMode.darken): const [
    SingleActivator(LogicalKeyboardKey.f7),
  ],
  blendModeActionId(BrushBlendMode.lighten): const [
    SingleActivator(LogicalKeyboardKey.f8),
  ],
  // プロジェクト: 今のフレームに画像を挿入 — 프레임 추가 makes its drawing
  // at the current frame too. レイヤープリセット: Anim Layer — a similar
  // command: the layer pill's ＋. 🗣️I-63-Q4 (유저 2026-10-09): 「알아서
  // 클튜/tvp기반으로 해당 프리셋에 넣어주고」.
  EditorActionIds.frameNewDrawing: const [
    SingleActivator(LogicalKeyboardKey.keyI),
  ],
  EditorActionIds.layerAdd: const [
    SingleActivator(LogicalKeyboardKey.keyN, control: true),
  ],
  // レイヤー: 現在のレイヤーを見る / すべて.
  EditorActionIds.layerVisibilitySolo: const [
    SingleActivator(LogicalKeyboardKey.equal),
  ],
};
