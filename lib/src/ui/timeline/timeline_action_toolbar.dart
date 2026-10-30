import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/app_frame_count_settings.dart';
import '../../models/app_frame_grid_settings.dart';
import '../../models/app_input_settings.dart' show AppInput, AppInputSettings;
import '../../models/frame.dart' show InbetweenMark;
import '../cut_command_group.dart';
import '../editor_session_manager.dart';
import '../sliced_value_listenable_builder.dart';
import '../session/storyboard_cursor.dart' show CommaTargetKind;
import '../widgets/app_icon_button.dart';
import 'comma_button.dart';
import 'inbetween_mark_icon.dart';
import 'timeline_shift_buttons.dart';
import '../widgets/command_pill.dart';
import '../widgets/kept_tail_row.dart' show FoldFloor;
import '../widgets/panel_flyout.dart';
import '../widgets/pill_strip.dart';
import 'instance_editor_commands.dart' show autoNameWithWindow;
import 'merge_layer_rows.dart';
import 'timeline_section_policy.dart';
import 'timeline_bar_menus.dart';
import 'toolbar_panel_context.dart';
import '../theme/app_theme.dart';
import '../shortcuts/editor_action_registry.dart';
import '../shortcuts/editor_shortcut_scope.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/frame_count_field.dart';

/// The N-comma input (UI-R17 #7): asks for an exposure count and applies
/// it to the selection (or the current block). Shared by the toolbar's N
/// button and the digit-5 shortcut.
///
/// B8: the count lands where the 1–4 presses land — on [panel], the panel
/// the button was pressed in. ↩️The digit shortcut passed none and kept the
/// session's cut-local verb; a key presses the button of the panel being
/// worked in now (유저 2026-09-24), so every caller names its panel and the
/// third dispatch that stood here is gone (F-283).
Future<void> showTimelineCommaCountDialog(
  BuildContext context,
  EditorSessionManager session, {
  required ToolbarPanelContext panel,
}) async {
  final target = panel.commaTarget;
  if (target == null) {
    return;
  }
  // 🗣️I-24-open-entry (유저 2026-10-01): 「노출 길이 설정 (프레임), 노출
  // 길이 설정 (컷) 이렇게 하자 … 길이 설정도 기존 길이 띄워둔다」 — what the
  // press will re-time, read off the ladder the press itself takes.
  final shown = session.storyboardCursor.commaTargetShown(target);
  final strings = AppText.strings;
  final comma = await _askFrameCount(
    context,
    session,
    keyPrefix: 'set-comma-n',
    title: strings.windowTitleOn(
      strings.setLengthAction,
      _commaTargetNoun(shown.kinds),
    ),
    titleIcon: Icons.timelapse_outlined,
    initialCount: shown.length,
  );
  if (comma != null && comma >= 1) {
    panel.setComma(comma);
  }
}

/// 🗣️I-58 (유저 2026-10-01): 「버튼누르면 창 열려서 숫자만 입력가능한창.
/// 3적고 확인누르면 현재 블록에서 헤더부터 시작해서 3코마마다 점 찍음」 — the
/// mark every n koma, pressed on [panel] as the N commas are. With no band
/// it counts from the playhead's cell, and it toggles as the mark's button
/// does (F-402 — `LayerMarks.markEvery`).
///
/// The window picks the mark — ○ or ● — opening on the one picked last:
/// 🗣️I-130-Q2 (유저 2026-10-25 「창에서 마크를 고른다」 — 간격 숫자 옆에
/// ○ / ● 고르기(지난번 고른 것 기억). 자동 추가 버튼은 하나 그대로). Before
/// any pick, on the mark an unnamed drawing wears (F-489-Q1 「둘 다
/// 따라간다」).
Future<void> showMarkEveryDialog(
  BuildContext context,
  EditorSessionManager session, {
  required ToolbarPanelContext panel,
}) async {
  final strings = AppText.strings;
  var mark =
      AppFrameCountSettings.settings.value.lastEveryMark ??
      AppFrameGridSettings.settings.value.unnamedMark;
  final every = await _askFrameCount(
    context,
    session,
    keyPrefix: 'mark-every',
    // The marks go down frame blocks alone ([LayerMarks.markEvery]).
    title: strings.windowTitleOn(
      editorActionLabel(EditorActionIds.frameMarkEvery),
      strings.tlFrame,
    ),
    titleIcon: _markEveryIcon,
    // The interval is the one number the title does not say.
    field: strings.markEveryField,
    mark: (
      picked: mark,
      onPicked: (picked) {
        mark = picked;
        session.appSettings.setFrameCountSettings(
          AppFrameCountSettings.settings.value.copyWith(lastEveryMark: picked),
        );
      },
    ),
  );
  if (every != null && every >= 1) {
    panel.markEvery(every, mark);
  }
}

/// The mark a count window picks beside its count, and the hook that hears
/// a pick ([showMarkEveryDialog]).
typedef _MarkPick = ({
  InbetweenMark picked,
  ValueChanged<InbetweenMark> onPicked,
});

const _markEveryIcon = Icons.linear_scale;

/// What a comma window names in its title's brackets: the kinds it
/// re-times, together where it re-times several.
String _commaTargetNoun(List<CommaTargetKind> kinds) {
  final strings = AppText.strings;
  return [
    for (final kind in kinds)
      switch (kind) {
        CommaTargetKind.cut => strings.tlCut,
        CommaTargetKind.frame => strings.tlFrame,
        CommaTargetKind.se => strings.tlKindSe,
        CommaTargetKind.transition => strings.tlKindTransition,
      },
  ].join(' · ');
}

/// A count of frames, asked in a window and popped as frames — null when
/// it closes without one. Every window that asks for a count of frames
/// asks with [FrameCountField] (I-24); one that lays a mark picks it
/// beside the count ([mark]).
Future<int?> _askFrameCount(
  BuildContext context,
  EditorSessionManager session, {
  required String keyPrefix,
  required String title,
  required IconData titleIcon,
  String? field,
  int? initialCount,
  _MarkPick? mark,
}) => showDialog<int>(
  context: context,
  builder: (context) => _FrameCountWindow(
    keyPrefix: keyPrefix,
    title: title,
    titleIcon: titleIcon,
    field: field,
    initialCount: initialCount,
    framesPerSecond: session.projectSettings.projectFrameRate.countingBase,
    // 🗣️I-24-open-entry-Q1 (유저 2026-10-01): 「마지막에 쓴 방식으로 연다」
    // — the entry last switched to, kept as an app setting so a restart
    // keeps it too.
    entry: AppFrameCountSettings.settings.value.lastEntry,
    onEntryChanged: (entry) => session.appSettings.setFrameCountSettings(
      AppFrameCountSettings.settings.value.copyWith(lastEntry: entry),
    ),
    mark: mark,
  ),
);

