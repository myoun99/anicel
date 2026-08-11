import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'cut/cut_note_dialog.dart';
import 'editor_command_actions.dart';
import 'dialogs/canvas_size_dialog.dart';
import 'dialogs/rename_cut_dialog.dart';
import 'editor_session_manager.dart';
import 'text/app_strings.dart';
import 'theme/app_theme.dart' show AppColors;
import 'widgets/app_icon_button.dart';
import 'widgets/command_pill.dart';
import 'widgets/panel_flyout.dart';

/// The CUT pill, mounted IDENTICALLY on the timeline and storyboard bars.
///
/// One of the bar's four nouns ([CommandPill]): the name cell writes 「컷」
/// and opens the full cut command set, and the one verb outside the menu is
/// `＋`, whose top band offers the other ways of making one (duplicate,
/// linked). The cut used to be folded into the layer group as "행"; the user
/// split it back out because 「오히려 나누는 게 알기 쉬울 것 같아서」.
///
/// Owns its dialog flows (rename/note/canvas size) so both hosts share the
/// wiring; menu item keys reuse the retired buttons' key strings so tests
/// only gain a menu-open tap.
class CutCommandGroup extends StatefulWidget {
  const CutCommandGroup({super.key, required this.session});

  final EditorSessionManager session;

  @override
  State<CutCommandGroup> createState() => _CutCommandGroupState();
}

class _CutCommandGroupState extends State<CutCommandGroup> {
  EditorSessionManager get session => widget.session;

