import 'timeline/layer_name_commands.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../models/cut.dart';
import '../models/layer_mark.dart';
import 'cut/cut_note_dialog.dart';
import 'dialogs/cut_settings_window.dart';
import 'editor_command_actions.dart';
import 'dialogs/app_progress_dialog.dart';
import 'dialogs/dialog_verb.dart';
import 'dialogs/canvas_size_dialog.dart';
import 'editor_session_manager.dart';
import 'shortcuts/editor_action_registry.dart';
import 'shortcuts/editor_shortcut_scope.dart';
import 'text/app_strings.dart';
import 'widgets/command_pill.dart';
import 'widgets/panel_flyout.dart';
import 'timeline/layer_label_controls.dart'
    show layerMarkColor, layerMarkFlyoutEntries;

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
/// Its dialog flows (rename/note/settings/canvas size) are free functions of
/// this file, so both hosts — and a key — share the wiring; menu item keys
/// reuse the retired buttons' key strings so tests only gain a menu-open
/// tap.
class CutCommandGroup extends StatefulWidget {
  const CutCommandGroup({super.key, required this.session});

  final EditorSessionManager session;

  @override
  State<CutCommandGroup> createState() => _CutCommandGroupState();
}

/// 「컷 메모」 is the memo on the timesheet's FIRST page — F-301-Q1 (유저
/// 2026-10-08): 「봉투와 「컷 메모」 창은 1쪽 메모 … 구조만 통일하면됨」.
Future<void> _editActiveCutNote(
  BuildContext context,
  EditorSessionManager session,
) => askAboutThenCommit<String, String>(
  context,
  session.cutVerbs.activeCutNoteOf(0),
  dialog: (note) => CutNoteDialog(initialNote: note),
  commit: (note) => session.cutVerbs.updateActiveCutNote(page: 0, note: note),
);

/// 컷 설정 on the cuts the pick is about — the range's, or the active cut
/// ([CutVerbs.addressedCutIds], as the 색 라벨 beside it).
Future<void> _editCutSettings(
  BuildContext context,
  EditorSessionManager session,
) => askAboutThenCommit<Map<String, String>, Map<LayerMark, String>>(
  context,
  session.cutVerbs.addressedCutStaff,
  dialog: (staff) => CutSettingsWindow(cutStaff: staff),
  commit: session.cutVerbs.setAddressedCutStaffNames,
);

Future<void> _resizeActiveCutCanvas(
  BuildContext context,
  EditorSessionManager session,
) => askAboutThenCommit<Cut, CanvasResizeRequest>(
  context,
  // Gap state: no cut canvas to resize.
  session.activeCutOrNull,
  dialog: (cut) => CanvasSizeDialog(
    initialSize: cut.canvasSize,
    onAdjustOnCanvas: () => session.canvasAdjust.begin(cut.id, cut.canvasSize),
  ),
  commit: (request) => _resizeBehindTheWaitWindow(
    context,
    () => session.cutVerbs.resizeActiveCutCanvas(
      request.size,
      anchor: request.anchor,
    ),
  ),
);

/// Lands the canvas adjusted on the canvas (I-79): the size its edges make,
/// the picture moved by the edges pulled out on the left and the top —
/// behind the same wait window as a size typed into the window.
Future<void> landCanvasAdjust(
  BuildContext context,
  EditorSessionManager session,
) async {
  final adjust = session.canvasAdjust;
  final size = adjust.size;
  final offset = adjust.contentOffset;
  if (size == null || offset == null) {
    return;
  }
  if (!adjust.isOpenOn(session.activeCutOrNull?.id)) {
    adjust.end();
    return;
  }
  await _resizeBehindTheWaitWindow(context, () {
    session.cutVerbs.placeActiveCutCanvas(size, contentOffset: offset);
    adjust.end();
  });
}

/// A canvas resize, the one way every door runs it.
///
/// D3: the app's ONE wait-for-this window, exactly as save wears it.
/// The command is synchronous, but runWithAppProgress paints the
/// window before starting the task; the trailing endOfFrame holds
/// the modal barrier over the SECOND half of the resize — the
/// canvas host's adoption pass and the first recomposite land on
/// the next frame, and no input may slip between the halves (an
/// edit there would commit a stroke at the wrong canvas size).
Future<void> _resizeBehindTheWaitWindow(
  BuildContext context,
  VoidCallback resize,
) => runWithAppProgress<void>(
  context: context,
  title: AppText.strings.canvasSizeTitle,
  titleIcon: Icons.aspect_ratio,
  runningLabel: AppText.strings.resizeProgressRunning,
  doneLabel: AppText.strings.resizeProgressDone,
  windowKey: const ValueKey<String>('resize-progress-dialog'),
  task: (report) async {
    resize();
    await WidgetsBinding.instance.endOfFrame;
  },
);

