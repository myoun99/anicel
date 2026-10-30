import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/input/modifier_keys.dart';
import '../../services/shortcuts/program_keymap.dart';
import '../debug/key_trace.dart';
import 'brush_actions.dart';
import 'editor_action_registry.dart';
import 'focused_text_field.dart';
import 'panel_actions.dart';
import 'sheet_arrow.dart';
import 'shortcut_activator_codec.dart';
import 'shortcut_presets.dart';
import 'shortcut_settings_store.dart';
import 'touch_shortcuts.dart';

/// The layout an install opens on ([EditorShortcutBindings.preset]).
const ShortcutLayout _startingPreset = ShortcutPreset.clipStudio;

/// The LIVE shortcut bindings: the keys of the preset in use merged with the
/// user's persisted overrides. Notifies on every change so the app-level
/// Shortcuts map, the menu labels and the settings dialog all rebuild
/// from one source.
class EditorShortcutBindings extends ChangeNotifier {
  EditorShortcutBindings({
    this.store,
  });

  /// Null disables persistence (tests, and FLUTTER_TEST runs).
  final ShortcutSettingsStore? store;

  /// Every action a key can be put on: the registry's, then the workspace's
  /// panels ([setPanelActions]) and the brush library's ([setBrushActions])
  /// as they stand.
  List<EditorActionDefinition> get definitions => _definitions;
  List<EditorActionDefinition> _definitions = editorActionsHere();
  Map<String, EditorActionDefinition> _definitionsById = {
    for (final definition in editorActionsHere()) definition.id: definition,
  };

  List<EditorActionDefinition> _panelActions = const [];
  List<EditorActionDefinition> _brushActions = const [];

  /// The brush library's rows (I-56, `brushActionsOf`) — the last of the
  /// list, changing with the library. Notifies when they are other rows.
  ///
  /// ⚠️What was recorded for a brush that is not among [actions] stays where
  /// it is and presses nothing ([isBrushActionId]).
  void setBrushActions(List<EditorActionDefinition> actions) {
    if (!_sameRows(_brushActions, actions)) {
      _brushActions = actions;
      _relist();
    }
  }

  /// The workspace's panels as rows (I-40, `panelActionsOf`) — right after
  /// the registry's, whose last category they continue. The same law as the
  /// brushes' ([isPanelActionId]).
  void setPanelActions(List<EditorActionDefinition> actions) {
    if (!_sameRows(_panelActions, actions)) {
      _panelActions = actions;
      _relist();
    }
  }

  /// Whether [rows] are the rows already [held]. What these are made from
  /// tells of every change — a group folded shut in its panel, a panel shown
  /// or hidden — and everything that shows a key listens here: rows that
  /// are what they were tell nobody.
  static bool _sameRows(
    List<EditorActionDefinition> held,
    List<EditorActionDefinition> rows,
  ) =>
      held.length == rows.length &&
      Iterable<int>.generate(rows.length).every(
        (i) =>
            held[i].id == rows[i].id &&
            held[i].label == rows[i].label &&
            held[i].brushPress == rows[i].brushPress,
      );

  void _relist() {
    _definitions = [
      ...editorActionsHere(),
      ..._panelActions,
      ..._brushActions,
    ];
    _definitionsById = {
      for (final definition in _definitions) definition.id: definition,
    };
    notifyListeners();
  }

  /// The layout the keys start from (I-63): a preset the app ships, or one
  /// of the user's ([userPresets], I-107).
  ///
  /// 🗣️I-63-Q5 (유저 2026-10-09): an install opens on 「클립 스튜디오
  /// 기반」. ↩️It opened on [ShortcutPreset.anicel] until that answer; the
  /// first words (유저 2026-10-03: 「기본값은 일반으로」) named a preset that
  /// became the two programs' ones.
  /// ⚠️Only the shortcut file tells a device in use from a new install, and
  /// a device whose keys were never changed has none — it opens here too, as
  /// the question said it would.
  ShortcutLayout get preset => _preset;
  ShortcutLayout _preset = _startingPreset;

  /// The presets the user made, in the order they were made (I-107).
  List<UserShortcutPreset> get userPresets => _userPresets;
  List<UserShortcutPreset> _userPresets = const [];

