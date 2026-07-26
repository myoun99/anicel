import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart' show instantMenuAnimation;
import 'editor_action_registry.dart';
import 'editor_shortcut_bindings.dart';
import 'shortcut_activator_codec.dart';
import 'touch_shortcuts.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// The Keyboard Shortcuts editor (Edit menu): a searchable action list
/// grouped by category, click-to-record capture, conflict highlighting
/// and per-action / global resets — the PS/CSP settings-page convention.
class ShortcutSettingsDialog extends StatefulWidget {
  const ShortcutSettingsDialog({super.key, required this.bindings});

  final EditorShortcutBindings bindings;

  @override
  State<ShortcutSettingsDialog> createState() => _ShortcutSettingsDialogState();
}

class _ShortcutSettingsDialogState extends State<ShortcutSettingsDialog> {
  final TextEditingController _search = TextEditingController();

  /// The action currently recording a new key (null = none). While set, a
  /// key-event listener captures the next non-modifier press.
  String? _recordingActionId;
  final FocusNode _recordFocus = FocusNode(debugLabel: 'shortcut-record');

  @override
  void initState() {
    super.initState();
    widget.bindings.addListener(_onBindingsChanged);
  }

  @override
  void dispose() {
    widget.bindings.removeListener(_onBindingsChanged);
    _search.dispose();
    _recordFocus.dispose();
    super.dispose();
  }

  void _onBindingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _startRecording(String actionId) {
    setState(() => _recordingActionId = actionId);
    _recordFocus.requestFocus();
  }

  KeyEventResult _onRecordKey(FocusNode node, KeyEvent event) {
    final actionId = _recordingActionId;
    if (actionId == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _recordingActionId = null);
      return KeyEventResult.handled;
    }
    // Modifier presses alone keep waiting for the real trigger.
    final modifiers = {
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    };
    if (modifiers.contains(key)) {
      return KeyEventResult.handled;
    }
    final pressed = HardwareKeyboard.instance;
    widget.bindings.setActivators(actionId, [
      SingleActivator(
        key,
        control: pressed.isControlPressed,
        shift: pressed.isShiftPressed,
        alt: pressed.isAltPressed,
        meta: pressed.isMetaPressed,
      ),
    ]);
    setState(() => _recordingActionId = null);
    return KeyEventResult.handled;
  }

  /// The DISPLAYED wording, which is what the user is typing against — a
  /// search that only matched the English registry would find nothing in
  /// any other language.
  String _labelOf(EditorActionDefinition definition) =>
      AppText.strings.shortcutLabel(definition.id, definition.label);

  String _categoryOf(EditorActionDefinition definition) =>
      AppText.strings.shortcutCategory(
        definition.category,
        definition.category,
      );

  List<EditorActionDefinition> get _filtered {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.bindings.definitions;
    }
    return [
      for (final definition in widget.bindings.definitions)
        if (_labelOf(definition).toLowerCase().contains(query) ||
            _categoryOf(definition).toLowerCase().contains(query))
          definition,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bindings = widget.bindings;
    final conflicted = bindings.conflictedActionIds;
    final touchConflicted = bindings.touchConflictedActionIds;
    final definitions = _filtered;

    final rows = <Widget>[];
    String? category;
    for (final definition in definitions) {
      if (definition.category != category) {
        category = definition.category;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              _categoryOf(definition),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      rows.add(
        _actionRow(
          definition,
          conflicted.contains(definition.id),
          touchConflicted.contains(definition.id),
        ),
      );
    }

    return AppWindow(
      windowKey: const ValueKey<String>('shortcut-settings-dialog'),
      title: AppText.strings.shortcutTitle,
      titleIcon: Icons.keyboard_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 520,
      height: 520,
      scrollBody: false,
      body: Focus(
        focusNode: _recordFocus,
        onKeyEvent: _onRecordKey,
        child: SizedBox(
          width: 480,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('shortcut-search-field'),
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: AppText.strings.shortcutSearch,
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (conflicted.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Some actions share the same key — the highlighted '
                    'bindings collide.',
                    key: const ValueKey<String>('shortcut-conflict-banner'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: ListView(
                  key: const ValueKey<String>('shortcut-action-list'),
                  children: rows,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppWindowAction(
          label: AppText.strings.shortcutResetAll,
          actionKey: const ValueKey<String>('shortcut-reset-all-button'),
          emphasis: AppWindowActionEmphasis.danger,
          onPressed: bindings.resetAll,
        ),
        AppWindowAction(
          label: 'Close',
          actionKey: const ValueKey<String>('shortcut-close-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _actionRow(
    EditorActionDefinition definition,
    bool conflicted,
    bool touchConflicted,
  ) {
    final theme = Theme.of(context);
    final bindings = widget.bindings;
    final recording = _recordingActionId == definition.id;
    final activators = bindings.activatorsFor(definition.id);
    final touchGesture = bindings.touchGestureFor(definition.id);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(_labelOf(definition), style: theme.textTheme.bodyMedium),
          ),
          if (recording)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                AppText.strings.shortcutRecordingHint,
                key: const ValueKey<String>('shortcut-recording-hint'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            )
          else
            for (final activator in activators)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Chip(
                  label: Text(
                    singleActivatorLabel(activator),
                    style: theme.textTheme.labelSmall,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: conflicted
                      ? theme.colorScheme.errorContainer
                      : null,
                ),
              ),
          // The TOUCH binding (R11-⑨): one multi-finger gesture per
          // action, picked from the fixed vocabulary — same custom feel
          // as the key bindings, same conflict highlighting.
          PopupMenuButton<Object>(
            key: ValueKey<String>('shortcut-touch-${definition.id}'),
            tooltip: AppText.strings.shortcutTouch,
            popUpAnimationStyle: instantMenuAnimation,
            // A popup item cannot carry a null VALUE (indistinguishable
            // from dismissal), so 'None' rides a sentinel string.
            onSelected: (value) => widget.bindings.setTouchGesture(
              definition.id,
              value is TouchGesture ? value : null,
            ),
            itemBuilder: (context) => [
              PopupMenuItem<Object>(
                key: ValueKey<String>('shortcut-touch-${definition.id}-none'),
                value: 'none',
                child: const Text('None'),
              ),
              for (final gesture in TouchGesture.values)
                PopupMenuItem<Object>(
                  key: ValueKey<String>(
                    'shortcut-touch-${definition.id}-${gesture.name}',
                  ),
                  value: gesture,
                  child: Text(gesture.label),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: touchGesture == null
                  ? Icon(
                      Icons.touch_app_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    )
                  : Chip(
                      label: Text(
                        touchGesture.label,
                        style: theme.textTheme.labelSmall,
                      ),
                      avatar: const Icon(Icons.touch_app_outlined, size: 14),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: touchConflicted
                          ? theme.colorScheme.errorContainer
                          : null,
                    ),
            ),
          ),
          IconButton(
            key: ValueKey<String>('shortcut-record-${definition.id}'),
            tooltip: AppText.strings.shortcutRecordNew,
            icon: const Icon(Icons.keyboard, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => _startRecording(definition.id),
          ),
          IconButton(
            key: ValueKey<String>('shortcut-reset-${definition.id}'),
            tooltip: AppText.strings.shortcutResetToDefault,
            icon: const Icon(Icons.restart_alt, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed:
                bindings.isOverridden(definition.id) ||
                    bindings.isTouchOverridden(definition.id)
                ? () => bindings.resetAction(definition.id)
                : null,
          ),
        ],
      ),
    );
  }
}
