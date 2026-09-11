import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  });

  final String id;
  final String label;
  final String category;
  final List<SingleActivator> defaultActivators;

  /// The multi-finger touch gesture bound by default (R11-⑨); most
  /// actions ship unbound — every action is ASSIGNABLE in the settings
  /// dialog either way. Stored as the [TouchGesture] enum NAME to keep
  /// this file free of UI imports.
  final String? defaultTouchGesture;

  /// A HELD action (I-15): its key is in force while it is down and lets go
  /// with it — the pan on Space. It is not an intent, so it never enters
  /// the Shortcuts map; `EditorKeyHolds` takes it on the same road instead.
  final bool hold;
}

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
  static const toolBrush = 'tool-brush';
  static const toolEraser = 'tool-eraser';
  static const toolEyedropper = 'tool-eyedropper';
  static const toolFill = 'tool-fill';
  static const toolSelectRect = 'tool-select-rect';
  static const toolLasso = 'tool-lasso';
  static const toolMove = 'tool-move';
  static const selectionDeselect = 'selection-deselect';
  static const selectionNudgeUp = 'selection-nudge-up';
  static const selectionNudgeDown = 'selection-nudge-down';
  static const selectionFreeTransform = 'selection-free-transform';
  static const selectionTransformCommit = 'selection-transform-commit';
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
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true),
      SingleActivator(LogicalKeyboardKey.keyY, control: true),
    ],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolBrush,
    label: 'Brush Tool',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyB)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolEraser,
    label: 'Eraser Tool',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyE)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolEyedropper,
    label: 'Eyedropper Tool',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyI)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolFill,
    label: 'Fill Tool',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyG)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolSelectRect,
    label: 'Rectangle Select Tool',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyM)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolLasso,
    label: 'Lasso Select Tool',
    category: 'Tools',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyL)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.toolMove,
    label: 'Move Tool',
    category: 'Tools',
    // PS/CSP muscle memory: V = the move tool.
    defaultActivators: [SingleActivator(LogicalKeyboardKey.keyV)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.selectionDeselect,
    label: 'Deselect',
    category: 'Selection',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyD, control: true),
    ],
  ),
  // The arrow keys are shared, with dispatch-level arbitration: with a
  // live selection they NUDGE (Photoshop behavior); otherwise left/right
  // flip frames and up/down walk the timeline's DISPLAYED layer rows
  // (TVP layer nav, UI-R20 #14).
  const EditorActionDefinition(
    id: EditorActionIds.selectionNudgeUp,
    label: 'Nudge Selection / Layer Up',
    category: 'Selection',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.arrowUp)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.selectionNudgeDown,
    label: 'Nudge Selection / Layer Down',
    category: 'Selection',
    defaultActivators: [SingleActivator(LogicalKeyboardKey.arrowDown)],
  ),
  const EditorActionDefinition(
    id: EditorActionIds.selectionFreeTransform,
    label: 'Free Transform',
    category: 'Selection',
    defaultActivators: [
      SingleActivator(LogicalKeyboardKey.keyT, control: true),
    ],
  ),
  // Enter/Escape only mean commit/cancel while a transform box is open
  // (no-ops otherwise); text fields keep them (bare keys stand down).
  const EditorActionDefinition(
    id: EditorActionIds.selectionTransformCommit,
    label: 'Commit Transform',
    category: 'Selection',
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
];
