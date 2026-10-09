import '../widgets/app_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/brush_group.dart';
import '../brush/brush_press.dart';
import '../brush/brush_tool_state.dart';
import '../input/control_press_claim.dart'
    show ControlPressClaim, silentPress;
import '../timeline/layer_label_controls.dart' show layerLaneToggleSlotWidth;
import '../timeline/layer_rail_columns.dart' show LayerFoldTwirl;
import '../widgets/panel_flyout.dart';
import '../widgets/pill_strip.dart';
import 'brush_actions.dart';
import 'editor_action_registry.dart';
import 'editor_shortcut_bindings.dart';
import 'editor_shortcut_scope.dart';
import 'shortcut_activator_codec.dart';
import 'shortcut_presets.dart';
import 'shortcut_shelf.dart';
import 'touch_shortcuts.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// The Keyboard Shortcuts editor (Edit menu): a searchable action list
/// shelved by where each key's button stands ([ShortcutShelf]),
/// click-to-record capture, conflict highlighting and per-action / global
/// resets — the PS/CSP settings-page convention.
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

  String _shelfName(ShortcutShelf shelf) =>
      AppText.strings.shortcutShelfName(shelf.name, shelf.label);

  String get _query => _search.text.trim().toLowerCase();

  /// Whether [definition] answers [query] — by its own name, or by the name
  /// of any shelf it stands on: a search for 「알약」 finds every pill's rows.
  bool _matches(EditorActionDefinition definition, String query) =>
      query.isEmpty ||
      _labelOf(definition).toLowerCase().contains(query) ||
      definition.shelf.path.any(
        (shelf) => _shelfName(shelf).toLowerCase().contains(query),
      );

  /// The BUNDLES standing open — a shelf's, named by [_shelfBundleOf]; a
  /// brush group's, by its title row's action; a root section's, by
  /// [_rootBundleOf]. A paint tool has its own brush bundles (F-319): the
  /// brush tool's Inks and the eraser's Inks are two.
  ///
  /// 🗣️I-56-Q1 (유저 2026-10-01), the answer picked: 「브러시 그룹마다 접히는
  /// 묶음」 = 「다른 카테고리는 지금 그대로, 브러시는 그룹마다 한 묶음으로 기본
  /// 접힘 — 그룹 줄 자체(그룹 키)는 묶음 제목 줄에 둔다. 검색하면 맞는 묶음이
  /// 펼쳐진다」. So none is open when the window opens, and a search opens
  /// the ones it finds something in ([_openFoundBundles]) — by putting them
  /// in this one set, so the twirl folds them again like any other.
  /// ↩️「다른 카테고리는 지금 그대로」 until 유저 2026-10-08
  /// (menu-rows-and-panels-are-shortcut-rows): 「단축키 많으니까 항목은
  /// 기본적으로 접을수있게. 브러시항목에서 쓴 거나 법 통일하면서」 — every
  /// category is a bundle now, under the same law. ↩️The categories became
  /// shelves (shortcut-presets-anicel-and-clip-studio-Q1, 유저 2026-10-09:
  /// 「버튼이 있는 자리로」) — every shelf, a place's too, folds the same way.
  final Set<String> _openBundles = {};

  /// The bundle of [shelf]'s rows and shelves — the fold its heading
  /// carries.
  static String _shelfBundleOf(ShortcutShelf shelf) => 'shelf-${shelf.name}';

  /// The root section's bundle in [tool]'s library: the brushes of no
  /// group. ⚠️Its title is a word and not a row — the root is not a group
  /// and has no press.
  static String _rootBundleOf(CanvasTool tool) => '${tool.name}-root';

  /// The bundle [definition] stands in, or null for every other action.
  String? _bundleOf(EditorActionDefinition definition) =>
      switch (definition.brushPress) {
        BrushGroupPress(:final tool, :final group) => brushGroupActionId(
          tool,
          group,
        ),
        BrushPresetPress(:final tool, group: final group?) =>
          brushGroupActionId(tool, group),
        BrushPresetPress(:final tool) => _rootBundleOf(tool),
        null => null,
      };

  /// Whether [definition] is a brush of a root section — one that stands
  /// under the section's word, which is no row of its own.
  bool _isLoose(EditorActionDefinition definition) =>
      switch (definition.brushPress) {
        BrushPresetPress(group: null) => true,
        _ => false,
      };

  /// The bundles [query] finds something in — every shelf above a row it
  /// finds, a brush title or a brush.
  Set<String> _bundlesFound(String query) => {
    for (final definition in widget.bindings.definitions)
      if (_matches(definition, query)) ...{
        for (final shelf in definition.shelf.path) _shelfBundleOf(shelf),
        ?_bundleOf(definition),
      },
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

  /// The list's rows: a heading per shelf the search finds something in —
  /// a place's, and under it, while it stands open, its shelves' — with,
  /// while a shelf stands open, every action of it the search matches, and
  /// of the brush library a title per bundle with — while that stands open
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

    // ONE heading a shelf, its rows together under it, the shelves in the
    // order [ShortcutShelf] lists them and each under the one it stands on.
    // ↩️A heading was written each time the category changed down the
    // list, and the registry held six of them in two places — File, Tools,
    // Edit, Selection, View and Timeline each stood twice.
    final byShelf = <ShortcutShelf, List<EditorActionDefinition>>{};
    for (final definition in bindings.definitions) {
      (byShelf[definition.shelf] ??= []).add(definition);
    }
    final rows = <Widget>[];
    // The root sections whose word already stands — one a paint tool.
    final rootsTitled = <String>{};
    void shelve(ShortcutShelf shelf) {
      final fold = _shelfBundleOf(shelf);
      if (!found.contains(fold)) {
        return;
      }
      rows.add(_shelfHeading(theme, shelf));
      if (!_openBundles.contains(fold)) {
        return;
      }
      for (final each in shelf.shelves) {
        shelve(each);
      }
      final depth = shelf.path.length;
      for (final definition
          in byShelf[shelf] ?? const <EditorActionDefinition>[]) {
        final bundle = _bundleOf(definition);
        final shown = shows(definition, bundle);
        final rootTitleDue =
            bundle != null &&
            _isLoose(definition) &&
            !rootsTitled.contains(bundle) &&
            found.contains(bundle);
        if (rootTitleDue) {
          rootsTitled.add(bundle);
          rows.add(_rootTitleRow(theme, bundle, depth));
        }
        if (shown) {
          rows.add(
            _actionRow(
              definition,
              conflicted.contains(definition.id),
              touchConflicted.contains(definition.id),
              depth: depth,
              bundle: bundle,
            ),
          );
        }
      }
    }

    for (final place in ShortcutShelf.places) {
      shelve(place);
    }
    return rows;
  }

  /// A shelf's heading, a step in from the shelf it stands on and carrying
  /// its fold as a brush bundle's title does — a place's in the accent.
  Widget _shelfHeading(ThemeData theme, ShortcutShelf shelf) {
    final bundle = _shelfBundleOf(shelf);
    final place = shelf.parent == null;
    return Padding(
      key: ValueKey<String>('shortcut-shelf-${shelf.name}'),
      padding: EdgeInsets.only(
        left: (shelf.path.length - 1) * _step,
        top: place ? 12 : 2,
        bottom: place ? 4 : 2,
      ),
      child: _foldRow(
        bundle,
        Row(
          children: [
            _twirl(bundle),
            Expanded(
              child: Text(
                _shelfName(shelf),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: place ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One step of the list's depth: the twirl's own width, so a row's words
  /// start where the words of the row it folds under do.
  static const double _step = layerLaneToggleSlotWidth;

  /// A row that folds [bundle], pressed anywhere on itself — its twirl
  /// first, left of its words, and only showing.
  ///
  /// 🗣️유저 2026-10-09 (shortcut-presets-anicel-and-clip-studio): 「항목 접게
  /// 만든거 좋은데 펼치는거랑 스크롤바랑 겹치는건지 안열림. 그냥 그 줄 누르면
  /// 열리도록. 그러고 접기펼치기버튼은 항목 글자 왼쪽에 두도록. 다만 물론
  /// 누르는건 그 항목 전체니까 접기펼치기 위젯은 그냥 보이기만할뿐인것임」.
  /// ↩️The twirl was the press, at the row's far edge where the layer rail
  /// keeps its own (F-29) — and that edge is where the list's scrollbar
  /// runs. A control ON the row (a brush group's record · unassign · reset
  /// · touch) keeps its own press: the deepest claim wins.
  Widget _foldRow(String bundle, Widget row) => ControlPressClaim(
    onPressed: () => _toggleBundle(bundle),
    child: InkWell(
      onTap: silentPress(() => _toggleBundle(bundle)),
      child: row,
    ),
  );

  /// The fold of [bundle] — the app's one twirl, showing it ([_foldRow]
  /// is the press).
  Widget _twirl(String bundle) => LayerFoldTwirl(
    keyValue: 'shortcut-bundle-$bundle',
    expanded: _openBundles.contains(bundle),
    onToggle: null,
  );

  Widget _rootTitleRow(ThemeData theme, String bundle, int depth) => Padding(
    key: ValueKey<String>('shortcut-row-$bundle'),
    padding: EdgeInsets.only(left: depth * _step, top: 2, bottom: 2),
    child: _foldRow(
      bundle,
      Row(
        children: [
          _twirl(bundle),
          Expanded(
            child: Text(
              brushRootSectionLabel,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
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
    required int depth,
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

    // A row stands a step in from its shelf's heading ([depth] steps), and
    // a brush a step in from its bundle's title — each row's words where
    // the words of the row it folds under start.
    final steps = bundle != null && !titlesBundle ? depth + 1 : depth;
    final folds = bundle != null && titlesBundle ? bundle : null;
    return Padding(
      key: ValueKey<String>('shortcut-row-${definition.id}'),
      padding: EdgeInsets.only(left: steps * _step, top: 2, bottom: 2),
      // 🗣️F-318: the row gained a button, and a row with several keys
      // and a touch gesture was already within a few pixels of its
      // width. The keys and the gesture take what they need up to
      // [_keysShare] of the row and WRAP past it — the name keeps the
      // rest, and no row overflows whatever is recorded on it.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final row = Row(
            children: [
              if (folds != null) _twirl(folds),
              Expanded(
                child: Text(
                  _labelOf(definition),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
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
          );
          return folds == null ? row : _foldRow(folds, row);
        },
      ),
    );
  }
}
