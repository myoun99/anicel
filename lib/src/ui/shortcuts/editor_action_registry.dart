import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/app_language.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/canvas_shape_kind.dart';
import '../../models/export_format_selection.dart' show ExportStillFormat;
import '../../models/inbetween_mark.dart';
import '../../models/layer_blend_mode.dart';
import '../../models/layer_effect.dart'
    show EffectKind, effectKindsAddedAlone;
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/pixel_clipboard_verb.dart';
import '../../native/window_full_screen.dart';
import '../../services/cel_pixel_overwrite.dart' show CelPixelVerb;
import '../brush/brush_press.dart';
import '../brush/brush_tool_state.dart'
    show CanvasTool, canvasToolRailGroup, canvasToolShapes;
import '../brush/tool_press.dart';
import '../brush/transform_tool_options.dart' show TransformMode;
import '../text/app_strings.dart' show AppStrings;
import '../text/model_vocabulary.dart'
    show
        BrushBlendModeWords,
        EffectKindWords,
        LayerBlendModeWords,
        LayerKindWords,
        LayerMarkWords;
import 'sheet_arrow.dart' show SheetArrow, SheetKeys, SheetMove;
import 'shortcut_shelf.dart';

/// The single shortcut intent: every editor action dispatches through ONE
/// intent type carrying its [actionId], so the app mounts exactly one
/// Actions handler and the Shortcuts map stays data-driven from the
/// registry (P1: fully customizable from day one).
class EditorActionIntent extends Intent {
  const EditorActionIntent(this.actionId);

  final String actionId;
}

/// One registered editor action: the id keys the override store, the
/// label/shelf feed the Keyboard Shortcuts dialog, the default
/// activators seed the Shortcuts map, and menu items borrow the primary
/// activator as their shortcut label. THIS list is the single authority
/// all three consumers read.
class EditorActionDefinition {
  const EditorActionDefinition({
    required this.id,
    required this.label,
    required this.shelf,
    required this.defaultActivators,
    this.defaultTouchGesture,
    this.hold = false,
    this.zoomsView = false,
    this.toolPress,
    this.pixelVerb,
    this.blendMode,
    this.pixelClipboardVerb,
    this.sheetMove,
    this.brushPress,
    this.menuRow = false,
    this.panelButton = false,
    this.platforms,
  }) : composedName = null;

  /// An action whose name is COMPOSED rather than tabled: [name] says it in
  /// a language, and its English is the registry's own wording ([label]) —
  /// one composer for both, so the two cannot come to differ.
  EditorActionDefinition.composed({
    required this.id,
    required String Function(AppLanguage language) name,
    required this.shelf,
    required this.defaultActivators,
    this.toolPress,
    this.blendMode,
    this.menuRow = false,
    this.panelButton = false,
  }) : label = name(AppLanguage.en),
       composedName = name,
       defaultTouchGesture = null,
       hold = false,
       zoomsView = false,
       pixelVerb = null,
       pixelClipboardVerb = null,
       sheetMove = null,
       brushPress = null,
       platforms = null;

  final String id;
  final String label;

  /// Where its button stands — the shortcut window's heading for it, and
  /// every heading above that one ([ShortcutShelf.path]).
  final ShortcutShelf shelf;
  final List<SingleActivator> defaultActivators;

  /// The action's name in a language, when that name is composed of other
  /// names — a shape tile's of its verb and its shape, a blend action's of
  /// the blend's own, an add-layer row's of the menu's name and the kind's
  /// — and null for every action a table names by its id.
  ///
  /// ↩️Until 2026-10-08 each family was a branch wherever a name is asked
  /// (is it a shape tile, is it a blend), and again where the tables are
  /// checked for a row. The layer kinds and the effect kinds (I-40) would
  /// have been the third and fourth branch; a family says its own name now.
  final String Function(AppLanguage language)? composedName;

  /// The multi-finger touch gesture bound by default (R11-⑨); most
  /// actions ship unbound — every action is ASSIGNABLE in the settings
  /// dialog either way. Stored as the [TouchGesture] enum NAME, so this
  /// file does not import the touch layer.
  final String? defaultTouchGesture;

  /// A HELD action (I-15): its key is in force while it is down and lets go
  /// with it — the pan on Space. It is not an intent, so it never enters
  /// the Shortcuts map; `EditorKeyHolds` takes it on the same road instead.
  final bool hold;

  /// A viewport ZOOM — I-19's two steps, and fit and 1:1 (I-40), which land
  /// a zoom too.
  ///
  /// 🚨R6q3 (유저 2026-08-25, 답 2번): 「키보드 줌도 통과시킨다. 재생 중 줌은
  /// 입력 수단과 무관하게 한 법으로」. The playback gate lets these through
  /// exactly where it lets a pointer zoom through. ⛔This says what the action
  /// IS; the law that reads it lives in the gate (`viewZoomPassesPlayback`),
  /// never as a playback check inside the zoom.
  final bool zoomsView;

  /// What a TOOL action presses — a rail button or a tile of the tool
  /// library — or null for every other action.
  ///
  /// 🗣️I-19 (유저 2026-09-13): 「툴 자체에 설정할수도있고 툴 내부의 세부툴도
  /// 설정가능하게」. The row says what it presses, the rail and the library
  /// build their buttons out of the same presses, and the shell applies one
  /// through `pressTool` — so the key and the button are one press, and a
  /// button finds its action by [toolActionIdFor].
  final ToolPress? toolPress;

  /// The verb a row of the colour edit list runs, or null — WHICH row the
  /// action is, and how that row finds its action ([pixelVerbActionIdFor]).
  /// The press is the row's own ([menuRow]).
  ///
  /// 🗣️유저 2026-09-13: 「색변환의 픽셀비우기를 백스페이스로 하란건, 그 외
  /// 같이있는 버튼들도 다 숏컷 지정가능하게 등록하란거는 앞으로의 규칙이야」.
  ///
  /// ↩️Until 2026-10-08 the shell ran the verb itself behind the row's gate
  /// — the row's two lines written a second time, as 저장 had been.
  final CelPixelVerb? pixelVerb;

  /// The blend mode a BLEND action picks for the tool in hand, or null.
  ///
  /// 🗣️I-31 (유저 2026-09-14): 「도구의 블렌드모드(브러시나 채우기나)내용
  /// 숏컷으로서 등록. 컬러,비하인드 등 리스트 전부」. It picks what the
  /// strip's blend chooser picks, where that chooser can pick — see
  /// `BrushToolState.blendIsAChoice`.
  final BrushBlendMode? blendMode;

  /// The clipboard row of the colour edit list a row runs (I-55), or null —
  /// the same rule as [pixelVerb], for the list's other kind of verb.
  final PixelClipboardVerb? pixelClipboardVerb;

  /// A move on the sheet (F-241), or null: the way it walks as the timeline
  /// reads it, and whether it is the one-frame step. Its DIRECTION keys are
  /// written as the timeline reads them, and on the X-sheet a pressed one is
  /// turned to the timeline's before it is matched, and a bound one is shown
  /// turned (`SheetArrowTurn`).
  ///
  /// ↩️F-261: 「A key that is not an arrow never turns」 stood here. Which
  /// keys are direction keys is the bindings' answer now ([SheetKeys]) — the
  /// keys bound bare to the block and row moves — and this is what tells the
  /// keys and the flip which move walks which way ([sheetMoveActionId]).
  final SheetMove? sheetMove;

  /// What a BRUSH action presses (I-56) — a group's tab or one brush of the
  /// brush library — or null for every other action. These rows are not in
  /// [editorActionDefinitions]: the library is the user's own, so they are
  /// made from it as it stands (`brushActionsOf`).
  final BrushPress? brushPress;

  /// A row of a menu (I-40) — the top strip's two, or the timeline bar's
  /// (the pills' menus and the colour edit list): the action IS that row,
  /// and a key presses it where the row can be pressed (`pressFlyoutRow`,
  /// over the rows the shell gathers from both).
  ///
  /// 🗣️유저 2026-09-18: 「버튼 전수감사해서 숏컷리스트에 등록 … 설정의 패널
  /// 열기 닫기같은거든 뭐든 모든 버튼」. ⛔A menu row's action has no road of
  /// its own to what the row does: 저장 had one — the row's call written a
  /// second time in the shell's switch — and two roads to one verb are what
  /// drift apart.
  final bool menuRow;

  /// A button of a panel (I-40) — the brush library's import, the guide
  /// list's ＋, the media pool's ＋ …: the action IS that button, and a key
  /// presses the callback the button holds, on a panel a key reaches
  /// (`PanelKeys` — the tool in hand's panels, and the panels of no tool).
  /// Like [menuRow], it has no road of its own to what the button does.
  final bool panelButton;

  /// The platforms the action is offered on — null: every one. A platform
  /// with no button for the action has no key for it either: the shortcut
  /// list does not show it there ([offeredHere]).
  ///
  /// 🗣️I-103-Q2 (유저 2026-10-16): the window's full screen is a switch on
  /// the desktops only — 「아이패드 · 안드로이드에는 이 줄이 없다」.
  final Set<TargetPlatform>? platforms;

  /// Whether this platform offers the action ([platforms]).
  bool get offeredHere => platforms?.contains(defaultTargetPlatform) ?? true;
}

/// The move that walks [arrow] on the timeline: its one-frame step when
/// [fine] and the sheet has one that way, the block or row move otherwise —
/// the extra finger on a row is still the row (F-28).
String sheetMoveActionId(SheetArrow arrow, {required bool fine}) {
  String? moveOf({required bool step}) => editorActionDefinitions
      .where((definition) => definition.sheetMove == (arrow: arrow, fine: step))
      .firstOrNull
      ?.id;
  return (fine ? moveOf(step: true) : null) ?? moveOf(step: false)!;
}

/// The action a tool button or tile presses, found by its press — so the
/// button names its action without spelling an id (I-19).
String toolActionIdFor(ToolPress press) => _toolActionIds[press]!;

final Map<ToolPress, String> _toolActionIds = {
  for (final definition in editorActionDefinitions)
    ?definition.toolPress: definition.id,
};

/// The action a colour edit row runs, found by its verb.
String pixelVerbActionIdFor(CelPixelVerb verb) => _pixelVerbActionIds[verb]!;

/// The action a clipboard row of the colour edit list runs (I-55).
String pixelClipboardActionIdFor(PixelClipboardVerb verb) =>
    _pixelClipboardActionIds[verb]!;

final Map<PixelClipboardVerb, String> _pixelClipboardActionIds = {
  for (final definition in editorActionDefinitions)
    ?definition.pixelClipboardVerb: definition.id,
};

final Map<CelPixelVerb, String> _pixelVerbActionIds = {
  for (final definition in editorActionDefinitions)
    ?definition.pixelVerb: definition.id,
};

