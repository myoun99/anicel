import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/cut_metadata.dart';
import 'cut/cut_note_dialog.dart';
import 'dialogs/cut_settings_window.dart';
import 'editor_command_actions.dart';
import 'dialogs/behind_the_wait_window.dart';
import 'dialogs/dialog_verb.dart';
import 'dialogs/canvas_size_dialog.dart';
import 'dialogs/new_cut_dialog.dart';
import 'editor_session_manager.dart';
import 'session/canvas_adjust.dart';
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
/// `＋`, which makes a cut. The cut used to be folded into the layer group
/// as "행"; the user split it back out because 「오히려 나누는 게 알기 쉬울
/// 것 같아서」.
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
) => askAboutThenCommit<CutMetadata, CutSettingsSave>(
  context,
  session.cutVerbs.addressedCutMetadata,
  dialog: (cut) => CutSettingsWindow(cut: cut),
  commit: (save) => session.cutVerbs.setAddressedCutStaff(
    save.names,
    openFolds: save.openFolds,
  ),
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
    onAdjustOnCanvas: () => session.canvasAdjust.begin(
      CanvasEdgesDraft.of(cut.id, cut.canvasSize),
    ),
  ),
  commit: (request) => resizeBehindTheWaitWindow(
    context,
    () => session.cutVerbs.resizeActiveCutCanvas(
      request.size,
      anchor: request.anchor,
    ),
    title: AppText.strings.canvasSizeTitle,
    ahead: (report) => session.cutVerbs.resizeActiveCutCanvasAhead(
      request.size,
      anchor: request.anchor,
      report: report,
    ),
  ),
);

/// Lands what is adjusted on the canvas. A canvas (I-79): the size its
/// edges make, the picture moved by the edges pulled out on the left and the
/// top — behind the same wait window as a size typed into the window. The
/// camera's frame (I-80): the project camera takes its size, as the camera
/// size window's 적용 gives it.
Future<void> landCanvasAdjust(
  BuildContext context,
  EditorSessionManager session,
) async {
  final adjust = session.canvasAdjust;
  if (!adjust.isOpenOn(session.activeCutOrNull?.id)) {
    adjust.end();
    return;
  }
  switch (adjust.draft) {
    case CameraSizeDraft(:final size):
      session.camera.setProjectCameraSize(size);
      adjust.end();
    case CanvasEdgesDraft(:final size, :final contentOffset):
      await resizeBehindTheWaitWindow(
        context,
        () {
          session.cutVerbs.placeActiveCutCanvas(
            size,
            contentOffset: contentOffset,
          );
          adjust.end();
        },
        title: AppText.strings.canvasSizeTitle,
        ahead: (report) => session.cutVerbs.placeActiveCutCanvasAhead(
          size,
          contentOffset: contentOffset,
          report: report,
        ),
      );
    case null:
      return;
  }
}

/// What the cut pill's ＋ does when pressed — open the new cut window
/// ([NewCutDialog]) and make the cut it confirms where the ＋ stands — or
/// null where it has no place to put one ([CutPlacement.canCreateCut],
/// #18): the button and its key read this one answer.
///
/// 🗣️F-455 (유저 2026-10-23): 「컷 종류버튼의 새 컷은 +버튼이랑 겹치니
/// 삭제 … 종류버튼에 들어갈거 없으니 잠정적으로 삭제. 필요해질때 다시 만듬」
/// — the ＋ wears no band. ↩️Its band offered 새 컷 (the ＋'s own verb a
/// second time) and 겸용컷 만들기, which went to [cutMenuEntries].
VoidCallback? newCutPress(
  BuildContext context,
  EditorSessionManager session,
) => session.cutPlacement.canCreateCut
    ? () => unawaited(_askNewCut(context, session))
    : null;

/// The window offers the cut [CutVerbs.createCut] makes unasked — its name
/// where it lands, A4 200dpi — and the cut is made as the window leaves it.
Future<void> _askNewCut(BuildContext context, EditorSessionManager session) {
  final planned = session.cutVerbs.plannedNewCut;
  var size = planned?.canvasSize;
  return askAboutThenCommit<Cut, String>(
    context,
    planned,
    dialog: (cut) => NewCutDialog(
      initialName: cut.name,
      initialSize: cut.canvasSize,
      onSizeChanged: (typed) => size = typed,
    ),
    commit: (name) =>
        session.cutVerbs.createCut(name: name, canvasSize: size),
  );
}

