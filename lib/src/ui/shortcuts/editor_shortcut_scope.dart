import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'editor_action_registry.dart';
import 'editor_shortcut_bindings.dart';
import 'shortcut_activator_codec.dart';

/// The live shortcut bindings, where every control below can read them.
///
/// 🗣️I-19 (유저 2026-09-12): 「이런 버튼들 툴버튼도 그런데 툴팁으로 숏컷 키
/// 보여주도록. 낡지않을구조로.」 A tooltip that spelled its key would go stale
/// the day the key was re-recorded. A control that READS the bindings through
/// this notifier rebuilds when they change — and reads nothing where there are
/// none, a widget pumped on its own.
class EditorShortcutScope extends InheritedNotifier<EditorShortcutBindings> {
  const EditorShortcutScope({
    super.key,
    required EditorShortcutBindings bindings,
    required super.child,
  }) : super(notifier: bindings);

  static EditorShortcutBindings? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<EditorShortcutScope>()
      ?.notifier;

  /// The bindings WITHOUT subscribing — for a key handler, which runs outside
  /// any build and has nothing to rebuild.
  static EditorShortcutBindings? peek(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EditorShortcutScope>()?.notifier;
}

/// A registry action's name in the program language — the ONE name its
/// button, its menu item and the shortcut list all say.
String editorActionLabel(String actionId) {
  final definition = editorActionDefinitions.firstWhere(
    (definition) => definition.id == actionId,
  );
  return AppText.strings.shortcutLabel(actionId, definition.label);
}

/// [label] followed by the live keys of the actions a control is the entrance
/// of — 「Copy (Ctrl+C)」, 「Select Tool (M, L)」, 「コピー (⌘C)」.
///
/// ⛔No key is ever written at a call site: a control names its ACTIONS and
/// the bindings answer, so the key the user re-records is the key shown.
String shortcutTooltip(
  BuildContext context,
  String label,
  List<String> actionIds,
) {
  if (actionIds.isEmpty) {
    return label;
  }
  final bindings = EditorShortcutScope.maybeOf(context);
  if (bindings == null) {
    return label;
  }
  final keys = [
    for (final actionId in actionIds)
      if (bindings.primaryActivatorFor(actionId) case final activator?)
        singleActivatorLabel(activator),
  ];
  return keys.isEmpty ? label : '$label (${keys.join(', ')})';
}

/// A [Tooltip] spelled by [shortcutTooltip], for a control that is not an
/// [AppIconButton] — the comma set's text buttons.
///
/// ⚠️A WIDGET, not a string built by the caller: the toolbars cache their
/// groups, and a string composed in a cached builder would keep the key it
/// was built with. Reading the bindings in this build is what re-labels it
/// when a key is re-recorded.
class ShortcutTooltip extends StatelessWidget {
  const ShortcutTooltip({
    super.key,
    required this.label,
    required this.shortcuts,
    required this.child,
  });

  final String label;
  final List<String> shortcuts;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: shortcutTooltip(context, label, shortcuts),
    child: child,
  );
}