/// The count window: the count given as frames or as seconds+frames
/// ([FrameCountField], I-24), popped as frames.
class _FrameCountWindow extends StatefulWidget {
  const _FrameCountWindow({
    required this.keyPrefix,
    required this.title,
    required this.titleIcon,
    required this.field,
    required this.framesPerSecond,
    required this.entry,
    required this.onEntryChanged,
    required this.initialCount,
    required this.mark,
  });

  /// `<keyPrefix>-dialog`, `<keyPrefix>-apply`, and the field's own.
  final String keyPrefix;
  final String title;
  final IconData titleIcon;
  final String? field;
  final int framesPerSecond;

  /// The count the window opens on — the length already there
  /// (I-24-open-entry: 「길이 설정도 기존 길이 띄워둔다」); null opens it
  /// showing none, which applies nothing until a number is given.
  final int? initialCount;

  /// The entry the window opens on.
  final FrameCountEntry entry;
  final ValueChanged<FrameCountEntry> onEntryChanged;

  /// The mark it picks beside the count — null for a window that lays none.
  final _MarkPick? mark;

  @override
  State<_FrameCountWindow> createState() => _FrameCountWindowState();
}

class _FrameCountWindowState extends State<_FrameCountWindow> {
  late int? _count = widget.initialCount;
  late InbetweenMark? _mark = widget.mark?.picked;

  void _apply() => Navigator.of(context).pop(_count);

  void _pick(InbetweenMark mark) {
    setState(() => _mark = mark);
    widget.mark?.onPicked(mark);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    final mark = _mark;
    return AppWindow(
      windowKey: ValueKey<String>('${widget.keyPrefix}-dialog'),
      title: widget.title,
      titleIcon: widget.titleIcon,
      onClose: () => Navigator.of(context).pop(),
      width: 300,
      body: FrameCountField(
        keyPrefix: widget.keyPrefix,
        label: widget.field,
        framesPerSecond: widget.framesPerSecond,
        count: _count,
        onChanged: (count) => setState(() => _count = count),
        initialEntry: widget.entry,
        onEntryChanged: widget.onEntryChanged,
        beside: mark == null
            ? null
            : PillStrip(
                items: [
                  for (final each in InbetweenMark.values)
                    PillItem(
                      keyValue: '${widget.keyPrefix}-mark-${each.name}',
                      label: editorActionLabel(markToggleActionOf(each)),
                      icon: inbetweenMarkIcon(each),
                      selected: each == mark,
                      onTap: () => _pick(each),
                    ),
                ],
              ),
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonApply,
          actionKey: ValueKey<String>('${widget.keyPrefix}-apply'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: _apply,
          // Enter applies, as it did while the count was a typed field —
          // the window opens with the keyboard on Apply (F-479).
          autofocus: true,
        ),
      ],
    );
  }
}

/// The command bar above the timeline grid (CSP-style, R-toolbar round):
/// only the high-frequency commands stay as direct icons — everything else
/// lives in the shared flyouts.
///
/// Layout: four pills — `[컷 ＋] [레이어 ＋ 🗑] [프레임 ＋ ✕ ● ↑ ↓ 1 2 3 4 N]
/// [✦]` — each one a noun's name cell followed by that noun's verbs. There
/// are no `▾` carets: a name cell IS its menu, and a `＋` that can make more
/// than one thing wears a band along its top edge instead. Menu items reuse
/// the retired toolbar buttons' key strings so tests only gain a menu-open
/// tap. The exposure ± buttons are GONE — block edge grips replaced them
/// outright (session APIs kept for grips).
/// Builds its group ONCE and hands the same widget back until its [gates]
/// answer differently.
///
/// The toolbar's layer and cut groups render nothing that changes: literal
/// labels, fixed icons, unconditional enablement, and flyout entries built
/// lazily at OPEN time. They rebuilt anyway, because the enablement-sensitive
/// FRAME group next to them makes the whole toolbar rebuild — measured at 24
/// layers, that dragged 144 widgets through every notify that landed a cel.
///
/// 🚨It HEARS its gates itself ([toolbarGateNews]) — the bar around it is
/// not built again for them (a-gate-rebuilds-the-whole-toolbar, 2026-10-24).
/// ↩️Its key was read only when the bar was built again, so each host
/// cached the bar on a token of every gate on it and a flip in one group
/// built them all; the shared pill alone heard its own, through the slice
/// this is now for every group.
///
/// CONTRACT: the builder may only read values that cannot change while
/// [gates] holds still. Lazily-read state is free (a flyout opens with
/// fresh values through the stable session); anything RENDERED must be in
/// [gates], and its source in [toolbarGateNews]. Inherited widgets stay
/// live either way — dependencies are tracked per element, so a theme
/// change still rebuilds the cached subtree.
class _StaticCommandGroup extends StatelessWidget {
  const _StaticCommandGroup({
    required this.news,
    required this.gates,
    required this.builder,
    this.zoned = false,
  });

  final Listenable news;

  /// Every value the group shows — what it is built again for.
  final Object? Function() gates;
  final WidgetBuilder builder;

  /// Whether what [builder] makes lays its own zones
  /// ([CommandGroupZone]) — the frame pill's, round its groups — rather
  /// than baking whole here.
  final bool zoned;

  @override
  Widget build(BuildContext context) => SlicedListenableBuilder<Object?>(
    listenable: news,
    slice: gates,
    builder: (context, shown) => _BakedCommandGroup(
      shown: shown,
      builder: builder,
      zoned: zoned,
    ),
  );
}

/// A group's widgets as last built, and the zone they bake in.
class _BakedCommandGroup extends StatefulWidget {
  const _BakedCommandGroup({
    required this.shown,
    required this.builder,
    required this.zoned,
  });

  final Object? shown;
  final WidgetBuilder builder;
  final bool zoned;

  @override
  State<_BakedCommandGroup> createState() => _BakedCommandGroupState();
}

class _BakedCommandGroupState extends State<_BakedCommandGroup> {
  Widget? _cached;
  TextScaler? _builtAt;

  @override
  void didUpdateWidget(covariant _BakedCommandGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shown != widget.shown) {
      _cached = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // The pills size themselves to their words (text-scale-fixed-height-bars,
    // 유저 2026-09-18: 「막대가 글자 크기를 따라 자란다」), so the OS text size
    // is a fact every group shows. Read here, it is also the dependency that
    // brings this build back when the size changes under a running app.
    final scaler = MediaQuery.textScalerOf(context);
    if (scaler != _builtAt) {
      _builtAt = scaler;
      _cached = null;
    }
    // Each group is its own ZONE. The bar used to be baked as one surface,
    // which meant a single button's state changing re-baked every button
    // on the row; now dirt from one group stops at that group's own
    // boundary.
    return _cached ??= switch (widget.zoned) {
      true => widget.builder(context),
      false => CommandGroupZone(child: widget.builder(context)),
    };
  }
}

