import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/app_language.dart';
import '../../models/canvas_shape_kind.dart';
import '../../services/cel_pixel_overwrite.dart' show CelPixelVerb;
import '../brush/brush_tool_state.dart' show CanvasTool, canvasToolRailGroup;
import '../brush/tool_press.dart';
import '../brush/transform_tool_options.dart' show TransformMode;
import '../text/app_strings.dart' show AppStrings;

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
        // 「선택도구의 올가미 선택에 w로 두고싶어」.
        if (verb == CanvasTool.select && shape == CanvasShapeKind.lasso)
          const SingleActivator(LogicalKeyboardKey.keyW),
      ],
      toolPress: ShapeTilePress(verb, shape),
    ),
];

/// Registry ids (referenced from dispatch and menu labels).
abstract final class EditorActionIds {
  static const framePrevious = 'frame-previous';
  static const frameNext = 'frame-next';
  static const frameWalkLeft = 'frame-walk-left';
  static const frameWalkRight = 'frame-walk-right';
  static const frameWalkUp = 'frame-walk-up';
  static const frameWalkDown = 'frame-walk-down';
  static const drawingPrevious = 'drawing-previous';
  static const drawingNext = 'drawing-next';

  /// 🗣️I-15: 「단축키에 이동 추가 … 기본값을 … 스페이스바로」 — a HELD
  /// shortcut ([EditorActionDefinition.hold]).
  static const canvasPanHold = 'canvas-pan-hold';
  static const playbackToggle = 'playback-toggle';
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
  static const toolGuide = 'tool-guide';
  static const toolSelect = 'tool-select';
  static const toolTransform = 'tool-transform';
  static const toolTransformNormal = 'tool-transform-normal';
  static const toolTransformFree = 'tool-transform-free';
  static const toolTransformMesh = 'tool-transform-mesh';
  static const toolCut = 'tool-cut';
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

  /// The colour edit list's four verbs, in its order — every one an action
  /// (유저 2026-09-13: 「그 외 같이있는 버튼들도 다 숏컷 지정가능하게」).
  static const editReplaceColour = 'edit-replace-colour';
  static const editClearPixels = 'edit-clear-pixels';
  static const editDeleteColour = 'edit-delete-colour';
  static const editKeepColour = 'edit-keep-colour';

  /// 「컨트롤s로 저장 로직 연결, 컨트롤쉬프트s로 다른이름저장」.
  static const fileSave = 'file-save';
  static const fileSaveAs = 'file-save-as';

  /// 「= 버튼은 활성레이어 솔로 버튼으로 연결」 — the legend eye menu's solo.
  static const layerVisibilitySolo = 'layer-visibility-solo';

  /// 「캔버스 확대축소버튼. 키보드에서 shift+>(확대) shift+<(축소). 배율은
  /// 설정에 줌 스냅 설정한대로」.
  static const canvasZoomIn = 'canvas-zoom-in';
  static const canvasZoomOut = 'canvas-zoom-out';
}

