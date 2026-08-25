import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor_action_registry.dart';
import 'shortcut_activator_codec.dart';
import 'shortcut_settings_store.dart';
import 'touch_shortcuts.dart';

/// The LIVE shortcut bindings: registry defaults merged with the user's
/// persisted overrides. Notifies on every change so the app-level
/// Shortcuts map, the menu labels and the settings dialog all rebuild
/// from one source.
class EditorShortcutBindings extends ChangeNotifier {
  EditorShortcutBindings({
    this.store,
    List<EditorActionDefinition>? definitions,
  }) : definitions = definitions ?? editorActionDefinitions;

  /// Null disables persistence (tests, and FLUTTER_TEST runs).
  final ShortcutSettingsStore? store;

  final List<EditorActionDefinition> definitions;

  final Map<String, List<SingleActivator>> _overrides = {};

  EditorActionDefinition? definitionFor(String actionId) {
    for (final definition in definitions) {
      if (definition.id == actionId) {
        return definition;
      }
    }
    return null;
  }

  /// The action's LIVE activators (override or defaults). An override may
  /// be an empty list = the action is deliberately unbound.
  List<SingleActivator> activatorsFor(String actionId) {
    return _overrides[actionId] ??
        definitionFor(actionId)?.defaultActivators ??
        const [];
  }

  /// The first live activator — what menu items show as their shortcut
  /// label; null while unbound.
  SingleActivator? primaryActivatorFor(String actionId) {
    final activators = activatorsFor(actionId);
    return activators.isEmpty ? null : activators.first;
  }

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
      for (final activator in activatorsFor(definition.id)) {
        map[activator] = EditorActionIntent(definition.id);
      }
    }
    return map;
  }

  /// Action ids whose activators collide with another action's (the
  /// settings dialog highlights them).
  Set<String> get conflictedActionIds {
    final byActivator = <String, List<String>>{};
    for (final definition in definitions) {
      for (final activator in activatorsFor(definition.id)) {
        byActivator
            .putIfAbsent(activatorKey(activator), () => [])
            .add(definition.id);
      }
    }
    return {
      for (final ids in byActivator.values)
        if (ids.length > 1) ...ids,
    };
  }

  /// Replaces [actionId]'s activators; a value equal to the defaults
  /// clears the override. Persists and notifies.
  void setActivators(String actionId, List<SingleActivator> activators) {
    final defaults = definitionFor(actionId)?.defaultActivators ?? const [];
    final matchesDefaults =
        activators.length == defaults.length &&
        [
          for (var i = 0; i < activators.length; i += 1)
            activatorsEqual(activators[i], defaults[i]),
        ].every((equal) => equal);
    if (matchesDefaults) {
      _overrides.remove(actionId);
    } else {
      _overrides[actionId] = List.unmodifiable(activators);
    }
    _persist();
    notifyListeners();
  }

  void resetAction(String actionId) {
    final removedKeys = _overrides.remove(actionId) != null;
    final removedTouch = _touchOverrides.remove(actionId) != null;
    if (removedKeys || removedTouch) {
      _persist();
      notifyListeners();
    }
  }

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
  Set<String> get touchConflictedActionIds {
    final byGesture = <TouchGesture, List<String>>{};
    for (final definition in definitions) {
      final gesture = touchGestureFor(definition.id);
      if (gesture != null) {
        byGesture.putIfAbsent(gesture, () => []).add(definition.id);
      }
    }
    return {
      for (final ids in byGesture.values)
        if (ids.length > 1) ...ids,
    };
  }

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

  /// Loads persisted overrides (unknown action ids and malformed entries
  /// are dropped — an app update or corrupt file never breaks bindings).
  Future<void> restore() async {
    final payload = await store?.load();
    final overridesJson = payload?['overrides'];
    if (overridesJson is! Map) {
      return;
    }
    _overrides.clear();
    for (final entry in overridesJson.entries) {
      final actionId = entry.key;
      if (actionId is! String || definitionFor(actionId) == null) {
        continue;
      }
      final listJson = entry.value;
      if (listJson is! List) {
        continue;
      }
      _overrides[actionId] = List.unmodifiable([
        for (final activatorJson in listJson)
          ?singleActivatorFromJson(activatorJson),
      ]);
    }
    _touchOverrides.clear();
    final touchJson = payload?['touch'];
    if (touchJson is Map) {
      for (final entry in touchJson.entries) {
        final actionId = entry.key;
        if (actionId is! String || definitionFor(actionId) == null) {
          continue;
        }
        final name = entry.value;
        if (name == null) {
          _touchOverrides[actionId] = null;
        } else if (name is String) {
          final gesture = TouchGesture.fromName(name);
          if (gesture != null) {
            _touchOverrides[actionId] = gesture;
          }
        }
      }
    }
    notifyListeners();
  }

  Future<void> _pendingPersist = Future<void>.value();

  /// Resolves when every override write issued so far has hit disk —
  /// awaited by tests and available for a shutdown flush. Writes chain,
  /// so ordering (last writer wins) is preserved.
  Future<void> get pendingPersist => _pendingPersist;

  void _persist() {
    final store = this.store;
    if (store == null) {
      return;
    }
    final payload = {
      'overrides': {
        for (final entry in _overrides.entries)
          entry.key: [
            for (final activator in entry.value)
              singleActivatorToJson(activator),
          ],
      },
      'touch': {
        for (final entry in _touchOverrides.entries)
          entry.key: entry.value?.name,
      },
    };
    _pendingPersist = _pendingPersist.then((_) => store.save(payload));
  }
}

/// The app-level ShortcutManager: bare-key shortcuts (no Ctrl/Meta) stand
/// down while a text field has focus, so typing 'b' into a rename dialog
/// never switches tools. Modifier shortcuts still resolve — but any the
/// field itself handles (Ctrl+Z text undo) are consumed below us first.
class EditorShortcutManager extends ShortcutManager {
  EditorShortcutManager({super.shortcuts});

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (_editableTextHasFocus &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    return super.handleKeypress(context, event);
  }

  /// 🚨F-22 (유저 2026-08-24: 「멤버에서 클릭해서 숫자 수동편집시 **1부터
  /// 5까지의 숫자입력이 안먹히는거같음**」) — and 1…5 are the five bare-key
  /// shortcuts. The guard above was written for exactly this and never
  /// fired once.
  ///
  /// ⛔`primaryFocus.context.widget is EditableText` is not the test it
  /// reads as. `EditableText` builds a `Focus` around itself and hands that
  /// node out, so the primary focus context's own widget is that `Focus` —
  /// measured, and the comparison had been false for every text field in
  /// the app since it was written. Typing a digit into any field ran the
  /// shortcut instead, and 'b' in a rename dialog did switch tools.
  ///
  /// ★So ask the tree, not the node: the field is an ANCESTOR of the
  /// element holding focus, which is a fact about how `EditableText` is
  /// built rather than about which widget happens to own the node.
  bool get _editableTextHasFocus {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) {
      return false;
    }
    if (focusContext.widget is EditableText) {
      return true;
    }
    return focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }
}