  /// What the user recorded, PER PRESET: a key recorded while one layout is
  /// in use is a change to that layout, and stays with it — a preset of the
  /// user's keeps its own ([UserShortcutPreset.recorded]).
  ///
  /// ⚠️Not said by the user — asked on the board (I-63-Q6). One set over
  /// every preset would carry a repair made for one program's layout (a key
  /// moved off a clash that only that layout has) into the others.
  final Map<ShortcutPreset, Map<String, List<SingleActivator>>>
  _overridesByPreset = {
    for (final preset in ShortcutPreset.values) preset: {},
  };

  /// What was recorded while [layout] was in use.
  Map<String, List<SingleActivator>> _recordedUnder(ShortcutLayout layout) =>
      switch (layout) {
        ShortcutPreset() => _overridesByPreset[layout]!,
        UserShortcutPreset(:final recorded) => recorded,
      };

  Map<String, List<SingleActivator>> get _overrides => _recordedUnder(_preset);

  /// Starts from [preset]'s keys, under whatever was recorded while it was
  /// last in use. Persists and notifies.
  void setPreset(ShortcutLayout preset) {
    if (preset == _preset) {
      return;
    }
    _preset = preset;
    _persist();
    notifyListeners();
  }

  EditorActionDefinition? definitionFor(String actionId) =>
      _definitionsById[actionId];

  /// Whether a saved entry for [actionId] is kept: an action there is, or a
  /// brush the library — a panel the workspace — may yet tell of.
  bool keeps(String actionId) =>
      definitionFor(actionId) != null ||
      isBrushActionId(actionId) ||
      isPanelActionId(actionId);

  /// The keys the preset in use was made with for [actionId].
  List<SingleActivator> defaultActivatorsFor(String actionId) =>
      _madeKeys(_preset, actionId);

  /// The keys [layout] was made with for [actionId]: its own, or the ones
  /// the preset it stands on ships the action with ([presetActivators]) as
  /// THIS platform presses them — the command modifier written as Ctrl is ⌘
  /// on a Mac or an iPad ([platformActivator]).
  List<SingleActivator> _madeKeys(ShortcutLayout layout, String actionId) {
    if (layout.ownKeys[actionId] case final own?) {
      return own;
    }
    final definition = definitionFor(actionId);
    return [
      if (definition != null)
        for (final activator in presetActivators(layout.base, definition))
          platformActivator(activator),
    ];
  }

  /// The action's LIVE activators (override or defaults). An override may
  /// be an empty list = the action is deliberately unbound.
  List<SingleActivator> activatorsFor(String actionId) =>
      _heldUnder(_preset, actionId);

  /// What [actionId] holds under [layout]: what was recorded while it was in
  /// use, or what it was made with.
  List<SingleActivator> _heldUnder(ShortcutLayout layout, String actionId) =>
      _recordedUnder(layout)[actionId] ?? _madeKeys(layout, actionId);

  /// The first live activator — what menu items show as their shortcut
  /// label; null while unbound.
  SingleActivator? primaryActivatorFor(String actionId) {
    final activators = activatorsFor(actionId);
    return activators.isEmpty ? null : activators.first;
  }

  /// Whether [event] presses a view-ZOOM action through its live keys —
  /// the question the playback gate asks for R6q3.
  bool zoomsViewOn(KeyEvent event) {
    for (final definition in definitions) {
      if (definition.zoomsView && presses(definition.id, event)) {
        return true;
      }
    }
    return false;
  }

  /// Whether [event] presses [actionId] through one of its live keys, in
  /// any of the forms [pressableForms] names.
  ///
  /// ★THE ONE ANSWER to 「does this key press that action」: the app-level
  /// [shortcuts] map is built from the same forms, and the held keys and the
  /// playback gate ask here — so a key a layout types differently presses
  /// all three or none of them.
  ///
  /// 🚨With the modifiers AS HELD ([ModifierKeys.keyboard]): a held view
  /// key is asked again whenever they change, and on Windows a pen's move
  /// lets go of Shift in the engine's record with the key still down —
  /// Shift+Space turned into the pan under a pen (I-61). At a key that
  /// presses anything the two agree: the engine syncs to Windows first.
  bool presses(String actionId, KeyEvent event) {
    for (final activator in activatorsFor(actionId)) {
      for (final form in _formsOf(actionId, activator)) {
        if (form.accepts(event, ModifierKeys.keyboard)) {
          return true;
        }
      }
    }
    return false;
  }