/// The shape tiles of [verb] as actions, one per shape it speaks
/// (`canvasToolShapes`).
///
/// ★GENERATED from the verb × shape product, never hand-written:
/// [CanvasShapeKind] warns that the product grows like one, so a new shape
/// arrives in its tiles and in the shortcut list at once. Their names are
/// composed (`shapeTileLabel`) — the English one here from the English
/// table — so no language tables a shape tile twice.
List<EditorActionDefinition> _shapeTileActions(CanvasTool verb) => [
  for (final shape in canvasToolShapes(verb))
    EditorActionDefinition.composed(
      id: shapeTileActionId(verb, shape),
      name: (language) => shapeTileLabel(verb, shape, AppStrings.of(language)),
      shelf: ShortcutShelf.toolTiles,
      defaultActivators: [
        // 「선택도구의 올가미 선택에 w로 두고싶어」. ↩️F-261 (유저
        // 2026-10-02): W walks up now, and 「올가미를 z」. ↩️I-63 (유저
        // 2026-10-03): 「올가미선택을 x로두고 z는 비워두도록. 언두 실수할때
        // z만 누르거나하니까」 — so bare Z presses NOTHING, on purpose: it
        // is the key a hand lands on when Ctrl slips off an undo.
        // ↩️I-119 holds it for the line from the last stroke, which lays
        // nothing until a click — asked on the board (I-119-Q3).
        if (verb == CanvasTool.select && shape == CanvasShapeKind.lasso)
          const SingleActivator(LogicalKeyboardKey.keyX),
        // 🗣️I-63 ⑤ (유저 2026-10-04, F-279): 「올가미채우기를 y로」.
        if (verb == CanvasTool.fillShape && shape == CanvasShapeKind.lasso)
          const SingleActivator(LogicalKeyboardKey.keyY),
        // 🗣️I-53 (유저 2026-09-28): 「잘라내기도구에서 올가미 잘라내기를
        // 단축키 c로 두도록 변경하고, 스탬프를 v로」 — 「잘라내기를
        // 고르고싶으면 올가미 잘라내기의 단축키를 사용할 예정」.
        if (verb == CanvasTool.cut && shape == CanvasShapeKind.lasso)
          const SingleActivator(LogicalKeyboardKey.keyC),
      ],
      toolPress: ShapeTilePress(verb, shape),
    ),
];

/// The id of [verb]'s [shape] tile — named for the rail tool the tile
/// belongs to ('tool-select-lasso', 'tool-fill-rect'), which is the id the
/// rectangle select already had.
String shapeTileActionId(CanvasTool verb, CanvasShapeKind shape) =>
    'tool-${canvasToolRailGroup(verb).name}-${shape.name}';

/// The tool blend modes as actions, one per [BrushBlendMode] — the strip's
/// blend chooser, in its order.
///
/// 🗣️I-31: 「그리고 위에서부터 순서대로 F1부터 F12까지 등록할수있는만큼
/// 초기값으로서 숏컷 등록」 — the first twelve get F1–F12, the rest none.
///
/// ★GENERATED from the list, like the shape tiles: a mode added to it
/// arrives here with it, and its name is composed from the mode's own
/// ([blendModeActionLabel]), so no table names a mode twice.
List<EditorActionDefinition> _blendModeActions() => [
  for (final (index, mode) in BrushBlendMode.values.indexed)
    EditorActionDefinition.composed(
      id: blendModeActionId(mode),
      name: (language) => blendModeActionLabel(mode, language),
      shelf: ShortcutShelf.blendModes,
      defaultActivators: [
        if (index < _functionKeys.length) SingleActivator(_functionKeys[index]),
      ],
      blendMode: mode,
    ),
];

const _functionKeys = [
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
];

/// The action that picks [mode] — spelled here once, for whoever names a
/// blend action without the list in hand (a shortcut preset).
String blendModeActionId(BrushBlendMode mode) => 'tool-blend-${mode.name}';

/// The kinds the layer pill's add menu offers, in its order — its rows and
/// their actions are both made from this list.
///
/// ⛔NO 「현재 선택한 레이어와 같은 종류」 entry (유저 2026-08-12: 「레이어
/// +에 있는 현재 선택한 레이어로 생성 삭제. 필요없음. 묻지마.」). The `＋`
/// itself makes an animation layer now, so an entry meaning "whatever is
/// selected" answered a question nothing asks.
const addLayerKinds = [
  LayerKind.animation,
  LayerKind.storyboard,
  LayerKind.image,
  LayerKind.se,
  LayerKind.instruction,
  // R6b: the row that filters everything below it. It lands above the
  // active layer like every other kind, which is what puts the rows it
  // grades underneath it.
  LayerKind.adjustment,
  // R5 #14: a FOLDER is something you add, empty, and then fill by
  // dropping rows on it — the file-manager shape, replacing "group the
  // active layer into a folder".
  LayerKind.folder,
  // Neither the camera nor the transition is offered — a cut owns exactly
  // one camera and the transition row belongs to the track.
];

/// The English of [EditorActionIds.layerAdd], which the kinds' names are
/// composed over as well.
const _addLayerLabel = 'New Layer';

/// The add menu's kinds as actions, one per kind it offers.
///
/// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록 … 뭐든
/// 모든 버튼」; asked how far (I-40-Q1, 10-08), 유저 chose the command
/// buttons and menu rows of the editing screen. ★GENERATED from the menu's
/// own list, so a kind added to the menu arrives in the shortcut list with
/// it, and named by composition — 「레이어 추가: 애니메이션」 — out of two
/// names the tables already hold.
/// ⚠️Not [EditorActionIds.layerAdd]: that is the pill's `＋`, which adds the
/// one kind the panel being worked in adds; a row here adds ITS kind, where
/// the panel can.
List<EditorActionDefinition> _addLayerKindActions() => [
  for (final kind in addLayerKinds)
    EditorActionDefinition.composed(
      id: addLayerKindActionId(kind),
      name: (language) => addLayerKindActionLabel(kind, language),
      shelf: ShortcutShelf.layerPill,
      defaultActivators: const [],
      menuRow: true,
    ),
];

String addLayerKindActionId(LayerKind kind) => 'layer-add-${kind.name}';

String addLayerKindActionLabel(LayerKind kind, AppLanguage language) {
  final add = AppStrings.of(
    language,
  ).shortcutLabel(EditorActionIds.layerAdd, _addLayerLabel);
  return '$add: ${kind.labelFor(language)}';
}

/// The fx pill's rows as actions, one per kind added alone
/// ([effectKindsAddedAlone]) — the menu lists every one, always (it dims
/// what the row cannot take), and so does this. The action's name is the
/// row's own: 「{name} 추가」. A plugin's row is no action: which plugins
/// there are is this device's, not the shortcut list's.
List<EditorActionDefinition> _addEffectActions() => [
  for (final kind in effectKindsAddedAlone)
    EditorActionDefinition.composed(
      id: addEffectActionId(kind),
      name: (language) => addEffectActionLabel(kind, language),
      shelf: ShortcutShelf.fxPill,
      defaultActivators: const [],
      menuRow: true,
    ),
];

String addEffectActionId(EffectKind kind) => 'effect-add-${kind.jsonValue}';

/// The rail legend's rows as actions — every row the columns' flyouts can
/// show (`TimelineLegendMenus`), on the timeline's rail and the
/// storyboard's, pressed on the panel being worked in.
///
/// 🗣️I-40 (유저 2026-09-18 · I-40-Q1 10-08): the editing screen's command
/// buttons and menu rows. A row is named by its own words where they say
/// what it does (「SE 행 표시」 · 「마크 필터 해제」); where they need their
/// column to be understood, the column comes first — 「표시 열: 모두
/// 표시」 — as an add-layer row's kind comes after its menu's name.
abstract final class RailLegendActionIds {
  static const sectionSe = 'rail-section-se';
  static const sectionCamera = 'rail-section-camera';
  static const sheetAllOn = 'rail-sheet-all-on';
  static const sheetAllOff = 'rail-sheet-all-off';
  static const soloSheet = 'rail-solo-sheet';
  static const markFilterClear = 'rail-mark-filter-clear';
  static const clipClear = 'rail-clip-clear';
  static const soloClip = 'rail-solo-clip';
  static const fxEnableAll = 'rail-fx-enable-all';
  static const fxBypassAll = 'rail-fx-bypass-all';
  static const soloFx = 'rail-solo-fx';
  static const onionOnDisplayed = 'rail-onion-on-displayed';
  static const onionOpenPanel = 'rail-onion-open-panel';
  static const eyeShowAll = 'rail-eye-show-all';
  static const eyeHideAll = 'rail-eye-hide-all';
}

/// A colour solo's action: one per label there can be, though the column
/// lists only the labels on the rows (and the ones the filter holds).
String railSoloMarkActionId(LayerMark mark) =>
    'rail-solo-mark-${mark.keySlug}';

/// A kind solo's action: one per kind.
String railSoloKindActionId(LayerKind kind) => 'rail-solo-kind-${kind.name}';

/// The blend column's sweep to [mode] — one per mode it offers.
String railBlendActionId(LayerBlendMode mode) => 'rail-blend-${mode.name}';

/// The modes the blend column's sweep offers — its rows and their actions
/// are both made from this list. The sweep writes drawing rows; pass-through
/// is a group's answer alone.
final List<LayerBlendMode> railBlendModes = LayerBlendMode.optionsFor(
  isGroup: false,
);

EditorActionDefinition _railLegendAction(
  String id,
  String Function(AppLanguage language) name,
) => EditorActionDefinition.composed(
  id: id,
  name: name,
  shelf: ShortcutShelf.layerHeader,
  defaultActivators: const [],
  menuRow: true,
);

List<EditorActionDefinition> _railLegendActions() {
  AppStrings s(AppLanguage language) => AppStrings.of(language);
  return [
    _railLegendAction(
      RailLegendActionIds.sectionSe,
      (l) => s(l).tlShowSeRows,
    ),
    _railLegendAction(
      RailLegendActionIds.sectionCamera,
      (l) => s(l).tlShowCameraRows,
    ),
    _railLegendAction(
      RailLegendActionIds.sheetAllOn,
      (l) => s(l).tlAllOnTimesheet,
    ),
    _railLegendAction(
      RailLegendActionIds.sheetAllOff,
      (l) => s(l).tlAllOffTimesheet,
    ),
    _railLegendAction(
      RailLegendActionIds.soloSheet,
      (l) => s(l).tlSoloSheetOnRows,
    ),
    _railLegendAction(
      RailLegendActionIds.markFilterClear,
      (l) => s(l).tlClearMarkFilter,
    ),
    _railLegendAction(
      RailLegendActionIds.clipClear,
      (l) => s(l).tlClearAllClips,
    ),
    _railLegendAction(
      RailLegendActionIds.soloClip,
      (l) => s(l).tlSoloClips,
    ),
    _railLegendAction(
      RailLegendActionIds.fxEnableAll,
      (l) => s(l).tlApplyAllFx,
    ),
    _railLegendAction(
      RailLegendActionIds.fxBypassAll,
      (l) => s(l).tlBypassAllFx,
    ),
    _railLegendAction(RailLegendActionIds.soloFx, (l) => s(l).tlSoloFxOnRows),
    _railLegendAction(
      RailLegendActionIds.onionOnDisplayed,
      (l) => s(l).tlOnionOnDisplayedToggle,
    ),
    _railLegendAction(
      RailLegendActionIds.onionOpenPanel,
      (l) => s(l).tlOpenOnionPanel,
    ),
    _railLegendAction(
      RailLegendActionIds.eyeShowAll,
      (l) => '${s(l).tlColVisibility}: ${s(l).tlShowAll}',
    ),
    _railLegendAction(
      RailLegendActionIds.eyeHideAll,
      (l) => '${s(l).tlColVisibility}: ${s(l).tlHideAll}',
    ),
    for (final mark in everyLayerMark())
      if (!mark.isNone)
        _railLegendAction(
          railSoloMarkActionId(mark),
          (l) => '${s(l).tlSoloColor}: ${mark.labelFor(l)}',
        ),
    for (final kind in LayerKind.values)
      _railLegendAction(
        railSoloKindActionId(kind),
        (l) => '${s(l).tlSoloKind}: ${kind.labelFor(l)}',
      ),
    for (final mode in railBlendModes)
      _railLegendAction(
        railBlendActionId(mode),
        (l) => '${s(l).tlAllDisplayedLayers}: ${mode.labelFor(l)}',
      ),
  ];
}