class TimelineActionToolbar extends StatelessWidget {
  const TimelineActionToolbar({
    super.key,
    required this.session,
    required this.panelContext,
    required this.onAddLayer,
    required this.onRenameLayer,
    this.onDeleteRowSelection,
    required this.onDeleteLayer,
    this.onEditInstance,
    required this.onCreateInstance,
    this.hiddenSections = const {},
    this.onToggleSection,
  });

  final EditorSessionManager session;

  /// B8 — WHICH PANEL is pressing. Every layer/frame/shared/fx verb and
  /// gate on this bar reads the host's context rather than the session's
  /// cut-local one, so the same bar acts against the panel it is mounted
  /// in. The cut group is the stated exception (already panel-correct).
  final ToolbarPanelContext panelContext;

  /// ⛔KEPT FOR ITS HOSTS, NO LONGER THE `＋`'s ACTION.
  ///
  /// ⑥ 유저 2026-08-12: 「레이어 +버튼, 선택된 레이어 기준이아니라 애니메이션
  /// 레이어 생성.」 The `＋` makes an ANIMATION layer now — a button that made
  /// a different kind depending on where you were standing could not be
  /// pressed without first looking, which is the opposite of what a bar
  /// button is for. The band above it still offers every kind explicitly.
  final VoidCallback onAddLayer;

  final VoidCallback onRenameLayer;

  /// F: the shared delete's ROW rung, with its confirmation. Null lets the
  /// rung run unconfirmed (a host with no dialogs to show).
  final VoidCallback? onDeleteRowSelection;
  final VoidCallback onDeleteLayer;

  /// Opens the unified instance-edit dialog for the active layer at the
  /// playhead (kind-dispatched by the host).
  ///
  /// NULL when the host cannot serve it — the frame pill's menu entry greys
  /// out rather than pretending. Nothing passes null today (the dispatch is
  /// [instance_editor_commands.dart] now, and both panels reach it); the
  /// nullability stays because a host that cannot serve a command should be
  /// able to say so rather than hand over one that does nothing.
  final VoidCallback? onEditInstance;

  // ⛔`resolveCanEditInstance` is GONE (B8): it was a one-question side
  // channel for the storyboard's transition row, and the panel context now
  // carries that answer with every other panel-scoped gate — one interface
  // instead of a hook per question.

  /// Kind-dispatched creation: new frame / camera key / SE entry /
  /// instruction event.
  final VoidCallback onCreateInstance;

  // ⛔`currentRow` is GONE (a-gate-rebuilds-the-whole-toolbar, 2026-10-24).
  // It said which rail is asking, for the ONE case the shift pair needs it:
  // nothing selected, so the shove aims at the row this rail stands on. The
  // timeline left it null — its current row IS the active layer, the
  // session's own fallback; the storyboard could not, because its rail's
  // standing row is separate state from the drawing target (user
  // 2026-07-27), and that is the whole reason the pair used to be mounted a
  // second time beside this bar. It was the storyboard's
  // [ToolbarPanelContext.shiftCurrentRow] passed BY VALUE, so its host had
  // to build the bar again for every stand; the pair asks [panelContext]
  // now, the answer its keys read too.

  /// Sections hidden from the grids; the Layer menu's show/hide items and
  /// the rail's fold chevrons both flip this.
  final Set<TimelineSection> hiddenSections;
  final ValueChanged<TimelineSection>? onToggleSection;

  /// Whether the Add button has anywhere to go — THE PANEL's one sentence
  /// (B8). The host-answers-first side channel and the session read both
  /// live inside [ToolbarPanelContext.canCreateInstance] now: the timeline
  /// context is [EditorSessionManager.canCreateInstance] verbatim, the
  /// storyboard's asks its own standing row (transition span, S-row entry)
  /// after the shared selection rungs.
  bool get _canCreateInstance => panelContext.canCreateInstance;

  /// The bar's menus for this panel — the lists these pills open, and the
  /// ones a key presses a row of ([TimelineBarMenus]).
  TimelineBarMenus get _menus =>
      TimelineBarMenus(session: session, panel: panelContext);

  /// What every group on this bar hears ([toolbarGateNews]).
  Listenable get _news => toolbarGateNews(session);

  // ⛔The two PROJECT-axis dropdowns (fps, audio sample rate) LEFT this bar
  // (유저 확정, 2026-08-10). They print project values and nothing about the
  // playhead, they are touched about once per project, and they were sitting
  // in the middle of the frame verbs — so they are entries of the settings
  // pill then, and are the project settings of the top strip's ⚙ now
  // ([ProjectSettingsMenu]).

  /// R26 #42: the app's standard icon button (the canvas bottom bar's
  /// style, promoted) — this toolbar used to size its own.
  Widget _iconButton({
    required ValueKey<String> key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool accent = false,
    bool danger = false,
    Color? color,
    List<String> shortcuts = const [],
  }) {
    return AppIconButton(
      keyValue: key.value,
      tooltip: tooltip,
      shortcuts: shortcuts,
      onPressed: onPressed,
      // 유저 확정: accent는 ＋ 글리프에만, ＋가 있는 모든 곳에 — the law
      // itself is [AppColors.addGlyph], since 「모든 곳」 has to be one
      // decision rather than the same decision made at each button.
      //
      // 🆕And its twin (유저 2026-08-12): 「+버튼은 강조색이라는 공통규칙있는데,
      // 딜리트는 지금처럼 빨간색 공통규칙두자」 — same shape, same rule, the
      // GLYPH only, and it goes out with the button.
      icon: Icon(
        icon,
        // [color] is the caller's own answer — a toggle's ON state, which
        // is neither of the two GLYPH laws below and must not borrow either
        // of their colours.
        color:
            color ??
            (danger
                ? AppColors.deleteGlyph(enabled: onPressed != null)
                : (accent
                      ? AppColors.addGlyph(enabled: onPressed != null)
                      : null)),
      ),
    );
  }

  /// [tooltip] is what the tooltip says — its words and the action whose
  /// live key follows them (I-19), one answer to one question.
  Widget _commaButton({
    required ValueKey<String> key,
    required String label,
    required ({String text, String action}) tooltip,
    required VoidCallback? onPressed,
  }) {
    // 🚨F-45 (유저 2026-08-29: 「F45는 해당 버튼쪽만 보지말고 **다른거도
    // 봐줘 통일해서**」). These five were the app's only chrome buttons
    // that mounted no claim at all: the ledger that keeps hand-rolled
    // buttons honest scans `IconButton(`, so a TEXT button walked straight
    // past it and a drag begun on 1·2·3·4·N leaked into the bar's pan.
    // The BOX is still theirs (a pill promised it); the LAW never was — the
    // face IS its claim ([CommaButton]).
    //
    // 🚨유저 #8 (2026-08-14): 「1,2,3,4,n만 천천히 페이드인하면서
    // 나타나거나 페이드아웃하면서 사라짐. **누가 이런 차이 두라했지?
    // 다 똑같이해. 페이드같은거 넣지마**」. ⛔They were the only toolbar
    // buttons that faded, and it was never authored — Material animated a
    // TextButton's foreground between its enabled and disabled colours. A
    // face reads its colour at build, as the icon buttons beside it do, so
    // there is nothing left to interpolate.
    return CommaButton(
      key: key,
      label: label,
      tooltip: tooltip.text,
      shortcuts: [tooltip.action],
      onPressed: onPressed,
    );
  }

