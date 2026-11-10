import 'dart:async';

import '../widgets/app_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/brush_group.dart';
import '../../services/input/modifier_keys.dart';
import '../../services/persistence/file_type_groups.dart' show FileTypeGroups;
import '../brush/brush_press.dart';
import '../brush/brush_tool_state.dart';
import '../brush/tool_library_panel.dart' show subToolTilesOf;
import '../brush/tool_press.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/app_prompt_dialog.dart';
import '../dialogs/dialog_verb.dart';
import '../dialogs/settings_file_export.dart';
import '../input/control_press_claim.dart'
    show ControlPressClaim, silentPress;
import '../timeline/layer_label_controls.dart' show layerLaneToggleSlotWidth;
import '../timeline/layer_rail_columns.dart' show LayerFoldTwirl;
import '../widgets/panel_flyout.dart';
import 'brush_actions.dart';
import 'editor_action_registry.dart';
import 'editor_shortcut_bindings.dart';
import 'editor_shortcut_scope.dart';
import 'shortcut_activator_codec.dart';
import 'shortcut_clash_names.dart';
import 'shortcut_presets.dart';
import 'shortcut_settings_store.dart' show shortcutPresetSettingsFile;
import 'shortcut_shelf.dart';
import 'touch_shortcuts.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../theme/app_theme.dart';

/// The Keyboard Shortcuts editor (Edit menu): a searchable action list
/// shelved by where each key's button stands ([ShortcutShelf]),
/// click-to-record capture, conflict highlighting and per-action / preset
/// resets — the PS/CSP settings-page convention.
class ShortcutSettingsDialog extends StatefulWidget {
  const ShortcutSettingsDialog({super.key, required this.bindings});

  final EditorShortcutBindings bindings;

  @override
  State<ShortcutSettingsDialog> createState() => _ShortcutSettingsDialogState();
}

class _ShortcutSettingsDialogState extends State<ShortcutSettingsDialog> {
  final TextEditingController _search = TextEditingController();

  /// What the next key pressed is for (null = nothing): a row's new key, or
  /// the key the list is searched by. While set, a key-event listener
  /// captures the next non-modifier press.
  ///
  /// 🗣️I-168 (유저 2026-11-10): 「동작검색 말고 단축키검색도 생성. 키보드
  /// 단축키 지정하는거 재사용해서 버튼누르고 단축키입력하면 그 키의 단축키
  /// 보이게. 리셋버튼으로 리셋」 — ONE recording, two answers to it.
  _Recording? _recording;
  final FocusNode _recordFocus = FocusNode(debugLabel: 'shortcut-record');

  /// The key the list is searched by ([_recording] took it), or null: the
  /// list shows the actions that hold it.
  SingleActivator? _sought;

  /// What the window does with its presets, on its bindings.
  _PresetVerbs get _presets => _PresetVerbs(widget.bindings);

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

  void _startRecording(_Recording recording) {
    setState(() => _recording = recording);
    _recordFocus.requestFocus();
  }

  /// Whether [actionId]'s row is recording its next key.
  bool _recordsFor(String actionId) => switch (_recording) {
    _ForAction(actionId: final recording) => recording == actionId,
    _ => false,
  };

  /// Takes every key off [actionId] — its own default too, which then
  /// stays off until the row is reset. A recording under way for it ends:
  /// the answer to 「which key?」 was 「none」.
  ///
  /// 🗣️F-318 (유저 2026-10-08): 「단축키 할당 해제 버튼같은게 없음」. The
  /// bindings have always held 「no key」 as a recorded answer (an empty
  /// list, written to the file and read back); nothing in the window
  /// recorded it — a key could only be replaced by another.
  void _unassign(String actionId) {
    if (_recordsFor(actionId)) {
      setState(() => _recording = null);
    }
    widget.bindings.setActivators(actionId, const []);
  }