/// The brush library's options menu (⋯) and the two buttons beside it as
/// actions — pressed in the library of the tool in hand, as its own row or
/// button would be (`BrushLibraryKeys`).
///
/// 🗣️I-40 (유저 2026-09-18 · I-40-Q1 10-08): the editing screen's command
/// buttons and menu rows. Named as the rail legend's rows are: by their own
/// words where they say what they do (「새 그룹」 · 「선택한 브러시 삭제」),
/// and with the menu's name first where they need it — a view switch's
/// word alone says nothing of what it switches (「브러시 옵션: 이름」).
abstract final class BrushLibraryActionIds {
  static const tipIcon = 'brush-library-tip-icon';
  static const strokePreview = 'brush-library-stroke-preview';
  static const name = 'brush-library-name';
  static const folderIcon = 'brush-library-folder-icon';
  static const folderName = 'brush-library-folder-name';
  static const newGroup = 'brush-library-new-group';
  static const renameGroup = 'brush-library-rename-group';
  static const deleteGroup = 'brush-library-delete-group';
  static const renameBrush = 'brush-library-rename-brush';
  static const deleteBrush = 'brush-library-delete-brush';
  static const exportBrush = 'brush-library-export-brush';
  static const exportGroup = 'brush-library-export-group';
  static const reset = 'brush-library-reset';
  static const importBrushes = 'brush-library-import';
  static const saveHeldBrush = 'brush-library-save-held-brush';
}

EditorActionDefinition _brushLibraryAction(
  String id,
  String Function(AppLanguage language) name, {
  bool menuRow = true,
  bool panelButton = false,
}) => EditorActionDefinition.composed(
  id: id,
  name: name,
  shelf: ShortcutShelf.brushLibrary,
  defaultActivators: const [],
  menuRow: menuRow,
  panelButton: panelButton,
);

List<EditorActionDefinition> _brushLibraryActions() {
  AppStrings s(AppLanguage language) => AppStrings.of(language);
  String inMenu(AppLanguage language, String word) =>
      '${s(language).brBrushOptions}: $word';
  return [
    // The two buttons left of the ⋯, in their order.
    _brushLibraryAction(
      BrushLibraryActionIds.importBrushes,
      (l) => s(l).brImportBrushes,
      menuRow: false,
      panelButton: true,
    ),
    _brushLibraryAction(
      BrushLibraryActionIds.saveHeldBrush,
      (l) => s(l).brSaveAsPreset,
      menuRow: false,
      panelButton: true,
    ),
    // The menu's rows, in its order.
    _brushLibraryAction(
      BrushLibraryActionIds.tipIcon,
      (l) => inMenu(l, s(l).brTipIcon),
    ),
    _brushLibraryAction(
      BrushLibraryActionIds.strokePreview,
      (l) => inMenu(l, s(l).brStrokePreview),
    ),
    _brushLibraryAction(
      BrushLibraryActionIds.name,
      (l) => inMenu(l, s(l).brName),
    ),
    _brushLibraryAction(
      BrushLibraryActionIds.folderIcon,
      (l) => inMenu(l, s(l).brFolderIcon),
    ),
    _brushLibraryAction(
      BrushLibraryActionIds.folderName,
      (l) => inMenu(l, s(l).brFolderName),
    ),
    _brushLibraryAction(BrushLibraryActionIds.newGroup, (l) => s(l).brNewGroup),
    _brushLibraryAction(
      BrushLibraryActionIds.renameGroup,
      (l) => s(l).brRenameGroup,
    ),
    _brushLibraryAction(
      BrushLibraryActionIds.deleteGroup,
      (l) => s(l).brDeleteGroup,
    ),
    _brushLibraryAction(
      BrushLibraryActionIds.renameBrush,
      (l) => s(l).brRenameSelected,
    ),
    _brushLibraryAction(
      BrushLibraryActionIds.deleteBrush,
      (l) => s(l).brDeleteSelected,
    ),
    _brushLibraryAction(
      BrushLibraryActionIds.exportBrush,
      (l) => s(l).brExportSelected,
    ),
    _brushLibraryAction(
      BrushLibraryActionIds.exportGroup,
      (l) => s(l).brExportGroup,
    ),
    _brushLibraryAction(
      BrushLibraryActionIds.reset,
      (l) => s(l).brResetLibrary,
    ),
  ];
}

/// The project settings' rows as actions, in the menu's order — each named
/// by the window it opens, since the row itself wears its value as it
/// stands (「FPS 24」), which no key could be called by.
List<EditorActionDefinition> _projectSettingsActions() {
  EditorActionDefinition opens(
    String id,
    String Function(AppStrings strings) title,
  ) => EditorActionDefinition.composed(
    id: id,
    name: (language) => title(AppStrings.of(language)),
    shelf: ShortcutShelf.settings,
    defaultActivators: const [],
    menuRow: true,
  );
  return [
    opens(EditorActionIds.projectFrameRate, (s) => s.projectFpsTitle),
    opens(EditorActionIds.projectAudioRate, (s) => s.tlProjectAudioRate),
    opens(EditorActionIds.projectCameraSize, (s) => s.cameraSizeTitle),
    opens(EditorActionIds.projectPlaybackMode, (s) => s.playbackMode),
  ];
}

String addEffectActionLabel(EffectKind kind, AppLanguage language) =>
    addEffectLabel(kind.labelFor(language), language);

/// 「{name} 추가」 — an Fx list's row, of a kind or of a plugin.
String addEffectLabel(String name, AppLanguage language) =>
    AppStrings.of(language).tlAddEffectTemplate.replaceAll('{name}', name);

/// The formats 「다른 이름으로 저장」 writes a picture in, in its second
/// level's order after the project — its rows and their actions are both
/// made from this list.
///
/// 🗣️backlog-21-Q1 (유저 2026-10-08): 「「다른 이름으로 저장」에 둘째 단 —
/// 프로젝트(.anicel) · PNG · JPG」 — and I-117-Q1 (유저 2026-10-21): the
/// four formats the export window learned then, after them: 「넷 다 넣음」.
/// The formats the answers name, and no more.
const saveAsImageFormats = [
  ExportStillFormat.png,
  ExportStillFormat.jpg,
  ExportStillFormat.bmp,
  ExportStillFormat.tga,
  ExportStillFormat.tiff,
  ExportStillFormat.webp,
];

/// Save As's picture rows as actions, one per format it writes.
///
/// 🗣️I-40: every menu row is an action. Named by composition —
/// 「다른 이름으로 저장: PNG」 — out of the word the row that opens them
/// wears and the format's own name. ⚠️Not [EditorActionIds.fileSaveAs]:
/// that one saves the PROJECT, and its row is the first of the three.
List<EditorActionDefinition> _saveAsImageActions() => [
  for (final format in saveAsImageFormats)
    EditorActionDefinition.composed(
      id: saveAsImageActionId(format),
      name: (language) => saveAsImageActionLabel(format, language),
      shelf: ShortcutShelf.file,
      defaultActivators: const [],
      menuRow: true,
    ),
];

String saveAsImageActionId(ExportStillFormat format) =>
    'file-save-as-${format.fileExtension}';

String saveAsImageActionLabel(ExportStillFormat format, AppLanguage language) =>
    '${AppStrings.of(language).saveAsTitle}: ${format.label}';

/// A blend action's name — 「합성: 곱하기」, 「Blend: Multiply」.
String blendModeActionLabel(BrushBlendMode mode, AppLanguage language) =>
    '${AppStrings.of(language).brBlend}: ${mode.labelFor(language)}';

/// The action that toggles [mark] — its button's, and the name the mark
/// wears wherever one of the two is picked: the mark-every window, and
/// Preferences ▸ Display's unnamed drawing (F-489).
String markToggleActionOf(InbetweenMark mark) => switch (mark) {
  InbetweenMark.one => EditorActionIds.frameToggleMarkOne,
  InbetweenMark.two => EditorActionIds.frameToggleMarkTwo,
};

/// Registry ids (referenced from dispatch and menu labels).
abstract final class EditorActionIds {
  static const framePrevious = 'frame-previous';
  static const frameNext = 'frame-next';
  static const drawingPrevious = 'drawing-previous';
  static const drawingNext = 'drawing-next';

  /// 🗣️I-15: 「단축키에 이동 추가 … 기본값을 … 스페이스바로」 — a HELD
  /// shortcut ([EditorActionDefinition.hold]).
  static const canvasPanHold = 'canvas-pan-hold';
  static const canvasRotateHold = 'canvas-rotate-hold';

  /// 「직전 획에서 직선」 (I-119), held as the pan is.
  static const canvasLineHold = 'canvas-line-hold';
  static const playbackToggle = 'playback-toggle';

  /// The frame panels' transport's 「처음으로」 (F-261).
  static const playbackToStart = 'playback-to-start';

  /// The playback bar's loop / play-once switch (I-40).
  static const playbackLoopToggle = 'playback-loop-toggle';
  static const voiceRecordToggle = 'voice-record-toggle';
  static const undo = 'edit-undo';
  static const redo = 'edit-redo';

  /// 확정 — `ConfirmVerb`. ↩️It was `selection-transform-commit`, and it
  /// committed a transform and nothing else (confirm-button).
  static const confirm = 'edit-confirm';

  /// The tools and their tiles (I-19). The shape tiles' ids are generated
  /// from their verb and shape — see `_shapeTileActions`.
  static const toolBrush = 'tool-brush';
  static const toolEraser = 'tool-eraser';
  static const toolEyedropper = 'tool-eyedropper';
  static const toolFill = 'tool-fill';
  static const toolFillBucket = 'tool-fill-bucket';
  static const toolText = 'tool-text';
  static const toolShape = 'tool-shape';
  static const toolGuide = 'tool-guide';
  static const toolSelect = 'tool-select';
  static const toolTransform = 'tool-transform';
  static const toolTransformNormal = 'tool-transform-normal';
  static const toolTransformFree = 'tool-transform-free';
  static const toolTransformMesh = 'tool-transform-mesh';
  static const toolCut = 'tool-cut';
  static const toolCutWhole = 'tool-cut-whole';
  static const toolCutStamp = 'tool-cut-stamp';
  static const selectionDeselect = 'selection-deselect';
  static const selectionInvert = 'selection-invert';
  static const selectionInvertInCanvas = 'selection-invert-in-canvas';
  static const layerUp = 'layer-up';
  static const layerDown = 'layer-down';
  static const selectionTransformCancel = 'selection-transform-cancel';
  static const onionSkinToggle = 'onion-skin-toggle';

  /// The frame panels' camera view switch, beside their transport (I-40).
  static const cameraViewToggle = 'camera-view-toggle';

  /// Buttons of panels (I-40), pressed through `PanelKeys` on a panel a key
  /// reaches ([EditorActionDefinition.panelButton]).
  static const guideAddSymmetry = 'guide-add-symmetry';
  static const guideAddPerspective = 'guide-add-perspective';
  static const textDeleteText = 'text-delete-text';
  static const mediaPoolImport = 'media-pool-import';
  static const timesheetFormat = 'timesheet-format';
  static const timesheetDataMode = 'timesheet-data-mode';
  static const conteFormat = 'conte-format';
  static const envelopeFormat = 'envelope-format';
  static const paletteNew = 'palette-new';