  /// How the sheet in front of the user turns the arrows (F-241) — the
  /// shell hands its flip HUD in. Null reads every arrow as the timeline
  /// does.
  SheetArrowTurn? sheet;

  /// The sheet's direction keys as the bindings stand: every key bound bare
  /// to a move that walks a way — not its one-frame step — in the order the
  /// move lists them (F-261, [SheetKeys]).
  SheetKeys get sheetKeys {
    final keysByArrow = {
      for (final arrow in SheetArrow.values) arrow: <LogicalKeyboardKey>[],
    };
    for (final definition in definitions) {
      if (definition.sheetMove case (:final arrow, fine: false)) {
        keysByArrow[arrow]!.addAll([
          for (final activator in activatorsFor(definition.id))
            if (!activator.shift &&
                !activator.control &&
                !activator.alt &&
                !activator.meta)
              activator.trigger,
        ]);
      }
    }
    return SheetKeys(keysByArrow);
  }

  /// [activator]'s pressable forms for [actionId]: a DIRECTION key of a move
  /// on the sheet ([EditorActionDefinition.sheetMove]) is matched turned.
  Iterable<ShortcutActivator> _formsOf(
    String actionId,
    SingleActivator activator,
  ) {
    final place = _turnOf(actionId, activator);
    return place == null
        ? pressableForms(activator)
        : [SheetTurnedActivator(activator, () => sheet, place.keys)];
  }

  /// Where [activator] of [actionId] turns: its key's place among the
  /// direction keys, or null when it does not turn.
  ({SheetKeys keys, SheetArrow arrow, int set})? _turnOf(
    String actionId,
    SingleActivator activator,
  ) {
    if (definitionFor(actionId)?.sheetMove == null) {
      return null;
    }
    final keys = sheetKeys;
    final place = keys.placeOf(activator.trigger);
    return place == null
        ? null
        : (keys: keys, arrow: place.arrow, set: place.set);
  }

  /// [activator] as it reads on the sheet in front of the user — a turned
  /// key shows the key that presses it HERE (유저 F-241: 「단축키 바뀐
  /// 상황에서 그에맞게 텍스트 내용도 변경」).
  SingleActivator shownActivatorFor(
    String actionId,
    SingleActivator activator,
  ) {
    final turn = sheet;
    final place = _turnOf(actionId, activator);
    if (turn == null || place == null) {
      return activator;
    }
    final shown = turn.sheetArrowFor(place.arrow);
    return _withTrigger(activator, place.keys.keyAt(shown, place.set));
  }

  /// [pressed], recorded for [actionId] on the sheet in front of the user,
  /// as it is kept: a turned key is kept as the timeline reads it, so it
  /// turns again on the other sheet.
  SingleActivator keptActivatorFor(
    String actionId,
    SingleActivator pressed,
  ) {
    final turn = sheet;
    final place = _turnOf(actionId, pressed);
    if (turn == null || place == null) {
      return pressed;
    }
    final kept = turn.timelineArrowFor(place.arrow);
    return _withTrigger(pressed, place.keys.keyAt(kept, place.set));
  }

  static SingleActivator _withTrigger(
    SingleActivator activator,
    LogicalKeyboardKey trigger,
  ) => SingleActivator(
    trigger,
    control: activator.control,
    shift: activator.shift,
    alt: activator.alt,
    meta: activator.meta,
  );

  bool isOverridden(String actionId) => _overrides.containsKey(actionId);

  bool isTouchOverridden(String actionId) =>
      _touchOverrides.containsKey(actionId);

  /// The app-level Shortcuts map: every live activator → the action's
  /// intent. On a conflict (one activator bound to several actions) the
  /// LAST registry entry wins here; [conflictedActionIds] surfaces the
  /// clash to the settings dialog.
  Map<ShortcutActivator, Intent> get shortcuts {
    final map = <ShortcutActivator, Intent>{};
    for (final definition in definitions) {
      // A HELD action is taken on the way past (EditorKeyHolds), never
      // dispatched as an intent.
      if (definition.hold) {
        continue;
      }
      for (final activator in activatorsFor(definition.id)) {
        for (final form in _formsOf(definition.id, activator)) {
          map[form] = EditorActionIntent(definition.id);
        }
      }
    }
    return map;
  }