  KeyEventResult _onRecordKey(FocusNode node, KeyEvent event) {
    final recording = _recording;
    if (recording == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _recording = null);
      return KeyEventResult.handled;
    }
    // Modifier presses alone keep waiting for the real trigger.
    if (isModifierKey(key)) {
      return KeyEventResult.handled;
    }
    final pressed = SingleActivator(
      key,
      control: ModifierKeys.isControlPressed,
      shift: ModifierKeys.isShiftPressed,
      alt: ModifierKeys.isAltPressed,
      meta: ModifierKeys.isMetaPressed,
    );
    switch (recording) {
      case _ForAction(:final actionId):
        widget.bindings.setActivators(actionId, [
          // An arrow for a move on the sheet is kept as the timeline reads
          // it (F-241), so it turns again on the other sheet.
          widget.bindings.keptActivatorFor(actionId, pressed),
        ]);
        setState(() => _recording = null);
      case _ForSearch():
        setState(() {
          _recording = null;
          _sought = pressed;
          _openFoundBundles();
        });
    }
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

  /// Whether [definition] holds the key the list is searched by — the key
  /// as its row would record it (`keptActivatorFor`), so an arrow is found
  /// on whichever sheet it was pressed — or no key is sought.
  bool _holdsSought(EditorActionDefinition definition) => switch (_sought) {
    null => true,
    final key => widget.bindings.holds(
      definition.id,
      widget.bindings.keptActivatorFor(definition.id, key),
    ),
  };

  /// Whether [definition] is found: by its words ([_matches]) and by the
  /// sought key ([_holdsSought]) — ⚠️MY READING (I-168-Q1's why): the two
  /// searches together leave what answers both.
  bool _found(EditorActionDefinition definition, String query) =>
      _matches(definition, query) && _holdsSought(definition);

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

  /// The bundles [definition] stands in — every shelf above it and, a brush
  /// title or a brush, its own.
  Iterable<String> _foldsOver(EditorActionDefinition definition) => [
    for (final shelf in definition.shelf.path) _shelfBundleOf(shelf),
    ?_bundleOf(definition),
  ];

  /// The bundles the search finds something in ([_found]).
  Set<String> _bundlesFound(String query) => {
    for (final definition in widget.bindings.definitions)
      if (_found(definition, query)) ..._foldsOver(definition),
  };

  /// What stands red: every action a clash takes in — keys or touch alike —
  /// and every bundle over it, a brush group's title row among them (it is
  /// named by the bundle it folds).
  ///
  /// 🗣️F-522 (유저 2026-11-01): 「할당 충돌하면 해당 들어있는 항목 다
  /// 빨간강조색으로. 어디 들어있는건지 안보임. 패널 안 빨간강조색만들고 미디어
  /// 빨간강조색만들고 이런식」 — every shelf starts shut, so a clash stood
  /// behind folds with only the banner to say it was there. What is under a
  /// fold is what the red answers, whatever the search shows of it.
  Set<String> _clashed() {
    final bindings = widget.bindings;
    final clashing = {
      ...bindings.conflictedActionIds,
      ...bindings.touchConflictedActionIds,
    };
    return {
      for (final definition in bindings.definitions)
        if (clashing.contains(definition.id)) ...{
          definition.id,
          ..._foldsOver(definition),
        },
    };
  }

