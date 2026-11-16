import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../services/input/modifier_keys.dart';
import '../brush/brush_tool_state.dart';
import '../brush/temporary_tool.dart';
import '../canvas/canvas_line_hold.dart';
import '../canvas/canvas_view_hold.dart';
import 'editor_action_registry.dart';
import 'editor_shortcut_bindings.dart';
import 'shortcut_activator_codec.dart' show isModifierKey, modifierHeld;

/// The keys that are HELD rather than pressed (I-15).
///
/// 🗣️유저 2026-09-11: 「손바닥 툴을 만들지는 않음. 다만 단축키에 이동?
/// 추가하는건 추가하고, 기본값을 휠클릭이 아니라 스페이스바로 이동. 그리고
/// 기존 재생단축키가 스페이스바인데 그냥 해제. 스포이드는 그대로 해서
/// 누르는동안 툴 바뀌도록」 — and, while doing it, 「법 하나 통일하는거
/// 유념해줘」.
///
/// ★ONE LAW FOR EVERY HELD INPUT: while it is held its action is in force,
/// and letting go ends it. A pen or mouse button always worked that way
/// (PEN-7a — the tool switches through [TemporaryTool], a wheel click
/// pans); a held key now goes through the same two doors: the eyedropper
/// through [TemporaryTool], the pan and the turn through [CanvasViewHold].
/// The line from the last stroke (I-119) is held the same way, through
/// [CanvasLineHold].
///
/// ⚠️TAKEN on the shortcut road, LET GO on the keyboard's. A press is taken
/// where every shortcut is (`EditorShortcutManager`), so a focused text
/// field keeps its space bar the way it keeps its letters; a release is
/// heard app-wide, because a key let go after the focus moved must still
/// let go.
final class EditorKeyHolds {
  EditorKeyHolds({
    required this.bindings,
    required this.tool,
    required this.temporaryTool,
    required ValueListenable<bool> strokeLive,
  }) : _strokeLive = strokeLive {
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    CanvasViewHold.reask = _reaskTheView;
    strokeLive.addListener(_onStrokeLive);
  }

  final EditorShortcutBindings bindings;
  final ValueListenable<BrushToolState> tool;
  final TemporaryTool temporaryTool;

  /// True while a stroke is being drawn. A tool switch WAITS for it to end
  /// — the pen's own law: a barrel button that rises mid-stroke never
  /// hijacks the live line. The pan needs no wait: a press already down
  /// keeps its route, so the pan only ever takes the NEXT press.
  ValueListenable<bool> get strokeLive => _strokeLive;
  ValueListenable<bool> _strokeLive;

  /// Hears [next] instead — the stroke of the project that came on screen.
  ///
  /// 🚨The holds are the WINDOW's and outlive a project tab switch (I-7):
  /// a key held across one must still let go of what it took, so the
  /// shell points this at the new project rather than making another.
  set strokeLive(ValueListenable<bool> next) {
    if (identical(next, _strokeLive)) {
      return;
    }
    _strokeLive.removeListener(_onStrokeLive);
    _strokeLive = next;
    next.addListener(_onStrokeLive);
    _onStrokeLive();
  }

  final Map<LogicalKeyboardKey, _KeyHold> _held = {};

  /// The presses holding the view, by key, the latest last — kept to be
  /// asked again as the modifiers change under them. 🗣️I-88 (유저
  /// 2026-10-09): 「스페이스바+컨트롤상태에선 회전으로 작동하도록」 — a STATE of
  /// the keys, not an order: Space then the turn's modifier turns, and that
  /// modifier let go pans again. ↩️I-88-Q1 moved the turn to Shift+Space;
  /// the law did not move with it.
  final Map<LogicalKeyboardKey, KeyEvent> _viewPresses = {};

  /// Eyedropper keys that came down mid-stroke: held, and in force the
  /// moment the stroke ends.
  final Set<LogicalKeyboardKey> _waiting = {};