/// The default action set. Frame flipping on `,`/`.` (with arrow aliases)
/// and drawing jumps on Ctrl+`,`/`.` are the animation-desk core; tools
/// and transport follow PS/CSP convention.
final List<EditorActionDefinition> editorActionDefinitions = [
  // Arrows are the PRIMARY flip keys (R10-⑧ — the primary shows as the
  // PEN-7c: plain arrows walk DRAWINGS (block-to-block — the animator's
  // flip unit); Ctrl+arrows step ONE frame (the fine unit). Comma/period
  // keep the frame-step desk-muscle aliases; everything rebinds in the
  // shortcut settings as always.
  const EditorActionDefinition(
    id: EditorActionIds.framePrevious,
    label: 'Previous Frame',
    category: 'Navigation',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.comma)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameNext,
    label: 'Next Frame',
    category: 'Navigation',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.period)],
  ),
  // F-28 (유저 2026-08-28): the Ctrl+arrows are DIRECTIONS, so they read
  // the sheet — along the frame axis one frame, across it one row. That
  // is why they left the two definitions above: comma and period name a
  // frame, not a direction, and on an X-sheet they must still step frames.
  const EditorActionDefinition(
    id: EditorActionIds.frameWalkLeft,
    label: 'Step Left',
    category: 'Navigation',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowLeft, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameWalkRight,
    label: 'Step Right',
    category: 'Navigation',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowRight, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameWalkUp,
    label: 'Step Up',
    category: 'Navigation',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowUp, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.frameWalkDown,
    label: 'Step Down',
    category: 'Navigation',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowDown, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.drawingPrevious,
    label: 'Previous Drawing',
    category: 'Navigation',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowLeft),
      SingleActivator(LogicalKeyboardKey.comma, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.drawingNext,
    label: 'Next Drawing',
    category: 'Navigation',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.arrowRight),
      SingleActivator(LogicalKeyboardKey.period, control: true),
    ],
  ),
  // 🗣️I-15 (유저 2026-09-11): 「손바닥 툴을 만들지는 않음. 다만 단축키에
  // 이동? 추가하는건 추가하고, 기본값을 휠클릭이 아니라 스페이스바로
  // 이동」 — held, not pressed: while Space is down a primary drag pans.
  const EditorActionDefinition(
    id: EditorActionIds.canvasPanHold,
    label: 'Pan (hold)',
    category: 'Navigation',
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
    defaultActivators: [],
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
  // Bare Delete and Backspace: a focused text field keeps both (bare keys
  // stand down there), so they never reach a pill while you are typing.
  const EditorActionDefinition(
    id: EditorActionIds.editDelete,
    label: 'Delete',
    category: 'Edit',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.delete)],
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
  // 「잘라내기는 잘라내기 툴 자체에 c로 설정」.
  const EditorActionDefinition(
    id: EditorActionIds.toolCut,
    label: 'Cut Tool',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyC)],
    toolPress: RailToolPress(CanvasTool.cut),
  ),
  ..._shapeTileActions(CanvasTool.cut),
  const EditorActionDefinition(
    id: EditorActionIds.toolCutStamp,
    label: 'Stamp',
    category: 'Tools',
    defaultActivators: [],
    toolPress: ToolTilePress(CanvasTool.cutStamp),
  ),
  const EditorActionDefinition(
    id: EditorActionIds.selectionDeselect,
    label: 'Deselect',
    category: 'Selection',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyD, control: true),
    ],
  ),
  // The arrow keys walk the sheet: on the timeline left/right flip frames
  // and up/down walk its DISPLAYED layer rows (TVP layer nav, UI-R20 #14),
  // and the X-sheet swaps the two (F-28). ↩️With a live selection they used
  // to NUDGE it (Photoshop behavior) — 유저 2026-09-12: 「선택툴 선택한채로
  // 화살표키누르면 그림 이동되는데 왜 멋대로 넣은거지? 기능부터 잔존코드 싹
  // 삭제」 (F-86), so the pair lost the nudge's name and category with it.
  const EditorActionDefinition(
    id: EditorActionIds.layerUp,
    label: 'Layer Up',
    category: 'Navigation',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.arrowUp)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.layerDown,
    label: 'Layer Down',
    category: 'Navigation',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.arrowDown)],
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
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyO)],
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
  // 🗣️I-19: 「shift+>(확대) shift+<(축소)」. Written as the key under the
  // glyph — `>` is Shift+. on the layouts in use — because the logical key
  // Flutter reports is the unshifted one.
  const EditorActionDefinition(
    id: EditorActionIds.canvasZoomIn,
    label: 'Zoom In',
    category: 'View',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.period, shift: true),
    ],
    zoomsView: true,
  ),
  const EditorActionDefinition(
    id: EditorActionIds.canvasZoomOut,
    label: 'Zoom Out',
    category: 'View',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.comma, shift: true),
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
  const EditorActionDefinition(
    id: EditorActionIds.frameNewDrawing,
    label: 'New Drawing',
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
  // 🗣️I-19: 「= 버튼은 활성레이어 솔로 버튼으로 연결」. On a JIS keyboard
  // `=` is Shift+-, which presses this through the character it types
  // (`pressableForms`, a-key-is-the-character-it-types).
  const EditorActionDefinition(
    id: EditorActionIds.layerVisibilitySolo,
    label: 'Solo active layer',
    category: 'Timeline',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.equal)],
  ),
];