  /// Action ids whose activators collide with another action's (the
  /// settings dialog highlights them).
  Set<String> get conflictedActionIds => _conflictedIds(
    (actionId) => activatorsFor(actionId).map(activatorKey),
  );

  /// Every action id that shares one of its [keysOf] keys with another
  /// action — the key→actions inversion both conflict queries are.
  Set<String> _conflictedIds<K>(Iterable<K> Function(String actionId) keysOf) {
    final byKey = <K, List<String>>{};
    for (final definition in definitions) {
      for (final key in keysOf(definition.id)) {
        byKey.putIfAbsent(key, () => []).add(definition.id);
      }
    }
    return {
      for (final ids in byKey.values)
        if (ids.length > 1) ...ids,
    };
  }

  /// Replaces [actionId]'s activators; a value equal to the defaults
  /// clears the override. Persists and notifies.
  void setActivators(String actionId, List<SingleActivator> activators) {
    if (_sameKeys(activators, defaultActivatorsFor(actionId))) {
      _overrides.remove(actionId);
    } else {
      _overrides[actionId] = List.unmodifiable(activators);
    }
    _persist();
    notifyListeners();
  }

  static bool _sameKeys(List<SingleActivator> a, List<SingleActivator> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every(
        (i) => activatorsEqual(a[i], b[i]),
      );

  /// [preset] copied — what it was made with and what was recorded over that
  /// — into a new preset of the user's named [name], which comes into use:
  /// the layout in use by the ＋ of the window's list (I-107-Q1), any of the
  /// list's by its row's duplicate (I-107-Q3).
  UserShortcutPreset duplicatePreset(ShortcutLayout preset, String name) =>
      _add(name, preset.base, keysOf(preset));

  /// What [preset] presses over its base's: what it was made with, and
  /// what was recorded over that — what a duplicate of it holds, and a
  /// file of it (I-142).
  Map<String, List<SingleActivator>> keysOf(ShortcutLayout preset) => {
    ...preset.ownKeys,
    ..._recordedUnder(preset),
  };

  /// [preset] under [name]. Saves and notifies.
  void renamePreset(UserShortcutPreset preset, String name) {
    preset.name = name;
    _persist();
    notifyListeners();
  }

  /// [keys] over [base]'s as a new preset of the user's named [name], which
  /// comes into use. Persists and notifies.
  UserShortcutPreset _add(
    String name,
    ShortcutPreset base,
    Map<String, List<SingleActivator>> keys,
  ) {
    final preset = UserShortcutPreset(
      id: _unusedId(),
      name: name,
      base: base,
      keys: keys,
    );
    _userPresets = List.unmodifiable([..._userPresets, preset]);
    _preset = preset;
    _persist();
    notifyListeners();
    return preset;
  }

  /// An id none of the user's presets has.
  String _unusedId() {
    var number = _userPresets.length + 1;
    while (_userPresets.any((preset) => preset.id == 'user-$number')) {
      number += 1;
    }
    return 'user-$number';
  }

  /// Takes [preset] off the list, and what was recorded under it with it.
  /// ⚠️MY READING — not said: one deleted while it is in use leaves the
  /// preset it stood on in use.
  void deletePreset(UserShortcutPreset preset) {
    if (!_userPresets.contains(preset)) {
      return;
    }
    _userPresets = List.unmodifiable([
      for (final kept in _userPresets)
        if (kept != preset) kept,
    ]);
    if (_preset == preset) {
      _preset = preset.base;
    }
    _persist();
    notifyListeners();
  }

  /// A new preset of the user's named [name], made of [keymaps] — files of
  /// the program whose preset is [base].
  ///
  /// The presets' law ([ProgramKeys]) with the files as the program: an
  /// action they give keys takes those and no other, and every other action
  /// keeps what it holds, less any key they gave another.
  /// ⚠️MY READING of 「파일이 말하지 않은 동작은 그대로」: what an action
  /// holds is what it holds in the layout in use where that stands on the
  /// same program's preset — CLIP STUDIO's two files may come in one after
  /// the other, and the second builds on the first — and otherwise what it
  /// holds in that program's preset, as the user has it.
  UserShortcutPreset presetOfFiles(
    String name,
    ShortcutPreset base,
    List<ProgramKeymap> keymaps,
  ) {
    final law = ProgramKeys({
      for (final MapEntry(key: actionId, value: keys)
          in fileKeysOf(keymaps).entries)
        actionId: [for (final key in keys) platformActivator(key)],
    });
    final from = _preset.base == base ? _preset : base;
    final made = <String, List<SingleActivator>>{};
    for (final actionId in {
      for (final definition in definitions) definition.id,
      ...from.ownKeys.keys,
      ..._recordedUnder(from).keys,
    }) {
      final keys = law.of(actionId, _heldUnder(from, actionId));
      if (!_sameKeys(keys, _madeKeys(base, actionId))) {
        made[actionId] = List.unmodifiable(keys);
      }
    }
    return _add(name, base, made);
  }

  void resetAction(String actionId) {
    final removedKeys = _overrides.remove(actionId) != null;
    final removedTouch = _touchOverrides.remove(actionId) != null;
    if (removedKeys || removedTouch) {
      _persist();
      notifyListeners();
    }
  }

  /// Back to the keys the preset in use ships with, and the registry's touch
  /// gestures. What was recorded under another preset stays with it.
  void resetAll() {
    if (_overrides.isEmpty && _touchOverrides.isEmpty) {
      return;
    }
    _overrides.clear();
    _touchOverrides.clear();
    _persist();
    notifyListeners();
  }

  // --- Touch gestures (R11-⑨) ----------------------------------------------
  //
  // Every registry action may bind ONE multi-finger gesture, mirroring the
  // key overrides: registry default + persisted user override, an explicit
  // null override = deliberately unbound.

  final Map<String, TouchGesture?> _touchOverrides = {};

  /// The action's LIVE touch gesture (override or registry default).
  TouchGesture? touchGestureFor(String actionId) {
    if (_touchOverrides.containsKey(actionId)) {
      return _touchOverrides[actionId];
    }
    return TouchGesture.fromName(definitionFor(actionId)?.defaultTouchGesture);
  }

  /// The dispatch lookup for a fired gesture; null while unbound. On a
  /// conflict the LAST registry entry wins (keyboard parity);
  /// [touchConflictedActionIds] surfaces the clash to the dialog.
  String? actionIdForTouchGesture(TouchGesture gesture) {
    String? actionId;
    for (final definition in definitions) {
      if (touchGestureFor(definition.id) == gesture) {
        actionId = definition.id;
      }
    }
    return actionId;
  }

  /// Action ids whose touch gesture collides with another action's.
  Set<String> get touchConflictedActionIds => _conflictedIds((actionId) {
    final gesture = touchGestureFor(actionId);
    return gesture == null ? const <TouchGesture>[] : [gesture];
  });

  /// Binds (or with null, unbinds) [actionId]'s touch gesture; a value
  /// equal to the registry default clears the override.
  void setTouchGesture(String actionId, TouchGesture? gesture) {
    final defaultGesture = TouchGesture.fromName(
      definitionFor(actionId)?.defaultTouchGesture,
    );
    if (gesture == defaultGesture) {
      _touchOverrides.remove(actionId);
    } else {
      _touchOverrides[actionId] = gesture;
    }
    _persist();
    notifyListeners();
  }

  /// Loads the persisted preset and overrides, as
  /// [shortcutSettingsFromPayload] reads them — or, where the file holds
  /// none, the keys an install opens on: [_startingPreset], nothing
  /// recorded. With no [store] (a test), what is held stays.
  ///
  /// 🗣️I-142-Q3 (유저 2026-10-29): 「전부 갈아끼운다」 — a settings file
  /// that put the keys back at their defaults puts them back here.
  /// ↩️Nothing read kept the keys as they were (10-29).
  Future<void> restore() async {
    final store = this.store;
    if (store == null) {
      return;
    }
    final saved = shortcutSettingsFromPayload(
      await store.load(),
      keeps: keeps,
    );
    _userPresets = List.unmodifiable(saved?.userPresets ?? const []);
    _preset = saved?.inUse ?? _startingPreset;
    for (final MapEntry(key: preset, value: overrides)
        in _overridesByPreset.entries) {
      overrides
        ..clear()
        ..addAll(saved?.recorded[preset] ?? const {});
    }
    _touchOverrides
      ..clear()
      ..addAll(saved?.touch ?? const {});
    notifyListeners();
  }

  Future<void> _pendingPersist = Future<void>.value();

  /// Resolves once the file holds the last overrides written — awaited by
  /// tests and available for a shutdown flush. The writes keep their order
  /// ([saveVersionedSettings]), so the last one written is the one kept.
  Future<void> get pendingPersist => _pendingPersist;

  void _persist() {
    final store = this.store;
    if (store == null) {
      return;
    }
    _pendingPersist = store.save(
      shortcutSettingsPayload(
        inUse: _preset,
        recorded: {
          for (final layout in [...ShortcutPreset.values, ..._userPresets])
            layout: _recordedUnder(layout),
        },
        userPresets: _userPresets,
        touch: _touchOverrides,
      ),
    );
  }
}

/// Every form in which [activator] can be pressed: the key itself, and —
/// where a layout puts the character that key names on Shift — the
/// combination that TYPES it.
///
/// 🚨★★A KEY IS THE CHARACTER IT TYPES (a-key-is-the-character-it-types).
/// 🗣️유저 2026-09-13 (I-19): 「일본어 키보드나 한국어 상태등 키보드가 영어가
/// 아닐때도 대응하도록」. A binding like `=` names a character, but a
/// [SingleActivator] matches a logical KEY, and Windows names a printable
/// key by what it types UNSHIFTED. On a JIS keyboard `=` is Shift+-: the
/// event is `minus` with Shift held, typing '=', and `SingleActivator(equal)`
/// never sees it — the Solo key had no way in at all. ↩️Solo ships on T
/// since F-261; the law stands for every binding that names a character,
/// the ones a user records included.
///
/// ⛔ONLY UNDER SHIFT, and that is not a preference. Shift is the one way a
/// character arrives under ANOTHER key's name (a key is named by its
/// unshifted character), so it is exactly the case a key binding misses. A
/// plain [CharacterActivator] would also answer keys that type the same
/// character without Shift — the numpad's `.` would step a frame the way
/// `.` does, which nobody asked for.
///
/// ⚠️Only a binding with no Shift of its own names a character; Shift+.
/// names the `>` KEY. And only one printed character that is not a letter:
/// a letter key reports its own letter on every layout already.
/// ⚠️Where the platform types no character — Windows under Ctrl — the typed
/// form never matches, and the key alone answers as it always did.
/// ⚠️A key bound explicitly beats the typed form of another binding: the
/// Shortcuts manager tries keyed activators before unkeyed ones.
Iterable<ShortcutActivator> pressableForms(SingleActivator activator) sync* {
  yield activator;
  final label = activator.trigger.keyLabel;
  final namesACharacter =
      !activator.shift &&
      label.runes.length == 1 &&
      label.trim().isNotEmpty &&
      label.toLowerCase() == label.toUpperCase();
  if (namesACharacter) {
    yield ShiftTypedActivator(
      CharacterActivator(
        label,
        control: activator.control,
        alt: activator.alt,
        meta: activator.meta,
      ),
    );
  }
}

/// [timeline] — a direction key written as the timeline reads it — pressed
/// on whichever sheet is up: the key that arrives is turned by [turn] to its
/// set's key for the way it reads before it is matched (F-241,
/// `SheetArrowTurn`; F-261, [SheetKeys]). Null turns nothing.
class SheetTurnedActivator extends ShortcutActivator {
  const SheetTurnedActivator(this.timeline, this.turn, this.keys);