  // ⛔`_groupDivider` is gone. A group is a PILL now and its border says
  // where it ends — a rule drawn between two bordered things says nothing
  // the borders had not already said.

  /// The LAYER pill.
  ///
  /// Cached (see [_StaticCommandGroup]) on the hidden-section mask — the
  /// menu's show/hide checkmarks read `hiddenSections` from THIS closure —
  /// on the program LANGUAGE, because the name cell prints a word now, and
  /// on the one predicate a verb outside the menu reads.
  Widget _layerPill() => _StaticCommandGroup(
    news: _news,
    gates: () => Object.hash(
      hiddenSections.fold<int>(
        0,
        (mask, section) => mask | (1 << section.index),
      ),
      AppText.settings.value.programLanguage,
      session.layerVerbs.canDeleteActiveLayer,
      // ①: the rename button lives here now, so its gate has to be part of
      // what wakes this group up.
      _menus.canEditActiveLayer,
    ),
    builder: (context) => CommandPill(
      key: const ValueKey<String>('timeline-toolbar-layer-group'),
      head: PillNameCell(
        keyValue: 'timeline-layer-menu-button',
        label: AppText.strings.tlLayer,
        tooltip: AppText.strings.tlLayerCommands,
        entriesBuilder: () => _menus.layer(context),
      ),
      children: [
        const PillDivider(),
        StrapIconButton(
          buttonKey: 'timeline-toolbar-add-layer-button',
          menuKey: 'timeline-toolbar-add-layer-menu',
          icon: Icons.add,
          accent: true,
          // 🗣️I-63 ③: this button IS the Add Layer action's entrance, so it
          // wears that action's name and shows its key (I-19).
          tooltip: editorActionLabel(EditorActionIds.layerAdd),
          shortcuts: const [EditorActionIds.layerAdd],
          // ⑥: ONE kind, always — 유저 「선택된 레이어 기준이아니라 애니메이션
          // 레이어 생성」. Placement is unchanged (above the selected row, and
          // the top of the action section when that is not a legal home).
          // B8: WHICH one kind is the panel's word — the timeline's context
          // says animation, the storyboard's says the S row it can grow.
          onPressed: panelContext.addLayer,
          entriesBuilder: _menus.addLayer,
        ),
        // ⛔THE LAYER RENAME IS GONE FROM HERE TOO — T25 (유저 2026-08-14:
        // 「레이어 이름변경 버튼 필요없어지니 삭제」).
        //
        // ① had put it here, out of the menu and onto the pill. It leaves on
        // the SAME condition the layer delete left on, one rung later: the
        // shared verb has to already do this button's whole job.
        //
        // ✅It does, and it did before T25 started —
        // `renameActiveLayerWithDialog` reads `renameableSelectedLayerIds`
        // and commits `renameSelectedLayers`, which IS 확정 #20's batch
        // (「선택된 편집가능 레이어 전부를 같은 이름으로 일괄 변경」). The
        // shared Edit Instance routes to that exact function, so renaming a
        // layer is now: select the row, press the one Edit Instance.
        //
        // ⛔THE LAYER DELETE IS GONE FROM HERE — ⑰ is finished.
        //
        // It stood beside this `＋` on ONE stated condition: the shared
        // delete asks WHAT IS SELECTED, and `PillSubject.layers` was a rung
        // nothing could reach while rows had no selection. ⑨ (#952) built
        // that selection and F carried the confirmation across
        // (`onDeleteRowSelection`), so the successor does this button's whole
        // job — including asking first. Deleting the predecessor is
        // [[duplication-program]]'s last step, and it waited for the one
        // condition that makes it safe rather than for nobody to notice.
        //
        // Deleting a layer is now: select the row, press the one delete —
        // 「딜리트 = 버튼 하나 … 레이어를 선택했으면 레이어 삭제」 (⑰).
        //
        // ⛔The CUT delete keeps its own button for the reason this one no
        // longer needs one: cut SELECTION exists only on the storyboard's
        // axis, so from here the shared pill can never be handed a cut.
      ],
    ),
  );

  /// Every gate the shared pill shows — what it is built again for.
  Object _sharedPillKey() => (
    panelContext.deleteSubject,
    AppText.settings.value.programLanguage,
    // ㉕: the three that joined the delete read their own gates.
    // T3 made it four — 잘라내기 asks the same question copy does.
    // B8: every gate is the PANEL's now — the timeline context answers
    // with the session getters this key used to name, the storyboard's
    // with its standing row, host answer included (the side channel this
    // key used to carry as its last entry).
    panelContext.canCutRun,
    panelContext.canCopyFrame,
    panelContext.canPasteLinkedFrame,
    panelContext.canPasteIndependentFrame,
    // T25: and the fifth resident reads its own subject, for the same
    // reason the delete reads `deleteSubject` — the button's enablement
    // and what the press DOES have to come from one answer.
    onEditInstance != null && panelContext.canEditInstance,
    // The 색 편집 head reads the gate its rows open behind.
    session.pixelVerbs.canOpenColourEdit,
    // I-45: the link-independent button, from its own one answer.
    panelContext.canUnlink,
    // F-455: 복제, likewise.
    panelContext.canDuplicate,
    // I-78: 병합, likewise.
    panelContext.canMerge,
    // I-18: 자동 이름 지정, likewise.
    panelContext.canAutoName,
  );