  /// The tool settings' own buttons (I-40), pressed the same way, as the
  /// settings of the tool in hand.
  static const transformFlipHorizontal = 'transform-flip-horizontal';
  static const transformFlipVertical = 'transform-flip-vertical';
  static const transformReset = 'transform-reset';
  static const cutStampPasteAtOrigin = 'cut-stamp-paste-at-origin';
  static const cutStampReset = 'cut-stamp-reset';
  static const cutStampRegisterTip = 'cut-stamp-register-tip';
  static const guideAddVanishingPoint = 'guide-add-vanishing-point';
  static const guideRasterize = 'guide-rasterize';
  static const textCentreAcross = 'text-centre-across';
  static const textCentreDown = 'text-centre-down';
  static const textIntoDrawing = 'text-into-drawing';

  static const canvasRotateCcw = 'canvas-rotate-ccw';
  static const canvasRotateCw = 'canvas-rotate-cw';
  static const canvasFlipHorizontal = 'canvas-flip-horizontal';

  /// The view pill's other view buttons (I-40): ↕, the straighten, fit and
  /// 1:1.
  static const canvasFlipVertical = 'canvas-flip-vertical';
  static const canvasStraighten = 'canvas-straighten';
  static const canvasFit = 'canvas-fit';
  static const canvasResetView = 'canvas-reset-view';
  static const timelineComma1 = 'timeline-comma-1';
  static const timelineComma2 = 'timeline-comma-2';
  static const timelineComma3 = 'timeline-comma-3';
  static const timelineComma4 = 'timeline-comma-4';
  static const timelineCommaN = 'timeline-comma-n';

  /// The film verbs. These are the buttons a rough pass wears out — a
  /// two-second three-comma test is about thirty presses of them — and
  /// until now they existed ONLY as toolbar icons, so there was nothing to
  /// bind a key to and nothing for a custom rail slot to point at.
  static const frameNewDrawing = 'frame-new-drawing';
  static const frameBlankExposure = 'frame-blank-exposure';
  /// I-130's two in-between marks: ○ mark 1, ● mark 2 — the ● keeping the
  /// id it had as the one mark, so a key bound to it stays on it.
  static const frameToggleMarkOne = 'frame-toggle-mark-one';
  static const frameToggleMarkTwo = 'frame-toggle-mark';
  static const frameMarkEvery = 'frame-mark-every';
  static const timelinePushBlocks = 'timeline-push-blocks';
  static const timelinePullBlocks = 'timeline-pull-blocks';

  /// The timeline bar's view actions (I-40): the zoom in and out of the panel
  /// being worked in — keys with no button since F-463 took the − and + off
  /// — and the timeline's ⇄ X-sheet.
  static const timelineZoomIn = 'timeline-zoom-in';
  static const timelineZoomOut = 'timeline-zoom-out';

  /// The zoom fit, right of the zoom's readout (I-111).
  static const timelineZoomFit = 'timeline-zoom-fit';
  static const timelineOrientationToggle = 'timeline-orientation-toggle';

  /// 🗣️I-19 (유저 2026-09-12): 「여러 단축키 기존 버튼에 연결. 우선
  /// 컨트롤c,v는 각각 타임라인 공용알약의 복사/링크붙여넣기로 연결 …
  /// 컨트롤x는 잘라내기, 컨트롤b는 독립붙여넣기? 백스페이스는 색변환의
  /// 픽셀비우기, 딜리트는 삭제버튼」 — each one the shared pill's own button.
  static const editCut = 'edit-cut';
  static const editCopy = 'edit-copy';
  static const editPasteLinked = 'edit-paste-linked';
  static const editPasteIndependent = 'edit-paste-independent';
  static const editDelete = 'edit-delete';

  /// 🗣️F-261 (유저 2026-10-02): 「아직 타임라인버튼 단축키에 등록안된거있음.
  /// 일단 편집버튼」 — the shared pill's Edit (T25).
  static const editInstance = 'edit-instance';

  /// 🗣️I-18 — 자동 이름 지정, the shared pill's button beside Edit.
  static const editAutoName = 'edit-auto-name';

  /// 🗣️I-45 — 링크 독립, the shared pill's button beside the linked paste.
  static const editUnlink = 'edit-unlink';

  /// 🗣️F-455 — 복제, the shared pill's button beside the delete (유저
  /// 2026-10-23: 「공용알약에 복제 버튼 만들고 레이어랑 컷버튼의
  /// 레이어복제/컷복제 삭제」).
  static const editDuplicate = 'edit-duplicate';

  /// 🗣️I-78 — 병합, the shared pill's button beside 복제 (유저 2026-10-06:
  /// 「프레임도 사용가능할거같으니 공용알약에 두는걸 생각중」).
  static const editMerge = 'edit-merge';

  /// The colour edit list's five verbs, in its order — every one an action
  /// (유저 2026-09-13: 「그 외 같이있는 버튼들도 다 숏컷 지정가능하게」).
  static const editReplaceColour = 'edit-replace-colour';
  static const editDeleteColour = 'edit-delete-colour';
  static const editKeepColour = 'edit-keep-colour';
  static const editClearPixels = 'edit-clear-pixels';

  /// 2치화 (I-13).
  static const editBinarize = 'edit-binarize';

  /// Its clipboard rows — 픽셀 잘라내기 (I-90), 픽셀 복사 and the two pastes
  /// (I-55).
  static const editCutPixels = 'edit-cut-pixels';
  static const editCopyPixels = 'edit-copy-pixels';
  static const editPastePixelsAbove = 'edit-paste-pixels-above';
  static const editPastePixelsBelow = 'edit-paste-pixels-below';

  /// 「컨트롤s로 저장 로직 연결, 컨트롤쉬프트s로 다른이름저장」.
  static const fileSave = 'file-save';
  static const fileSaveAs = 'file-save-as';

  /// 🗣️I-40: the rest of the top strip's two menus, each id the id its row
  /// has always been keyed and worded by (`menu-<id>`).
  static const fileNew = 'file-new';
  static const fileOpen = 'file-open';
  static const fileOpenFolder = 'file-open-folder';
  static const fileBackUpFailedCopy = 'file-back-up-failed-copy';
  static const fileExport = 'file-export';
  static const workSettings = 'work-settings';

  /// The project settings' rows (I-40), one level under the ⚙ — each opens
  /// its own change window.
  static const projectFrameRate = 'project-frame-rate';
  static const projectAudioRate = 'project-audio-rate';
  static const projectCameraSize = 'project-camera-size';
  static const projectPlaybackMode = 'project-playback-mode';
  static const keyboardShortcuts = 'edit-keyboard-shortcuts';
  static const preferences = 'edit-preferences';
  static const about = 'help-about';

  /// 🗣️I-139 (유저 2026-10-28): 「의견 보내기」 under 「Anicel 정보」 — one row,
  /// a window that chooses between the two feedback forms (I-139-Q2).
  static const sendFeedback = 'help-send-feedback';
  static const inputInspector = 'edit-input-inspector';
  static const frameTimingOverlay = 'edit-frame-timing-overlay';
  static const frameStats = 'edit-frame-stats';
  static const showRepaints = 'edit-show-repaints';
  static const toolRailOnRight = 'window-tool-rail-right';
  static const regionOnTop = 'window-region-on-top';

  /// Where the brush's values stand — the top strip, or the canvas's pill
  /// (I-34).
  static const brushValuesOnStrip = 'window-brush-values-on-strip';

  /// Whether the tool strip holds its tools alone — no shortcut buttons
  /// (undo, redo, onion, solo …) above them (I-128).
  static const railToolsOnly = 'window-rail-tools-only';

  /// The window's full screen (I-103-Q2) — the desktops' only.
  static const fullScreen = 'window-full-screen';

  /// The floating region's fold chevron (I-40).
  static const regionFold = 'window-region-fold';
  static const resetLayout = 'window-reset-layout';

  /// 「= 버튼은 활성레이어 솔로 버튼으로 연결」 — the legend eye menu's solo.
  /// ↩️The key is T since F-261. ↩️Q since I-63.
  static const layerVisibilitySolo = 'layer-visibility-solo';

  /// 🗣️I-63 ③ (유저 2026-10-03): 「프레임 추가랑 레이어 추가버튼도 단축키
  /// 기본값 등록하고싶음」 — the layer pill's ＋.
  static const layerAdd = 'layer-add';

  /// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록. 타임라인
  /// 버튼같은거나」 — the timeline bar's menus: the cut pill's one (and its
  /// ＋), the layer pill's two, the frame pill's. Where the retired menu bar
  /// worded a row by an id (`menuAction.<id>`), the action keeps that id.
  static const cutNew = 'cut-new';
  static const cutCreateLinked = 'cut-create-linked';
  static const cutEditNote = 'cut-edit-note';
  static const cutSettings = 'cut-settings';
  static const cutCanvasSize = 'cut-canvas-size';
  static const cutConvertLinked = 'cut-convert-linked';
  static const layerDetach = 'layer-detach';
  static const layerRasterize = 'layer-rasterize';
  static const layerStoryboard = 'layer-storyboard';
  static const layerAttachFreeAbove = 'layer-attach-free-above';
  static const layerAttachFreeBelow = 'layer-attach-free-below';
  static const layerAttachSyncedAbove = 'layer-attach-synced-above';
  static const layerAttachSyncedBelow = 'layer-attach-synced-below';
  static const frameSelectRowSpan = 'frame-select-row-span';

  /// The frame pill's standing switch (F-61), a button rather than a row.
  static const frameAutoCreate = 'frame-auto-create';

  /// 「캔버스 확대축소버튼. 키보드에서 shift+>(확대) shift+<(축소). 배율은
  /// 설정에 줌 스냅 설정한대로」. ↩️The keys are Shift+E and Shift+Q since
  /// F-261.
  static const canvasZoomIn = 'canvas-zoom-in';
  static const canvasZoomOut = 'canvas-zoom-out';
}

