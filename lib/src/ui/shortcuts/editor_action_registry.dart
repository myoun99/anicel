import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/app_language.dart';
import '../../models/brush_blend_mode.dart';
import '../../models/canvas_shape_kind.dart';
import '../../models/pixel_clipboard_verb.dart';
import '../../services/cel_pixel_overwrite.dart' show CelPixelVerb;
import '../brush/brush_tool_state.dart' show CanvasTool, canvasToolRailGroup;
import '../brush/tool_press.dart';
import '../brush/transform_tool_options.dart' show TransformMode;
import '../text/app_strings.dart' show AppStrings;
import '../text/model_vocabulary.dart' show BrushBlendModeWords;
import 'sheet_arrow.dart' show SheetArrow, SheetKeys, SheetMove;

/// The single shortcut intent: every editor action dispatches through ONE
/// intent type carrying its [actionId], so the app mounts exactly one
/// Actions handler and the Shortcuts map stays data-driven from the
/// registry (P1: fully customizable from day one).
class EditorActionIntent extends Intent {
  const EditorActionIntent(this.actionId);

  final String actionId;
}

/// One registered editor action: the id keys the override store, the
/// label/category feed the Keyboard Shortcuts dialog, the default
/// activators seed the Shortcuts map, and menu items borrow the primary
/// activator as their shortcut label. THIS list is the single authority
/// all three consumers read.
class EditorActionDefinition {
  const EditorActionDefinition({
    required this.id,
    required this.label,
    required this.category,
    required this.defaultActivators,
    this.defaultTouchGesture,
    this.hold = false,
    this.zoomsView = false,
    this.toolPress,
    this.pixelVerb,
    this.blendMode,
    this.pixelClipboardVerb,
    this.sheetMove,
  });

  final String id;
  final String label;
  final String category;
  final List<SingleActivator> defaultActivators;

  /// The multi-finger touch gesture bound by default (R11-⑨); most
  /// actions ship unbound — every action is ASSIGNABLE in the settings
  /// dialog either way. Stored as the [TouchGesture] enum NAME, so this
  /// file does not import the touch layer.
  final String? defaultTouchGesture;

  /// A HELD action (I-15): its key is in force while it is down and lets go
  /// with it — the pan on Space. It is not an intent, so it never enters
  /// the Shortcuts map; `EditorKeyHolds` takes it on the same road instead.
  final bool hold;

  /// A viewport ZOOM — I-19's two keys.
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

