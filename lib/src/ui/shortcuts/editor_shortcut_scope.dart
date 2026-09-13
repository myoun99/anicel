import 'package:flutter/material.dart';

import '../brush/tool_press.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart';
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
///
/// ⚠️A shape tile's name is COMPOSED rather than tabled ([shapeTileLabel]),
/// so it is asked here, where every reader of a name already comes.
String editorActionLabel(String actionId) {
  final definition = editorActionDefinitions.firstWhere(
    (definition) => definition.id == actionId,
  );
  if (definition.toolPress case ShapeTilePress(:final verb, :final shape)) {
    return shapeTileLabel(verb, shape);
  }
  return AppText.strings.shortcutLabel(actionId, definition.label);
}

/// [label] followed by the live keys of the actions a control is the entrance
/// of — 「Copy (Ctrl+C)」, 「Brush Tool (B)」, 「コピー (⌘C)」.
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
  final keys = shortcutKeys(EditorShortcutScope.maybeOf(context), actionIds);
  return keys == null ? label : '$label ($keys)';
}

/// The live keys of [actionIds] as one label — 「Ctrl+S」, 「B, E」 — or null
/// when none of them is bound. ★The ONE spelling a button's tooltip and a
/// menu row's trailing key both print.
String? shortcutKeys(EditorShortcutBindings? bindings, List<String> actionIds) {
  if (bindings == null || actionIds.isEmpty) {
    return null;
  }
  final keys = [
    for (final actionId in actionIds)
      if (bindings.primaryActivatorFor(actionId) case final activator?)
        singleActivatorLabel(activator),
  ];
  return keys.isEmpty ? null : keys.join(', ');
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

/// The live keys of [actionIds] for a row that already says its own name —
/// 「저장 Ctrl+S」: after the label, dim, and nothing at all while unbound.
///
/// 🗣️유저 2026-09-13 (I-19-menu-keys): 「중간에 점 두는게아니라 저장 Ctrl+S
/// 이런식으로. 단축키 텍스트는 흐린색. 단축키 텍스트 오른쪽정렬」 — then
/// 「단축키 색 지금보다 더 불투명도 낮춰서. 진짜 흐리게」. ONE widget for every
/// such row — a menu item, a tile of the tool library — so how a key beside a
/// name looks is decided once ([AppColors.shortcutKeys]).
class ShortcutKeysText extends StatelessWidget {
  const ShortcutKeysText({
    super.key,
    required this.actionIds,
    this.bindings,
    this.enabled = true,
  });

  final List<String> actionIds;

  /// Null reads the scope above. A flyout is a ROUTE, outside the scope, so
  /// it hands in the bindings it read where it opened.
  final EditorShortcutBindings? bindings;

  /// Whether the row can be pressed — a dead row's key is dimmer still.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final keys = shortcutKeys(
      bindings ?? EditorShortcutScope.maybeOf(context),
      actionIds,
    );
    if (keys == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Text(
        keys,
        style: TextStyle(
          fontSize: 12,
          color: enabled
              ? AppColors.shortcutKeys
              : AppColors.shortcutKeysDisabled,
        ),
      ),
    );
  }
}