  /// 🚨★★★ THE SHARED PILL — verbs that belong to no noun (⑰㉕, 유저 2026-08-12:
  /// 「프레임알약 옆에 공용버튼 들어가는 알약만들고 거기」).
  ///
  /// It has **no name cell**, and that is the point: its verbs act on whatever
  /// is selected, and a selection is not a thing with a menu. Giving it one
  /// would have been a border drawn around a gap.
  ///
  /// ⛔Three delete buttons died for this one: `delete-cut-button` in the cut
  /// menu, `delete-layer-button` in the layer menu, and the loose
  /// `timeline-delete-layer-button` beside it. Each was hard-wired to one
  /// noun, which is why the same word did different things depending on where
  /// you reached for it — and why nothing on the bar could delete a CUT while
  /// the cut menu was closed.
  ///
  /// ↩️The four ⚠️ below and the cel's line were this pill's OWN listeners;
  /// every group hears them now ([toolbarGateNews],
  /// a-gate-rebuilds-the-whole-toolbar), and each still says why.
  /// ⚠️Subscribed to the ROW SELECTION, and it has to be.
  ///
  /// The subject this pill asks for is mostly session state that arrives with
  /// a notify — but ⑨'s row selection is a [ValueNotifier] on purpose (it
  /// grows per pointer move, and a notify per move would rebuild every panel).
  /// Without this the pill's `deleteSubject` was only re-read when something
  /// ELSE happened to notify, so selecting rows left the one delete greyed
  /// out — the state was right and the button had not looked again (㉞'s
  /// shape, one floor up).
  /// ⚠️And to the CURRENT ROW, for the same reason one floor along.
  ///
  /// T25 moved Edit Instance in here, and it brought its subscription with
  /// it: `currentRow` publishes through its own notifier WITHOUT a session
  /// notify (it moves per press), so a baked button that only re-reads on a
  /// session notify shows the answer from whichever row you were standing on
  /// last. Dropping this listener while moving the button is exactly how
  /// ㉞'s shape comes back, and the storyboard's transition row caught it
  /// immediately — its Edit Instance is enabled by the HOST's answer about
  /// the standing row and nothing else.
  /// ⚠️It listens to ALL FOUR selection channels, not two.
  ///
  /// The row selection and the standing row were enough while every button
  /// here read a row or the playhead. The copy, cut and paste gates read the
  /// clipboard's band — the cell band or the cut band — and a gate that is
  /// not listened to is a button that lights one notify late. (Found first
  /// by the deselect button's test, a live cell band leaving it dark, while
  /// that button was here; it left this pill on 08-26.)
  /// 🚨And it hears them through its KEY — the gates it shows — not bare
  /// (2026-10-24, card the-whole-block-drag-has-no-door). A block moves as
  /// the selection it is (UI-R8), so every step of a move, and every pointer
  /// move of a sweep, moves the band heard here. Built again on each, with
  /// the same key, the pill still dirtied the panel's layout scope: the
  /// panel's whole host was laid out and painted again at every step of the
  /// drag (F-244: a drag step is a tick). Every group hears its gates this
  /// way now.
  /// 🚨★★★AND THE THING A SELECTION IS NOT: WHETHER THE CEL HAS A DRAWING.
  ///
  /// 「지금 무엇이 선택됐나」 is what this pill is for, but the gates in its
  /// key do not only ask which rows and ranges are marked — they ask whether
  /// the cel you are standing on has anything in it, and that changes
  /// without any selection moving. 픽셀 비우기 empties the cel you are
  /// already standing on; nothing else fired, so the buttons stayed lit over
  /// a block the user had just cleared (유저 2026-08-27: 「인덱스 이동해서 그림
  /// 사라진거 확인하더라도 버튼 여전히 활성화되있고」).
  ///
  /// ⛔The PLAYHEAD was deliberately not among this pill's listeners. It
  /// looked like the same hole, and it was not: removing the cel's line
  /// reddened its test, removing a playhead line did not — the pill re-read
  /// on a scrub through the rebuild the session's own notify carried. An
  /// addition whose necessity cannot be shown is the shape that put
  /// 「갱신된다」 into #1269 with no guard at all.
  ///
  /// ↩️F-75 (유저 2026-09-11): the playhead half WAS a hole — one that
  /// listener could never close. A committed seek is not a session notify,
  /// and the bar around this pill was cached on its host's token, so a seek
  /// between two drawn cels, equal on every other gate, reused the bar whole
  /// and this pill never looked again. The answer travelled in the hosts'
  /// tokens until the groups heard the seek themselves.
  Widget _sharedPill() => _StaticCommandGroup(
    news: _news,
    gates: _sharedPillKey,
    builder: (context) => CommandPill(
      key: const ValueKey<String>('timeline-toolbar-shared-group'),
      children: [
        // ⛔THE DESELECT IS NOT HERE. It was, for one round, and that made
        // TWO buttons called 선택 해제 wearing the same `Icons.deselect` —
        // this one letting go of the timeline's selections, `rail-deselect-
        // button` letting go of the marquee, and nothing on screen saying
        // which was which (유저 2026-08-27: 「선택해제 타임라인에 중복으로
        // 존재하는거」).
        //
        // The rail's is the one that stayed, and it lets go of the marquee
        // alone (유저 2026-10-14, I-40) — a tap lets go of the timeline's
        // selections (T10). ⚠️The 취소 button, if it is built, goes beside
        // THAT one; the note about holding its neighbour slot moved with the
        // button it was about.
        // 🚨T25 — Edit Instance, on the SHARED pill because its subject is
        // 「지금 무엇이 선택됐나」 and that is what this pill is for.
        //
        // ⚠️It keeps the key it had on the frame pill. The button moved; it
        // did not become a different button, and every test that reached it
        // still does.
        // 🗣️F-261: an action now, so it wears that action's name and its key
        // — I-19's five beside it did the same.
        _iconButton(
          key: const ValueKey<String>('shared-edit-button'),
          tooltip: editorActionLabel(EditorActionIds.editInstance),
          shortcuts: const [EditorActionIds.editInstance],
          icon: Icons.edit_outlined,
          // B8: ONE source — the panel. The timeline's context answers with
          // the session's subject (the same answer [editSelectionInstance]
          // dispatches on, so lit and does-something cannot come apart);
          // the storyboard's answers with its standing row's block, from
          // the SAME resolver its host dispatches on.
          onPressed: onEditInstance != null && panelContext.canEditInstance
              ? onEditInstance
              : null,
        ),
        // 🗣️I-18 — 자동 이름 지정, beside Edit (유저: 「타임라인 공용 알약에
        // 새 버튼 신설. 내용은 블록 이름 자동편집으로 … 버튼은 자동 이름
        // 지정」). It asks what is selected, the pill's one ladder, and
        // numbers what the panel names from the number its window asks for.
        // A context of its own: the window opens from where it was pressed.
        Builder(
          builder: (context) => _iconButton(
            key: const ValueKey<String>('shared-auto-name-button'),
            tooltip: editorActionLabel(EditorActionIds.editAutoName),
            shortcuts: const [EditorActionIds.editAutoName],
            icon: Icons.format_list_numbered,
            onPressed: panelContext.canAutoName
                ? () => unawaited(
                    autoNameWithWindow(context, session, panel: panelContext),
                  )
                : null,
          ),
        ),
        const PillDivider(),
        // 🚨T3 신설 — 잘라내기, 「복사 버튼 왼쪽」 (유저 2026-08-13).
        //
        // Copy keeps the original and stores the clip; this one stores the
        // clip and takes the original out, and the tail closes over the
        // hole. It is the LIFT half of the one splice — the same half a
        // paste-over-a-selection does before it puts the clip down — so it
        // needed no placement rules of its own.
        // 🗣️I-19: each of these six IS one action's entrance, so it wears
        // that action's registry name and names the action for its key.
        _iconButton(
          key: const ValueKey<String>('shared-cut-button'),
          tooltip: editorActionLabel(EditorActionIds.editCut),
          shortcuts: const [EditorActionIds.editCut],
          icon: Icons.content_cut,
          onPressed: panelContext.cutPress,
        ),
        // I-77: with rows selected the copy takes the ROWS, and the two
        // pastes put down whichever the hand holds. The panel answers which
        // ([ToolbarPanelContext]); nothing here knows the difference.
        _iconButton(
          key: const ValueKey<String>('shared-copy-button'),
          tooltip: editorActionLabel(EditorActionIds.editCopy),
          shortcuts: const [EditorActionIds.editCopy],
          icon: Icons.content_copy,
          onPressed: panelContext.copyPress,
        ),
        // ㉕ 확정 #8: the paste that makes a REAL frame, not a link. Two
        // buttons rather than one with a modifier, because which one you
        // meant is not a detail — a linked paste that was meant to be
        // independent is only discovered later, by drawing on it and
        // watching another cel change.
        _iconButton(
          key: const ValueKey<String>('shared-paste-independent-button'),
          tooltip: editorActionLabel(EditorActionIds.editPasteIndependent),
          shortcuts: const [EditorActionIds.editPasteIndependent],
          icon: Icons.content_paste,
          onPressed: panelContext.pasteIndependentPress,
        ),
        _iconButton(
          key: const ValueKey<String>('shared-paste-linked-button'),
          tooltip: editorActionLabel(EditorActionIds.editPasteLinked),
          shortcuts: const [EditorActionIds.editPasteLinked],
          icon: Icons.link,
          onPressed: panelContext.pasteLinkedPress,
        ),
        // 🚨I-45 — 링크 독립, beside the paste that makes a link (유저
        // 2026-09-20: 「링크 독립버튼. 위치는 타임라인의 공용 알약부분? 프레임
        // 독립시키거나 레이어나 컷이나」). It asks what is selected, the pill's
        // one ladder: rows → their links, the frame axis → its shared
        // pictures, and on the storyboard the cuts.
        _iconButton(
          key: const ValueKey<String>('shared-unlink-button'),
          tooltip: editorActionLabel(EditorActionIds.editUnlink),
          shortcuts: const [EditorActionIds.editUnlink],
          icon: Icons.link_off,
          onPressed: panelContext.unlinkPress,
        ),
        // 🗣️F-455 (유저 2026-10-23): 「공용알약에 복제 버튼 만들고 레이어랑
        // 컷버튼의 레이어복제/컷복제 삭제」 — the layer pill's and the cut
        // pill's duplicates, one button. The panel answers which noun
        // ([ToolbarPanelContext.canDuplicate]): the rows on the timeline,
        // the cut on the storyboard.
        _iconButton(
          key: const ValueKey<String>('shared-duplicate-button'),
          tooltip: editorActionLabel(EditorActionIds.editDuplicate),
          shortcuts: const [EditorActionIds.editDuplicate],
          icon: Icons.control_point_duplicate,
          onPressed: panelContext.duplicatePress,
        ),
        // 🗣️I-78 (유저 2026-10-06): 「병합버튼. 우선 레이어 다중선택하고
        // 병합하는걸 원하는데, 프레임도 사용가능할거같으니 공용알약에 두는걸
        // 생각중」 — beside 복제, the other verb that makes a row of rows. A
        // context of its own: the press opens its windows from here.
        Builder(
          builder: (context) => _iconButton(
            key: const ValueKey<String>('shared-merge-button'),
            tooltip: editorActionLabel(EditorActionIds.editMerge),
            shortcuts: const [EditorActionIds.editMerge],
            icon: Icons.merge,
            onPressed: panelContext.canMerge
                ? () => unawaited(
                    mergeSelectionSubject(
                      context,
                      session,
                      panelContext.mergeSubject,
                    ),
                  )
                : null,
          ),
        ),
        _iconButton(
          key: const ValueKey<String>('shared-delete-button'),
          tooltip: editorActionLabel(EditorActionIds.editDelete),
          shortcuts: const [EditorActionIds.editDelete],
          icon: Icons.delete_outline,
          danger: true,
          onPressed: panelContext.deletePress(
            onDeleteRowSelection: onDeleteRowSelection,
          ),
        ),
        const PillDivider(),
        // 🚨THE TWO PIXEL VERBS, on THIS pill.
        //
        // 유저 2026-08-10 put ③ here in the first place — 「다만 이 버튼은
        // 타임라인에 두는게 나을듯」 — and the reason holds for both: the
        // selection that decides HOW MANY drawings change is the frame range,
        // and it is drawn here. A button belongs beside the thing that
        // decides how much it does. The marquee only decides how much of ONE
        // drawing.
        //
        // ⚠️They sit after the delete rather than beside the deselect, whose
        // neighbour slot is held for the 취소 button (see there).
        //
        // ⛔Dimmed with nothing to act on, never hidden.
        //
        // ✅ONE BUTTON, FOUR VERBS (유저 2026-08-27, I-8-Q3/Q4): 「그걸 하나의
        // 버튼으로 넣어서 앵커팝오버로 열리도록 한 버튼으로. 색 편집 버튼이란
        // 느낌? 그 안에 색관련 편집버튼 존재하는느낌」 — and 「기존에 있던
        // 색변환이랑 픽셀삭제 그 버튼 안에 들어가는거 잊지말고」.
        //
        // The head RUNS NOTHING. 색 편집 is a category, not a verb, so a
        // press that also did one of its verbs would be one button answering
        // two questions. The retired buttons' key strings live on as the
        // menu items', so tests only gain a menu-open tap.
        Builder(
          builder: (context) => _iconButton(
            key: const ValueKey<String>('shared-colour-edit-button'),
            tooltip: AppText.strings.tlSharedColourEdit,
            icon: Icons.palette_outlined,
            onPressed: session.pixelVerbs.canOpenColourEdit
                ? () => showPanelFlyout(context, entries: _menus.colourEdit())
                : null,
          ),
        ),
      ],
    ),
  );