/// The band over the cut pill's ＋ — the ways of making a cut.
///
/// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록. 타임라인
/// 버튼같은거나」 — every row here and in [cutMenuEntries] IS an action: it
/// wears that action's name, names the action for its key, and a key
/// presses the row itself ([pressFlyoutRow]). ⛔So these two lists are
/// functions, not methods of the pill's state: the shell builds the same
/// rows to press one.
List<PanelFlyoutEntry> cutAddEntries(EditorSessionManager session) {
  return [
    PanelFlyoutHeader(AppText.strings.cutAddCut),
    PanelFlyoutItem(
      keyValue: 'add-cut-new',
      label: editorActionLabel(EditorActionIds.cutNew),
      shortcuts: const [EditorActionIds.cutNew],
      icon: Icons.add,
      // The ＋'s own sentence ([CutPlacement.canCreateCut], #18). ↩️The row
      // was lit wherever the band opened, and where the verb had no place
      // to put a cut it took the press and did nothing.
      enabled: session.cutPlacement.canCreateCut,
      onSelected: session.cutVerbs.createCut,
    ),
    // ↩️It read 「Duplicate active cut」 here and 「Duplicate cut」 in the
    // menu beside it — one verb, and one action's name now.
    PanelFlyoutItem(
      keyValue: 'add-cut-duplicate',
      label: editorActionLabel(EditorActionIds.cutDuplicate),
      shortcuts: const [EditorActionIds.cutDuplicate],
      icon: Icons.content_copy,
      onSelected: session.cutVerbs.duplicateActiveCut,
    ),
    // 겸용컷: same pictures, own timing. It only ever lived in the top
    // menu bar, and it belongs beside the other ways of making a cut.
    // ↩️It borrowed the menu bar's wording by id; the id is its action's.
    PanelFlyoutItem(
      keyValue: 'add-cut-create-linked',
      label: editorActionLabel(EditorActionIds.cutCreateLinked),
      shortcuts: const [EditorActionIds.cutCreateLinked],
      icon: Icons.link,
      enabled: session.activeCutOrNull != null,
      onSelected: session.cutVerbs.createLinkedCutFromActiveCut,
    ),
  ];
}