  final SingleActivator timeline;
  final SheetArrowTurn? Function() turn;
  final SheetKeys keys;

  /// The keys of [timeline]'s set — the only ones that can turn into it.
  @override
  Iterable<LogicalKeyboardKey> get triggers =>
      keys.setOf(keys.placeOf(timeline.trigger)!.set);

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    final pressed = keys.placeOf(event.logicalKey);
    if (pressed == null) {
      return false;
    }
    final read = turn()?.timelineArrowFor(pressed.arrow) ?? pressed.arrow;
    return timeline.accepts(
      _withKey(event, keys.keyAt(read, pressed.set)),
      state,
    );
  }

  static KeyEvent _withKey(KeyEvent event, LogicalKeyboardKey key) =>
      switch (event) {
        KeyDownEvent() => KeyDownEvent(
          physicalKey: event.physicalKey,
          logicalKey: key,
          character: event.character,
          timeStamp: event.timeStamp,
          synthesized: event.synthesized,
          deviceType: event.deviceType,
        ),
        KeyRepeatEvent() => KeyRepeatEvent(
          physicalKey: event.physicalKey,
          logicalKey: key,
          character: event.character,
          timeStamp: event.timeStamp,
          deviceType: event.deviceType,
        ),
        _ => KeyUpEvent(
          physicalKey: event.physicalKey,
          logicalKey: key,
          timeStamp: event.timeStamp,
          synthesized: event.synthesized,
          deviceType: event.deviceType,
        ),
      };