  void _openFoundBundles() {
    final query = _query;
    if (query.isNotEmpty || _sought != null) {
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
    final clashed = _clashed();
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
        return _found(definition, query);
      }
      if (!found.contains(bundle)) {
        return false;
      }
      // A title found by its WORDS shows its brushes — those that hold the
      // key the list is searched by, when one is (I-168).
      return definition.brushPress is BrushGroupPress ||
          (_openBundles.contains(bundle) &&
              _holdsSought(definition) &&
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
      rows.add(_shelfHeading(theme, shelf, red: clashed.contains(fold)));
      if (!_openBundles.contains(fold)) {
        return;
      }
      final depth = shelf.path.length;
      void put(EditorActionDefinition definition, int depth) {
        final bundle = _bundleOf(definition);
        final shown = shows(definition, bundle);
        final rootTitleDue =
            bundle != null &&
            _isLoose(definition) &&
            !rootsTitled.contains(bundle) &&
            found.contains(bundle);
        if (rootTitleDue) {
          rootsTitled.add(bundle);
          rows.add(
            _rootTitleRow(
              theme,
              bundle,
              depth,
              red: clashed.contains(bundle),
            ),
          );
        }
        if (shown) {
          rows.add(
            _ActionRow(
              key: ValueKey<String>('shortcut-row-${definition.id}'),
              bindings: bindings,
              definition: definition,
              conflicted: conflicted.contains(definition.id),
              touchConflicted: touchConflicted.contains(definition.id),
              red: clashed.contains(definition.id),
              recording: _recordsFor(definition.id),
              depth: depth,
              bundle: bundle,
              bundleOpen: bundle != null && _openBundles.contains(bundle),
              onToggleBundle: bundle == null
                  ? null
                  : () => _toggleBundle(bundle),
              onRecord: () => _startRecording(_ForAction(definition.id)),
              onUnassign: () => _unassign(definition.id),
            ),
          );
        }
      }

      // 🗣️F-580: a tool's row, and a step in under it what is the tool's —
      // its tiles in the tool library's order, then the shelf that names
      // it — before the next tool's. ↩️「세부 도구」 held every tool's
      // tiles and the tool library's shelves together (F-560).
      final shelfRows = byShelf[shelf] ?? const <EditorActionDefinition>[];
      final tiles = {
        for (final definition in shelfRows)
          if (definition.toolPress case final SubToolPress press)
            press: definition,
      };
      for (final definition in shelfRows) {
        if (definition.toolPress is SubToolPress) {
          continue;
        }
        put(definition, depth);
        if (definition.toolPress case RailToolPress(:final group)) {
          for (final tile in subToolTilesOf(group)) {
            if (tiles[tile.press] case final tileRow?) {
              put(tileRow, depth + 1);
            }
          }
          for (final each in shelf.shelves) {
            if (each.tool == group) {
              shelve(each);
            }
          }
        }
      }
      // The shelves that name no tool, after the rows: rows after an open
      // shelf's rows would read as that shelf's.
      for (final each in shelf.shelves) {
        if (each.tool == null) {
          shelve(each);
        }
      }
    }

    for (final place in ShortcutShelf.places) {
      shelve(place);
    }
    return rows;
  }

