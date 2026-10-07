import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

/// THE SHARED PILL'S ROW CLIPBOARD, PRESSED THE WAY A USER DOES (I-77): the
/// rows are SELECTED, and the pill's copy and its two pastes are pressed on
/// the timeline's context — the one entrance rows have.
///
/// ↩️The fixtures these serve called `LayerClipboard.copyActiveLayer`,
/// `pasteLayerFromClipboard` and `LayerVerbs.linkDuplicateActiveLayer` —
/// the layer menu's three verbs, which I-77 deleted with their entries
/// (유저 2026-10-06: 「레이어버튼의 레이어복사/붙여넣기는 필요없으니 삭제」 ·
/// 「링크해서 복제도 필요없어지니 삭제」).

/// Copies [rows] — the ACTIVE row when none is named — with the pill, and
/// puts the row selection back as it was: a fixture's copy is not the
/// statement about the selection a user's is.
void copyRowsWithThePill(
  EditorSessionManager session, [
  Iterable<LayerId>? rows,
]) {
  final before = session.rowSelection.value;
  session.rowSelection.value = [
    for (final id in rows ?? [session.activeLayer!.id]) LayerRowAddress(id),
  ];
  TimelineToolbarPanelContext(session).copyFrame();
  session.rowSelection.value = before;
}

/// The pill's independent paste of what is in hand.
void pasteWithThePill(EditorSessionManager session) =>
    TimelineToolbarPanelContext(session).pasteIndependentFrame();

/// The pill's linked paste of what is in hand.
void pasteLinkedWithThePill(EditorSessionManager session) =>
    TimelineToolbarPanelContext(session).pasteLinkedFrame();

/// What the layer menu's 「링크해서 복제」 made, by the road that replaced
/// it: the active row copied and pasted linked, standing back on the row it
/// was made from — where that entry left you, and where the fixtures
/// written against it go on from.
void linkDuplicateActiveRow(EditorSessionManager session) {
  final source = session.activeLayer!.id;
  copyRowsWithThePill(session);
  pasteLinkedWithThePill(session);
  session.selectLayer(source);
}