/// The same window for a 겸용 cut of the active cut (🗣️I-100-Q1): the name
/// [CutVerbs.createLinkedCutFromActiveCut] gives it unasked, over the
/// active cut's canvas, which it keeps.
Future<void> _askLinkedCut(
  BuildContext context,
  EditorSessionManager session,
) => askAboutThenCommit<({String name, CanvasSize canvasSize}), String>(
  context,
  session.cutVerbs.plannedLinkedCut,
  dialog: (planned) => NewCutDialog(
    action: EditorActionIds.cutCreateLinked,
    initialName: planned.name,
    initialSize: planned.canvasSize,
    onSizeChanged: null,
  ),
  commit: (name) => session.cutVerbs.createLinkedCutFromActiveCut(name: name),
);

/// The cut pill's menu as it opens. [context] is where a row's window opens
/// from — the pill's, or the shell's when a key presses the row.
///
/// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록. 타임라인
/// 버튼같은거나」 — every row here IS an action: it wears that action's
/// name, names the action for its key, and a key presses the row itself
/// ([pressFlyoutRow]). ⛔So this list is a function, not a method of the
/// pill's state: the shell builds the same rows to press one.
///
/// ⛔🗣️F-455 (유저 2026-10-23) took five rows out:
/// - 컷 이름 변경 — 「공용알약꺼 쓰거나 더블클릭으로 되니 삭제」;
/// - 컷 복제 — 「공용알약에 복제 버튼 만들고 … 컷복제 삭제」;
/// - 컷 왼쪽/오른쪽으로 — 「필요시 공용알약에서 구현할것임」;
/// - 카메라 AE 키프레임 복사 — 「다른 카드에서 선택한 행 ae복사(애니메이션
///   행의 경우 트랜스폼이나 노출같은거 다 포함해서)로 폭넓게 구현할것임」.
List<PanelFlyoutEntry> cutMenuEntries(
  BuildContext context,
  EditorSessionManager session,
) {
  return [
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
    // ↩️It wore the window's title, 「Canvas size」; it wears its action's
    // name, as every row does.
    PanelFlyoutItem(
      keyValue: 'resize-cut-canvas-button',
      label: editorActionLabel(EditorActionIds.cutCanvasSize),
      shortcuts: const [EditorActionIds.cutCanvasSize],
      icon: Icons.aspect_ratio,
      onSelected: () =>
          unawaited(_resizeActiveCutCanvas(context, session)),
    ),
    const PanelFlyoutDivider(),
    // 겸용컷: same pictures, own timing — 🗣️F-455: 「종류버튼의 겸용컷
    // 만들기는 컷 버튼으로 옮김. 겸용컷 변환 위」. ↩️It stood in the ＋'s
    // band, beside the other ways of making a cut.
    PanelFlyoutItem(
      keyValue: 'add-cut-create-linked',
      label: editorActionLabel(EditorActionIds.cutCreateLinked),
      shortcuts: const [EditorActionIds.cutCreateLinked],
      icon: Icons.link,
      enabled: session.activeCutOrNull != null,
      onSelected: () => unawaited(_askLinkedCut(context, session)),
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
    // NO push/pull here any more: it is ONE verb aimed at whatever is
    // selected, so it lives as ONE button pair on the rail's toolbar
    // (TimelineShiftButtons) rather than a cut-flavoured copy in this
    // menu. The cut axis is still what it commits when a cut row is what
    // the selection is on.
    //
    // ⛔The cut DELETE is in NEITHER place now. It left this menu for the
    // pill (① 유저 2026-08-12), and left the pill for the one shared
    // delete (T24 유저 2026-08-13) — see the build method for why the
    // objection that kept it there expired.
  ];
}

class _CutCommandGroupState extends State<CutCommandGroup> {
  EditorSessionManager get session => widget.session;

  /// Baked whole, as the layer pill is. ↩️In TWO zones round the cut's name
  /// ([CommandGroupZone]) from F-463 ④: the name ticked, and a tick layer
  /// inside a bake kept the pill from baking (`panel_static_raster_test`).
  /// The name stands at the head of the bar's right group since F-491
  /// (`TimelineViewCluster`).
  @override
  Widget build(BuildContext context) {
    return CommandPill(
      head: PillNameCell(
        keyValue: 'cut-menu-button',
        label: AppText.strings.tlCut,
        tooltip: AppText.strings.cutCommands,
        entriesBuilder: () => cutMenuEntries(context, session),
      ),
      children: _verbs(),
    );
  }

  /// The pill's verbs after the name.
  List<Widget> _verbs() => [
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
      // `add` and not `add_photo_alternate`: which noun it adds is what
      // the pill around it already says, and 「＋가 있는 모든 곳」 wears
      // the same glyph (유저 확정).
      icon: Icons.add,
      accent: true,
      // 🗣️I-40: this button IS the New cut action's entrance, so it
      // wears that action's name and shows its key (I-19). No band
      // ([newCutPress] has why).
      tooltip: editorActionLabel(EditorActionIds.cutNew),
      shortcuts: const [EditorActionIds.cutNew],
      onPressed: newCutPress(context, session),
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
  ];
}