/// The default action set. Tools and transport follow PS/CSP convention.
final List<EditorActionDefinition> editorActionDefinitions = [
  // 🗣️F-241 (유저 2026-09-29): 「이전/다음 프레임, 이전/다음 블록, 위/아래
  // 레이어 이렇게 개편」 — SIX moves, named by what they do, all on the
  // arrows. Their arrows are written as the timeline reads them and turn
  // with the X-sheet ([EditorActionDefinition.sheetMove]).
  // ↩️The Ctrl+arrows were four DIRECTION actions of their own (F-28: 「Step
  // Left」 …): 「이전프레임이랑 왼쪽으로 한걸음이랑 똑같은데 … 싹 삭제」.
  // The one-frame arrow is Shift now: 「컨트롤+화살표가 아니라
  // 쉬프트+화살표로 변경」 — and it is the frame's ONLY key: 「이전/다음
  // 프레임은 ,.가 아니라 쉬프트<>만이야. ,.는 삭제」. A block's second key,
  // Ctrl+`,`/`.`, was never asked for: 「이전원화 다음원화는 왜 단축키
  // 두개인지? … 컨트롤+, 이런건 삭제. 절대 멋대로 넣지말고 넣을땐 보고할것」.
  // ↩️F-261 (유저 2026-10-02) ASKED for the second set: 「프레임이동은 배치
  // 바꾼다기보단 배치 추가. ws 위아래, ad 좌우(프레임)이동. 1프레임씩
  // 이동하는거도 동일하게 쉬프트a 쉬프트d」 — WASD beside the arrows, turning
  // with the sheet as the arrows do ([SheetKeys]).
  const EditorActionDefinition(
    id: EditorActionIds.framePrevious,
    label: 'Previous Frame',
    shelf: ShortcutShelf.moves,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true),
      SingleActivator(LogicalKeyboardKey.keyA, shift: true),
    ],
    sheetMove: (arrow: SheetArrow.left, fine: true),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameNext,
    label: 'Next Frame',
    shelf: ShortcutShelf.moves,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowRight, shift: true),
      SingleActivator(LogicalKeyboardKey.keyD, shift: true),
    ],
    sheetMove: (arrow: SheetArrow.right, fine: true),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.drawingPrevious,
    label: 'Previous Block',
    shelf: ShortcutShelf.moves,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowLeft),
      SingleActivator(LogicalKeyboardKey.keyA),
    ],
    sheetMove: (arrow: SheetArrow.left, fine: false),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.drawingNext,
    label: 'Next Block',
    shelf: ShortcutShelf.moves,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowRight),
      SingleActivator(LogicalKeyboardKey.keyD),
    ],
    sheetMove: (arrow: SheetArrow.right, fine: false),
  ),
  // The DISPLAYED layer rows (TVP layer nav, UI-R20 #14). ↩️With a live
  // selection the arrows used to NUDGE it (Photoshop behavior) — 유저
  // 2026-09-12: 「선택툴 선택한채로 화살표키누르면 그림 이동되는데 왜 멋대로
  // 넣은거지? 기능부터 잔존코드 싹 삭제」 (F-86).
  const EditorActionDefinition(
    id: EditorActionIds.layerUp,
    label: 'Layer Up',
    shelf: ShortcutShelf.moves,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowUp),
      SingleActivator(LogicalKeyboardKey.keyW),
    ],
    sheetMove: (arrow: SheetArrow.up, fine: false),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.layerDown,
    label: 'Layer Down',
    shelf: ShortcutShelf.moves,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowDown),
      SingleActivator(LogicalKeyboardKey.keyS),
    ],
    sheetMove: (arrow: SheetArrow.down, fine: false),
  ),
  // 🗣️I-15 (유저 2026-09-11): 「손바닥 툴을 만들지는 않음. 다만 단축키에
  // 이동? 추가하는건 추가하고, 기본값을 휠클릭이 아니라 스페이스바로
  // 이동」 — held, not pressed: while Space is down a primary drag pans.
  // 🗣️F-241: 「이동 누르는동안은 프레임관련이아니고 캔버스관련이잖아」 — it
  // moves the canvas, so it stands with the canvas view's keys.
  const EditorActionDefinition(
    id: EditorActionIds.canvasPanHold,
    label: 'Pan (hold)',
    shelf: ShortcutShelf.view,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.space)],
    hold: true,
  ),
  // 🗣️I-88 (유저 2026-10-09): 「키보드유저용 캔버스 쉽게 회전하려고 지금
  // 스페이스바는 이동이니까 스페이스바+컨트롤상태에선 회전으로 작동하도록」 —
  // held as the pan is, and a primary drag turns the view about its middle.
  // ↩️I-88-Q1 (유저 2026-10-10): 「Anicel 배치도 Shift+Space」 — 「굳이
  // 컨트롤+스페이스 일 필요는없음. 통일해서 작동만하면됨. 클튜 키라면
  // 검증된거란거니 좋네」. Ctrl is ⌘ on a Mac or an iPad, and ⌘+Space is
  // Spotlight there, so Ctrl+Space never reached the app; Clip Studio's
  // Shift+Space does, on every device.
  const EditorActionDefinition(
    id: EditorActionIds.canvasRotateHold,
    label: 'Rotate (hold)',
    shelf: ShortcutShelf.view,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.space, shift: true),
    ],
    hold: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.playbackToggle,
    label: 'Play / Pause',
    shelf: ShortcutShelf.playback,
    // PEN-7b: four-finger tap = play/pause (the Callipeg convention the
    // user picked), beside the 2-tap undo / 3-tap redo family.
    defaultTouchGesture: 'fourFingerTap',
    // I-15: 「기존 재생단축키가 스페이스바인데 그냥 해제」 — Space is the
    // pan hold now. Every action stays assignable in the dialog.
    // ↩️F-261 (유저 2026-10-02): 「자주쓰는 버튼 그냥 직관적이지 않더라도
    // 왼쪽으로 몰아넣을까 … 재생/정지버튼은 S로두고 처음으로버튼 A, 그리고
    // 편집버튼은 D로두자」 — the left hand's keys, whatever the letter says.
    // ↩️And once WASD walked the sheet (same day): 「올가미를 z, 편집을 x,
    // 처음으로를 쉬프트z, 재생을 쉬프트x」.
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyX, shift: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.playbackToStart,
    label: 'To Start',
    shelf: ShortcutShelf.playback,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyZ, shift: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.playbackLoopToggle,
    label: 'Loop / Play Once',
    shelf: ShortcutShelf.playback,
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.voiceRecordToggle,
    label: 'Record Voice (start/stop)',
    shelf: ShortcutShelf.playback,
    // REC1-B: Ctrl+R, REAPER's record key — plain R stays the drawing-app
    // canvas-rotate convention this app already follows.
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyR, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.undo,
    label: 'Undo',
    shelf: ShortcutShelf.edit,
    // Procreate's muscle memory: two-finger tap = undo.
    defaultTouchGesture: 'twoFingerTap',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyZ, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.redo,
    label: 'Redo',
    shelf: ShortcutShelf.edit,
    // Procreate's muscle memory: three-finger tap = redo.
    defaultTouchGesture: 'threeFingerTap',
    // 🪦Ctrl+Y redid as well — a second key on one action, retired
    // 2026-09-13: 「다시실행 중복할당된거 제거하고 잔재도 제거해」. Ctrl+Y is
    // 자유 변형 now.
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true),
    ],
  ),
  // 🗣️I-119 (유저 2026-10-21): 「브러시 도구(브러시,지우개) 전용기능,
  // 컨트롤키 누르고있으면 저번에 찍은 마지막 dab? 점 부터 현재 호버중인
  // 커서까지 라이브로 직선 보여주고 … 거기서 찍으면 직선 그림」 — held, as
  // the pan is. ↩️Asked for on Ctrl, which is every shortcut's modifier
  // too; I-119-Q1: 「그럼 컨트롤 말고 다른 키로 배치하자. 추천대로」 — Z, the
  // one letter left free under the left hand. ⚠️Bare Z was left free ON
  // PURPOSE (I-63, the lasso tile's key above); whether the line may have
  // it is asked on the board (I-119-Q3). Clip Studio and TVPaint have no
  // key for this, so their presets leave it without one (F-417-Q1).
  const EditorActionDefinition(
    id: EditorActionIds.canvasLineHold,
    label: 'Line from the Last Stroke (hold)',
    shelf: ShortcutShelf.edit,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyZ)],
    hold: true,
  ),
  // I-40: the stamp's three buttons — under Edit, where a paste in place
  // and a picture made a brush stand in the programs people come from.
  EditorActionDefinition.composed(
    id: EditorActionIds.cutStampPasteAtOrigin,
    name: (language) => AppStrings.of(language).toolCutPasteAtOrigin,
    shelf: ShortcutShelf.edit,
    defaultActivators: const [],
    panelButton: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.cutStampReset,
    label: 'Reset Stamp',
    shelf: ShortcutShelf.edit,
    defaultActivators: [],
    panelButton: true,
  ),
  EditorActionDefinition.composed(
    id: EditorActionIds.cutStampRegisterTip,
    name: (language) => AppStrings.of(language).toolCutRegisterTip,
    shelf: ShortcutShelf.edit,
    defaultActivators: const [],
    panelButton: true,
  ),
  // 🗣️I-19 (유저 2026-09-12): keys for buttons that already exist — the
  // shared pill's clipboard, its delete and the colour edit's clear. Each
  // label is the BUTTON's own name, so its tooltip and this list cannot
  // call one verb two things. ⚠️`control` in every default here is the
  // platform's COMMAND key: ⌘ on a Mac or an iPad (`platformActivator`).
  const EditorActionDefinition(
    id: EditorActionIds.editCut,
    label: 'Cut',
    shelf: ShortcutShelf.sharedPill,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyX, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editCopy,
    label: 'Copy',
    shelf: ShortcutShelf.sharedPill,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyC, control: true),
    ],
  ),
  // 🚨F-156 (유저 2026-09-17): 「붙여넣기 기본값 단축키 변경. 독립 붙여넣기를
  // 컨트롤+v로, 링크 붙여넣기를 컨트롤+b로」 — V is the INDEPENDENT paste,
  // the one an ordinary program's Ctrl+V does, and the link takes B.
  // ↩️It was the other way round: 「컨트롤c,v는 각각 타임라인 공용알약의
  // 복사/링크붙여넣기로」. ㉕: the independent paste makes the copied cel's
  // content a cel of its OWN — named for what it makes rather than for what
  // it is not.
  const EditorActionDefinition(
    id: EditorActionIds.editPasteLinked,
    label: 'Paste linked',
    shelf: ShortcutShelf.sharedPill,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyB, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editPasteIndependent,
    label: 'Paste independent',
    shelf: ShortcutShelf.sharedPill,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyV, control: true),
    ],
  ),
  // 🗣️I-45 (유저 2026-09-20): 「링크 독립버튼. 위치는 타임라인의 공용
  // 알약부분?」 — a button, so a row a key can be put on (유저 2026-09-13:
  // 「버튼이면 왠만해선 숏컷 지정 가능하게 리스트로 올리는걸 기본으로」). It
  // ships unbound: nobody named a key. The words are the user's own for it,
  // 「링크 독립」, and they live here now — the button wears this name.
  const EditorActionDefinition(
    id: EditorActionIds.editUnlink,
    label: 'Make independent',
    shelf: ShortcutShelf.sharedPill,
    defaultActivators: [],
  ),
  // Bare Delete and Backspace: a focused text field keeps both (bare keys
  // stand down there), so they never reach a pill while you are typing.
  const EditorActionDefinition(
    id: EditorActionIds.editDelete,
    label: 'Delete',
    shelf: ShortcutShelf.sharedPill,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.delete)],
  ),
  // 🗣️F-455 — a button, so a row a key can be put on (유저 2026-09-13:
  // 「버튼이면 왠만해선 숏컷 지정 가능하게」). It ships unbound: nobody named a
  // key.
  const EditorActionDefinition(
    id: EditorActionIds.editDuplicate,
    label: 'Duplicate',
    shelf: ShortcutShelf.sharedPill,
    defaultActivators: [],
  ),
  // 🗣️I-78 — a button, so a row a key can be put on; unbound, as nobody
  // named a key. ⚠️Neither program's table names it: neither program's
  // command for it is in hand from its own references (I-88).
  const EditorActionDefinition(
    id: EditorActionIds.editMerge,
    label: 'Merge',
    shelf: ShortcutShelf.sharedPill,
    defaultActivators: [],
  ),
  // 🗣️I-18 (유저): 「타임라인 공용 알약에 새 버튼 신설 … 버튼은 자동 이름
  // 지정」 — a button, so a row a key can be put on (유저 2026-09-13:
  // 「버튼이면 왠만해선 숏컷 지정 가능하게」). It ships unbound: nobody named a
  // key. The label is the button's own, and no action's name carries a '…'
  // (B9, F-437).
  // 🗣️F-261: the Edit beside it — D, with the left hand's other keys (see
  // the play key). ↩️X once D walked right (「편집을 x」). ↩️I-63 (유저
  // 2026-10-03): 「지금 편집버튼 x인데 쉬프트+f로」 — X is the lasso
  // select's now.
  const EditorActionDefinition(
    id: EditorActionIds.editInstance,
    label: 'Edit',
    shelf: ShortcutShelf.sharedPill,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyF, shift: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editAutoName,
    label: 'Auto Name',
    shelf: ShortcutShelf.sharedPill,
    defaultActivators: [],
  ),
  // 🗣️유저 2026-09-13: 「색변환의 픽셀비우기를 백스페이스로 하란건, 그 외
  // 같이있는 버튼들도 다 숏컷 지정가능하게 등록하란거는 앞으로의 규칙이야.
  // 버튼이면 왠만해선 숏컷 지정 가능하게 리스트로 올리는걸 기본으로 두고
  // 싶어」 — the colour edit list's rows, in its order; Backspace is the
  // one key the list ships with.
  const EditorActionDefinition(
    id: EditorActionIds.editReplaceColour,
    label: 'Replace Color',
    shelf: ShortcutShelf.colourEdit,
    defaultActivators: [],
    pixelVerb: CelPixelVerb.replaceColour,
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editDeleteColour,
    label: 'Delete Color',
    shelf: ShortcutShelf.colourEdit,
    defaultActivators: [],
    pixelVerb: CelPixelVerb.deleteColour,
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editKeepColour,
    label: 'Keep Color',
    shelf: ShortcutShelf.colourEdit,
    defaultActivators: [],
    pixelVerb: CelPixelVerb.keepColour,
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editClearPixels,
    label: 'Clear Pixels',
    shelf: ShortcutShelf.colourEdit,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.backspace)],
    pixelVerb: CelPixelVerb.clearPixels,
    menuRow: true,
  ),
  // 🗣️I-13 (유저 2026-10-16): 2치화, under 픽셀 비우기 (Q1 = a). No key
  // ships with it: none was named.
  const EditorActionDefinition(
    id: EditorActionIds.editBinarize,
    label: 'Binarize',
    shelf: ShortcutShelf.colourEdit,
    defaultActivators: [],
    pixelVerb: CelPixelVerb.binarize,
    menuRow: true,
  ),
  // 🗣️I-55 (유저 2026-10-01): the list's clipboard rows, under the same rule
  // — actions, in the list's order. No key ships with them: none was named.
  // I-90 (10-10) added 픽셀 잘라내기 above 픽셀 복사, and named no key either.
  const EditorActionDefinition(
    id: EditorActionIds.editCutPixels,
    label: 'Cut Pixels',
    shelf: ShortcutShelf.colourEdit,
    defaultActivators: [],
    pixelClipboardVerb: PixelClipboardVerb.cut,
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editCopyPixels,
    label: 'Copy Pixels',
    shelf: ShortcutShelf.colourEdit,
    defaultActivators: [],
    pixelClipboardVerb: PixelClipboardVerb.copy,
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editPastePixelsAbove,
    label: 'Paste Pixels Above',
    shelf: ShortcutShelf.colourEdit,
    defaultActivators: [],
    pixelClipboardVerb: PixelClipboardVerb.pasteAbove,
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editPastePixelsBelow,
    label: 'Paste Pixels Below',
    shelf: ShortcutShelf.colourEdit,
    defaultActivators: [],
    pixelClipboardVerb: PixelClipboardVerb.pasteBelow,
    menuRow: true,
  ),
  // 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록 … 뭐든
  // 모든 버튼」 — the project menu's rows, in the menu's order. Each is the
  // row itself ([EditorActionDefinition.menuRow]); none but the two saves
  // ships with a key: nobody named one.
  const EditorActionDefinition(
    id: EditorActionIds.fileNew,
    label: 'New project',
    shelf: ShortcutShelf.file,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.fileOpen,
    label: 'Open File',
    shelf: ShortcutShelf.file,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.fileOpenFolder,
    label: 'Open Folder',
    shelf: ShortcutShelf.file,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.fileSave,
    label: 'Save',
    shelf: ShortcutShelf.file,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyS, control: true),
    ],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.fileSaveAs,
    label: 'Save as',
    shelf: ShortcutShelf.file,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true),
    ],
    menuRow: true,
  ),
  ..._saveAsImageActions(),
  const EditorActionDefinition(
    id: EditorActionIds.fileBackUpFailedCopy,
    label: 'Back up failed copy',
    shelf: ShortcutShelf.file,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.fileExport,
    label: 'Export',
    shelf: ShortcutShelf.file,
    defaultActivators: [],
    menuRow: true,
  ),
  // 🗣️I-19 (유저 2026-09-13): 「툴 내의 세부툴도 숏컷 지정 가능하게 하려고.
  // 툴 자체에 설정할수도있고 툴 내부의 세부툴도 설정가능하게」. ★Every rail
  // tool and every tile of the tool library is an action, in rail order, and
  // each row says what it presses ([EditorActionDefinition.toolPress]).
  //
  // 🪦Three keys that had grown up beside the tools are gone. V was the MOVE
  // tool's (R11-8a, 「PS/CSP muscle memory」) — 「이동툴이라기보단 그냥
  // 변형툴이잖아. v 삭제하고 v 관련 잔재있으면 삭제」. M and L were the
  // rectangle and lasso TOOLS from before the outline became a setting
  // (R17-U) — 「선택 도구도 M이랑 L 있는거 의문이고, 변형툴처럼 법 통일해서
  // 잔재제거」.
  const EditorActionDefinition(
    id: EditorActionIds.toolBrush,
    label: 'Brush Tool',
    shelf: ShortcutShelf.tools,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyB)],
    toolPress: RailToolPress(CanvasTool.brush),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolEraser,
    label: 'Eraser Tool',
    shelf: ShortcutShelf.tools,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyE)],
    toolPress: RailToolPress(CanvasTool.eraser),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolEyedropper,
    label: 'Eyedropper Tool',
    shelf: ShortcutShelf.tools,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyI)],
    toolPress: RailToolPress(CanvasTool.eyedropper),
  ),
  // 「채우기툴을 f로 변경하고」 — it was G.
  const EditorActionDefinition(
    id: EditorActionIds.toolFill,
    label: 'Fill Tool',
    shelf: ShortcutShelf.tools,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyF)],
    toolPress: RailToolPress(CanvasTool.fill),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolFillBucket,
    label: 'Bucket',
    shelf: ShortcutShelf.toolTiles,
    defaultActivators: [],
    toolPress: ToolTilePress(CanvasTool.fill),
  ),
  ..._shapeTileActions(CanvasTool.fillShape),
  // R9-rest: no key of its own — a bare T solos the active layer (F-261),
  // and a person binds what they want.
  const EditorActionDefinition(
    id: EditorActionIds.toolText,
    label: 'Text Tool',
    shelf: ShortcutShelf.tools,
    defaultActivators: [],
    toolPress: RailToolPress(CanvasTool.text),
  ),
  // I-40: the text tool's settings' 🗑 — the text in hand goes — and its
  // 래스터라이즈, the text in hand made drawing.
  EditorActionDefinition.composed(
    id: EditorActionIds.textDeleteText,
    name: (language) => AppStrings.of(language).textToolDeleteText,
    shelf: ShortcutShelf.texts,
    defaultActivators: const [],
    panelButton: true,
  ),
  // I-95: the two under the text tool's X and Y that stand the text in hand
  // on the canvas's middle lines — named in their buttons' own words, as
  // 래스터라이즈 is.
  EditorActionDefinition.composed(
    id: EditorActionIds.textCentreAcross,
    name: (language) => AppStrings.of(language).textToolCentreAcross,
    shelf: ShortcutShelf.texts,
    defaultActivators: const [],
    panelButton: true,
  ),
  EditorActionDefinition.composed(
    id: EditorActionIds.textCentreDown,
    name: (language) => AppStrings.of(language).textToolCentreDown,
    shelf: ShortcutShelf.texts,
    defaultActivators: const [],
    panelButton: true,
  ),
  EditorActionDefinition.composed(
    id: EditorActionIds.textIntoDrawing,
    name: (language) => AppStrings.of(language).textToolIntoDrawing,
    shelf: ShortcutShelf.texts,
    defaultActivators: const [],
    panelButton: true,
  ),
  // I-69: no key of its own, nor its tiles' — a person binds what they
  // want.
  const EditorActionDefinition(
    id: EditorActionIds.toolShape,
    label: 'Shape Tool',
    shelf: ShortcutShelf.tools,
    defaultActivators: [],
    toolPress: RailToolPress(CanvasTool.shape),
  ),
  ..._shapeTileActions(CanvasTool.shape),
  // 「가이드 툴을 g로 지정」.
  const EditorActionDefinition(
    id: EditorActionIds.toolGuide,
    label: 'Guide Tool',
    shelf: ShortcutShelf.tools,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyG)],
    toolPress: RailToolPress(CanvasTool.guide),
  ),
  // I-40: the guide list's two ＋ — one a kind of guide.
  const EditorActionDefinition(
    id: EditorActionIds.guideAddSymmetry,
    label: 'New symmetry guide',
    shelf: ShortcutShelf.guides,
    defaultActivators: [],
    panelButton: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.guideAddPerspective,
    label: 'New perspective guide',
    shelf: ShortcutShelf.guides,
    defaultActivators: [],
    panelButton: true,
  ),
  // And the settings' ＋ of the perspective guide picked in that list.
  EditorActionDefinition.composed(
    id: EditorActionIds.guideAddVanishingPoint,
    name: (language) => AppStrings.of(language).guideAddVanishingPoint,
    shelf: ShortcutShelf.guides,
    defaultActivators: const [],
    panelButton: true,
  ),
  // …and its 래스터라이즈 (vanishing-point-types-Q5).
  EditorActionDefinition.composed(
    id: EditorActionIds.guideRasterize,
    name: (language) => AppStrings.of(language).guideRasterize,
    shelf: ShortcutShelf.guides,
    defaultActivators: const [],
    panelButton: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolSelect,
    label: 'Select Tool',
    shelf: ShortcutShelf.tools,
    defaultActivators: [],
    toolPress: RailToolPress(CanvasTool.select),
  ),
  ..._shapeTileActions(CanvasTool.select),
  const EditorActionDefinition(
    id: EditorActionIds.toolTransform,
    label: 'Transform Tool',
    shelf: ShortcutShelf.tools,
    defaultActivators: [],
    toolPress: RailToolPress(CanvasTool.move),
  ),
  // R26 #17: Ctrl+T is not a transform of its own — it arms the transform
  // TOOL, so one code path (and one set of guards) owns transforming. And it
  // arms it in a MODE now: 「그냥 변형이 아니라 일반변형에 컨트롤+t로
  // 연결하고 퍼스변형 이름을 자유변형으로 바꾸고, 자유변형을 컨트롤+y로」.
  const EditorActionDefinition(
    id: EditorActionIds.toolTransformNormal,
    label: 'Normal Transform',
    shelf: ShortcutShelf.toolTiles,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyT, control: true),
    ],
    toolPress: TransformModePress(TransformMode.normal),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolTransformFree,
    label: 'Free Transform',
    shelf: ShortcutShelf.toolTiles,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyY, control: true),
    ],
    toolPress: TransformModePress(TransformMode.perspective),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolTransformMesh,
    label: 'Mesh Warp',
    shelf: ShortcutShelf.toolTiles,
    defaultActivators: [],
    toolPress: TransformModePress(TransformMode.mesh),
  ),
  // ↩️「잘라내기는 잘라내기 툴 자체에 c로 설정」 (09-13) gave C to the tool
  // itself; I-53 (09-28) moved it to the lasso cut's tile — see
  // `_shapeTileActions`.
  const EditorActionDefinition(
    id: EditorActionIds.toolCut,
    label: 'Cut Tool',
    shelf: ShortcutShelf.tools,
    defaultActivators: [],
    toolPress: RailToolPress(CanvasTool.cut),
  ),
  ..._shapeTileActions(CanvasTool.cut),
  // 🗣️I-28 (유저 2026-09-30): 「잘라내기 툴의 도구 라이브러리에 전체 잘라내기
  // 신설」 — a tile that runs at the press (I-28-Q2), and so a key that does.
  const EditorActionDefinition(
    id: EditorActionIds.toolCutWhole,
    label: 'Whole Picture Cut',
    shelf: ShortcutShelf.toolTiles,
    defaultActivators: [],
    toolPress: CutWholePress(),
  ),
  // 🗣️I-53 (유저 2026-09-28): 「스탬프를 v로」. ↩️V alone was retired from
  // the move tool on 09-13 (「v 삭제하고 v 관련 잔재있으면 삭제」) — the
  // key left that tool; this is the user handing it to another.
  const EditorActionDefinition(
    id: EditorActionIds.toolCutStamp,
    label: 'Stamp',
    shelf: ShortcutShelf.toolTiles,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyV)],
    toolPress: ToolTilePress(CanvasTool.cutStamp),
  ),
  ..._blendModeActions(),
  const EditorActionDefinition(
    id: EditorActionIds.selectionDeselect,
    label: 'Deselect',
    shelf: ShortcutShelf.selection,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyD, control: true),
    ],
  ),
  // Enter is 확정 — the last stroke laid down again, or 적용 while the
  // transform tool is up (`ConfirmVerb`); Escape cancels a transform. Text
  // fields keep both (bare keys stand down).
  const EditorActionDefinition(
    id: EditorActionIds.confirm,
    label: 'Confirm',
    shelf: ShortcutShelf.selection,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.enter),
      SingleActivator(LogicalKeyboardKey.numpadEnter),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.selectionTransformCancel,
    label: 'Cancel Transform',
    shelf: ShortcutShelf.selection,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.escape)],
  ),
  // I-40: the Select and Transform tools' settings buttons. Their 다각형
  // 닫기 and 적용 are 확정's own halves and name it ([confirm]).
  //
  // 🗣️선택 반전 is not pressed AS the settings: it answers whatever tool is
  // in hand, as 선택 해제 does (유저 2026-10-11, I-40-Q8: 「어느
  // 도구에서나(선택 해제처럼)」). Its button keeps its place in the Select
  // tool's settings and runs the same verb. Its two walls are two actions
  // (I-108); the keys it had stay with the wall it had.
  EditorActionDefinition.composed(
    id: EditorActionIds.selectionInvertInCanvas,
    name: (language) => AppStrings.of(language).selectionInvertInCanvas,
    shelf: ShortcutShelf.selection,
    defaultActivators: const [],
  ),
  EditorActionDefinition.composed(
    id: EditorActionIds.selectionInvert,
    name: (language) => AppStrings.of(language).selectionInvert,
    shelf: ShortcutShelf.selection,
    defaultActivators: const [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.transformFlipHorizontal,
    label: 'Flip Transform Horizontal',
    shelf: ShortcutShelf.selection,
    defaultActivators: [],
    panelButton: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.transformFlipVertical,
    label: 'Flip Transform Vertical',
    shelf: ShortcutShelf.selection,
    defaultActivators: [],
    panelButton: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.transformReset,
    label: 'Reset Transform',
    shelf: ShortcutShelf.selection,
    defaultActivators: [],
    panelButton: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.onionSkinToggle,
    label: 'Toggle Onion Skin',
    shelf: ShortcutShelf.view,
    // 🗣️F-261 (유저 2026-10-02): 「우선 어니언스킨을 Q로」 — the left hand's.
    // ↩️I-63 (유저 2026-10-03): 「활성레이어솔로 그냥 q로 이동,
    // 어니언스킨을 t로이동」 — the two trade places.
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyT)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.cameraViewToggle,
    label: 'Toggle Camera View',
    shelf: ShortcutShelf.timelineBar,
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.canvasRotateCcw,
    label: 'Rotate Canvas View Left',
    shelf: ShortcutShelf.view,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyR)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.canvasRotateCw,
    label: 'Rotate Canvas View Right',
    shelf: ShortcutShelf.view,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyR, shift: true)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.canvasFlipHorizontal,
    label: 'Flip Canvas View Horizontal',
    shelf: ShortcutShelf.view,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyH)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.canvasFlipVertical,
    label: 'Flip Canvas View Vertical',
    shelf: ShortcutShelf.view,
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.canvasStraighten,
    label: 'Straighten Canvas View',
    shelf: ShortcutShelf.view,
    defaultActivators: [],
  ),
  // Fit and 1:1 land a zoom, as the ± steps do — so they pass playback where
  // the steps pass (R6q3: 「재생 중 줌은 입력 수단과 무관하게 한 법으로」;
  // the pill's own buttons sit in the canvas chrome the hole lets through).
  const EditorActionDefinition(
    id: EditorActionIds.canvasFit,
    label: 'Fit Canvas View',
    shelf: ShortcutShelf.view,
    defaultActivators: [],
    zoomsView: true,
  ),
  // ↩️F-381: 1:1 put the whole view back, and was named for it; it lands the
  // zoom alone now. ⛔The id keeps the old words — saved shortcuts are bound
  // to the id, not to the label.
  const EditorActionDefinition(
    id: EditorActionIds.canvasResetView,
    label: 'Reset Canvas Zoom (100%)',
    shelf: ShortcutShelf.view,
    defaultActivators: [],
    zoomsView: true,
  ),
  // 🗣️I-19: 「shift+>(확대) shift+<(축소)」.
  // ↩️F-261 (유저 2026-10-02): 「확대축소도 그래서 z랑 x로 … 둘째키로
  // 안남길거야. 그래서 쉬프트.관련은 삭제」 — X in and Z out, the outward
  // step on the left as `<` was, and the Shift pair gone.
  // ↩️Same day, once WASD walked the sheet: 「쉬프트q를 축소, 쉬프트e를
  // 확대」.
  const EditorActionDefinition(
    id: EditorActionIds.canvasZoomIn,
    label: 'Zoom In',
    shelf: ShortcutShelf.view,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyE, shift: true),
    ],
    zoomsView: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.canvasZoomOut,
    label: 'Zoom Out',
    shelf: ShortcutShelf.view,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyQ, shift: true),
    ],
    zoomsView: true,
  ),
  // The comma set row (UI-R17 #7, TVP-style): 1-4 set the exposure of the
  // current block — or every selected block, packed — outright; 5 opens
  // the N input. Bare digits stand down while text fields have focus.
  const EditorActionDefinition(
    id: EditorActionIds.timelineComma1,
    label: 'Set 1 Comma',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.digit1)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelineComma2,
    label: 'Set 2 Commas',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.digit2)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelineComma3,
    label: 'Set 3 Commas',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.digit3)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelineComma4,
    label: 'Set 4 Commas',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.digit4)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelineCommaN,
    label: 'Set N Commas',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.digit5)],
  ),
  // The film verbs ship UNBOUND. Every one of them is a key an animator
  // will want under a finger, but which key is a working habit, not a
  // default we can guess — and the digits are already spoken for by the
  // comma set above. Registering them is what makes them assignable at
  // all: the shortcut dialog lists the registry, so an unbound action is
  // still a row the user can put a key on.
  // 🗣️I-63 ③ (유저 2026-10-03): 「프레임추가는 이름이 새 그림인데
  // 그게아니라 프레임 추가로 하고」 — the row is named for the button it
  // presses, the frame pill's ＋. ↩️It read 'New Drawing' (「새 그림」).
  // 🗣️I-63-Q4 (유저 2026-10-09): 「anicel엔 tvp기반으로 넣도록. 겹치면 알아서
  // 판단」 — TVPaint makes the drawing here on `I`, which is the eyedropper
  // here, so the frame takes Shift+I: TVPaint's own key for making it on the
  // next frame, the nearest key that program gives the verb.
  const EditorActionDefinition(
    id: EditorActionIds.frameNewDrawing,
    label: 'New Frame',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyI, shift: true)],
  ),
  // 🗣️I-63 ③ (유저 2026-10-03): 「프레임 추가랑 레이어 추가버튼도 단축키
  // 기본값 등록하고싶음 … j말고 왼손쪽에 다른걸로 할당하고싶음」 — the
  // layer pill's ＋ is a row now, beside Add Frame. 🗣️Its key is TVPaint's
  // new animation layer, Ctrl+N (I-63-Q4, the answer above).
  const EditorActionDefinition(
    id: EditorActionIds.layerAdd,
    label: _addLayerLabel,
    shelf: ShortcutShelf.layerPill,
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyN, control: true),
    ],
  ),
  // 🗣️I-58 (유저 2026-10-18): 「x버튼은 비우기 … 마크 점은 중간나누기
  // 마크」 — each named for the button it presses. ↩️They read 'Blank
  // Exposure' and 'Toggle Mark'.
  const EditorActionDefinition(
    id: EditorActionIds.frameBlankExposure,
    label: 'Clear',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [],
  ),
  // 🗣️I-130 (유저 2026-10-25): 「기존 중간나누기 버튼 왼쪽에 중간나누기
  // 마크1 버튼 신설」 — ○ before ●, as their buttons stand. No key was said
  // for it. ↩️The ● read 'In-between Mark' while it was the one mark.
  const EditorActionDefinition(
    id: EditorActionIds.frameToggleMarkOne,
    label: 'In-between Mark 1',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameToggleMarkTwo,
    label: 'In-between Mark 2',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [],
  ),
  // 🗣️I-58 (유저 2026-10-01): the ● every n koma — 「중간나누기 마크
  // 자동추가」 — from each selected block's head, else from the playhead's
  // cell (F-402). No key was said for it.
  const EditorActionDefinition(
    id: EditorActionIds.frameMarkEvery,
    label: 'Auto-add In-between Marks',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelinePushBlocks,
    label: 'Push Blocks',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelinePullBlocks,
    label: 'Pull Blocks',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [],
  ),
  // 「타임라인 줌」 — the user's own name for this cluster on both panels
  // (I-57).
  const EditorActionDefinition(
    id: EditorActionIds.timelineZoomIn,
    label: 'Timeline Zoom In',
    shelf: ShortcutShelf.timelineBar,
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelineZoomOut,
    label: 'Timeline Zoom Out',
    shelf: ShortcutShelf.timelineBar,
    defaultActivators: [],
  ),
  // 🗣️I-111 (유저 2026-10-19): 「타임라인/콘티패널등 줌 fit 버튼 추가.
  // 해당 패널의 엔드라인에 맞춰서 스크롤바 fit하는것」 · 「위치는 줌
  // 확대버튼 오른쪽」. No key was said for it. ↩️Its place is right of the
  // zoom's readout since F-463 took the − and + buttons off (「그 옆의 줌
  // fit버튼은 그대로」); the two actions above stayed, with no button.
  const EditorActionDefinition(
    id: EditorActionIds.timelineZoomFit,
    label: 'Timeline Zoom to Fit',
    shelf: ShortcutShelf.timelineBar,
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelineOrientationToggle,
    label: 'Timeline / X-sheet',
    shelf: ShortcutShelf.timelineBar,
    defaultActivators: [],
  ),
  // 🗣️I-19: 「= 버튼은 활성레이어 솔로 버튼으로 연결」.
  // ↩️F-261 (유저 2026-10-02): 「활성레이어솔로도 옮길까 … 지워줘 … T로가자」
  // — T, the left hand's last free letter, and `=` binds nothing.
  // ↩️I-63 (유저 2026-10-03): 「활성레이어솔로 그냥 q로 이동, 어니언스킨을
  // t로이동」 — Q, and the onion skin takes T.
  const EditorActionDefinition(
    id: EditorActionIds.layerVisibilitySolo,
    label: 'Solo active layer',
    shelf: ShortcutShelf.view,
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyQ)],
  ),
  // 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록. 타임라인
  // 버튼같은거나」 — the rows of the timeline bar's menus, in the bar's own
  // order: 컷 · 레이어 · 프레임. Each IS its row and is pressed as the row
  // ([EditorActionDefinition.menuRow]) on the panel being worked in. None has
  // a key: no key was ever said for one.
  // 🗣️I-58 (유저 2026-10-18): 「컷 추가버튼은 새 컷이고 레이어는 레이어
  // 추가고 프레임은 추가임 … 통일(레이어 추가 이런식으로 ㅁㅁ 추가. ㅁㅁ
  // 삭제)」 — and at 12:31, the one form chosen: 「ㅁㅁ 추가말고 새 ㅁㅁ로
  // 하자」. Every verb that makes a thing reads 「새 ㅁㅁ」 (New …), its pair
  // 「ㅁㅁ 삭제」. ↩️It read 'New cut', then 'Add cut' (the first half, before
  // the form was chosen).
  // ↩️F-455 (유저 2026-10-23: 「컷 종류버튼의 새 컷은 +버튼이랑 겹치니
  // 삭제」): 새 컷 is the ＋ itself now, not a row of its band — a key
  // presses the ＋'s own press (`newCutPress`), as the layer pill's ＋'s does.
  const EditorActionDefinition(
    id: EditorActionIds.cutNew,
    label: 'New cut',
    shelf: ShortcutShelf.cutPill,
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.cutEditNote,
    label: 'Edit cut note',
    shelf: ShortcutShelf.cutPill,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.cutSettings,
    label: 'Cut settings',
    shelf: ShortcutShelf.cutPill,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.cutCanvasSize,
    label: 'Canvas size',
    shelf: ShortcutShelf.cutPill,
    defaultActivators: [],
    menuRow: true,
  ),
  // F-455: 겸용컷 만들기 left the ＋'s band for the menu, above 겸용컷 변환
  // (유저: 「종류버튼의 겸용컷 만들기는 컷 버튼으로 옮김. 겸용컷 변환 위」).
  const EditorActionDefinition(
    id: EditorActionIds.cutCreateLinked,
    label: 'Create linked cut',
    shelf: ShortcutShelf.cutPill,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.cutConvertLinked,
    label: 'Convert to linked cut',
    shelf: ShortcutShelf.cutPill,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.layerDetach,
    label: 'Detach from base',
    shelf: ShortcutShelf.layerPill,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.layerRasterize,
    label: 'Rasterize layer',
    shelf: ShortcutShelf.layerPill,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.layerStoryboard,
    label: 'Storyboard layer',
    shelf: ShortcutShelf.layerPill,
    defaultActivators: [],
    menuRow: true,
  ),
  ..._addLayerKindActions(),
  const EditorActionDefinition(
    id: EditorActionIds.layerAttachFreeAbove,
    label: 'Attach free layer above',
    shelf: ShortcutShelf.layerPill,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.layerAttachFreeBelow,
    label: 'Attach free layer below',
    shelf: ShortcutShelf.layerPill,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.layerAttachSyncedAbove,
    label: 'Attach synced layer above',
    shelf: ShortcutShelf.layerPill,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.layerAttachSyncedBelow,
    label: 'Attach synced layer below',
    shelf: ShortcutShelf.layerPill,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameSelectRowSpan,
    label: 'Select whole row',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [],
    menuRow: true,
  ),
  // The frame pill's standing switch (F-61) — a button, not a row, so the
  // shell presses what the button presses. 🗣️I-58 (유저 2026-10-18): 「빈
  // 칸에 그리면 프레임 자동 생성은 프레임 자동 생성」. ↩️It read 'Make a
  // frame where there is none'.
  const EditorActionDefinition(
    id: EditorActionIds.frameAutoCreate,
    label: 'Auto-create Frames',
    shelf: ShortcutShelf.framePill,
    defaultActivators: [],
  ),
  // The fx pill's rows, after the frame pill's — the bar's order.
  ..._addEffectActions(),
  // The rail legend's rows, under the bar: its columns from left to right.
  ..._railLegendActions(),
  // The brush library's ⋯ and the two buttons beside it — before the
  // settings menu's rows, which close the registry.
  ..._brushLibraryActions(),
  // I-40: the panels' own buttons, each under its panel's name — the media
  // pool's ＋ (by the window it opens), the timesheet's format window and
  // its notation ⇄ data switch.
  EditorActionDefinition.composed(
    id: EditorActionIds.mediaPoolImport,
    name: (language) => AppStrings.of(language).imImport,
    shelf: ShortcutShelf.media,
    defaultActivators: const [],
    panelButton: true,
  ),
  EditorActionDefinition.composed(
    id: EditorActionIds.timesheetFormat,
    name: (language) => AppStrings.of(language).sheetFormatTitle,
    shelf: ShortcutShelf.timesheet,
    defaultActivators: const [],
    panelButton: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timesheetDataMode,
    label: 'Notation / data sheet',
    shelf: ShortcutShelf.timesheet,
    defaultActivators: [],
    panelButton: true,
  ),
  // The other sheets' format windows, opened as the timesheet's is (I-93).
  // ↩️The conte's cover and blank page were rows of its settings list, each
  // an action (I-40), until they moved into its window — whose switches,
  // as every window's, take no key (I-40-Q1).
  EditorActionDefinition.composed(
    id: EditorActionIds.conteFormat,
    name: (language) => AppStrings.of(language).conteFormatTitle,
    shelf: ShortcutShelf.conteSheet,
    defaultActivators: const [],
    panelButton: true,
  ),
  EditorActionDefinition.composed(
    id: EditorActionIds.envelopeFormat,
    name: (language) => AppStrings.of(language).envelopeFormatTitle,
    shelf: ShortcutShelf.envelope,
    defaultActivators: const [],
    panelButton: true,
  ),
  // The palette panel's ＋ (I-131): a new palette, the default from then.
  EditorActionDefinition.composed(
    id: EditorActionIds.paletteNew,
    name: (language) => AppStrings.of(language).paletteNew,
    shelf: ShortcutShelf.palette,
    defaultActivators: const [],
    panelButton: true,
  ),
  // 🗣️I-40: the settings menu's rows — 「설정의 패널 열기 닫기같은거든 뭐든」.
  // A row that only opens a second level (프로젝트 설정 · 패널 · 디버그) runs
  // nothing and is no action; the rows under it are.
  const EditorActionDefinition(
    id: EditorActionIds.workSettings,
    label: 'Work settings',
    shelf: ShortcutShelf.settings,
    defaultActivators: [],
    menuRow: true,
  ),
  ..._projectSettingsActions(),
  const EditorActionDefinition(
    id: EditorActionIds.keyboardShortcuts,
    label: 'Keyboard shortcuts',
    shelf: ShortcutShelf.settings,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.preferences,
    label: 'Preferences',
    shelf: ShortcutShelf.settings,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.about,
    label: 'About Anicel',
    shelf: ShortcutShelf.settings,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.sendFeedback,
    label: 'Send Feedback',
    shelf: ShortcutShelf.settings,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.inputInspector,
    label: 'Input Inspector',
    shelf: ShortcutShelf.debug,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameTimingOverlay,
    label: 'Frame Timing Overlay',
    shelf: ShortcutShelf.debug,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameStats,
    label: 'Frame Stats',
    shelf: ShortcutShelf.debug,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.showRepaints,
    label: 'Show Repaints',
    shelf: ShortcutShelf.debug,
    defaultActivators: [],
    menuRow: true,
  ),
  // ⚠️LAST, and that is the point: the workspace's own panels follow these
  // as rows of the same shelf (`panelActionsOf`).
  const EditorActionDefinition(
    id: EditorActionIds.toolRailOnRight,
    label: 'Tool strip on the right',
    shelf: ShortcutShelf.panels,
    defaultActivators: [],
    menuRow: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.regionOnTop,
    label: 'Timeline region on top',
    shelf: ShortcutShelf.panels,
    defaultActivators: [],
    menuRow: true,
  ),
  // 🗣️I-34 (유저 2026-10-18): named for the place that is NOT the default
  // — 「이름도 브러시 값을 상단띠로로 바꾸자. 기본이 알약이다라는걸
  // 암묵적으로 표시하려고」.
  const EditorActionDefinition(
    id: EditorActionIds.brushValuesOnStrip,
    label: 'Brush values on the top strip',
    shelf: ShortcutShelf.panels,
    defaultActivators: [],
    menuRow: true,
  ),
  // 🗣️I-128 (유저 2026-10-25): 「이 숏컷 버튼 안쓰는 사람 위해서 설정의 패널에
  // 해당 영역 끌수있게 옵션 제공」 — named, as its neighbours, for the
  // state that is not the default.
  const EditorActionDefinition(
    id: EditorActionIds.railToolsOnly,
    label: 'Tools only on the tool strip',
    shelf: ShortcutShelf.panels,
    defaultActivators: [],
    menuRow: true,
  ),
  // 🗣️I-103-Q2 (유저 2026-10-16): a row of the workspace drawer and a row of
  // this list. Its default key waits on I-103-Q3 — the F11 the question
  // named is the overlay blend's (I-31's F1–F12, in order).
  const EditorActionDefinition(
    id: EditorActionIds.fullScreen,
    label: 'Full screen',
    shelf: ShortcutShelf.panels,
    defaultActivators: [],
    menuRow: true,
    platforms: WindowFullScreen.platforms,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.regionFold,
    label: 'Fold / unfold the timeline region',
    shelf: ShortcutShelf.panels,
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.resetLayout,
    label: 'Reset workspace layout',
    shelf: ShortcutShelf.panels,
    defaultActivators: [],
    menuRow: true,
  ),
];

/// The registry as this platform offers it — every action but those of a
/// button it has none of ([EditorActionDefinition.offeredHere]): what the
/// shortcut list holds (`EditorShortcutBindings`).
List<EditorActionDefinition> editorActionsHere() => [
  for (final definition in editorActionDefinitions)
    if (definition.offeredHere) definition,
];