  /// The FRAME pill — the verbs a rough pass wears out, none of them folded.
  ///
  /// 🚨Nothing on it outside its groups shows a value but its name: the
  /// pill holds zones of its own (the groups below), so it cannot bake
  /// whole as the layer pill does — a bake inside a bake freezes — and is
  /// built again only for its name, in a zone of its own. ↩️The cut pill
  /// was zoned too, round the cut's name (F-463 ④ to F-491).
  /// ↩️The name was a group of its own inside the pill, built where the
  /// pill could not see it, so the tail paid an icon's 5 after a word's 7
  /// (frame-pill-tail-breath-regressed — 유저 #7 again).
  Widget _framePill() => _StaticCommandGroup(
    news: _news,
    gates: () => AppText.settings.value.programLanguage,
    builder: (context) => _frameCommandPill(),
    zoned: true,
  );

  Widget _frameCommandPill() => CommandPill(
    key: const ValueKey<String>('timeline-toolbar-frame-group'),
    head: CommandGroupZone(
      child: PillNameCell(
        keyValue: 'timeline-frame-menu-button',
        label: AppText.strings.tlFrame,
        tooltip: AppText.strings.tlFrameCommands,
        entriesBuilder: _menus.frame,
      ),
    ),
    children: [
      const PillDivider(),
      // Cached on the predicates THESE buttons read, for the reason
      // spelled out at the comma group below.
      _StaticCommandGroup(
        news: _news,
        gates: () => (
          _canCreateInstance,
          panelContext.canBlankExposure,
          panelContext.canToggleMark,
          panelContext.canMarkEvery,
          session.languageSettings.value,
        ),
        builder: (context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⛔NO band on this `＋`: it makes ONE thing, in the place you
            // are standing. A band means there is something to choose, so
            // its absence here is the signal rather than an omission.
            //
            // 🗣️I-58 (유저 2026-10-18): 「컷 추가버튼은 새 컷이고 레이어는
            // 레이어 추가고 프레임은 추가임 … 통일」 — the ＋ × ● wear their
            // actions' names, as the cut's and the layer's ＋ do (I-40).
            // ↩️Each had a string of its own.
            _iconButton(
              key: const ValueKey<String>('new-frame-button'),
              tooltip: editorActionLabel(EditorActionIds.frameNewDrawing),
              // The film verbs ship unbound; naming the action is what shows
              // a key the day one is recorded for it.
              shortcuts: const [EditorActionIds.frameNewDrawing],
              icon: Icons.add,
              accent: true,
              onPressed: _canCreateInstance ? onCreateInstance : null,
            ),
            _iconButton(
              key: const ValueKey<String>('blank-exposure-button'),
              tooltip: editorActionLabel(EditorActionIds.frameBlankExposure),
              shortcuts: const [EditorActionIds.frameBlankExposure],
              icon: Icons.close,
              onPressed: panelContext.canBlankExposure
                  ? panelContext.blankExposure
                  : null,
            ),
            // 🚨F-61 (유저): 「프레임 자동생성 버튼 툴 설정에 있는데, **왜
            // 이딴식으로 결정한거지? 내가 분명 타임라인 헤더쪽에
            // 두라하지않았나?** 프레임 알약 안, **중간나누기 버튼 오른쪽**에
            // 두도록. 기존 잔재는 삭제」.
            //
            // ↩️A session read 「중간나누기 버튼」 as the × above (中割なし)
            // and stood this to its right. The user names the × 「비우기」
            // and the ● 「중간나누기 마크」 (I-58, 10-18), and keeps this
            // where it stands — I-58-Q1: 「토글은 지금 자리, 새 버튼만 ●
            // 오른쪽」.
            //
            // ⚠️A SETTING among commands, and that is the point: it is the
            // standing answer to 「what does a press on an empty cell do」,
            // so it belongs beside the verbs that make and unmake a block
            // rather than beside brush size.
            //
            // ★It listens for ITSELF. This group is memoized on
            // [_StaticCommandGroup.gates] and baked into a
            // [CommandGroupZone]; the toolbar does not rebuild when
            // `AppInput.settings` moves, so a plain read here would show
            // yesterday's state for ever. A listener inside the bake is
            // safe — a rebuild ends in `markNeedsPaint`, which is exactly
            // what the raster captures on. ⛔What must never go in is
            // another repaint BOUNDARY; a `ValueListenableBuilder` is not
            // one.
            ValueListenableBuilder<AppInputSettings>(
              valueListenable: AppInput.settings,
              builder: (context, input, _) => _iconButton(
                key: const ValueKey<String>('auto-frame-toggle-button'),
                // 🗣️I-40: an action now, so it wears that action's name and
                // shows its key — as the buttons either side of it do.
                tooltip: editorActionLabel(EditorActionIds.frameAutoCreate),
                shortcuts: const [EditorActionIds.frameAutoCreate],
                icon: Icons.auto_awesome,
                // ⛔NOT `accent:` — that flag is [AppColors.addGlyph] and
                // 유저 확정 reserved it for the ＋ glyph 「＋가 있는 모든
                // 곳에」. This is an ON state, which the app already says in
                // colour alone (`project_settings_menu`: current ? accent :
                // text) — and colour alone is the standing rule for
                // selection.
                color: input.autoCreateFrameOnDraw ? AppColors.accent : null,
                // F-191: through the setting's own door, which writes it
                // down. ↩️It set the live notifier alone, so the toggle came
                // back off (or on) with every restart.
                // The press is [toggleAutoCreateFrameOnDraw] — its key's too.
                onPressed: () => toggleAutoCreateFrameOnDraw(session),
              ),
            ),
            // 🗣️I-130 (유저 2026-10-25): 「기존 중간나누기 버튼 왼쪽에
            // 중간나누기 마크1 버튼 신설」 — ○ mark 1, then ● mark 2.
            for (final (mark, key) in const [
              (InbetweenMark.one, 'toggle-mark-one-button'),
              (InbetweenMark.two, 'toggle-mark-button'),
            ])
              _iconButton(
                key: ValueKey<String>(key),
                tooltip: editorActionLabel(markToggleActionOf(mark)),
                shortcuts: [markToggleActionOf(mark)],
                icon: inbetweenMarkIcon(mark),
                onPressed: panelContext.canToggleMark
                    ? () => panelContext.toggleMark(mark)
                    : null,
              ),
            // 🗣️I-58-Q1 (유저 2026-10-18): 「토글은 지금 자리, 새 버튼만 ●
            // 오른쪽」.
            _iconButton(
              key: const ValueKey<String>('mark-every-button'),
              tooltip: editorActionLabel(EditorActionIds.frameMarkEvery),
              shortcuts: const [EditorActionIds.frameMarkEvery],
              icon: _markEveryIcon,
              onPressed: panelContext.canMarkEvery
                  ? () => showMarkEveryDialog(
                      context,
                      session,
                      panel: panelContext,
                    )
                  : null,
            ),
          ],
        ),
      ),
      // ① 유저 확정: 「프레임 알약 밖으로 … Edit Instance」.
      //
      // 🚨A SIBLING ZONE, not a fourth button in the group above and NOT
      // nested inside it. Two reasons, and the second one cost a suite run:
      //
      // ① Its gate flips on the crossing that group is built to sleep
      //    through (cel → empty paper), so folding it in re-baked ＋ and the
      //    mark button on every flip — the exact defect
      //    `toolbar_button_group_memo_test` exists for, and caught.
      // ② ⛔A BAKE INSIDE A BAKE FREEZES. This file already said so, at the
      //    build method: the round that made these groups took the outer
      //    wrapper OFF for this reason. Nesting the zone inside the icon
      //    group left this button showing whatever it was baked with — grey
      //    — and the rename dialog simply never opened.
      //
      // 🚨And it subscribes to the STANDING ROW, which a menu entry never had
      // to: a flyout builds its entries when it opens, so it always read this
      // gate fresh, while a baked button only re-reads when something wakes
      // it — and `currentRow` publishes WITHOUT a session notify (it moves
      // per press). Same shape ⑰'s shared delete hit with `rowSelection`.
      // ⛔EDIT INSTANCE HAS LEFT THIS PILL — it is on the SHARED one now
      // (T25, 유저 2026-08-14: 「인스턴스 편집 버튼도 공통버튼으로 이동.
      // 그래서 **선택범위 통해 동사통일화** 가능하게」).
      //
      // It belonged here while its subject was the frame under the playhead.
      // With a selection to ask, the subject is whatever IS selected — a
      // cut, some rows, or that frame — and "acts on whatever is selected"
      // is the shared pill's entire definition. It walks the same ladder the
      // shared delete already walks.
      const PillDivider(),
      // Design D: the rigid shove a drag used to do, aimed. Scope = the live
      // selection's rows, or the current row at the current cell. ONE pair
      // for both axes, and now ONE pair for both panels: it is a frame-axis
      // shove, so it belongs to the FRAME noun, and [panelContext] is how the
      // asking rail names itself.
      //
      // A zone with no gates of its own: the pair hears its own (it stands
      // alone too, [TimelineShiftButtons]), and the zone keeps it — and its
      // paint — while the bar is built again round it.
      _StaticCommandGroup(
        news: _news,
        gates: () => null,
        builder: (context) =>
            TimelineShiftButtons(session: session, panel: panelContext),
      ),
      const PillDivider(),
      // Comma set (UI-R17 #7, TVP-style): the current block — or the whole
      // selection, packed — takes the pressed exposure outright; N asks for
      // a count. Shortcuts 1-5.
      //
      // Cached on THEIR OWN predicate. Five buttons that all read one boolean
      // sat in the same rebuild as the icon buttons beside them, so a flip
      // step that changed only this one rebuilt every button in the row — and
      // one that changed only an icon button's rebuilt all five of these.
      // Measured: crossing "no cel ↔ cel" changed 5 of the toolbar's 10
      // buttons and rebuilt all 10.
      _StaticCommandGroup(
        news: _news,
        gates: () => (
          panelContext.canSetComma,
          session.languageSettings.value,
        ),
        builder: (context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // B8: the press lands on THE PANEL's block — the timeline's
            // selection-or-current, or the storyboard's block under the
            // cursor (컷블록 위 4 = 컷길이 4), one rule per panel for every
            // block kind.
            for (var comma = 1; comma <= 4; comma += 1)
              _commaButton(
                key: ValueKey<String>('set-comma-$comma-button'),
                label: '$comma',
                tooltip: (
                  text: AppText.strings.tlSetCommaTemplate.replaceAll(
                    '{n}',
                    '$comma',
                  ),
                  action: const [
                    EditorActionIds.timelineComma1,
                    EditorActionIds.timelineComma2,
                    EditorActionIds.timelineComma3,
                    EditorActionIds.timelineComma4,
                  ][comma - 1],
                ),
                onPressed: panelContext.canSetComma
                    ? () => panelContext.setComma(comma)
                    : null,
              ),
            Builder(
              builder: (context) => _commaButton(
                key: const ValueKey<String>('set-comma-n-button'),
                label: 'N',
                tooltip: (
                  text: AppText.strings.tlSetCommasN,
                  action: EditorActionIds.timelineCommaN,
                ),
                onPressed: panelContext.canSetComma
                    ? () => showTimelineCommaCountDialog(
                        context,
                        session,
                        panel: panelContext,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  /// The FX pill — a noun with no verbs outside its menu yet, which the
  /// grammar allows: same shape, empty list.
  ///
  /// Safe inside the cached group for the R13-2 reason: the builder closes
  /// over the stable session and reads the active layer's chain when the
  /// flyout OPENS, so a reused button widget cannot show a stale list.
  Widget _fxPill() => _StaticCommandGroup(
    news: _news,
    gates: () => AppText.settings.value.programLanguage,
    builder: (context) => CommandPill(
      head: PillNameCell(
        keyValue: 'timeline-effects-button',
        // T15 (유저 2026-08-13): 「fx버튼, 지금 아이콘인데 다른거랑 통일해서
        // fx라고 텍스트로 바꾸자. 레이어나 컷도 그렇잖아」 — a pill's head is
        // its NOUN and the other three print theirs; this was the only
        // wordless name on the bar.
        //
        // ⚠️NOT the rail's `fx` glyph: that italic accent lettering means
        // "these effects are ON", and a name that also reported a state would
        // be answering two questions with one word.
        //
        // Untranslated on purpose — 현장 용어 stays in the original, which is
        // the same reason it needs no AppStrings key.
        label: 'Fx',
        tooltip: AppText.strings.tlEffects,
        entriesBuilder: _menus.effects,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // ⛔The outer border and fill are gone. Every noun wears its own pill
    // border now, so a box around all four of them was a frame around
    // frames — and the command bar it sits in already has an edge.
    //
    // 🆕The INSET and the overflow scroller are the BAR's
    // ([TimelineCommandBar.leadingInset]) — ⑫. They used to be here, which
    // works only while this widget IS the whole left side: the storyboard
    // puts two more groups beside it, padded that row, and so paid the inset
    // twice and nested one horizontal scroller inside another.
    //
    // ⛔The bake is NOT here either. It used to wrap the whole bar, which
    // meant one button's state changing re-baked every button on the row.
    // Each [_StaticCommandGroup] bakes ITSELF now, so the groups are ZONES:
    // siblings, each with its own dirty bit, each re-baking only for its own
    // reason. The wrapper had to come off rather than stay as an outer
    // layer, because a bake inside a bake is the one thing that freezes.
    return Row(
      key: const ValueKey<String>('timeline-action-toolbar'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // 컷 · 레이어 · 프레임 · FX — the four nouns, in the order the data
        // nests (유저 확정). Keyed on the language for the same reason as
        // the others: every name cell prints a word.
        // …and on the ＋'s gate: a band over the cut that is there leaves
        // nowhere to make one, and a bake keyed on the language alone kept
        // the ＋ lit through it.
        // 🗣️F-463 ⑥: 「컷쪽은 컷알약까지 최소폭」 — the least of the pills
        // the bar shows ([FoldFloor]), and the transport before them is
        // kept with it (F-491).
        FoldFloor(
          child: _StaticCommandGroup(
            news: _news,
            gates: () => (
              AppText.settings.value.programLanguage,
              session.cutPlacement.canCreateCut,
            ),
            builder: (context) => CutCommandGroup(session: session),
          ),
        ),
        const SizedBox(width: 6),
        _layerPill(),
        const SizedBox(width: 6),
        _framePill(),
        const SizedBox(width: 6),
        // 유저 확정: 프레임 알약 옆. It follows the nouns because it is not
        // one — everything in it acts on the selection.
        _sharedPill(),
        const SizedBox(width: 6),
        _fxPill(),
      ],
    );
  }
}