  /// A shelf's heading, a step in from the shelf it stands on and carrying
  /// its fold as a brush bundle's title does — a place's in the accent,
  /// any in the clash's [red].
  Widget _shelfHeading(
    ThemeData theme,
    ShortcutShelf shelf, {
    required bool red,
  }) {
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
        () => _toggleBundle(bundle),
        Row(
          children: [
            _twirl(bundle, open: _openBundles.contains(bundle)),
            Expanded(
              child: Text(
                _shelfName(shelf),
                style: _wordsIn(
                  theme,
                  theme.textTheme.labelLarge,
                  red: red,
                  color: place ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rootTitleRow(
    ThemeData theme,
    String bundle,
    int depth, {
    required bool red,
  }) => Padding(
    key: ValueKey<String>('shortcut-row-$bundle'),
    padding: EdgeInsets.only(left: depth * _step, top: 2, bottom: 2),
    child: _foldRow(
      () => _toggleBundle(bundle),
      Row(
        children: [
          _twirl(bundle, open: _openBundles.contains(bundle)),
          Expanded(
            child: Text(
              brushRootSectionLabel,
              style: _wordsIn(theme, theme.textTheme.bodyMedium, red: red),
            ),
          ),
        ],
      ),
    ),
  );

  /// Sized as the import and export windows are: its share of the app
  /// screen by area ([AppWindow.screenShare], F-337), and never smaller than
  /// the 520 × 520 it stood at. 🗣️F-580 (유저 2026-11-10): 「키보드 단축키 창
  /// 좀 더 커도될듯. 너무작음」. ↩️520 × 520 whatever the screen. The
  /// LayoutBuilder stands OUTSIDE the window, as the import window's does:
  /// the screen it shares is the app's, not the dialog's.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, screen) => _window(
      context,
      AppWindow.screenShare(screen, least: const Size(520, 520)),
    ),
  );

  Widget _window(BuildContext context, Size room) {
    final theme = Theme.of(context);
    final bindings = widget.bindings;
    final conflicted = bindings.conflictedActionIds;
    final rows = _rows(theme);

    return AppWindow(
      windowKey: const ValueKey<String>('shortcut-settings-dialog'),
      title: AppText.strings.shortcutTitle,
      titleIcon: Icons.keyboard_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: room.width,
      height: room.height,
      scrollBody: false,
      body: Focus(
        focusNode: _recordFocus,
        onKeyEvent: _onRecordKey,
        child: SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 🗣️I-63: the preset the keys below start from. Picking one
              // shows ITS keys and what was recorded under it — from a
              // list, as every preset is picked (유저 2026-10-12, I-93:
              // 「이런 프리셋 변경은 특히 앱 통틀어서 리스트 팝오버로」).
              // ↩️It was a pill strip until then.
              Align(
                alignment: Alignment.centerLeft,
                child: PanelFlyoutButton(
                  key: const ValueKey<String>('shortcut-preset'),
                  label: _PresetVerbs.nameOf(bindings.preset),
                  entriesBuilder: () => _presets.entries(context),
                ),
              ),
              const SizedBox(height: 8),
              // 🗣️I-168-Q1 (유저 2026-11-11): 「검색 칸 오른쪽, 같은 줄」 —
              // the search by key stands beside the search by words.
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('shortcut-search-field'),
                      controller: _search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: AppText.strings.shortcutSearch,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(_openFoundBundles),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _KeySearch(
                    sought: _sought,
                    recording: _recording is _ForSearch,
                    onRecord: () => _startRecording(const _ForSearch()),
                    onClear: _sought == null
                        ? null
                        : () => setState(() => _sought = null),
                  ),
                ],
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
              //
              // 🗣️I-158: who clashes stands beside it ([ShortcutClashNames]),
              // on a half of its own: the sentence wraps the same whatever
              // the names are, so the list under it never moves.
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Visibility.maintain(
                  visible: conflicted.isNotEmpty,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppText.strings.shortcutConflictBanner,
                          key: const ValueKey<String>(
                            'shortcut-conflict-banner',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: _clashNamesHeight,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ShortcutClashNames(bindings: bindings),
                          ),
                        ),
                      ),
                    ],
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
          label: AppText.strings.shortcutResetPreset,
          actionKey: const ValueKey<String>('shortcut-preset-reset-button'),
          emphasis: AppWindowActionEmphasis.danger,
          onPressed: () => unawaited(_presets.reset(context)),
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
}

/// What the window does with its presets — the list its preset button opens
/// and the reset at its foot.
///
/// ↩️Methods of the window's State until F-522 took it past six hundred
/// lines.
final class _PresetVerbs {
  const _PresetVerbs(this.bindings);

  final EditorShortcutBindings bindings;

  /// A preset's name: one the app ships in the program language — the app's
  /// own name in every one — and the user's as it was given.
  static String nameOf(ShortcutLayout preset) => switch (preset) {
    ShortcutPreset() => AppText.strings.shortcutPresetName(
      preset.name,
      preset.label,
    ),
    UserShortcutPreset(:final name) => name,
  };

  /// The presets, as they are when the list OPENS: the three the app ships,
  /// then the user's own.
  ///
  /// 🗣️I-107-Q1 (유저 2026-10-18): 「프리셋 리스트 추가/삭제 가능하게해서
  /// 사용자 입맛대로 추가해서 설정가능하고」 — in the font list's shape: the
  /// ＋ on the heading, a delete at the end of each row that can go.
  /// 🗣️I-107-Q3 (유저 2026-10-18): 「a + 이름 바꾸기」 · 「프리셋
  /// 복제버튼도 추가」 — a rename beside the delete, and a duplicate on every
  /// row.
  List<PanelFlyoutEntry> entries(BuildContext context) {
    final strings = AppText.strings;
    return [
      PanelFlyoutHeader(
        strings.shortcutPresets,
        action: PanelFlyoutRowAction(
          keyValue: 'shortcut-preset-add',
          icon: Icons.add,
          tooltip: strings.shortcutPresetNew,
          does: PanelFlyoutActionDoes.adds,
          onPressed: () => unawaited(
            _duplicatePreset(
              context,
              bindings.preset,
              title: strings.shortcutPresetNew,
            ),
          ),
        ),
      ),
      for (final preset in ShortcutPreset.values) _presetRow(context, preset),
      if (bindings.userPresets.isNotEmpty) const PanelFlyoutDivider(),
      for (final preset in bindings.userPresets) _presetRow(context, preset),
    ];
  }

  /// [preset]'s row: picked, it comes into use. Every row has its
  /// duplicate and its export, and the user's own their rename and delete
  /// beside them.
  PanelFlyoutItem _presetRow(BuildContext context, ShortcutLayout preset) {
    final strings = AppText.strings;
    final key = 'shortcut-preset-${preset.id}';
    return PanelFlyoutItem(
      keyValue: key,
      label: nameOf(preset),
      selected: preset == bindings.preset,
      onSelected: () => bindings.setPreset(preset),
      actions: [
        if (preset is UserShortcutPreset)
          PanelFlyoutRowAction(
            keyValue: '$key-rename',
            icon: Icons.drive_file_rename_outline,
            tooltip: strings.shortcutPresetRename,
            onPressed: () => unawaited(_renamePreset(context, preset)),
          ),
        PanelFlyoutRowAction(
          keyValue: '$key-duplicate',
          icon: Icons.content_copy,
          tooltip: strings.shortcutPresetDuplicate,
          does: PanelFlyoutActionDoes.adds,
          onPressed: () => unawaited(
            _duplicatePreset(
              context,
              preset,
              title: strings.shortcutPresetDuplicate,
            ),
          ),
        ),
        // I-142-Q1 · Q4 (유저 2026-10-29): 「주인 자리에서 내보내고」 ·
        // 「프리셋 하나」 — every row's, a shipped one's too: what comes back
        // in through 「파일 열기」 is a new preset of the user's either way.
        PanelFlyoutRowAction(
          keyValue: '$key-export',
          icon: Icons.upload_file_outlined,
          tooltip: strings.shortcutPresetExport,
          onPressed: () => unawaited(_exportPreset(context, preset)),
        ),
        if (preset is UserShortcutPreset)
          PanelFlyoutRowAction(
            keyValue: '$key-delete',
            icon: Icons.delete_outline,
            tooltip: strings.shortcutPresetDelete,
            does: PanelFlyoutActionDoes.deletes,
            onPressed: () => unawaited(_deletePreset(context, preset)),
          ),
      ],
    );
  }

  /// [preset] copied into a new preset under the name the user gives — the
  /// ＋'s copy of the layout in use, and a row's duplicate.
  Future<void> _duplicatePreset(
    BuildContext context,
    ShortcutLayout preset, {
    required String title,
  }) => askThenCommit<String>(
    context,
    dialog: (_) => AppPromptDialog.keyed(
      keyPrefix: 'shortcut-preset-copy',
      title: title,
      titleIcon: Icons.content_copy,
      fieldLabel: AppText.strings.commonNameField,
      initialValue: AppText.strings.copyNamed(nameOf(preset)),
      confirmLabel: AppText.strings.commonSave,
      emptyError: AppText.strings.shortcutPresetNameEmpty,
    ),
    commit: (name) => bindings.duplicatePreset(preset, name),
  );

  /// [preset] written as a shortcut file of its own (I-142), under the name
  /// its row shows.
  Future<void> _exportPreset(BuildContext context, ShortcutLayout preset) {
    final name = nameOf(preset);
    return handSettingsFileToUser(
      context,
      name: name,
      type: FileTypeGroups.anicelShortcut,
      contents: () => shortcutPresetSettingsFile(
        preset,
        name: name,
        keys: bindings.keysOf(preset),
      ),
    );
  }

  Future<void> _renamePreset(
    BuildContext context,
    UserShortcutPreset preset,
  ) => askThenCommit<String>(
    context,
    dialog: (_) => AppPromptDialog.keyed(
      keyPrefix: 'shortcut-preset-rename',
      title: AppText.strings.shortcutPresetRename,
      titleIcon: Icons.drive_file_rename_outline,
      fieldLabel: AppText.strings.commonNameField,
      initialValue: preset.name,
      confirmLabel: AppText.strings.commonRename,
      emptyError: AppText.strings.shortcutPresetNameEmpty,
    ),
    commit: (name) => bindings.renamePreset(preset, name),
  );

  /// A preset of the user's deleted, once the user says so — it holds a
  /// whole layout of keys.
  Future<void> _deletePreset(
    BuildContext context,
    UserShortcutPreset preset,
  ) => confirmThenCommit(
    context,
    dialog: (context) => confirmWindow(
      context,
      ConfirmQuestion(
        keys: confirmDialogKeys('shortcut-preset-delete'),
        title: AppText.strings.shortcutPresetDelete,
        titleIcon: Icons.delete_outline,
        message: AppText.strings.shortcutPresetDeleteBody(preset.name),
      ),
      accept: ConfirmChoice(AppText.strings.commonDelete),
    ),
    commit: () => bindings.deletePreset(preset),
  );

  /// The preset in use back as it came, once the user says so — it can
  /// hold a whole layout of recorded keys.
  ///
  /// 🗣️F-522 (유저 2026-11-01): 「키보드 단축키 모두초기화버튼, 현재 프리셋
  /// 초기화로 바꾸고, 누르면 초기화하겟냐고 메시지창 띄우기」. ↩️「모두
  /// 초기화」 fired on the press, and said more than it did: what was
  /// recorded under another preset has always stayed with it.
  Future<void> reset(BuildContext context) => confirmThenCommit(
    context,
    dialog: (context) => confirmWindow(
      context,
      ConfirmQuestion(
        keys: confirmDialogKeys('shortcut-preset-reset'),
        title: AppText.strings.shortcutResetPreset,
        titleIcon: Icons.restart_alt,
        message: AppText.strings.shortcutResetPresetBody(
          nameOf(bindings.preset),
        ),
      ),
      accept: ConfirmChoice(AppText.strings.commonReset),
    ),
    commit: bindings.resetAll,
  );
}

/// One step of the list's depth: the twirl's own width, so a row's words
/// start where the words of the row it folds under do.
const double _step = layerLaneToggleSlotWidth;

/// The clash's names' line, as tall with a pair as with the list's button
/// or with nothing in it.
const double _clashNamesHeight = 28;

/// [style] as a row writes it: in the banner's red where a clash stands
/// ([_ShortcutSettingsDialogState._clashed]), in [color] everywhere else.
TextStyle? _wordsIn(
  ThemeData theme,
  TextStyle? style, {
  required bool red,
  Color? color,
}) => style?.copyWith(color: red ? theme.colorScheme.error : color);

/// A row that folds, pressed anywhere on itself — [toggle] — its twirl
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
Widget _foldRow(VoidCallback toggle, Widget row) => ControlPressClaim(
  onPressed: toggle,
  child: InkWell(
    mouseCursor: AppCursors.press,
    onTap: silentPress(toggle),
    child: row,
  ),
);

/// The fold of [bundle] — the app's one twirl, showing it ([_foldRow] is
/// the press).
Widget _twirl(String bundle, {required bool open}) => LayerFoldTwirl(
  name: 'shortcut-bundle-$bundle',
  expanded: open,
  onToggle: null,
);

/// What a recording writes while it waits for its key — a row's, or the
/// search's (I-168): the one sentence, in the program language.
Widget _recordingHint(ThemeData theme, String keyValue) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 8),
  child: Text(
    AppText.strings.shortcutRecordingHint,
    key: ValueKey<String>(keyValue),
    style: theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary,
    ),
  ),
);

/// A key as the window shows it — [red] where it clashes.
Widget _keyChip(ThemeData theme, String label, {bool red = false}) => Chip(
  label: Text(label, style: theme.textTheme.labelSmall),
  visualDensity: VisualDensity.compact,
  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  backgroundColor: red ? theme.colorScheme.errorContainer : null,
);

/// The ⌨ that starts a recording: a row's new key, or the key the list is
/// searched by (I-168: 「키보드 단축키 지정하는거 재사용해서」).
Widget _recordButton({
  required String keyValue,
  required String tooltip,
  required VoidCallback onPressed,
}) => AppIconButton(
  keyValue: keyValue,
  tooltip: tooltip,
  icon: const Icon(Icons.keyboard),
  onPressed: onPressed,
);

/// What the next key pressed is for ([_ShortcutSettingsDialogState]).
sealed class _Recording {
  const _Recording();
}

/// [actionId]'s new key.
final class _ForAction extends _Recording {
  const _ForAction(this.actionId);

