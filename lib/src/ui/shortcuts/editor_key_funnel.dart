import 'package:flutter/material.dart';

import 'editor_action_registry.dart';
import 'editor_shortcut_bindings.dart';

/// THE SHELL'S KEY ROAD: the bindings a key is read against, the held keys
/// (I-15 — 「이동」 on Space, the eyedropper's Alt) and the funnel a bound
/// key runs into.
typedef EditorKeyRoad = ({
  EditorShortcutBindings bindings,
  KeyEventResult Function(KeyEvent event) onHoldKey,
  void Function(String actionId) invoke,
});

/// The bound keys over [child]: the bindings' map through
/// [EditorShortcutManager] — a held key first, bare letters standing down
/// while a text field has focus — and every key it binds into the road's
/// funnel, which [admits].
///
/// 🗣️ONE for the shell and a window over it (I-127, 유저 2026-10-25: 「도구
/// 단축키 통해서 변경하든 변경가능하게 … 물론 언두도 가능」): a dialog's route
/// is no child of the shell, so a key pressed in it never reaches the
/// shell's layer — the window lays the same one round itself.
class EditorKeyFunnel extends StatelessWidget {
  const EditorKeyFunnel({
    super.key,
    required this.road,
    this.enabled = true,
    this.admits,
    required this.child,
  });

  final EditorKeyRoad road;

  /// False stands every key and hold down — the window takes none while
  /// it runs.
  final bool enabled;

  /// Which bound actions reach the funnel; null lets every one through.
  final bool Function(String actionId)? admits;

  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: road.bindings,
    builder: (context, child) => Shortcuts.manager(
      manager: EditorShortcutManager(
        shortcuts: road.bindings.shortcuts,
        onHoldKey: enabled ? road.onHoldKey : null,
      ),
      child: Actions(
        actions: {
          EditorActionIntent: CallbackAction<EditorActionIntent>(
            onInvoke: (intent) {
              if (enabled && (admits?.call(intent.actionId) ?? true)) {
                road.invoke(intent.actionId);
              }
              return null;
            },
          ),
        },
        child: child!,
      ),
    ),
    child: child,
  );
}
