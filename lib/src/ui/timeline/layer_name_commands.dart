import 'package:flutter/material.dart';

import '../../models/cut.dart';
import '../dialogs/delete_layer_dialog.dart';
import '../dialogs/dialog_verb.dart';
import '../dialogs/rename_cut_dialog.dart';
import '../dialogs/rename_layer_dialog.dart';
import '../editor_session_manager.dart';

/// The two LAYER dialogs the command bar's layer pill opens.
///
/// Free functions because the pill is mounted on BOTH frame panels now
/// (유저: 스토리보드에서도 레이어를 만들고 지워야 한다) and these were
/// private methods of the timeline's host — the one panel that happened to
/// grow them first. Nothing in either flow is about the timeline; they take
/// a context to show a dialog in and a session to commit to.
///
/// ⚠️The heavier `Edit Instance` flow did NOT come with them. It is a
/// kind-dispatch across five dialogs plus the lane-key rename, ~300 lines
/// that still live in the timeline host, and moving them is its own change
/// rather than a passenger on this one. The frame pill's menu entry is
/// optional for exactly that reason: a panel that cannot serve it says so by
/// passing null, and the entry greys out instead of lying.
/// ⑰/F: the SHARED delete, when what is selected is ROWS.
///
/// ⚠️This exists so folding the layer delete into the shared pill does not
/// quietly drop its confirmation. The loose layer button asked before it
/// deleted; the shared pill's delete did not, because the rung it was folding
/// in (the frame block) is a smaller, cheaper thing to lose. Rows are not,
/// and a delete that used to ask must not stop asking just because the button
/// it lived on moved.
///
/// The dialog names what is going, so a multi-row delete cannot read as a
/// single-row one — the names ARE the message, and no new string is invented
/// to say a number the names already say.
Future<void> deleteRowSelectionWithDialog(
  BuildContext context,
  EditorSessionManager session,
) {
  final ids = session.layerVerbs.deletableSelectedLayerIds();
  if (ids.isEmpty) {
    return Future<void>.value();
  }
  final byId = {for (final layer in session.layers) layer.id: layer};
  final names = [
    for (final id in ids)
      if (byId[id] case final layer?) layer.name,
  ];
  return confirmThenCommit(
    context,
    dialog: (_) => DeleteLayerDialog(layerName: names.join(', ')),
    commit: session.deleteSelectionSubject,
  );
}

Future<void> deleteActiveLayerWithDialog(
  BuildContext context,
  EditorSessionManager session,
) {
  final activeLayer = session.activeLayer;
  if (activeLayer == null || !session.layerVerbs.canDeleteActiveLayer) {
    return Future<void>.value();
  }
  return confirmThenCommit(
    context,
    dialog: (_) => DeleteLayerDialog(layerName: activeLayer.name),
    commit: session.layerVerbs.deleteActiveLayer,
  );
}

/// ⑨: 「이름편집은 선택된 편집가능 레이어 전부를 같은 이름으로 일괄 변경」.
///
/// The verb ([EditorSessionManager.renameSelectedLayers]) landed with ⑨ and
/// had no door — this is the door. The dialog is the same one; only the
/// subject changed, and it changes the way every other row verb's does: ask
/// the selection, fall back to the row you are standing on.
///
/// The seed name is honest about that subject. One row (selected or active)
/// seeds its own name; SEVERAL seed nothing, because there is no single name
/// they currently share and offering one of them would quietly propose
/// renaming the rest to it.
Future<void> renameActiveLayerWithDialog(
  BuildContext context,
  EditorSessionManager session,
) {
  final selected = session.layerVerbs.renameableSelectedLayerIds();
  final activeLayer = session.activeLayer;
  if (selected.isEmpty && activeLayer == null) {
    return Future<void>.value();
  }
  final soleId = selected.length == 1 ? selected.single : null;
  final sole = soleId == null
      ? null
      : session.layers.where((layer) => layer.id == soleId).firstOrNull;
  final initialName = selected.length > 1
      ? ''
      : (sole ?? activeLayer)?.name ?? '';
  return askThenCommit<String>(
    context,
    dialog: (_) => RenameLayerDialog(initialName: initialName),
    commit: (nextName) => selected.isEmpty
        ? session.layerVerbs.renameActiveLayer(nextName)
        : session.layerVerbs.renameSelectedLayers(nextName),
  );
}

/// The CUT rename, lifted out of `CutCommandGroup` so the shared pill's
/// Edit Instance can reach its top rung (T25).
///
/// ⛔A free function for the reason the two above are: the pill is mounted
/// on both frame panels, and a private `State` method is reachable from
/// exactly one of them. That is the trap the layer dialogs were already in
/// before they moved here.
///
/// ⚠️No empty-name check here. [RenameCutDialog] pops the TRIMMED text and
/// refuses an empty one inline — deciding that is what the prompt window
/// is for — so a caller-side re-check was a second copy of the dialog's
/// own law, and the copy is the thing that drifts.
Future<void> renameActiveCutWithDialog(
  BuildContext context,
  EditorSessionManager session,
) => askAboutThenCommit<Cut, String>(
  context,
  session.activeCutOrNull, // Gap state: no cut to rename.
  dialog: (cut) => RenameCutDialog(initialName: cut.name),
  commit: session.cutVerbs.renameActiveCut,
);