  final String actionId;
}

/// The key the list is searched by (I-168).
final class _ForSearch extends _Recording {
  const _ForSearch();
}

/// The search by key beside the search by words (I-168): the rows' own ⌨
/// — pressed, the next key is the one sought, and the list keeps the
/// actions that hold it — and a ↺ that lets the key go, dead while none
/// is sought.
///
/// ⛔Its PLACE is always there (「없다가 생기는 UI 금지」): the hint and the
/// key sought share one slot, laid out as wide as the hint whether or not
/// it shows.
class _KeySearch extends StatelessWidget {
  const _KeySearch({
    required this.sought,
    required this.recording,
    required this.onRecord,
    required this.onClear,
  });

  final SingleActivator? sought;
  final bool recording;
  final VoidCallback onRecord;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final key = sought;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.centerRight,
          children: [
            Visibility.maintain(
              visible: recording,
              child: _recordingHint(theme, 'shortcut-search-by-key-hint'),
            ),
            if (key != null)
              Visibility.maintain(
                visible: !recording,
                child: KeyedSubtree(
                  key: const ValueKey<String>('shortcut-search-by-key-sought'),
                  child: _keyChip(theme, singleActivatorLabel(key)),
                ),
              ),
          ],
        ),
        _recordButton(
          keyValue: 'shortcut-search-by-key',
          tooltip: AppText.strings.shortcutSearchByKey,
          onPressed: onRecord,
        ),
        AppIconButton(
          keyValue: 'shortcut-search-by-key-clear',
          tooltip: AppText.strings.shortcutSearchByKeyClear,
          icon: const Icon(Icons.restart_alt),
          onPressed: onClear,
        ),
      ],
    );
  }
}