  /// The verb a row of the colour edit list runs, or null.
  ///
  /// 🗣️유저 2026-09-13: 「색변환의 픽셀비우기를 백스페이스로 하란건, 그 외
  /// 같이있는 버튼들도 다 숏컷 지정가능하게 등록하란거는 앞으로의 규칙이야」.
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

/// The shape tiles of [verb] as actions, one per [CanvasShapeKind].
///
/// ★GENERATED from the verb × shape product, never hand-written:
/// [CanvasShapeKind] warns that the product grows like one, so a new shape
/// arrives in its tiles and in the shortcut list at once. Their names are
/// composed (`shapeTileLabel`) — the English one here from the English
/// table — so no language tables a shape tile twice.
List<EditorActionDefinition> _shapeTileActions(CanvasTool verb) => [
  for (final shape in CanvasShapeKind.values)
    EditorActionDefinition(
      // Named for the rail tool the tile belongs to — 'tool-select-lasso',
      // 'tool-fill-rect' — which is the id the rectangle select already had.
      id: 'tool-${canvasToolRailGroup(verb).name}-${shape.name}',
      label: shapeTileLabel(verb, shape, AppStrings.of(AppLanguage.en)),
      category: 'Tools',
      defaultActivators: [
        // 「선택도구의 올가미 선택에 w로 두고싶어」. ↩️F-261 (유저
        // 2026-10-02): W walks up now, and 「올가미를 z」. ↩️I-63 (유저
        // 2026-10-03): 「올가미선택을 x로두고 z는 비워두도록. 언두 실수할때
        // z만 누르거나하니까」 — so bare Z presses NOTHING, on purpose: it
        // is the key a hand lands on when Ctrl slips off an undo.
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
    EditorActionDefinition(
      id: 'tool-blend-${mode.name}',
      label: blendModeActionLabel(mode, AppLanguage.en),
      category: 'Tools',
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

/// A blend action's name — 「합성: 곱하기」, 「Blend: Multiply」.
String blendModeActionLabel(BrushBlendMode mode, AppLanguage language) =>
    '${AppStrings.of(language).brBlend}: ${mode.labelFor(language)}';

/// Registry ids (referenced from dispatch and menu labels).
abstract final class EditorActionIds {
  static const framePrevious = 'frame-previous';
  static const frameNext = 'frame-next';
  static const drawingPrevious = 'drawing-previous';
  static const drawingNext = 'drawing-next';

  /// 🗣️I-15: 「단축키에 이동 추가 … 기본값을 … 스페이스바로」 — a HELD
  /// shortcut ([EditorActionDefinition.hold]).
  static const canvasPanHold = 'canvas-pan-hold';
  static const playbackToggle = 'playback-toggle';

  /// The sill transport's 「처음으로」 (F-261).
  static const playbackToStart = 'playback-to-start';
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
  static const layerUp = 'layer-up';
  static const layerDown = 'layer-down';
  static const selectionTransformCancel = 'selection-transform-cancel';
  static const onionSkinToggle = 'onion-skin-toggle';
  static const canvasRotateCcw = 'canvas-rotate-ccw';
  static const canvasRotateCw = 'canvas-rotate-cw';
  static const canvasFlipHorizontal = 'canvas-flip-horizontal';
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
  static const frameToggleMark = 'frame-toggle-mark';
  static const timelinePushBlocks = 'timeline-push-blocks';
  static const timelinePullBlocks = 'timeline-pull-blocks';

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

  /// The colour edit list's four verbs, in its order — every one an action
  /// (유저 2026-09-13: 「그 외 같이있는 버튼들도 다 숏컷 지정가능하게」).
  static const editReplaceColour = 'edit-replace-colour';
  static const editClearPixels = 'edit-clear-pixels';
  static const editDeleteColour = 'edit-delete-colour';
  static const editKeepColour = 'edit-keep-colour';

  /// Its clipboard rows (I-55) — 픽셀 복사 and the two pastes.
  static const editCopyPixels = 'edit-copy-pixels';
  static const editPastePixelsAbove = 'edit-paste-pixels-above';
  static const editPastePixelsBelow = 'edit-paste-pixels-below';

  /// 「컨트롤s로 저장 로직 연결, 컨트롤쉬프트s로 다른이름저장」.
  static const fileSave = 'file-save';
  static const fileSaveAs = 'file-save-as';

  /// 「= 버튼은 활성레이어 솔로 버튼으로 연결」 — the legend eye menu's solo.
  /// ↩️The key is T since F-261. ↩️Q since I-63.
  static const layerVisibilitySolo = 'layer-visibility-solo';

  /// 🗣️I-63 ③ (유저 2026-10-03): 「프레임 추가랑 레이어 추가버튼도 단축키
  /// 기본값 등록하고싶음」 — the layer pill's ＋.
  static const layerAdd = 'layer-add';

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
    category: 'Navigation',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true),
      SingleActivator(LogicalKeyboardKey.keyA, shift: true),
    ],
    sheetMove: (arrow: SheetArrow.left, fine: true),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameNext,
    label: 'Next Frame',
    category: 'Navigation',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowRight, shift: true),
      SingleActivator(LogicalKeyboardKey.keyD, shift: true),
    ],
    sheetMove: (arrow: SheetArrow.right, fine: true),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.drawingPrevious,
    label: 'Previous Block',
    category: 'Navigation',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowLeft),
      SingleActivator(LogicalKeyboardKey.keyA),
    ],
    sheetMove: (arrow: SheetArrow.left, fine: false),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.drawingNext,
    label: 'Next Block',
    category: 'Navigation',
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
    category: 'Navigation',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowUp),
      SingleActivator(LogicalKeyboardKey.keyW),
    ],
    sheetMove: (arrow: SheetArrow.up, fine: false),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.layerDown,
    label: 'Layer Down',
    category: 'Navigation',
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
    category: 'View',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.space)],
    hold: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.playbackToggle,
    label: 'Play / Pause',
    category: 'Playback',
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
    category: 'Playback',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyZ, shift: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.voiceRecordToggle,
    label: 'Record Voice (start/stop)',
    category: 'Playback',
    // REC1-B: Ctrl+R, REAPER's record key — plain R stays the drawing-app
    // canvas-rotate convention this app already follows.
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyR, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.undo,
    label: 'Undo',
    category: 'Edit',
    // Procreate's muscle memory: two-finger tap = undo.
    defaultTouchGesture: 'twoFingerTap',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyZ, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.redo,
    label: 'Redo',
    category: 'Edit',
    // Procreate's muscle memory: three-finger tap = redo.
    defaultTouchGesture: 'threeFingerTap',
    // 🪦Ctrl+Y redid as well — a second key on one action, retired
    // 2026-09-13: 「다시실행 중복할당된거 제거하고 잔재도 제거해」. Ctrl+Y is
    // 자유 변형 now.
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true),
    ],
  ),
  // 🗣️I-19 (유저 2026-09-12): keys for buttons that already exist — the
  // shared pill's clipboard, its delete and the colour edit's clear. Each
  // label is the BUTTON's own name, so its tooltip and this list cannot
  // call one verb two things. ⚠️`control` in every default here is the
  // platform's COMMAND key: ⌘ on a Mac or an iPad (`platformActivator`).
  const EditorActionDefinition(
    id: EditorActionIds.editCut,
    label: 'Cut',
    category: 'Edit',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyX, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editCopy,
    label: 'Copy',
    category: 'Edit',
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
    category: 'Edit',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyB, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editPasteIndependent,
    label: 'Paste independent',
    category: 'Edit',
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
    category: 'Edit',
    defaultActivators: [],
  ),
  // Bare Delete and Backspace: a focused text field keeps both (bare keys
  // stand down there), so they never reach a pill while you are typing.
  const EditorActionDefinition(
    id: EditorActionIds.editDelete,
    label: 'Delete',
    category: 'Edit',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.delete)],
  ),
  // 🗣️I-18 (유저): 「타임라인 공용 알약에 새 버튼 신설 … 버튼은 자동 이름
  // 지정」 — a button, so a row a key can be put on (유저 2026-09-13:
  // 「버튼이면 왠만해선 숏컷 지정 가능하게」). It ships unbound: nobody named a
  // key. The label is the button's own, and a bar button's writing carries
  // no '…' (B9).
  // 🗣️F-261: the Edit beside it — D, with the left hand's other keys (see
  // the play key). ↩️X once D walked right (「편집을 x」). ↩️I-63 (유저
  // 2026-10-03): 「지금 편집버튼 x인데 쉬프트+f로」 — X is the lasso
  // select's now.
  const EditorActionDefinition(
    id: EditorActionIds.editInstance,
    label: 'Edit',
    category: 'Edit',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyF, shift: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editAutoName,
    label: 'Auto Name',
    category: 'Edit',
    defaultActivators: [],
  ),
  // 🗣️유저 2026-09-13: 「색변환의 픽셀비우기를 백스페이스로 하란건, 그 외
  // 같이있는 버튼들도 다 숏컷 지정가능하게 등록하란거는 앞으로의 규칙이야.
  // 버튼이면 왠만해선 숏컷 지정 가능하게 리스트로 올리는걸 기본으로 두고
  // 싶어」 — the colour edit list's four rows, in its order; Backspace is the
  // one key the list ships with.
  const EditorActionDefinition(
    id: EditorActionIds.editReplaceColour,
    label: 'Replace Color',
    category: 'Edit',
    defaultActivators: [],
    pixelVerb: CelPixelVerb.replaceColour,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editClearPixels,
    label: 'Clear Pixels',
    category: 'Edit',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.backspace)],
    pixelVerb: CelPixelVerb.clearPixels,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editDeleteColour,
    label: 'Delete Color',
    category: 'Edit',
    defaultActivators: [],
    pixelVerb: CelPixelVerb.deleteColour,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editKeepColour,
    label: 'Keep Color',
    category: 'Edit',
    defaultActivators: [],
    pixelVerb: CelPixelVerb.keepColour,
  ),
  // 🗣️I-55 (유저 2026-10-01): the list's clipboard rows, under the same rule
  // — actions, in the list's order. No key ships with them: none was named.
  const EditorActionDefinition(
    id: EditorActionIds.editCopyPixels,
    label: 'Copy Pixels',
    category: 'Edit',
    defaultActivators: [],
    pixelClipboardVerb: PixelClipboardVerb.copy,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editPastePixelsAbove,
    label: 'Paste Pixels Above',
    category: 'Edit',
    defaultActivators: [],
    pixelClipboardVerb: PixelClipboardVerb.pasteAbove,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.editPastePixelsBelow,
    label: 'Paste Pixels Below',
    category: 'Edit',
    defaultActivators: [],
    pixelClipboardVerb: PixelClipboardVerb.pasteBelow,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.fileSave,
    label: 'Save',
    category: 'File',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyS, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.fileSaveAs,
    label: 'Save as…',
    category: 'File',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true),
    ],
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
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyB)],
    toolPress: RailToolPress(CanvasTool.brush),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolEraser,
    label: 'Eraser Tool',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyE)],
    toolPress: RailToolPress(CanvasTool.eraser),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolEyedropper,
    label: 'Eyedropper Tool',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyI)],
    toolPress: RailToolPress(CanvasTool.eyedropper),
  ),
  // 「채우기툴을 f로 변경하고」 — it was G.
  const EditorActionDefinition(
    id: EditorActionIds.toolFill,
    label: 'Fill Tool',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyF)],
    toolPress: RailToolPress(CanvasTool.fill),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolFillBucket,
    label: 'Bucket',
    category: 'Tools',
    defaultActivators: [],
    toolPress: ToolTilePress(CanvasTool.fill),
  ),
  ..._shapeTileActions(CanvasTool.fillShape),
  // R9-rest: no key of its own — a bare T solos the active layer (F-261),
  // and a person binds what they want.
  const EditorActionDefinition(
    id: EditorActionIds.toolText,
    label: 'Text Tool',
    category: 'Tools',
    defaultActivators: [],
    toolPress: RailToolPress(CanvasTool.text),
  ),
  // 「가이드 툴을 g로 지정」.
  const EditorActionDefinition(
    id: EditorActionIds.toolGuide,
    label: 'Guide Tool',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyG)],
    toolPress: RailToolPress(CanvasTool.guide),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolSelect,
    label: 'Select Tool',
    category: 'Tools',
    defaultActivators: [],
    toolPress: RailToolPress(CanvasTool.select),
  ),
  ..._shapeTileActions(CanvasTool.select),
  const EditorActionDefinition(
    id: EditorActionIds.toolTransform,
    label: 'Transform Tool',
    category: 'Tools',
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
    category: 'Tools',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyT, control: true),
    ],
    toolPress: TransformModePress(TransformMode.normal),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolTransformFree,
    label: 'Free Transform',
    category: 'Tools',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyY, control: true),
    ],
    toolPress: TransformModePress(TransformMode.perspective),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolTransformMesh,
    label: 'Mesh Warp',
    category: 'Tools',
    defaultActivators: [],
    toolPress: TransformModePress(TransformMode.mesh),
  ),
  // ↩️「잘라내기는 잘라내기 툴 자체에 c로 설정」 (09-13) gave C to the tool
  // itself; I-53 (09-28) moved it to the lasso cut's tile — see
  // `_shapeTileActions`.
  const EditorActionDefinition(
    id: EditorActionIds.toolCut,
    label: 'Cut Tool',
    category: 'Tools',
    defaultActivators: [],
    toolPress: RailToolPress(CanvasTool.cut),
  ),
  ..._shapeTileActions(CanvasTool.cut),
  // 🗣️I-28 (유저 2026-09-30): 「잘라내기 툴의 도구 라이브러리에 전체 잘라내기
  // 신설」 — a tile that runs at the press (I-28-Q2), and so a key that does.
  const EditorActionDefinition(
    id: EditorActionIds.toolCutWhole,
    label: 'Whole Picture Cut',
    category: 'Tools',
    defaultActivators: [],
    toolPress: CutWholePress(),
  ),
  // 🗣️I-53 (유저 2026-09-28): 「스탬프를 v로」. ↩️V alone was retired from
  // the move tool on 09-13 (「v 삭제하고 v 관련 잔재있으면 삭제」) — the
  // key left that tool; this is the user handing it to another.
  const EditorActionDefinition(
    id: EditorActionIds.toolCutStamp,
    label: 'Stamp',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyV)],
    toolPress: ToolTilePress(CanvasTool.cutStamp),
  ),
  ..._blendModeActions(),
  const EditorActionDefinition(
    id: EditorActionIds.selectionDeselect,
    label: 'Deselect',
    category: 'Selection',
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
    category: 'Edit',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.enter),
      SingleActivator(LogicalKeyboardKey.numpadEnter),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.selectionTransformCancel,
    label: 'Cancel Transform',
    category: 'Selection',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.escape)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.onionSkinToggle,
    label: 'Toggle Onion Skin',
    category: 'View',
    // 🗣️F-261 (유저 2026-10-02): 「우선 어니언스킨을 Q로」 — the left hand's.
    // ↩️I-63 (유저 2026-10-03): 「활성레이어솔로 그냥 q로 이동,
    // 어니언스킨을 t로이동」 — the two trade places.
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyT)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.canvasRotateCcw,
    label: 'Rotate Canvas View Left',
    category: 'View',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyR)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.canvasRotateCw,
    label: 'Rotate Canvas View Right',
    category: 'View',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyR, shift: true)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.canvasFlipHorizontal,
    label: 'Flip Canvas View Horizontal',
    category: 'View',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyH)],
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
    category: 'View',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyE, shift: true),
    ],
    zoomsView: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.canvasZoomOut,
    label: 'Zoom Out',
    category: 'View',
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
    category: 'Timeline',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.digit1)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelineComma2,
    label: 'Set 2 Commas',
    category: 'Timeline',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.digit2)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelineComma3,
    label: 'Set 3 Commas',
    category: 'Timeline',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.digit3)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelineComma4,
    label: 'Set 4 Commas',
    category: 'Timeline',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.digit4)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelineCommaN,
    label: 'Set N Commas…',
    category: 'Timeline',
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
  const EditorActionDefinition(
    id: EditorActionIds.frameNewDrawing,
    label: 'Add Frame',
    category: 'Timeline',
    defaultActivators: [],
  ),
  // 🗣️I-63 ③ (유저 2026-10-03): 「프레임 추가랑 레이어 추가버튼도 단축키
  // 기본값 등록하고싶음 … j말고 왼손쪽에 다른걸로 할당하고싶음」 — the
  // layer pill's ＋ is a row now, beside Add Frame. Which key each takes is
  // the user's to name; no key was said, so both wait unbound.
  const EditorActionDefinition(
    id: EditorActionIds.layerAdd,
    label: 'Add Layer',
    category: 'Timeline',
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameBlankExposure,
    label: 'Blank Exposure',
    category: 'Timeline',
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameToggleMark,
    label: 'Toggle Mark',
    category: 'Timeline',
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelinePushBlocks,
    label: 'Push Blocks',
    category: 'Timeline',
    defaultActivators: [],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.timelinePullBlocks,
    label: 'Pull Blocks',
    category: 'Timeline',
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
    category: 'Timeline',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyQ)],
  ),
];
