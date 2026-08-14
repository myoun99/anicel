import 'package:flutter/material.dart';

import '../../models/attached_mode.dart';
import '../../models/attached_placement.dart';
import '../../models/layer_effect.dart';
import '../../models/delete_subject.dart';
import '../../models/edit_instance_subject.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_row_address.dart';
import '../cut_command_group.dart';
import '../editor_session_manager.dart';
import '../widgets/app_icon_button.dart';
import 'timeline_shift_buttons.dart';
import '../widgets/command_pill.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/static_raster.dart';
import 'layer_label_controls.dart' show layerKindIcon;
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
    this.onDeleteRowSelection,
    required this.onDeleteLayer,
    this.onEditInstance,
    this.resolveCanEditInstance,
    required this.onCreateInstance,
    this.currentRow,
    this.hiddenSections = const {},
    this.onToggleSection,
  });

  final EditorSessionManager session;

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
    // ⑬ 유저 2026-08-12: 「스토리보드패널 트랜지션레이어 왜 프레임 추가버튼
    // 불가능하지?」
    //
    // 🚨The host answers FIRST, for the same reason Edit Instance does: the
    // storyboard rail's standing row is separate state from the cut's drawing
    // target (user 2026-07-27), so a row that lives only on that rail — the
    // transition row — is invisible to anything reading `activeLayer`. #925
    // taught Edit Instance to ask; `＋` was left behind and went on greying
    // out on the one row the user was standing on.
    if (resolveCanEditInstance?.call() case true) {
      return true;
    }
    final layer = session.activeLayer;
    if (layer == null || !session.hasActiveNonNegativeCell) {
      return false;
    }
    return switch (layer.kind) {
      LayerKind.se => session.canCreateDrawingAtCurrentFrame,
      _ => true,
    };
  }

  /// The one thing about Edit Instance a SESSION cannot answer: the
  /// storyboard's rail row is separate state from the drawing target (user
  /// 2026-07-27), so its transition row is invisible through
  /// [EditorSessionManager.activeLayer] and only the surface knows it.
  ///
  /// 🚨T25 — everything else moved to
  /// [EditorSessionManager.canEditCellInstanceAtCurrentFrame]. The kind
  /// switch used to live here, next to the button, while the DISPATCH read
  /// [EditorSessionManager.editInstanceSubject]: enablement and action came
  /// from two predicates that disagreed for camera, direction and SE cells,
  /// so the button lit up and the press did nothing.
  bool get _hostCanEditInstance => resolveCanEditInstance?.call() ?? false;

  /// The key suffix each kind's Add entry has always used — spelled out
  /// rather than derived from `kind.name`, so a rename of the enum cannot
  /// silently move a widget key the tests aim at.
  static String _addLayerKeySuffix(LayerKind kind) => switch (kind) {
    LayerKind.animation => 'animation',
    LayerKind.storyboard => 'storyboard',
    LayerKind.image => 'image',
    LayerKind.text => 'text',
    LayerKind.se => 'se',
    LayerKind.instruction => 'instruction',
    LayerKind.adjustment => 'adjustment',
    LayerKind.folder => 'folder',
    LayerKind.camera => 'camera',
    LayerKind.transition => 'transition',
  };

  static String _addLayerLabel(LayerKind kind) => switch (kind) {
    LayerKind.animation => AppText.strings.tlKindAnimation,
    LayerKind.storyboard => AppText.strings.tlKindStoryboard,
    LayerKind.image => AppText.strings.tlKindImage,
    LayerKind.text => AppText.strings.tlKindText,
    LayerKind.se => AppText.strings.tlKindSe,
    LayerKind.instruction => AppText.strings.tlKindInstruction,
    LayerKind.adjustment => AppText.strings.tlKindAdjustment,
    LayerKind.folder => AppText.strings.tlKindFolder,
    // Neither is offered by the Add menu — a cut owns exactly one camera and
    // the transition row belongs to the track.
    LayerKind.camera || LayerKind.transition => '',
  };

  List<PanelFlyoutEntry> _addLayerEntries() {
    return [
      PanelFlyoutHeader(AppText.strings.tlAddLayerHeader),
      // ⛔NO 「현재 선택한 레이어와 같은 종류」 entry (유저 2026-08-12:
      // 「레이어 +에 있는 현재 선택한 레이어로 생성 삭제. 필요없음. 묻지마.」).
      // The `＋` itself makes an animation layer now, so an entry meaning
      // "whatever is selected" answered a question nothing asks.
      //
      // ★EVERY entry wears its kind's own icon, and they come from
      // [layerKindIcon] rather than being chosen here (유저: 「레이어 생성,
      // 아이콘이 있고없고 그러는데, 다 아이콘 앞에 붙임」). Three of these
      // used to carry a hand-picked glyph and the rest carried none — which
      // is how the list came to disagree with the rail it creates rows for.
      // One table, so the menu and the row can never show different pictures
      // of the same noun.
      for (final kind in const [
        LayerKind.animation,
        LayerKind.storyboard,
        LayerKind.image,
        LayerKind.text,
        LayerKind.se,
        LayerKind.instruction,
        // R6b: the row that filters everything below it. It lands above the
        // active layer like every other kind, which is what puts the rows it
        // grades underneath it.
        LayerKind.adjustment,
        // R5 #14: a FOLDER is something you add, empty, and then fill by
        // dropping rows on it — the file-manager shape, replacing "group the
        // active layer into a folder".
        LayerKind.folder,
      ])
        PanelFlyoutItem(
          keyValue: 'add-layer-kind-${_addLayerKeySuffix(kind)}',
          label: _addLayerLabel(kind),
          icon: layerKindIcon(kind),
          // R9 #7: one storyboard row per cut — the entry greys out once the
          // cut has it, instead of accepting the tap and doing nothing.
          enabled: session.canAddLayerOfKind(kind),
          onSelected: () => session.addLayerOfKind(kind),
        ),
      // Attach layers (W5, UI-R20 #8 / UI-R21 #3): the same entrance the
      // Layer menu has — own cels riding the base's FX. FREE authors its
      // own timeline; SYNCED mirrors the base's exposures (ghost rows).
      const PanelFlyoutDivider(),
      // ① (유저 확정): the SAME glyph the rail draws on an attached row
      // ([LayerAttachArrowCell]), flipped the same way for the above
      // placement. These used to be `north_east`/`south_east` — a second
      // vocabulary for attachment, so the menu that MAKES the row and the
      // row it makes did not look like the same idea.
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-free-above',
        label: AppText.strings.tlAttachFreeAbove,
        icon: Icons.subdirectory_arrow_right,
        iconFlipY: true,
        enabled: session.canAddAttachedLayerToActive,
        onSelected: () => session.addAttachedLayer(
          AttachedPlacement.above,
          mode: AttachedMode.free,
        ),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-free-below',
        label: AppText.strings.tlAttachFreeBelow,
        icon: Icons.subdirectory_arrow_right,
        enabled: session.canAddAttachedLayerToActive,
        onSelected: () => session.addAttachedLayer(
          AttachedPlacement.below,
          mode: AttachedMode.free,
        ),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-above',
        label: AppText.strings.tlAttachSyncedAbove,
        icon: Icons.subdirectory_arrow_right,
        iconFlipY: true,
        enabled: session.canAddAttachedLayerToActive,
        onSelected: () => session.addAttachedLayer(AttachedPlacement.above),
      ),
      PanelFlyoutItem(
        keyValue: 'add-layer-attach-below',
        label: AppText.strings.tlAttachSyncedBelow,
        icon: Icons.subdirectory_arrow_right,
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

  /// A row the cut may only READ takes no verb from here — the transition
  /// row is authored on the global axis ("컷 타임라인은 보여주기만"), so
  /// selecting it must not light up rename/duplicate/delete.
  ///
  /// A getter because ① moved rename OUT of the menu: the pill's button and
  /// the entries that stayed behind have to answer the same question, and
  /// two copies of this line would eventually stop agreeing.
  bool get _canEditActiveLayer {
    final active = session.activeLayer;
    return active != null && !layerKindIsReadOnlyInCut(active.kind);
  }

  List<PanelFlyoutEntry> _layerEntries(BuildContext context) {
    final active = session.activeLayer;
    final editable = _canEditActiveLayer;
    return [
      // ⛔RENAME IS NOT HERE — ① moved it onto the pill itself (유저 확정:
      // 「레이어 알약 밖으로: 레이어 이름변경」). "밖으로" means out of the
      // MENU and onto that pill, which is where 컷 삭제 went for the same
      // sentence; it does not mean the shared pill, whose residents 확정 #11
      // fixes at four.
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
      // ⛔The layer DELETE left this menu (유저 2026-08-12: 「밖에 딜리트
      // 레이어있으니 버튼내부에있는 딜리트레이어 삭제」) — and then left the
      // bar entirely, because delete is ONE verb now that asks what is
      // selected. See the shared pill and [EditorSessionManager.deleteSubject].
    ];
  }

  // ⛔The two PROJECT-axis dropdowns (fps, audio sample rate) LEFT this bar
  // (유저 확정, 2026-08-10). They print project values and nothing about the
  // playhead, they are touched about once per project, and they were sitting
  // in the middle of the frame verbs — so they are entries of the settings
  // pill now ([ProjectSettingsPill]), which rides the 문턱 with the transport.

  List<PanelFlyoutEntry> _frameEntries() {
    return [
      // ⛔EDIT INSTANCE IS NOT HERE — ① moved it onto the frame pill (유저
      // 확정: 「프레임 알약 밖으로: 딜리트 · Edit Instance」). The delete half
      // of that sentence went further, to the shared pill, but ⑰ sent it
      // there — 「밖으로」 on its own means out of the menu.
      // ⛔COPY AND THE PASTES ARE NOT HERE — ㉕ put them on the SHARED pill
      // (확정 #11), beside the one delete. They belong to no noun: what they
      // act on is whatever is selected, which is exactly the sentence that
      // pill exists to say.
      // ⛔DELETE IS NOT HERE EITHER (T24, 유저 2026-08-13: 「프레임알약
      // 삭제버튼 … 일단 삭제. 공통버튼에 존재하니까」). It was the last
      // duplicate: the shared pill's one delete falls through to this exact
      // verb when nothing else is selected, so the menu item reached
      // `deleteCellAtCurrentFrame` by a second road under a second gate.
      //
      // ⚠️The ladder is the difference, and it is the confirmed law rather
      // than a loss: with rows selected the one delete deletes ROWS
      // (확정 D2, 컷 > 레이어 > 셀), so deleting just the cell now means
      // clearing the row selection first. That is what "하나의 딜리트"
      // means — the button asks what is selected instead of the reach
      // deciding for it.
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
    bool danger = false,
  }) {
    return AppIconButton(
      keyValue: key.value,
      tooltip: tooltip,
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
        color: danger
            ? AppColors.deleteGlyph(enabled: onPressed != null)
            : (accent
                  ? AppColors.addGlyph(enabled: onPressed != null)
                  : null),
      ),
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
      // ①: the rename button lives here now, so its gate has to be part of
      // what wakes this group up.
      _canEditActiveLayer,
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
          // ⑥: ONE kind, always — 유저 「선택된 레이어 기준이아니라 애니메이션
          // 레이어 생성」. Placement is unchanged (above the selected row, and
          // the top of the action section when that is not a legal home).
          onPressed: () => session.addLayerOfKind(LayerKind.animation),
          entriesBuilder: _addLayerEntries,
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
        // delete asks WHAT IS SELECTED, and `DeleteSubject.layers` was a rung
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
  Widget _sharedPill() => ValueListenableBuilder<List<TimelineRowAddress>>(
    valueListenable: session.rowSelection,
    builder: (context, _, _) => ValueListenableBuilder<TimelineRowAddress?>(
      valueListenable: session.currentRowListenable,
      builder: (context, _, _) => _sharedPillBody(),
    ),
  );

  Widget _sharedPillBody() => _StaticCommandGroup(
    rebuildKey: (
      session.deleteSubject,
      AppText.settings.value.programLanguage,
      // ㉕: the three that joined the delete read their own gates.
      session.canCopyFrameAtCurrentFrame,
      session.canPasteLinkedFrameAtCurrentFrame,
      session.canPasteIndependentFrameAtCurrentFrame,
      // T25: and the fifth resident reads its own subject, for the same
      // reason the delete reads `deleteSubject` — the button's enablement
      // and what the press DOES have to come from one answer.
      session.editInstanceSubject,
      // ...plus the HOST's answer, which no session getter can reach: the
      // storyboard's standing row is separate state from its drawing target
      // (유저 2026-07-27). Leaving it out bakes a stale enablement in
      // exactly the case that has no other source.
      onEditInstance != null && _hostCanEditInstance,
    ),
    builder: (context) => CommandPill(
      key: const ValueKey<String>('timeline-toolbar-shared-group'),
      children: [
        // 🚨T25 — Edit Instance, on the SHARED pill because its subject is
        // 「지금 무엇이 선택됐나」 and that is what this pill is for.
        //
        // ⚠️It keeps the key it had on the frame pill. The button moved; it
        // did not become a different button, and every test that reached it
        // still does.
        _iconButton(
          key: const ValueKey<String>('rename-frame-button'),
          tooltip: AppText.strings.tlEditInstance,
          icon: Icons.edit_outlined,
          // Two sources, and they are asking different things rather than
          // the same thing twice: the SUBJECT is what the session has
          // selected — the same answer [editSelectionInstance] dispatches on,
          // so lit and does-something cannot come apart — while the host
          // carries what only a surface can know. Either being a yes is a yes.
          onPressed:
              onEditInstance != null &&
                  (session.editInstanceSubject != EditInstanceSubject.nothing ||
                      _hostCanEditInstance)
              ? onEditInstance
              : null,
        ),
        const PillDivider(),
        _iconButton(
          key: const ValueKey<String>('copy-frame-button'),
          tooltip: AppText.strings.tlCopyFrame,
          icon: Icons.content_copy,
          onPressed: session.canCopyFrameAtCurrentFrame
              ? session.copyFrameAtCurrentFrame
              : null,
        ),
        // ㉕ 확정 #8: the paste that makes a REAL frame, not a link. Two
        // buttons rather than one with a modifier, because which one you
        // meant is not a detail — a linked paste that was meant to be
        // independent is only discovered later, by drawing on it and
        // watching another cel change.
        _iconButton(
          key: const ValueKey<String>('paste-independent-frame-button'),
          tooltip: AppText.strings.tlPasteIndependentFrame,
          icon: Icons.content_paste,
          onPressed: session.canPasteIndependentFrameAtCurrentFrame
              ? session.pasteIndependentFrameAtCurrentFrame
              : null,
        ),
        _iconButton(
          key: const ValueKey<String>('paste-linked-frame-button'),
          tooltip: AppText.strings.tlPasteLinkedFrame,
          icon: Icons.link,
          onPressed: session.canPasteLinkedFrameAtCurrentFrame
              ? session.pasteLinkedFrameAtCurrentFrame
              : null,
        ),
        _iconButton(
          key: const ValueKey<String>('shared-delete-button'),
          tooltip: AppText.strings.tlDeleteCell,
          icon: Icons.delete_outline,
          danger: true,
          // F: the ROWS rung asks first. It inherited that from the loose
          // layer button this round folded in — a delete that used to
          // confirm must not stop confirming because its button moved. The
          // cell rung goes straight through, as it always has.
          onPressed: switch (session.deleteSubject) {
            DeleteSubject.nothing => null,
            DeleteSubject.layers when onDeleteRowSelection != null =>
              onDeleteRowSelection,
            _ => session.deleteSelectionSubject,
          },
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
        _StaticCommandGroup(
          rebuildKey: AppText.settings.value.programLanguage,
          builder: (context) => CutCommandGroup(session: session),
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
