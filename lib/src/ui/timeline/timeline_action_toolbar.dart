import 'dart:async' show unawaited;
import 'package:flutter/material.dart';

import '../theme/app_scroll_behavior.dart';

import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_kind.dart';
import '../../models/project_frame_rate.dart';
import '../cut_command_group.dart';
import '../dialogs/fps_audio_choice_dialog.dart';
import '../editor_session_manager.dart';
import '../widgets/app_icon_button.dart';
import 'timeline_shift_buttons.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/split_icon_button.dart';
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
/// Layout: [split add-layer][Layer ▾] │ [Add instance][Blank][Mark][Frame ▾]
/// │ [cut group]. Menu items reuse the retired toolbar buttons' key strings
/// so tests only gain a menu-open tap. The exposure ± buttons are GONE —
/// block edge grips replaced them outright (session APIs kept for grips).
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
    required this.onEditInstance,
    required this.onCreateInstance,
    this.hiddenSections = const {},
    this.onToggleSection,
  });

  final EditorSessionManager session;

  /// The unified Add Layer entrance (same kind as the selection); the
  /// split ▾ adds kind-explicitly via [EditorSessionManager.addLayerOfKind].
  final VoidCallback onAddLayer;

  final VoidCallback onRenameLayer;
  final VoidCallback onDeleteLayer;

  /// Opens the unified instance-edit dialog for the active layer at the
  /// playhead (kind-dispatched by the host).
  final VoidCallback onEditInstance;

  /// Kind-dispatched creation: new frame / camera key / SE entry /
  /// instruction event.
  final VoidCallback onCreateInstance;

  /// Sections hidden from the grids; the Layer ▾ show/hide items and the
  /// rail's fold chevrons both flip this.
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
    final layer = session.activeLayer;
    if (layer == null) {
      return false;
    }
    // Standing on a LANE row, the instance is that lane's KEY — which the
    // owning layer's kind cannot answer.
    if (session.currentLaneKeyAddress != null) {
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

  /// R26 #30-1: whether the ACTIVE layer takes a blend mode (drawing
  /// section rows — attach rows included, their pixels blend on their
  /// own).
  /// R26 #32: the frame-rate presets. RT made the project rate an exact
  /// rational, so the NTSC pulldown rates are here alongside the whole
  /// ones — 23.976 is stored and played as 24000/1001, never as a
  /// rounded decimal.
  static const List<ProjectFrameRate> fpsPresets = ProjectFrameRate.presets;

  List<PanelFlyoutEntry> _fpsEntries(BuildContext context) {
    final current = session.projectFrameRate;
    return [
      for (final rate in fpsPresets)
        PanelFlyoutItem(
          // Integer rates keep their original key (`timeline-fps-24`);
          // the pulldown rates key off the fraction, since `23.976` in a
          // key string would be the same rounding we just removed.
          keyValue: rate.isInteger
              ? 'timeline-fps-${rate.numerator}'
              : 'timeline-fps-${rate.numerator}-${rate.denominator}',
          label: rate.label,
          checked: rate == current,
          onSelected: () => unawaited(_selectFrameRate(context, rate)),
        ),
      const PanelFlyoutDivider(),
      PanelFlyoutItem(
        keyValue: 'timeline-fps-custom',
        label: AppText.strings.tlCustom,
        icon: Icons.edit_outlined,
        onSelected: () => unawaited(showTimelineFpsDialog(context, session)),
      ),
    ];
  }

  /// EXPORT-AUDIO ④: a pulldown-pair change (23.976↔24 — 0.1% of real
  /// speed) asks what happens to SOUND, because audio exists in real
  /// seconds and cannot stay both frame-exact and time-exact. Any other
  /// change, or a project with no sound, just changes the rate. (The
  /// custom-rate dialog keeps the plain path — pulldown pairs live in
  /// the presets.)
  Future<void> _selectFrameRate(
    BuildContext context,
    ProjectFrameRate rate,
  ) async {
    final pull = audioPullBetween(session.projectFrameRate, rate);
    if (pull == null || !session.projectHasAnyAudio) {
      session.setProjectFrameRate(rate);
      return;
    }
    final choice = await showFpsAudioChoiceDialog(
      context,
      from: session.projectFrameRate,
      to: rate,
      strings: session.uiStrings,
    );
    switch (choice) {
      case null:
        return; // cancelled — the rate stays too
      case FpsAudioChoice.keep:
        session.setProjectFrameRate(rate);
      case FpsAudioChoice.pull:
        session.setProjectFrameRateWithAudioPull(rate);
    }
  }

  /// EXPORT-AUDIO ③: the audio-rate presets — 48k is the film standard,
  /// 44.1k the music one, 96k for the rare high-rate delivery.
  static const List<int> audioSampleRatePresets = [44100, 48000, 96000];

  /// '48kHz' / '44.1kHz' — kilohertz reads at a glance; the raw hertz
  /// number is a spec sheet.
  static String audioSampleRateLabel(int rate) => rate % 1000 == 0
      ? '${rate ~/ 1000}kHz'
      : '${(rate / 1000).toStringAsFixed(1)}kHz';

  List<PanelFlyoutEntry> _audioSampleRateEntries() {
    final current = session.projectAudioSampleRate;
    return [
      for (final rate in audioSampleRatePresets)
        PanelFlyoutItem(
          keyValue: 'timeline-samplerate-$rate',
          label: audioSampleRateLabel(rate),
          checked: rate == current,
          onSelected: () => session.setProjectAudioSampleRate(rate),
        ),
    ];
  }

  List<PanelFlyoutEntry> _frameEntries() {
    return [
      PanelFlyoutItem(
        keyValue: 'rename-frame-button',
        label: AppText.strings.tlEditInstance,
        icon: Icons.edit_outlined,
        enabled: _canEditInstance,
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
  }) {
    return AppIconButton(
      keyValue: key.value,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
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
          minimumSize: const Size(26, 30),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Widget _groupDivider(BuildContext context) {
    return SizedBox(
      height: 22,
      child: VerticalDivider(
        width: 14,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey<String>('timeline-action-toolbar'),
      decoration: ShapeDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: AppShapes.container(
          AppShapes.windowRadius,
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: UnbarredScrollable(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // ⛔The bake is NOT here. It used to wrap the whole bar,
            // which meant one button's state changing re-baked every
            // button on the row. Each [_StaticCommandGroup] bakes ITSELF
            // now, so the groups are ZONES: siblings, each with its own
            // dirty bit, each re-baking only for its own reason. The
            // wrapper had to come off rather than stay as an outer
            // layer, because a bake inside a bake is the one thing that
            // freezes.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Static (see [_StaticCommandGroup]): both buttons build their
                // entries at open time. The key is the hidden-section mask
                // because the Layer flyout's show/hide checkmarks read
                // `hiddenSections` from THIS closure — and the PROGRAM
                // LANGUAGE, because the labels are no longer fixed: a cached
                // group would keep printing the old language after a switch.
                _StaticCommandGroup(
                  rebuildKey: Object.hash(
                    hiddenSections.fold<int>(
                      0,
                      (mask, section) => mask | (1 << section.index),
                    ),
                    AppText.settings.value.programLanguage,
                  ),
                  builder: (context) => Row(
                    key: const ValueKey<String>('timeline-toolbar-layer-group'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SplitIconButton(
                        buttonKey: 'timeline-toolbar-add-layer-button',
                        menuKey: 'timeline-toolbar-add-layer-menu',
                        icon: Icons.add,
                        tooltip: AppText.strings.tlAddLayerHeader,
                        accent: true,
                        onPressed: onAddLayer,
                        entriesBuilder: _addLayerEntries,
                      ),
                      const SizedBox(width: 4),
                      PanelFlyoutButton(
                        key: const ValueKey<String>(
                          'timeline-layer-menu-button',
                        ),
                        label: AppText.strings.tlLayer,
                        tooltip: AppText.strings.tlLayerCommands,
                        entriesBuilder: () => _layerEntries(context),
                      ),
                      const SizedBox(width: 4),
                      // R5 #6: EFFECTS get a button of their own. The
                      // chain used to hang off the tail of the Layer
                      // menu, and the effect LIST is what this button is
                      // going to grow into — so it stopped being a tail.
                      //
                      // Safe inside the cached group for the R13-2
                      // reason: the builder closes over the stable
                      // session and reads the active layer's chain when
                      // the flyout OPENS, so a reused button widget
                      // cannot show a stale list.
                      PanelFlyoutButton(
                        key: const ValueKey<String>('timeline-effects-button'),
                        label: AppText.strings.tlEffects,
                        tooltip: AppText.strings.tlEffects,
                        entriesBuilder: _effectEntries,
                      ),
                      // R27 #6: the layer BLEND dropdown left this toolbar for
                      // the layer LABEL's rightmost column (user placement) —
                      // per-row reading, PS/CSP style. See LayerBlendModeChip.
                    ],
                  ),
                ),
                _groupDivider(context),
                Row(
                  key: const ValueKey<String>('timeline-toolbar-frame-group'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Cached on the three predicates THESE buttons read, for
                    // the reason spelled out at the comma group below.
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
                          _iconButton(
                            key: const ValueKey<String>('new-frame-button'),
                            tooltip: AppText.strings.tlAdd,
                            icon: Icons.add_box_outlined,
                            onPressed: _canCreateInstance
                                ? onCreateInstance
                                : null,
                          ),
                          _iconButton(
                            key: const ValueKey<String>(
                              'blank-exposure-button',
                            ),
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
                    // Design D: the rigid shove a drag used to do, aimed.
                    // Scope = the live selection's rows, or the current row
                    // at the current cell. ONE pair for both axes — this
                    // rail's rows are all layer rows, so it asks as itself.
                    TimelineShiftButtons(session: session),
                    const SizedBox(width: 4),
                    // Comma set (UI-R17 #7, TVP-style): the current block —
                    // or the whole selection, packed — takes the pressed
                    // exposure outright; N asks for a count. Shortcuts 1-5.
                    //
                    // Cached on THEIR OWN predicate. Five buttons that all
                    // read one boolean sat in the same rebuild as the icon
                    // buttons beside them, so a flip step that changed only
                    // this one rebuilt every button in the row — and one
                    // that changed only an icon button's rebuilt all five of
                    // these. Measured: crossing "no cel ↔ cel" changed 5 of
                    // the toolbar's 10 buttons and rebuilt all 10.
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
                              tooltip: AppText.strings.tlSetCommaTemplate
                                  .replaceAll('{n}', '$comma'),
                              onPressed:
                                  session.canSetCommaForSelectionOrCurrent
                                  ? () => session.setCommaForSelectionOrCurrent(
                                      comma,
                                    )
                                  : null,
                            ),
                          Builder(
                            builder: (context) => _commaButton(
                              key: const ValueKey<String>('set-comma-n-button'),
                              label: 'N',
                              tooltip: AppText.strings.tlSetCommasN,
                              onPressed:
                                  session.canSetCommaForSelectionOrCurrent
                                  ? () => showTimelineCommaCountDialog(
                                      context,
                                      session,
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    PanelFlyoutButton(
                      key: const ValueKey<String>('timeline-frame-menu-button'),
                      label: AppText.strings.tlFrame,
                      tooltip: AppText.strings.tlFrameCommands,
                      entriesBuilder: _frameEntries,
                    ),
                    const SizedBox(width: 4),
                    // The two PROJECT-axis dropdowns print project values and
                    // nothing about the playhead, so they are cached on those
                    // — a flip step must not rebuild them at all.
                    _StaticCommandGroup(
                      rebuildKey: (
                        session.projectFrameRate,
                        session.projectAudioSampleRate,
                        session.languageSettings.value,
                      ),
                      builder: (context) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // R26 #32: the PROJECT frame rate — the axis
                          // everything timed reads. One rate per project,
                          // never per cut.
                          PanelFlyoutButton(
                            key: const ValueKey<String>(
                              'timeline-fps-menu-button',
                            ),
                            label: session.projectFrameRate.label,
                            tooltip: AppText.strings.projectFpsTitle,
                            entriesBuilder: () => _fpsEntries(context),
                          ),
                          const SizedBox(width: 4),
                          // EXPORT-AUDIO ③: the PROJECT audio rate — what
                          // every sound conforms to and the mixer runs at.
                          PanelFlyoutButton(
                            key: const ValueKey<String>(
                              'timeline-samplerate-menu-button',
                            ),
                            label: audioSampleRateLabel(
                              session.projectAudioSampleRate,
                            ),
                            tooltip: AppText.strings.tlProjectAudioRate,
                            entriesBuilder: _audioSampleRateEntries,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                _groupDivider(context),
                // Static too: a New-cut split button and a Cut flyout, both
                // lazily-built. Keyed on the language for the same reason as
                // the layer group — the labels move when the setting does.
                _StaticCommandGroup(
                  rebuildKey: AppText.settings.value.programLanguage,
                  builder: (context) => CutCommandGroup(session: session),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
