import 'timeline/layer_name_commands.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../models/cut.dart';
import 'cut/cut_note_dialog.dart';
import 'editor_command_actions.dart';
import 'dialogs/app_progress_dialog.dart';
import 'dialogs/dialog_verb.dart';
import 'dialogs/canvas_size_dialog.dart';
import 'editor_session_manager.dart';
import 'text/app_strings.dart';
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
/// ⚠️The pill is mounted on BOTH bars but cut editing is a storyboard job
/// (유저 2026-08-13: 「컷 편집은 스토리보드패널에서 하는거고」) — this pill
/// rides the timeline 「일단 통일성으로」. That is why the shared delete not
/// reaching a cut from the timeline is the intended shape rather than a hole.
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

  /// ⛔The free function is the home, and it says why at its own head: the
  /// pill is mounted on BOTH frame panels and a private `State` method is
  /// reachable from exactly one of them. This copy had already drifted —
  /// it checked `mounted` where the other checks `context.mounted`.
  Future<void> _renameActiveCut() =>
      renameActiveCutWithDialog(context, session);

  Future<void> _editActiveCutNote() => askAboutThenCommit<String, String>(
    context,
    session.cutVerbs.activeCutNote,
    dialog: (note) => CutNoteDialog(initialNote: note),
    commit: session.cutVerbs.updateActiveCutNote,
  );

  Future<void> _resizeActiveCutCanvas() =>
      askAboutThenCommit<Cut, CanvasResizeRequest>(
        context,
        // Gap state: no cut canvas to resize.
        session.activeCutOrNull,
        dialog: (cut) => CanvasSizeDialog(initialSize: cut.canvasSize),
        // D3: the app's ONE wait-for-this window, exactly as save wears it.
        // The command is synchronous, but runWithAppProgress paints the
        // window before starting the task; the trailing endOfFrame holds
        // the modal barrier over the SECOND half of the resize — the
        // canvas host's adoption pass and the first recomposite land on
        // the next frame, and no input may slip between the halves (an
        // edit there would commit a stroke at the wrong canvas size).
        commit: (request) => runWithAppProgress<void>(
          context: context,
          title: AppText.strings.canvasSizeTitle,
          titleIcon: Icons.aspect_ratio,
          runningLabel: AppText.strings.resizeProgressRunning,
          doneLabel: AppText.strings.resizeProgressDone,
          windowKey: const ValueKey<String>('resize-progress-dialog'),
          task: (report) async {
            session.cutVerbs.resizeActiveCutCanvas(
              request.size,
              anchor: request.anchor,
            );
            await WidgetsBinding.instance.endOfFrame;
          },
        ),
      );

  List<PanelFlyoutEntry> _addEntries() {
    return [
      PanelFlyoutHeader(AppText.strings.cutAddCut),
      PanelFlyoutItem(
        keyValue: 'add-cut-new',
        label: AppText.strings.cutNewCut,
        icon: Icons.add,
        onSelected: session.cutVerbs.createCut,
      ),
      PanelFlyoutItem(
        keyValue: 'add-cut-duplicate',
        label: AppText.strings.cutDuplicateActive,
        icon: Icons.content_copy,
        onSelected: session.cutVerbs.duplicateActiveCut,
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
        onSelected: session.cutVerbs.createLinkedCutFromActiveCut,
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
        onSelected: session.cutVerbs.duplicateActiveCut,
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
        label: session.cutVerbs.isActiveCutThumbnailPinnedHere
            ? 'Unpin thumbnail frame'
            : 'Pin thumbnail frame',
        icon: session.cutVerbs.isActiveCutThumbnailPinnedHere
            ? Icons.image
            : Icons.image_outlined,
        checked: session.cutVerbs.isActiveCutThumbnailPinnedHere,
        onSelected: session.cutVerbs.toggleActiveCutThumbnailFrame,
      ),
      const PanelFlyoutDivider(),
      PanelFlyoutItem(
        keyValue: 'move-cut-left-button',
        label: AppText.strings.cutMoveLeft,
        icon: Icons.chevron_left,
        enabled: session.cutVerbs.canMoveActiveCutLeft,
        onSelected: session.cutVerbs.moveActiveCutLeft,
      ),
      PanelFlyoutItem(
        keyValue: 'move-cut-right-button',
        label: AppText.strings.cutMoveRight,
        icon: Icons.chevron_right,
        enabled: session.cutVerbs.canMoveActiveCutRight,
        onSelected: session.cutVerbs.moveActiveCutRight,
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
      // ⛔The cut DELETE is in NEITHER place now. It left this menu for the
      // pill (① 유저 2026-08-12), and left the pill for the one shared
      // delete (T24 유저 2026-08-13) — see the build method for why the
      // objection that kept it there expired.
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
        // #18 — the button reads the SAME sentence the verb runs on
        // ([CutPlacement.cutCreationPlan], the T25 law). The bare
        // tear-off before this could never go null, so the button lit in
        // exactly the states where pressing it did something other than
        // it promised — a gap press appended at the track's end, and the
        // frame buttons lit for that far-away cut. (Comment sits ABOVE
        // the button, and names the add glyph only in prose: the ＋-accent
        // source contract reads a ±320-char window around the glyph
        // constant — prose between it and its `accent:` pushes the answer
        // out of the window, and the constant's literal name inside a
        // comment is a match of its own.)
        StrapIconButton(
          buttonKey: 'new-cut-button',
          menuKey: 'new-cut-menu',
          // `add` and not `add_photo_alternate`: which noun it adds is what
          // the pill around it already says, and 「＋가 있는 모든 곳」 wears
          // the same glyph (유저 확정).
          icon: Icons.add,
          tooltip: AppText.strings.cutNewCut,
          onPressed: session.cutPlacement.canCreateCut
              ? session.cutVerbs.createCut
              : null,
          entriesBuilder: _addEntries,
          accent: true,
        ),
        // ⛔THE CUT DELETE IS GONE (T24, 유저 2026-08-13: 「컷알약 삭제버튼
        // 일단 삭제. 공통버튼에 존재하니까」). ⑰'s one delete has it.
        //
        // This button was kept back once, and the reason is worth keeping
        // because it is the reason that expired rather than a reason that
        // was wrong: the shared delete reaches a cut through a cut
        // SELECTION, the cut axis lives only on the storyboard, so removing
        // this would leave the timeline unable to delete a cut at all — the
        // same mistake as pulling the layer delete before ⑨ built row
        // selection.
        //
        // 유저 2026-08-13 retired the premise, not the reasoning: 「타임라인
        // 에서 컷 선택은 못해도되. 할필요도없어. **컷 편집은 스토리보드
        // 패널에서 하는거고**」 — and the cut pill itself is only here 「일단
        // 통일성으로」. A capability the timeline is not supposed to have is
        // not a capability the timeline loses.
      ],
    );
  }
}