  /// A key event on the shortcut road. HANDLED when its key holds anything
  /// — the space bar then does nothing else, its repeats included — but
  /// for a modifier, which passes on because it still modifies whatever it
  /// is held with: the eyedropper's Alt, and the pan's under TVPaint's keys
  /// (F-603).
  KeyEventResult engage(KeyEvent event) {
    final key = event.logicalKey;
    if (event is! KeyDownEvent || _takes(key)) {
      return _takes(key) ? _taken(key) : KeyEventResult.ignored;
    }
    if (_theToolsOwn(key)) {
      return KeyEventResult.ignored;
    }
    final view = _viewHoldOf(event);
    if (view != null) {
      _held[key] = _KeyHold.view;
      _viewPresses[key] = event;
      CanvasViewHold.held.value = view;
    } else if (bindings.presses(EditorActionIds.canvasLineHold, event)) {
      _held[key] = _KeyHold.line;
      CanvasLineHold.held.value = true;
    } else if (bindings.presses(EditorActionIds.eyedropperHold, event)) {
      if (strokeLive.value) {
        _waiting.add(key);
      } else {
        _holdEyedropper(key);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return _taken(key);
  }

  /// Whether [key] holds anything, or waits to.
  bool _takes(LogicalKeyboardKey key) =>
      _held.containsKey(key) || _waiting.contains(key);

  /// What [engage] answers for a key that holds: the key is spent — but a
  /// modifier's passes on.
  static KeyEventResult _taken(LogicalKeyboardKey key) =>
      isModifierKey(key) ? KeyEventResult.ignored : KeyEventResult.handled;

  /// Whether [key] going down is the tool's own modifier rather than a key
  /// that holds: a modifier going down with Alt held, under a tool whose
  /// own drag reads Alt ([canvasToolReadsAlt]) — whatever Alt holds, alone
  /// or with Ctrl, in whichever order they went down. A second Alt joins
  /// the hold the first is in.
  ///
  /// 🗣️F-299-Q1 (유저 2026-10-06), the answer picked: 「Alt 가 그 도구의 자기
  /// 수정자가 아닌 곳 전부에서 스포이드」 — the selection's subtract and the
  /// transform's scale keep their Alt. ↩️Asked of the eyedropper alone till
  /// F-603 (2026-11-16) put the pan on Alt under TVPaint's keys: the answer
  /// is Alt's, so it stands for whatever Alt holds.
  /// ⚠️Alt is the one modifier a tool's drag reads that has an answer. No
  /// tool's drag reads Ctrl or ⌘; a hold on Shift alone takes the Shift of
  /// the tools that read it — nobody has asked otherwise.
  bool _theToolsOwn(LogicalKeyboardKey key) =>
      isModifierKey(key) &&
      ModifierKeys.isAltPressed &&
      !_held.keys.any(_isAlt) &&
      canvasToolReadsAlt(tool.value.tool);

  /// What [press] holds the view for, with the modifiers as they stand —
  /// or null.
  ViewHold? _viewHoldOf(KeyEvent press) {
    if (bindings.presses(EditorActionIds.canvasRotateHold, press)) {
      return ViewHold.turn;
    }
    if (bindings.presses(EditorActionIds.canvasPanHold, press)) {
      return ViewHold.pan;
    }
    return null;
  }

  /// The eyedropper takes hold whatever tool is in hand (F-299) — but for
  /// the tools whose own drag reads its Alt ([_theToolsOwn]).
  void _holdEyedropper(LogicalKeyboardKey key) {
    _held[key] = _KeyHold.eyedropper;
    temporaryTool.hold(CanvasTool.eyedropper);
  }

  void _onStrokeLive() {
    if (strokeLive.value || _waiting.isEmpty) {
      return;
    }
    // ⚠️Not now: a stroke also ends inside a TEARDOWN (a panel unmounting
    // mid-stroke lets go of it), and switching the tool there would
    // rebuild a tree that is being taken down.
    scheduleMicrotask(_takeWaiting);
  }

  void _takeWaiting() {
    // A new stroke may have begun before the wait resolved.
    if (strokeLive.value) {
      return;
    }
    final waiting = [..._waiting];
    _waiting.clear();
    waiting.forEach(_holdEyedropper);
  }

  /// Every key let go, app-wide — and every modifier that goes down or up
  /// under a held view key, which asks that key's press again. Heard for
  /// the road's modifiers pressed alone too ([EditorShortcutBindings.lone]),
  /// before the key reaches a focus. Never consumes.
  bool _onKey(KeyEvent event) {
    bindings.lone.hearKey(event);
    final key = event.logicalKey;
    if (event is KeyUpEvent && !isModifierKey(key)) {
      _letGoOf(key);
    }
    _letGoOfModifiersNoLongerHeld();
    if (isModifierKey(key)) {
      _reaskTheView();
    }
    return false;
  }

  /// Every pointer event, app-wide — where a modifier let go with no key
  /// event is found ([_letGoOfModifiersNoLongerHeld]), and the view press
  /// asked again for it, as at a key's; and heard for the road's modifiers
  /// pressed alone, which a press comes after.
  void _onPointer(PointerEvent event) {
    bindings.lone.hearPointer(event);
    if (_letGoOfModifiersNoLongerHeld()) {
      _reaskTheView();
    }
  }

  /// [key] lets go of what it holds or waits to.
  void _letGoOf(LogicalKeyboardKey key) {
    _waiting.remove(key);
    _viewPresses.remove(key);
    final hold = _held.remove(key);
    if (hold != null) {
      _end(hold);
    }
  }

  /// Every modifier that holds or waits lets go once none of its kind is
  /// held — as [modifierHeld] says, asked at every key and pointer event,
  /// not read off its own key-up — whether any did.
  ///
  /// 🚨Card a-held-modifiers-repeat-is-heard-as-a-press: under a pen's or a
  /// finger's move Windows' engine lets go of Shift and Ctrl with the key
  /// still down, and drops the real release that comes after — a hold
  /// taken on Ctrl (F-603: modifiers alone hold too) let go at the first,
  /// and outlived the second. Both Alt keys, or both Ctrl keys, are one
  /// modifier: neither lets go while the other is held.
  bool _letGoOfModifiersNoLongerHeld() {
    final modifiers = [
      for (final key in {..._held.keys, ..._waiting})
        if (isModifierKey(key) && !modifierHeld(key)) key,
    ];
    modifiers.forEach(_letGoOf);
    return modifiers.isNotEmpty;
  }

  /// The held keys asked again, with the modifiers as they are held now:
  /// when one goes down or up, and when a press reads the hold
  /// ([CanvasViewHold.atThePress]) — a modifier let go unheard lets go of
  /// what it held, and the view press is asked again. A modifier that
  /// turns the press into neither keeps the hold as it is: Alt under Space
  /// is not a reason to let the view go.
  void _reaskTheView() {
    _letGoOfModifiersNoLongerHeld();
    if (_viewPresses.isEmpty) {
      return;
    }
    final view = _viewHoldOf(_viewPresses.values.last);
    if (view != null) {
      CanvasViewHold.held.value = view;
    }
  }

  /// Ends [hold] — unless another key still holds it.
  void _end(_KeyHold hold) {
    if (_held.containsValue(hold)) {
      return;
    }
    switch (hold) {
      case _KeyHold.view:
        CanvasViewHold.held.value = null;
      case _KeyHold.line:
        CanvasLineHold.held.value = false;
      case _KeyHold.eyedropper:
        temporaryTool.release(keep: false);
    }
  }

  /// Every hold ends — the window lost the OS's focus, and a key let go
  /// while another app has it is never heard here ([_onKey] hears every
  /// release this window gets, and that one it does not get).
  void letGoOfEverything() {
    _waiting.clear();
    _viewPresses.clear();
    final holds = {..._held.values};
    _held.clear();
    holds.forEach(_end);
  }

  /// A shell that goes away holds nothing. The view's hold is app-wide, so
  /// it lets go; a switched tool goes with the shell that owns it — putting
  /// it back would rebuild a tree that is being taken down.
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    if (CanvasViewHold.reask == _reaskTheView) {
      CanvasViewHold.reask = null;
    }
    _strokeLive.removeListener(_onStrokeLive);
    _waiting.clear();
    _viewPresses.clear();
    _held.clear();
    CanvasViewHold.held.value = null;
    CanvasLineHold.held.value = false;
  }
}

/// What a held key stands for while it is down — the view (a pan or a
/// turn, [CanvasViewHold]), the line from the last stroke
/// ([CanvasLineHold]) or the eyedropper.
enum _KeyHold { view, line, eyedropper }

bool _isAlt(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight;