/// One action's row: its name, its keys and touch gesture, and its record ·
/// unassign · reset buttons — a brush group's title folding its bundle.
///
/// ↩️A method of the window's State until 2026-10-10, when the shelves
/// (Q1) took the State past six hundred lines.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.bindings,
    required this.definition,
    required this.conflicted,
    required this.touchConflicted,
    required this.red,
    required this.recording,
    required this.depth,
    required this.onRecord,
    required this.onUnassign,
    this.bundle,
    this.bundleOpen = false,
    this.onToggleBundle,
  });

  final EditorShortcutBindings bindings;
  final EditorActionDefinition definition;
  final bool conflicted;
  final bool touchConflicted;

  /// Whether its name stands red: a clash is on it, or, a group's title,
  /// on what it folds.
  final bool red;

  /// Whether this row is recording its next key.
  final bool recording;

  /// How many steps its shelf stands in ([ShortcutShelf.path]).
  final int depth;
  final VoidCallback onRecord;
  final VoidCallback onUnassign;

  /// The brush bundle it stands in, or null; a group's title folds it.
  final String? bundle;
  final bool bundleOpen;
  final VoidCallback? onToggleBundle;

  /// How much of a row its keys and its touch gesture may take before they
  /// wrap — the name and the row's buttons keep the rest.
  static const double _keysShare = 0.6;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activators = bindings.activatorsFor(definition.id);
    final touchGesture = bindings.touchGestureFor(definition.id);
    final titlesBundle = definition.brushPress is BrushGroupPress;

    // The keys recorded on the row and its touch gesture — what stands
    // between its name and its buttons.
    final keys = <Widget>[
      if (recording)
        _recordingHint(theme, 'shortcut-recording-hint')
      else
        for (final activator in activators)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _keyChip(
              theme,
              singleActivatorLabel(
                bindings.shownActivatorFor(definition.id, activator),
              ),
              red: conflicted,
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
                  onPicked: (gesture) => bindings.setTouchGesture(
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
              if (folds != null) _twirl(folds, open: bundleOpen),
              Expanded(
                child: Text(
                  actionLabelOf(definition),
                  style: _wordsIn(theme, theme.textTheme.bodyMedium, red: red),
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
              _recordButton(
                keyValue: 'shortcut-record-${definition.id}',
                tooltip: AppText.strings.shortcutRecordNew,
                onPressed: onRecord,
              ),
              // Dead on a row with no key: there is nothing to take off.
              AppIconButton(
                keyValue: 'shortcut-unassign-${definition.id}',
                tooltip: AppText.strings.shortcutUnassign,
                icon: const Icon(Icons.backspace_outlined),
                onPressed: activators.isEmpty
                    ? null
                    : onUnassign,
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
          return folds == null ? row : _foldRow(onToggleBundle!, row);
        },
      ),
    );
  }
}
