import 'package:flutter/material.dart';

import '../dialogs/delete_layer_dialog.dart';
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
Future<void> deleteActiveLayerWithDialog(
  BuildContext context,
  EditorSessionManager session,
) async {
  final activeLayer = session.activeLayer;
  if (activeLayer == null || !session.canDeleteActiveLayer) {
    return;
  }
  final shouldDelete = await showDialog<bool>(
    context: context,
    builder: (context) => DeleteLayerDialog(layerName: activeLayer.name),
  );
  if (!context.mounted || shouldDelete != true) {
    return;
  }
  session.deleteActiveLayer();
}

Future<void> renameActiveLayerWithDialog(
  BuildContext context,
  EditorSessionManager session,
) async {
  final activeLayer = session.activeLayer;
  if (activeLayer == null) {
    return;
  }
  final nextName = await showDialog<String>(
    context: context,
    builder: (context) => RenameLayerDialog(initialName: activeLayer.name),
  );
  if (!context.mounted || nextName == null) {
    return;
  }
  session.renameActiveLayer(nextName);
}