/// The cut pill's menu as it opens. [context] is where a row's window opens
/// from — the pill's, or the shell's when a key presses the row.
List<PanelFlyoutEntry> cutMenuEntries(
  BuildContext context,
  EditorSessionManager session,
) {
  return [
    PanelFlyoutItem(
      keyValue: 'rename-cut-button',
      label: editorActionLabel(EditorActionIds.cutRename),
      shortcuts: const [EditorActionIds.cutRename],
      icon: Icons.edit_outlined,
      // ⛔The free function is the home, and it says why at its own head:
      // the pill is mounted on BOTH frame panels and a private `State`
      // method is reachable from exactly one of them. A copy here had
      // already drifted — it checked `mounted` where the other checks
      // `context.mounted`.
      onSelected: () =>
          unawaited(renameActiveCutWithDialog(context, session)),
    ),
    PanelFlyoutItem(
      keyValue: 'edit-cut-note-button',
      label: editorActionLabel(EditorActionIds.cutEditNote),
      shortcuts: const [EditorActionIds.cutEditNote],
      icon: Icons.note_alt_outlined,
      onSelected: () => unawaited(_editActiveCutNote(context, session)),
    ),
    // 🗣️유저 2026-09-26: 「색라벨 정하는건 블록마다 다른거니까 컷버튼안에
    // 있다던가. 선택범위 한상태로 조작가능한거 물론이고」 — THE label list
    // ([layerMarkFlyoutEntries], its third trigger after the rail chip and
    // the export window), aimed at the cuts the pick is about: the range's,
    // or the active cut ([CutVerbs.addressedCutIds]).
    // (No action: this row runs nothing — it opens the list of labels.)
    PanelFlyoutItem(
      keyValue: 'cut-mark-button',
      label: AppText.strings.tlLayerMark,
      swatch: layerMarkColor(session.cutVerbs.addressedCutMark),
      submenuBuilder: () => layerMarkFlyoutEntries(
        onSelected: session.cutVerbs.setAddressedCutMark,
      ),
    ),
    PanelFlyoutItem(
      keyValue: 'cut-settings-button',
      label: editorActionLabel(EditorActionIds.cutSettings),
      shortcuts: const [EditorActionIds.cutSettings],
      icon: Icons.tune,
      onSelected: () => unawaited(_editCutSettings(context, session)),
    ),
    // ↩️It wore the window's title, 「Canvas size」; the action's name ends
    // in the 「…」 every row that opens a window ends in.
    PanelFlyoutItem(
      keyValue: 'resize-cut-canvas-button',
      label: editorActionLabel(EditorActionIds.cutCanvasSize),
      shortcuts: const [EditorActionIds.cutCanvasSize],
      icon: Icons.aspect_ratio,
      onSelected: () =>
          unawaited(_resizeActiveCutCanvas(context, session)),
    ),
    const PanelFlyoutDivider(),
    PanelFlyoutItem(
      keyValue: 'duplicate-cut-button',
      label: editorActionLabel(EditorActionIds.cutDuplicate),
      shortcuts: const [EditorActionIds.cutDuplicate],
      icon: Icons.content_copy,
      onSelected: session.cutVerbs.duplicateActiveCut,
    ),
    PanelFlyoutItem(
      keyValue: 'convert-cut-to-linked-button',
      label: editorActionLabel(EditorActionIds.cutConvertLinked),
      shortcuts: const [EditorActionIds.cutConvertLinked],
      icon: Icons.add_link,
      enabled: canConvertActiveCutToLinked(session),
      onSelected: () =>
          unawaited(showConvertActiveCutToLinked(context, session)),
    ),
    // ONE name, and the check says which way the switch stands — as every
    // switch in a menu does. ↩️The label flipped between 「Pin thumbnail
    // frame」 and 「Unpin thumbnail frame」, a checked 「Unpin」 among them,
    // and in English whatever the program language was.
    PanelFlyoutItem(
      keyValue: 'set-cut-thumbnail-button',
      label: editorActionLabel(EditorActionIds.cutPinThumbnail),
      shortcuts: const [EditorActionIds.cutPinThumbnail],
      icon: session.cutVerbs.isActiveCutThumbnailPinnedHere
          ? Icons.image
          : Icons.image_outlined,
      checked: session.cutVerbs.isActiveCutThumbnailPinnedHere,
      onSelected: session.cutVerbs.toggleActiveCutThumbnailFrame,
    ),
    const PanelFlyoutDivider(),
    PanelFlyoutItem(
      keyValue: 'move-cut-left-button',
      label: editorActionLabel(EditorActionIds.cutMoveLeft),
      shortcuts: const [EditorActionIds.cutMoveLeft],
      icon: Icons.chevron_left,
      enabled: session.cutVerbs.canMoveActiveCutLeft,
      onSelected: session.cutVerbs.moveActiveCutLeft,
    ),
    PanelFlyoutItem(
      keyValue: 'move-cut-right-button',
      label: editorActionLabel(EditorActionIds.cutMoveRight),
      shortcuts: const [EditorActionIds.cutMoveRight],
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
      label: editorActionLabel(EditorActionIds.cutCopyAeCamera),
      shortcuts: const [EditorActionIds.cutCopyAeCamera],
      icon: Icons.videocam_outlined,
      onSelected: () => copyCameraAeKeyframes(context, session),
    ),
    // ⛔The cut DELETE is in NEITHER place now. It left this menu for the
    // pill (① 유저 2026-08-12), and left the pill for the one shared
    // delete (T24 유저 2026-08-13) — see the build method for why the
    // objection that kept it there expired.
  ];
}

class _CutCommandGroupState extends State<CutCommandGroup> {
  EditorSessionManager get session => widget.session;

  @override
  Widget build(BuildContext context) {
    return CommandPill(
      head: PillNameCell(
        keyValue: 'cut-menu-button',
        label: AppText.strings.tlCut,
        tooltip: AppText.strings.cutCommands,
        entriesBuilder: () => cutMenuEntries(context, session),
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
          accent: true,
          // 🗣️I-40: this button IS the New cut action's entrance — as its
          // band's first row is — so it wears that action's name and shows
          // its key (I-19).
          tooltip: editorActionLabel(EditorActionIds.cutNew),
          shortcuts: const [EditorActionIds.cutNew],
          onPressed: session.cutPlacement.canCreateCut
              ? session.cutVerbs.createCut
              : null,
          entriesBuilder: () => cutAddEntries(session),
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
