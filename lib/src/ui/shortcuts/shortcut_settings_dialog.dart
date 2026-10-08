import '../widgets/app_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/brush_group.dart';
import '../brush/brush_press.dart';
import '../timeline/layer_rail_columns.dart' show LayerFoldTwirl;
import '../widgets/panel_flyout.dart';
import '../widgets/pill_strip.dart';
import 'brush_actions.dart';
import 'editor_action_registry.dart';
import 'editor_shortcut_bindings.dart';
import 'editor_shortcut_scope.dart';
import 'shortcut_activator_codec.dart';
import 'shortcut_presets.dart';
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

  /// Takes every key off [actionId] — its own default too, which then
  /// stays off until the row is reset. A recording under way for it ends:
  /// the answer to 「which key?」 was 「none」.
  ///
  /// 🗣️F-318 (유저 2026-10-08): 「단축키 할당 해제 버튼같은게 없음」. The
  /// bindings have always held 「no key」 as a recorded answer (an empty
  /// list, written to the file and read back); nothing in the window
  /// recorded it — a key could only be replaced by another.
  void _unassign(String actionId) {
    if (_recordingActionId == actionId) {
      setState(() => _recordingActionId = null);
    }
    widget.bindings.setActivators(actionId, const []);
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
    if (isModifierKey(key)) {
      return KeyEventResult.handled;
    }
    final pressed = HardwareKeyboard.instance;
    widget.bindings.setActivators(actionId, [
      // An arrow for a move on the sheet is kept as the timeline reads it
      // (F-241), so it turns again on the other sheet.
      widget.bindings.keptActivatorFor(
        actionId,
        SingleActivator(
          key,
          control: pressed.isControlPressed,
          shift: pressed.isShiftPressed,
          alt: pressed.isAltPressed,
          meta: pressed.isMetaPressed,
        ),
      ),
    ]);
    setState(() => _recordingActionId = null);
    return KeyEventResult.handled;
  }

  /// The DISPLAYED wording, which is what the user is typing against — a
  /// search that only matched the English registry would find nothing in
  /// any other language.
  String _labelOf(EditorActionDefinition definition) =>
      actionLabelOf(definition);

  String _categoryOf(EditorActionDefinition definition) =>
      AppText.strings.shortcutCategory(
        definition.category,
        definition.category,
      );

  String get _query => _search.text.trim().toLowerCase();

  bool _matches(EditorActionDefinition definition, String query) =>
      query.isEmpty ||
      _labelOf(definition).toLowerCase().contains(query) ||
      _categoryOf(definition).toLowerCase().contains(query);

  /// The brush BUNDLES standing open — a group's, named by its title row's
  /// action; the root section's, by [_rootBundle].
  ///
  /// 🗣️I-56-Q1 (유저 2026-10-01), the answer picked: 「브러시 그룹마다 접히는
  /// 묶음」 = 「다른 카테고리는 지금 그대로, 브러시는 그룹마다 한 묶음으로 기본
  /// 접힘 — 그룹 줄 자체(그룹 키)는 묶음 제목 줄에 둔다. 검색하면 맞는 묶음이
  /// 펼쳐진다」. So none is open when the window opens, and a search opens
  /// the ones it finds something in ([_openFoundBundles]) — by putting them
  /// in this one set, so the twirl folds them again like any other.
  final Set<String> _openBundles = {};

  /// The root section's bundle: the brushes of no group. ⚠️Its title is a
  /// word and not a row — the root is not a group and has no press.
  static const _rootBundle = 'brush-root';

  /// The bundle [definition] stands in, or null for every other action.
  String? _bundleOf(EditorActionDefinition definition) =>
      switch (definition.brushPress) {
        BrushGroupPress(:final group) => brushGroupActionId(group),
        BrushPresetPress(group: final group?) => brushGroupActionId(group),
        BrushPresetPress() => _rootBundle,
        null => null,
      };

  /// The bundles [query] finds something in — a title or a brush.
  Set<String> _bundlesFound(String query) => {
    for (final definition in widget.bindings.definitions)
      if (_matches(definition, query)) ?_bundleOf(definition),
  };

  void _openFoundBundles() {
    final query = _query;
    if (query.isNotEmpty) {
      _openBundles.addAll(_bundlesFound(query));
    }
  }

  void _toggleBundle(String bundle) => setState(() {
    if (!_openBundles.remove(bundle)) {
      _openBundles.add(bundle);
    }
  });

  /// The list's rows: every action the search matches under its category,
  /// and of the brush library a title per bundle with — while it stands open
  /// — its brushes.
  List<Widget> _rows(ThemeData theme) {
    final bindings = widget.bindings;
    final conflicted = bindings.conflictedActionIds;
    final touchConflicted = bindings.touchConflictedActionIds;
    final query = _query;
    final found = _bundlesFound(query);
    // A bundle whose TITLE the search matched shows every brush it holds.
    final titlesFound = {
      for (final definition in bindings.definitions)
        if (definition.brushPress is BrushGroupPress &&
            _matches(definition, query))
          definition.id,
    };
    bool shows(EditorActionDefinition definition, String? bundle) {
      if (bundle == null) {
        return _matches(definition, query);
      }
      if (!found.contains(bundle)) {
        return false;
      }
      return definition.brushPress is BrushGroupPress ||
          (_openBundles.contains(bundle) &&
              (_matches(definition, query) || titlesFound.contains(bundle)));
    }

    final rows = <Widget>[];
    String? category;
    var rootTitled = false;
    for (final definition in bindings.definitions) {
      final bundle = _bundleOf(definition);
      final shown = shows(definition, bundle);
      final rootTitleDue =
          bundle == _rootBundle && !rootTitled && found.contains(_rootBundle);
      if (!shown && !rootTitleDue) {
        continue;
      }
      if (definition.category != category) {
        category = definition.category;
        rows.add(_categoryHeading(theme, definition));
      }
      if (rootTitleDue) {
        rootTitled = true;
        rows.add(_rootTitleRow(theme));
      }
      if (shown) {
        rows.add(
          _actionRow(
            definition,
            conflicted.contains(definition.id),
            touchConflicted.contains(definition.id),
            bundle: bundle,
          ),
        );
      }
    }
    return rows;
  }

  Widget _categoryHeading(
    ThemeData theme,
    EditorActionDefinition definition,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(
      _categoryOf(definition),
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.primary,
      ),
    ),
  );

  /// The fold of [bundle], where the layer rail's fold is (F-29): at the far
  /// edge of the name it folds under — the app's one twirl.
  Widget _twirl(String bundle) => LayerFoldTwirl(
    keyValue: 'shortcut-bundle-$bundle',
    expanded: _openBundles.contains(bundle),
    onToggle: () => _toggleBundle(bundle),
  );

  Widget _rootTitleRow(ThemeData theme) => Padding(
    key: const ValueKey<String>('shortcut-row-$_rootBundle'),
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(brushRootSectionLabel, style: theme.textTheme.bodyMedium),
        ),
        _twirl(_rootBundle),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bindings = widget.bindings;
    final conflicted = bindings.conflictedActionIds;
    final rows = _rows(theme);

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
              // 🗣️I-63: the preset the keys below start from. Picking one
              // shows ITS keys and what was recorded under it.
              Align(
                alignment: Alignment.centerLeft,
                child: PillStrip(
                  items: [
                    for (final preset in ShortcutPreset.values)
                      PillItem(
                        keyValue: 'shortcut-preset-${preset.name}',
                        label: AppText.strings.shortcutPresetName(
                          preset.name,
                          preset.label,
                        ),
                        selected: bindings.preset == preset,
                        onTap: () => bindings.setPreset(preset),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey<String>('shortcut-search-field'),
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: AppText.strings.shortcutSearch,
                  isDense: true,
                ),
                onChanged: (_) => setState(_openFoundBundles),
              ),
              // 🗣️F-318 (유저 2026-10-08): 「동일한 단축키 있을때 빨간
              // 경고메시지가 영어로 뜨고」 — the table has had the sentence
              // in every language since the window was localised
              // (`shortcutConflictBanner`); this line went on writing the
              // English one itself.
              //
              // ⛔Its PLACE is always there (「없다가 생기는 UI 금지」): laid
              // out in the program language whether or not a key clashes,
              // and shown when one does. ↩️It was mounted on the clash, and
              // the list under it jumped down a line — two, in the
              // languages the sentence wraps in.
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Visibility.maintain(
                  visible: conflicted.isNotEmpty,
                  child: Text(
                    AppText.strings.shortcutConflictBanner,
                    key: const ValueKey<String>('shortcut-conflict-banner'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
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
          label: AppText.strings.commonClose,
          actionKey: const ValueKey<String>('shortcut-close-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// How much of a row its keys and its touch gesture may take before they
  /// wrap — the name and the row's buttons keep the rest.
  static const double _keysShare = 0.6;

  Widget _actionRow(
    EditorActionDefinition definition,
    bool conflicted,
    bool touchConflicted, {
    String? bundle,
  }) {
    final theme = Theme.of(context);
    final bindings = widget.bindings;
    final recording = _recordingActionId == definition.id;
    final activators = bindings.activatorsFor(definition.id);
    final touchGesture = bindings.touchGestureFor(definition.id);
    final titlesBundle = definition.brushPress is BrushGroupPress;

    // The keys recorded on the row and its touch gesture — what stands
    // between its name and its buttons.
    final keys = <Widget>[
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
                singleActivatorLabel(
                  bindings.shownActivatorFor(definition.id, activator),
                ),
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
      // R6 #4: the shared flyout. These rows carried no `height`, so
      // they came out at Material's 48 beside the app's 32.
      //
      // ✅The sentinel is gone with the migration: a flyout item carries
      // a CALLBACK rather than a value, so "None" simply passes null and
      // no longer has to be told apart from a dismissal.
      PanelFlyoutTrigger(
        key: ValueKey<String>('shortcut-touch-${definition.id}'),
        tooltip: AppText.strings.shortcutTouch,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        entriesBuilder: () =>
            <TouchGesture?>[null, ...TouchGesture.values]
                .asFlyoutValueChoices(
                  current: touchGesture,
                  choiceOf: (gesture) => PanelFlyoutChoice(
                    key:
                        'shortcut-touch-${definition.id}-'
                        '${gesture?.name ?? 'none'}',
                    label: gesture?.label ?? AppText.strings.commonNone,
                  ),
                  onPicked: (gesture) => widget.bindings.setTouchGesture(
                    definition.id,
                    gesture,
                  ),
                ),
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
    ];

    return Padding(
      key: ValueKey<String>('shortcut-row-${definition.id}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      // 🗣️F-318: the row gained a button, and a row with several keys
      // and a touch gesture was already within a few pixels of its
      // width. The keys and the gesture take what they need up to
      // [_keysShare] of the row and WRAP past it — the name keeps the
      // rest, and no row overflows whatever is recorded on it.
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              // A brush stands under its bundle's title, a step in.
              child: Padding(
                padding: EdgeInsets.only(
                  left: bundle == null || titlesBundle ? 0 : 16,
                ),
                child: Text(
                  _labelOf(definition),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            if (bundle != null && titlesBundle) _twirl(bundle),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * _keysShare,
              ),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 2,
                children: keys,
              ),
            ),
            AppIconButton(
              keyValue: 'shortcut-record-${definition.id}',
              tooltip: AppText.strings.shortcutRecordNew,
              icon: const Icon(Icons.keyboard),
              onPressed: () => _startRecording(definition.id),
            ),
            // Dead on a row with no key: there is nothing to take off.
            AppIconButton(
              keyValue: 'shortcut-unassign-${definition.id}',
              tooltip: AppText.strings.shortcutUnassign,
              icon: const Icon(Icons.backspace_outlined),
              onPressed: activators.isEmpty
                  ? null
                  : () => _unassign(definition.id),
            ),
            AppIconButton(
              keyValue: 'shortcut-reset-${definition.id}',
              tooltip: AppText.strings.shortcutResetToDefault,
              icon: const Icon(Icons.restart_alt),
              onPressed:
                  bindings.isOverridden(definition.id) ||
                      bindings.isTouchOverridden(definition.id)
                  ? () => bindings.resetAction(definition.id)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