  @override
  String debugDescribeKeys() =>
      'sheet-turned ${timeline.debugDescribeKeys()}';
}

/// [typed]'s character reached with Shift held — the form [pressableForms]
/// adds for a layout that puts that character on Shift.
class ShiftTypedActivator extends ShortcutActivator {
  const ShiftTypedActivator(this.typed);

  final CharacterActivator typed;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      state.isShiftPressed && typed.accepts(event, state);

  @override
  String debugDescribeKeys() => 'Shift-typed ${typed.debugDescribeKeys()}';
}

/// The app-level ShortcutManager, and what it leaves to a text field.
///
/// A focused field keeps two kinds of key: every BARE key (typing 'b' into a
/// rename dialog never switches tools) and every key the field's own text
/// shortcuts bind (Ctrl+C, ⌘Z …). Any other modified key still resolves
/// here while a field has focus — Ctrl+S saves from inside a rename box.
class EditorShortcutManager extends ShortcutManager {
  EditorShortcutManager({super.shortcuts, this.onHoldKey});

  /// The held keys (I-15, `EditorKeyHolds.engage`) — taken on THIS road,
  /// after the text-field guard, so a focused field keeps its space bar the
  /// same way it keeps its letters.
  final KeyEventResult Function(KeyEvent event)? onHoldKey;

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    // F-241: every answer goes to the input inspector's `bind` line.
    if (_fieldKeeps(event)) {
      KeyTrace.answered(event, 'kept by the focused text field');
      return KeyEventResult.ignored;
    }
    final held = onHoldKey?.call(event) ?? KeyEventResult.ignored;
    if (held == KeyEventResult.handled) {
      KeyTrace.answered(event, 'held');
      return held;
    }
    final result = super.handleKeypress(context, event);
    if (event is! KeyUpEvent) {
      // ⚠️The engine's record, not the held keys: this says what the
      // manager above just ran, and it reads the record itself.
      final intent = shortcuts.entries
          .where((entry) => entry.key.accepts(event, HardwareKeyboard.instance))
          .firstOrNull
          ?.value;
      KeyTrace.answered(
        event,
        '${intent is EditorActionIntent ? intent.actionId : 'no binding'}'
        ' (${result.name})',
      );
    }
    return result;
  }

  /// Whether the text field that has focus keeps [event] for itself.
  ///
  /// 🚨I-19 (2026-09-13). Modified keys used to pass straight through, on
  /// the premise that 「the ones the field itself owns (Ctrl+Z) are consumed
  /// below us」. They never were: the platform's text shortcuts are mounted
  /// by the APP, above this manager, and a key climbs from the field — so it
  /// reaches this manager first. 🧪Measured: with Ctrl+C bound here, Ctrl+C
  /// in a focused TextField fired the binding, and so did Ctrl+V, Ctrl+X,
  /// Ctrl+Z and a Mac's ⌘C. Binding Ctrl+C to the timeline's copy would
  /// have made a rename box copy a FRAME.
  ///
  /// ★So the field's own path is asked: a key that another shortcut table
  /// between the field and the app binds belongs to that table — the text
  /// system's, in each platform's own modifier — and stands down here. The
  /// premise is made true rather than assumed.
  ///
  /// ⚠️Asked of the engine's record, not of the held keys: those tables are
  /// run by managers that read the record, and this says what they will do.
  bool _fieldKeeps(KeyEvent event) {
    final focusContext = focusedTextField();
    if (focusContext == null) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return true;
    }
    var bound = false;
    focusContext.visitAncestorElements((element) {
      final widget = element.widget;
      bound =
          widget is Shortcuts &&
          !identical(widget.manager, this) &&
          widget.shortcuts.keys.any(
            (activator) => activator.accepts(event, keyboard),
          );
      return !bound;
    });
    return bound;
  }
}
