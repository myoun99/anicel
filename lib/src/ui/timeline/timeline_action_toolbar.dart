import 'package:flutter/material.dart';

import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_row_address.dart';
import '../cut_command_group.dart';
import '../editor_session_manager.dart';
import '../widgets/app_icon_button.dart';
import 'timeline_shift_buttons.dart';
import '../widgets/command_pill.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/static_raster.dart';
import 'timeline_section_policy.dart';
import '../theme/app_theme.dart';
import '../text/app_strings.dart';
import '../dialogs/app_prompt_dialog.dart';

/// The N-comma input (UI-R17 #7): asks for an exposure count and applies
/// it to the selection (or the current block). Shared by the toolbar's N
/// button and the digit-5 shortcut.
Future<void> showTimelineCommaCountDialog(
  BuildContext context,
  EditorSessionManager session,
) async {
  final strings = AppText.strings;
  final entered = await showDialog<String>(
    context: context,
    builder: (context) => AppPromptDialog(
      windowKey: const ValueKey<String>('set-comma-n-dialog'),
      title: strings.setCommasTitle,
      titleIcon: Icons.timelapse_outlined,
      fieldLabel: strings.setCommasField,
      initialValue: '',
      confirmLabel: strings.commonApply,
      numeric: true,
      fieldKey: const ValueKey<String>('set-comma-n-field'),
      confirmKey: const ValueKey<String>('set-comma-n-apply'),
    ),
  );
  final comma = int.tryParse(entered ?? '');
  if (comma != null && comma >= 1) {
    session.setCommaForSelectionOrCurrent(comma);
  }
}