  Future<void> _renameActiveCut() async {
    final cut = session.activeCutOrNull;
    if (cut == null) {
      return; // Gap state: no cut to rename.
    }
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => RenameCutDialog(initialName: cut.name),
    );
    if (!mounted || nextName == null || nextName.trim().isEmpty) {
      return;
    }
    session.renameActiveCut(nextName);
  }

  Future<void> _editActiveCutNote() async {
    final initialNote = session.activeCutNote;
    if (initialNote == null) {
      return;
    }
    final nextNote = await showDialog<String>(
      context: context,
      builder: (context) => CutNoteDialog(initialNote: initialNote),
    );
    if (!mounted || nextNote == null) {
      return;
    }
    session.updateActiveCutNote(nextNote);
  }

  Future<void> _resizeActiveCutCanvas() async {
    final cut = session.activeCutOrNull;
    if (cut == null) {
      return; // Gap state: no cut canvas to resize.
    }
    final request = await showDialog<CanvasResizeRequest>(
      context: context,
      builder: (context) => CanvasSizeDialog(initialSize: cut.canvasSize),
    );
    if (!mounted || request == null) {
      return;
    }
    session.resizeActiveCutCanvas(request.size, anchor: request.anchor);
  }

  List<PanelFlyoutEntry> _addEntries() {
    return [
      PanelFlyoutHeader(AppText.strings.cutAddCut),
      PanelFlyoutItem(
        keyValue: 'add-cut-new',
        label: AppText.strings.cutNewCut,
        icon: Icons.add,
        onSelected: session.createCut,
      ),
      PanelFlyoutItem(
        keyValue: 'add-cut-duplicate',
        label: AppText.strings.cutDuplicateActive,
        icon: Icons.content_copy,
        onSelected: session.duplicateActiveCut,
      ),
      // 겸용컷: same pictures, own timing. It only ever lived in the top
      // menu bar, and it belongs beside the other ways of making a cut.
      // Borrows the menu's wording by id rather than growing a second
      // translation key for the same verb.
      PanelFlyoutItem(
        keyValue: 'add-cut-create-linked',
        label: AppText.strings.menuLabel(
          'cut-create-linked',
          'Create linked cut',
        ),
        icon: Icons.link,
        enabled: session.activeCutOrNull != null,
        onSelected: session.createLinkedCutFromActiveCut,
      ),
    ];
  }

  List<PanelFlyoutEntry> _menuEntries() {
    return [
      PanelFlyoutItem(
        keyValue: 'rename-cut-button',
        label: AppText.strings.cutRename,
        icon: Icons.edit_outlined,
        onSelected: _renameActiveCut,
      ),
      PanelFlyoutItem(
        keyValue: 'edit-cut-note-button',
        label: AppText.strings.cutEditNote,
        icon: Icons.note_alt_outlined,
        onSelected: _editActiveCutNote,
      ),
      PanelFlyoutItem(
        keyValue: 'resize-cut-canvas-button',
        label: AppText.strings.canvasSizeTitle,
        icon: Icons.aspect_ratio,
        onSelected: _resizeActiveCutCanvas,
      ),
      const PanelFlyoutDivider(),
      PanelFlyoutItem(
        keyValue: 'duplicate-cut-button',
        label: AppText.strings.cutDuplicateCut,
        icon: Icons.content_copy,
        onSelected: session.duplicateActiveCut,
      ),
      PanelFlyoutItem(
        keyValue: 'convert-cut-to-linked-button',
        label: AppText.strings.menuLabel(
          'cut-convert-linked',
          'Convert to linked cut…',
        ),
        icon: Icons.add_link,
        enabled: canConvertActiveCutToLinked(session),
        onSelected: () =>
            unawaited(showConvertActiveCutToLinked(context, session)),
      ),
      PanelFlyoutItem(
        keyValue: 'set-cut-thumbnail-button',
        label: session.isActiveCutThumbnailPinnedHere
            ? 'Unpin thumbnail frame'
            : 'Pin thumbnail frame',
        icon: session.isActiveCutThumbnailPinnedHere
            ? Icons.image
            : Icons.image_outlined,
        checked: session.isActiveCutThumbnailPinnedHere ? true : null,
        onSelected: session.toggleActiveCutThumbnailFrame,
      ),
      const PanelFlyoutDivider(),
      PanelFlyoutItem(
        keyValue: 'move-cut-left-button',
        label: AppText.strings.cutMoveLeft,
        icon: Icons.chevron_left,
        enabled: session.canMoveActiveCutLeft,
        onSelected: session.moveActiveCutLeft,
      ),
      PanelFlyoutItem(
        keyValue: 'move-cut-right-button',
        label: AppText.strings.cutMoveRight,
        icon: Icons.chevron_right,
        enabled: session.canMoveActiveCutRight,
        onSelected: session.moveActiveCutRight,
      ),
      // NO push/pull here any more: it is ONE verb aimed at whatever is
      // selected, so it lives as ONE button pair on the rail's toolbar
      // (TimelineShiftButtons) rather than a cut-flavoured copy in this
      // menu. The cut axis is still what it commits when a cut row is what
      // the selection is on.
      const PanelFlyoutDivider(),
      // Relocated from the retired camera panel to the top menu bar
      // (R11-⑤), and now to the cut it bakes: the active cut's camera work
      // as AE keyframe data on the clipboard.
      PanelFlyoutItem(
        keyValue: 'copy-cut-ae-camera-button',
        label: AppText.strings.menuLabel(
          'cut-copy-ae-camera',
          'Copy camera AE keyframes',
        ),
        icon: Icons.videocam_outlined,
        onSelected: () => copyCameraAeKeyframes(context, session),
      ),
      // ⛔The cut DELETE left this MENU (① 유저 2026-08-12: 「컷 알약 밖으로
      // 꺼낼 동사, 컷삭제, 리네임컷」) — it is a button on the pill now, one
      // door instead of two.
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CommandPill(
      head: PillNameCell(
        keyValue: 'cut-menu-button',
        label: AppText.strings.tlCut,
        tooltip: AppText.strings.cutCommands,
        entriesBuilder: _menuEntries,
      ),
      children: [
        const PillDivider(),
        StrapIconButton(
          buttonKey: 'new-cut-button',
          menuKey: 'new-cut-menu',
          // `add` and not `add_photo_alternate`: which noun it adds is what
          // the pill around it already says, and 「＋가 있는 모든 곳」 wears
          // the same glyph (유저 확정).
          icon: Icons.add,
          tooltip: AppText.strings.cutNewCut,
          onPressed: session.createCut,
          entriesBuilder: _addEntries,
          accent: true,
        ),
        // ① 유저 2026-08-12: 「컷 알약 밖으로 꺼낼 동사, 컷삭제, 리네임컷」 —
        // out of the MENU and onto the pill, which is where it is now.
        //
        // ⚠️⑰ wants this folded into the shared delete as well, and it will
        // be — but that verb reaches a cut through a cut SELECTION, and the
        // cut axis only exists on the storyboard. Removing this would have
        // left the timeline unable to delete a cut at all, which is the same
        // mistake as pulling the layer delete before ⑨ builds row selection:
        // a predecessor may only go once the successor can do its job.
        AppIconButton(
          keyValue: 'delete-cut-button',
          tooltip: AppText.strings.cutDelete,
          icon: Icon(
            Icons.delete_outline,
            color: AppColors.deleteGlyph(enabled: true),
          ),
          onPressed: session.deleteActiveCut,
        ),
      ],
    );
  }
}