/// R26 #32: the custom frame-rate input — the presets cover the standard
/// rates, this covers everything else (a project axis, so one undo step).
Future<void> showTimelineFpsDialog(
  BuildContext context,
  EditorSessionManager session,
) async {
  final strings = AppText.strings;
  final entered = await showDialog<String>(
    context: context,
    builder: (context) => AppPromptDialog(
      windowKey: const ValueKey<String>('project-fps-dialog'),
      title: strings.projectFpsTitle,
      titleIcon: Icons.speed_outlined,
      fieldLabel: strings.projectFpsField,
      initialValue: '${session.projectFps}',
      confirmLabel: strings.commonApply,
      numeric: true,
      fieldKey: const ValueKey<String>('project-fps-field'),
      confirmKey: const ValueKey<String>('project-fps-apply'),
    ),
  );
  final fps = int.tryParse(entered ?? '');
  if (fps != null && fps >= 1) {
    session.setProjectFps(fps);
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
/// Builds its group ONCE and hands the same widget back until [rebuildKey]
/// moves.
///
/// The toolbar's layer and cut groups render nothing that changes: literal
/// labels, fixed icons, unconditional enablement, and flyout entries built
/// lazily at OPEN time. They rebuilt anyway, because the enablement-sensitive
/// FRAME group next to them makes the whole toolbar rebuild — measured at 24
/// layers, that dragged 144 widgets through every notify that landed a cel.
///
/// CONTRACT: the builder may only read values that cannot change while
/// [rebuildKey] holds still. Lazily-read state is free (a flyout opens with
/// fresh values through the stable session); anything RENDERED must be in the
/// key. Inherited widgets stay live either way — dependencies are tracked per
/// element, so a theme change still rebuilds the cached subtree.
class _StaticCommandGroup extends StatefulWidget {
  const _StaticCommandGroup({required this.builder, this.rebuildKey});

  final WidgetBuilder builder;
  final Object? rebuildKey;

  @override
  State<_StaticCommandGroup> createState() => _StaticCommandGroupState();
}

class _StaticCommandGroupState extends State<_StaticCommandGroup> {
  Widget? _cached;

  @override
  void didUpdateWidget(covariant _StaticCommandGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rebuildKey != widget.rebuildKey) {
      _cached = null;
    }
  }

  @override
  Widget build(BuildContext context) => _cached ??= StaticRaster(
    // Each group is its own ZONE. The bar used to be baked as one
    // surface, which meant a single button's state changing re-baked
    // every button on the row; now dirt from one group stops at that
    // group's own boundary. Siblings, never nesting — a bake inside a
    // bake is the one thing that freezes.
    debugLabel: 'command-group',
    child: widget.builder(context),
  );
}

class TimelineActionToolbar extends StatelessWidget {
  const TimelineActionToolbar({
    super.key,
    required this.session,
    required this.onAddLayer,
    required this.onRenameLayer,
    required this.onDeleteLayer,
    this.onEditInstance,
    this.resolveCanEditInstance,
    required this.onCreateInstance,
    this.currentRow,
    this.hiddenSections = const {},
    this.onToggleSection,
  });

  final EditorSessionManager session;

  /// The unified Add Layer entrance (same kind as the selection); the band
  /// above it adds kind-explicitly via [EditorSessionManager.addLayerOfKind].
  final VoidCallback onAddLayer;

  final VoidCallback onRenameLayer;
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

  /// A host's answer for its own standing row, asked BEFORE the kind switch and
  /// only able to say yes.
  ///
  /// It exists because the storyboard rail's standing row is separate state from
  /// the drawing target (user 2026-07-27), so a row that lives only on that rail
  /// — the transition row — is invisible to a gate reading `activeLayer`. Null
  /// keeps the kind switch as the whole answer, which is the timeline's case.
  final bool Function()? resolveCanEditInstance;

  /// Kind-dispatched creation: new frame / camera key / SE entry /
  /// instruction event.
  final VoidCallback onCreateInstance;

  /// Which rail is asking, for the ONE case the shift pair needs it: nothing
  /// selected, so the shove aims at the row this rail is standing on.
  ///
  /// The timeline leaves it null — its current row IS the active layer, which
  /// is the session's own fallback. The storyboard cannot, because its rail's
  /// standing row is separate state from the drawing target (user 2026-07-27),
  /// and that is the whole reason the pair used to be mounted a second time
  /// beside this bar instead of inside it.
  final TimelineRowAddress? currentRow;

  /// Sections hidden from the grids; the Layer menu's show/hide items and
  /// the rail's fold chevrons both flip this.
  final Set<TimelineSection> hiddenSections;
  final ValueChanged<TimelineSection>? onToggleSection;

  /// Whether the Add button applies to the active layer's cell: drawing
  /// kinds keep their old any-cell gate, SE needs an EMPTY cell (covered
  /// cells edit instead), camera/instruction key/upsert anywhere.
  bool get _canCreateInstance {
    final layer = session.activeLayer;
    if (layer == null || !session.hasActiveNonNegativeCell) {
      return false;
    }
    return switch (layer.kind) {
      LayerKind.se => session.canCreateDrawingAtCurrentFrame,
      _ => true,
    };
  }

  /// Whether Edit Instance has something to open: drawing kinds need a
  /// named-frame cell (the rename gate), SE either an entry to edit or an
  /// empty cell to create into, camera/instruction any cell.
  bool get _canEditInstance {
    // A host may answer for its OWN standing row first. The storyboard's rail
    // row is separate state from the drawing target (user 2026-07-27), so its
    // transition row cannot be seen through [EditorSessionManager.activeLayer]
    // at all — and the surface is the only thing that knows which row it means.
    if (resolveCanEditInstance?.call() case final hostAnswer? when hostAnswer) {
      return true;
    }
    final layer = session.activeLayer;
    if (layer == null) {
      return false;
    }
    // Standing on a LANE row, the instance is that lane's KEY — which the
    // owning layer's kind cannot answer.
    if (session.canNameLaneKeys) {
      return true;
    }
    return switch (layer.kind) {
      LayerKind.camera ||
      LayerKind.instruction => session.hasActiveNonNegativeCell,
      LayerKind.se =>
        session.selectedFrame != null || session.canCreateDrawingAtCurrentFrame,
      _ => session.canRenameFrameAtCurrentFrame,
    };
  }

  List<PanelFlyoutEntry> _addLayerEntries() {
    return [
      PanelFlyoutHeader(AppText.strings.tlAddLayerHeader),
      PanelFlyoutItem(
        keyValue: 'add-layer-kind-same',
        label: AppText.strings.tlSameAsSelected,
        icon: Icons.add,
        onSelected: onAddLayer,
      ),
      const PanelFlyoutDivider(),
      PanelFlyoutItem(
        keyValue: 'add-layer-kind-animation',
        label: AppText.strings.tlKindAnimation,
        onSelected: () => session.addLayerOfKind(LayerKind.animation),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-kind-storyboard',
        label: AppText.strings.tlKindStoryboard,
        // R9 #7: one storyboard row per cut — the entry greys out once the
        // cut has it, instead of accepting the tap and doing nothing.
        enabled: session.canAddLayerOfKind(LayerKind.storyboard),
        onSelected: () => session.addLayerOfKind(LayerKind.storyboard),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-kind-image',
        label: AppText.strings.tlKindImage,
        onSelected: () => session.addLayerOfKind(LayerKind.image),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-kind-text',
        label: AppText.strings.tlKindText,
        onSelected: () => session.addLayerOfKind(LayerKind.text),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-kind-se',
        label: AppText.strings.tlKindSe,
        onSelected: () => session.addLayerOfKind(LayerKind.se),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-kind-instruction',
        label: AppText.strings.tlKindInstruction,
        onSelected: () => session.addLayerOfKind(LayerKind.instruction),
      ),
      // R6b: the row that filters everything below it. It lands above the
      // active layer like every other kind, which is what puts the rows it
      // grades underneath it.
      PanelFlyoutItem(
        keyValue: 'add-layer-kind-adjustment',
        label: AppText.strings.tlKindAdjustment,
        icon: Icons.tune,
        onSelected: () => session.addLayerOfKind(LayerKind.adjustment),
      ),
      // R5 #14: a FOLDER is something you add, empty, and then fill by
      // dropping rows on it — the file-manager shape, replacing "group the
      // active layer into a folder".
      PanelFlyoutItem(
        keyValue: 'add-layer-kind-folder',
        label: AppText.strings.tlKindFolder,
        icon: Icons.create_new_folder_outlined,
        onSelected: () => session.addLayerOfKind(LayerKind.folder),
      ),
      // Attach layers (W5, UI-R20 #8 / UI-R21 #3): the same entrance the
      // Layer menu has — own cels riding the base's FX. FREE authors its
      // own timeline; SYNCED mirrors the base's exposures (ghost rows).
      const PanelFlyoutDivider(),
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-free-above',
        label: AppText.strings.tlAttachFreeAbove,
        icon: Icons.north_east,
        enabled: session.canAddAttachedLayerToActive,
        onSelected: () => session.addAttachedLayer(
          AttachedPlacement.above,
          mode: AttachedMode.free,
        ),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-free-below',
        label: AppText.strings.tlAttachFreeBelow,
        icon: Icons.south_east,
        enabled: session.canAddAttachedLayerToActive,
        onSelected: () => session.addAttachedLayer(
          AttachedPlacement.below,
          mode: AttachedMode.free,
        ),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-above',
        label: AppText.strings.tlAttachSyncedAbove,
        icon: Icons.north_east,
        enabled: session.canAddAttachedLayerToActive,
        onSelected: () => session.addAttachedLayer(AttachedPlacement.above),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-below',
        label: AppText.strings.tlAttachSyncedBelow,
        icon: Icons.south_east,
        enabled: session.canAddAttachedLayerToActive,
        onSelected: () => session.addAttachedLayer(AttachedPlacement.below),
      ),
    ];
  }

  /// The EFFECTS button's list (R5 #6): add one of each kind, and take away
  /// the ones this row already carries.
  ///
  /// Adding one changes nothing until a value moves — the work happens in
  /// the row's FX lanes, which is why this is a menu and not a control on
  /// an already crowded row.
  List<PanelFlyoutEntry> _effectEntries() {
    final effects = session.activeLayer?.effects ?? const <LayerEffect>[];
    return [
      PanelFlyoutHeader(AppText.strings.tlEffects),
      for (final kind in EffectKind.values)
        PanelFlyoutItem(
          keyValue: 'add-effect-${kind.jsonValue}',
          label: AppText.strings.tlAddEffectTemplate.replaceAll(
            '{name}',
            kind.labelFor(AppText.language),
          ),
          icon: Icons.auto_fix_high_outlined,
          enabled: session.canAddEffectToActiveLayer,
          onSelected: () => session.addEffectToActiveLayer(kind),
        ),
      if (effects.isNotEmpty) const PanelFlyoutDivider(),
      for (final effect in effects)
        PanelFlyoutItem(
          keyValue: 'remove-effect-${effect.id.value}',
          label: AppText.strings.tlRemoveEffectTemplate.replaceAll(
            '{name}',
            effect.kind.labelFor(AppText.language),
          ),
          icon: Icons.remove_circle_outline,
          danger: true,
          onSelected: () => session.removeEffectFromActiveLayer(effect.id),
        ),
    ];
  }

  List<PanelFlyoutEntry> _layerEntries(BuildContext context) {
    final active = session.activeLayer;
    // A row the cut may only READ takes no verb from here — the transition
    // row is authored on the global axis ("컷 타임라인은 보여주기만"), so
    // selecting it must not light up rename/duplicate/delete.
    final editable = active != null && !layerKindIsReadOnlyInCut(active.kind);
    return [
      PanelFlyoutItem(
        keyValue: 'rename-layer-button',
        label: AppText.strings.tlRenameLayer,
        icon: Icons.drive_file_rename_outline,
        enabled: editable,
        onSelected: onRenameLayer,
      ),
      PanelFlyoutItem(
        keyValue: 'duplicate-layer-button',
        label: AppText.strings.tlDuplicateLayer,
        icon: Icons.copy_outlined,
        enabled: editable,
        onSelected: session.duplicateActiveLayer,
      ),
      PanelFlyoutItem(
        keyValue: 'copy-layer-button',
        label: AppText.strings.tlCopyLayer,
        icon: Icons.content_copy,
        enabled: active != null,
        onSelected: session.copyActiveLayer,
      ),
      PanelFlyoutItem(
        keyValue: 'paste-layer-button',
        label: session.layerClipboardName == null
            ? 'Paste layer'
            : 'Paste layer (${session.layerClipboardName})',
        icon: Icons.content_paste,
        enabled: session.hasLayerClipboard,
        onSelected: session.pasteLayerFromClipboard,
      ),
      // R5 #5: the row-order STEP verbs are gone, session methods and all
      // (user: "단축키로도 남기지마 일단"). The drag is the whole answer
      // now; the one thing the step could reach that a drop cannot — the
      // inside of an EMPTY folder — is the drop mode this round adds
      // instead, where dropping ON a folder row puts the layer in it.
      // 분리 (P3). MAKING an attach is the drag's alone: dropping a row
      // strictly inside a group mounts it, and R5 #15 gave the one case a gap
      // cannot reach — the first rider on a base — its own door, dropping ON
      // the row. The two "위/아래 레이어에 장착" entries that used to stand
      // here were that door before it existed, so R5 deleted them rather than
      // keep a second way to say the same thing.
      //
      // The RELEASE stays: it must not be a one-way door (user 2026-08-07).
      PanelFlyoutItem(
        keyValue: 'timeline-detach-layer-button',
        label: AppText.strings.tlDetachLayer,
        icon: Icons.link_off,
        enabled: session.canDetachActiveLayer,
        onSelected: session.detachActiveLayer,
      ),
      // R5 #5: IMPORT AUDIO left. The media browser is the one entrance —
      // it links an audio asset onto a frame block, which is the shape the
      // work actually has; this entry offered a second, thinner door.
      const PanelFlyoutDivider(),
      // R5 #6: the EFFECT chain moved out to a button of its own — the
      // effect list is going to be what that button shows, so it stopped
      // being a tail on the layer menu.
      //
      // R5 #14: and the two FOLDER-making commands went with it. "Group
      // into folder" wrapped the active layer; a folder is made EMPTY from
      // the Add Layer menu now and filled by dropping rows on it, which is
      // how every other app this user works in behaves. "New attach folder"
      // goes for the same reason — the drag makes those too.
      PanelFlyoutItem(
        keyValue: 'timeline-rasterize-layer-button',
        label: AppText.strings.menuLabel('layer-rasterize', 'Rasterize layer'),
        icon: Icons.texture_outlined,
        enabled: session.canRasterizeActiveLayer,
        onSelected: session.rasterizeActiveLayer,
      ),
      // 'SE name tag…' opened a window. R5 #7 put every control it held on
      // the SE row's Name Tag lane group, so the entry would only lead
      // somewhere that changes the same thing a second way.
      PanelFlyoutItem(
        keyValue: 'timeline-link-duplicate-button',
        label: AppText.strings.tlLinkDuplicateLayer,
        icon: Icons.link,
        enabled: session.canLinkDuplicateActiveLayer,
        onSelected: session.linkDuplicateActiveLayer,
      ),
      PanelFlyoutItem(
        keyValue: 'timeline-unlink-layer-button',
        label: AppText.strings.tlUnlinkLayer,
        icon: Icons.link_off,
        enabled: session.canUnlinkActiveLayer,
        onSelected: session.unlinkActiveLayer,
      ),
      const PanelFlyoutDivider(),
      PanelFlyoutItem(
        keyValue: 'toggle-storyboard-layer-button',
        label: AppText.strings.tlStoryboardLayer,
        icon: Icons.auto_stories_outlined,
        enabled: session.canToggleTargetLayerKind,
        checked: active?.kind == LayerKind.storyboard ? true : null,
        onSelected: session.toggleTargetLayerKind,
      ),
      // R5 #5: the SE and CAMERA section switches left. The legend's own
      // sections cell has shown and hidden both since UI-R7, so this pair
      // was a second door to one setting — and the one further from where
      // the rows are.
      const PanelFlyoutDivider(),
      PanelFlyoutItem(
        keyValue: 'delete-layer-button',
        label: AppText.strings.tlDeleteLayer,
        icon: Icons.delete_outline,
        danger: true,
        enabled: session.canDeleteActiveLayer,
        onSelected: onDeleteLayer,
      ),
    ];
  }

  // ⛔The two PROJECT-axis dropdowns (fps, audio sample rate) LEFT this bar
  // (유저 확정, 2026-08-10). They print project values and nothing about the
  // playhead, they are touched about once per project, and they were sitting
  // in the middle of the frame verbs — so they are entries of the settings
  // pill now ([ProjectSettingsPill]), which rides the 문턱 with the transport.

  List<PanelFlyoutEntry> _frameEntries() {
    return [
      PanelFlyoutItem(
        keyValue: 'rename-frame-button',
        label: AppText.strings.tlEditInstance,
        icon: Icons.edit_outlined,
        // A host with no dispatch to offer greys the entry out — the same
        // answer the enablement gate gives, from a different cause.
        enabled: onEditInstance != null && _canEditInstance,
        onSelected: onEditInstance,
      ),
      PanelFlyoutItem(
        keyValue: 'copy-frame-button',
        label: AppText.strings.tlCopyFrame,
        icon: Icons.content_copy,
        enabled: session.canCopyFrameAtCurrentFrame,
        onSelected: session.copyFrameAtCurrentFrame,
      ),
      PanelFlyoutItem(
        keyValue: 'paste-linked-frame-button',
        label: AppText.strings.tlPasteLinkedFrame,
        icon: Icons.link,
        enabled: session.canPasteLinkedFrameAtCurrentFrame,
        onSelected: session.pasteLinkedFrameAtCurrentFrame,
      ),
      const PanelFlyoutDivider(),
      PanelFlyoutItem(
        keyValue: 'delete-cell-button',
        label: AppText.strings.tlDeleteCell,
        icon: Icons.delete_outline,
        danger: true,
        enabled: session.canDeleteCellAtCurrentFrame,
        onSelected: session.deleteCellAtCurrentFrame,
      ),
    ];
  }

  /// R26 #42: the app's standard icon button (the canvas bottom bar's
  /// style, promoted) — this toolbar used to size its own.
  Widget _iconButton({
    required ValueKey<String> key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool accent = false,
  }) {
    return AppIconButton(
      keyValue: key.value,
      tooltip: tooltip,
      onPressed: onPressed,
      // 유저 확정: accent는 ＋ 글리프에만, ＋가 있는 모든 곳에 — the law
      // itself is [AppColors.addGlyph], since 「모든 곳」 has to be one
      // decision rather than the same decision made at each button.
      icon: Icon(icon, color: accent ? AppColors.addGlyph(enabled: onPressed != null) : null),
    );
  }

  Widget _commaButton({
    required ValueKey<String> key,
    required String label,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        key: key,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          // Sized to sit INSIDE a pill (28 outer, 2px of breath each side)
          // rather than to stand on its own in the bar.
          minimumSize: const Size(21, 24),
          maximumSize: const Size(24, 24),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12.5)),
      ),
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
    rebuildKey: Object.hash(
      hiddenSections.fold<int>(
        0,
        (mask, section) => mask | (1 << section.index),
      ),
      AppText.settings.value.programLanguage,
      session.canDeleteActiveLayer,
    ),
    builder: (context) => CommandPill(
      key: const ValueKey<String>('timeline-toolbar-layer-group'),
      head: PillNameCell(
        keyValue: 'timeline-layer-menu-button',
        label: AppText.strings.tlLayer,
        tooltip: AppText.strings.tlLayerCommands,
        entriesBuilder: () => _layerEntries(context),
      ),
      children: [
        const PillDivider(),
        StrapIconButton(
          buttonKey: 'timeline-toolbar-add-layer-button',
          menuKey: 'timeline-toolbar-add-layer-menu',
          icon: Icons.add,
          tooltip: AppText.strings.tlAddLayerHeader,
          accent: true,
          onPressed: onAddLayer,
          entriesBuilder: _addLayerEntries,
        ),
        // 유저 확정: 자주 쓸 만한 것을 알약 밖으로, 우선 딜리트 레이어만.
        // The menu keeps its own entry — that is the same shape `＋` already
        // has (the Add menu's "same as selected"), not a second door.
        AppIconButton(
          keyValue: 'timeline-delete-layer-button',
          tooltip: AppText.strings.tlDeleteLayer,
          icon: const Icon(Icons.delete_outline),
          onPressed: session.canDeleteActiveLayer ? onDeleteLayer : null,
        ),
      ],
    ),
  );

  /// The FRAME pill — the verbs a rough pass wears out, none of them folded.
  Widget _framePill() => CommandPill(
    key: const ValueKey<String>('timeline-toolbar-frame-group'),
    head: PillNameCell(
      keyValue: 'timeline-frame-menu-button',
      label: AppText.strings.tlFrame,
      tooltip: AppText.strings.tlFrameCommands,
      entriesBuilder: _frameEntries,
    ),
    children: [
      const PillDivider(),
      // Cached on the three predicates THESE buttons read, for the reason
      // spelled out at the comma group below.
      _StaticCommandGroup(
        rebuildKey: (
          _canCreateInstance,
          session.canCutExposureAtCurrentFrame,
          session.canToggleMarkAtCurrentFrame,
          session.languageSettings.value,
        ),
        builder: (context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ⛔NO band on this `＋`: it makes ONE thing, in the place you
            // are standing. A band means there is something to choose, so
            // its absence here is the signal rather than an omission.
            _iconButton(
              key: const ValueKey<String>('new-frame-button'),
              tooltip: AppText.strings.tlAdd,
              icon: Icons.add,
              accent: true,
              onPressed: _canCreateInstance ? onCreateInstance : null,
            ),
            _iconButton(
              key: const ValueKey<String>('blank-exposure-button'),
              tooltip: AppText.strings.tlBlankX,
              icon: Icons.close,
              onPressed: session.canCutExposureAtCurrentFrame
                  ? session.cutExposureAtCurrentFrame
                  : null,
            ),
            _iconButton(
              key: const ValueKey<String>('toggle-mark-button'),
              tooltip: AppText.strings.tlMark,
              icon: Icons.circle,
              onPressed: session.canToggleMarkAtCurrentFrame
                  ? session.toggleMarkAtCurrentFrame
                  : null,
            ),
          ],
        ),
      ),
      const PillDivider(),
      // Design D: the rigid shove a drag used to do, aimed. Scope = the live
      // selection's rows, or the current row at the current cell. ONE pair
      // for both axes, and now ONE pair for both panels: it is a frame-axis
      // shove, so it belongs to the FRAME noun, and [currentRow] is how the
      // asking rail names itself.
      TimelineShiftButtons(session: session, currentRow: currentRow),
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
        rebuildKey: (
          session.canSetCommaForSelectionOrCurrent,
          session.languageSettings.value,
        ),
        builder: (context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var comma = 1; comma <= 4; comma += 1)
              _commaButton(
                key: ValueKey<String>('set-comma-$comma-button'),
                label: '$comma',
                tooltip: AppText.strings.tlSetCommaTemplate.replaceAll(
                  '{n}',
                  '$comma',
                ),
                onPressed: session.canSetCommaForSelectionOrCurrent
                    ? () => session.setCommaForSelectionOrCurrent(comma)
                    : null,
              ),
            Builder(
              builder: (context) => _commaButton(
                key: const ValueKey<String>('set-comma-n-button'),
                label: 'N',
                tooltip: AppText.strings.tlSetCommasN,
                onPressed: session.canSetCommaForSelectionOrCurrent
                    ? () => showTimelineCommaCountDialog(context, session)
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
    rebuildKey: AppText.settings.value.programLanguage,
    builder: (context) => CommandPill(
      head: PillNameCell(
        keyValue: 'timeline-effects-button',
        icon: Icons.auto_fix_high_outlined,
        tooltip: AppText.strings.tlEffects,
        entriesBuilder: _effectEntries,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // ⛔The outer border and fill are gone. Every noun wears its own pill
    // border now, so a box around all four of them was a frame around
    // frames — and the command bar it sits in already has an edge.
    //
    // 🆕The scroller is BARRED again (유저, 2026-08-10: 「버튼 사라지기
    // 시작하면 생기는 스크롤바」). R4 retired the bar here when this was a
    // 30px row of loose buttons, where a lane laid across it took the bottom
    // third of every target; the pills are 28px inside a 36px row now, and
    // the app's bar exists only WHILE it overflows and costs no layout — so
    // the case that retired it no longer holds. See [UnbarredScrollable].
    return Padding(
      key: const ValueKey<String>('timeline-action-toolbar'),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      // ⛔The bake is NOT here. It used to wrap the whole bar, which meant
      // one button's state changing re-baked every button on the row. Each
      // [_StaticCommandGroup] bakes ITSELF now, so the groups are ZONES:
      // siblings, each with its own dirty bit, each re-baking only for its
      // own reason. The wrapper had to come off rather than stay as an outer
      // layer, because a bake inside a bake is the one thing that freezes.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 컷 · 레이어 · 프레임 · FX — the four nouns, in the order the
            // data nests (유저 확정). Keyed on the language for the same
            // reason as the others: every name cell prints a word.
            _StaticCommandGroup(
              rebuildKey: AppText.settings.value.programLanguage,
              builder: (context) => CutCommandGroup(session: session),
            ),
            const SizedBox(width: 6),
            _layerPill(),
            const SizedBox(width: 6),
            _framePill(),
            const SizedBox(width: 6),
            _fxPill(),
          ],
        ),
      ),
    );
  }
}
