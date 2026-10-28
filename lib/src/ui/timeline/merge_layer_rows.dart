import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/progress_share.dart';
import '../../models/cut.dart';
import '../../services/editing/layer_merge_plan.dart';
import '../../services/guide_geometry.dart' show GuideTransform;
import '../../services/import/cel_picture.dart' show EnginePicture;
import '../../services/import/raster_cel_import.dart' show layCelPicture;
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/app_progress_dialog.dart';
import '../editor_session_manager.dart';
import '../export/export_frame_renderer.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';

/// MERGE (I-78): the selected rows made one row — asked first where the
/// merge changes how they look (Q1 「포토샵 · 클튜처럼 (+경고)」), each of
/// its pictures drawn as the rows show it (Q6) behind the one wait window
/// heavy work shows ([runWithAppProgress]), and landed as one undo step
/// ([LayerMerging.land]).
Future<void> mergeLayerRows(
  BuildContext context,
  EditorSessionManager session,
) async {
  final asked = session.layerMerging.planOfSelection();
  if (asked == null) {
    return;
  }
  final (:cut, :plan) = asked;
  if (plan.changes.isNotEmpty &&
      await _accepts(context, plan.changes) != true) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  final strings = AppText.strings;
  await runWithAppProgress<void>(
    context: context,
    title: plan.result.name,
    titleIcon: Icons.merge,
    runningLabel: strings.bakeProgressRunning,
    doneLabel: strings.bakeProgressDone,
    windowKey: const ValueKey<String>('layer-merge-progress'),
    task: (report) async {
      await _layPictures(session, cut, plan, report);
      session.layerMerging.land(cut, plan);
    },
  );
}

/// Whether the merge goes ahead over the [changes] it makes to how the
/// rows look — null for a window walked away from.
Future<bool?> _accepts(BuildContext context, Set<LayerMergeChange> changes) {
  final strings = AppText.strings;
  return askConfirm(
    context,
    ConfirmQuestion(
      keys: confirmDialogKeys('layer-merge-changes'),
      title: strings.tlMergeChangesTitle,
      message: strings.tlMergeChangesBody,
      titleIcon: Icons.merge,
      details: [
        NoticeDetails(heading: strings.tlMergeChanges, open: true, [
          for (final change in LayerMergeChange.values)
            if (changes.contains(change))
              switch (change) {
                LayerMergeChange.blend => strings.tlMergeChangeBlend,
                LayerMergeChange.clip => strings.tlMergeChangeClip,
                LayerMergeChange.folder => strings.tlMergeChangeFolder,
              },
        ]),
      ],
    ),
    accept: ConfirmChoice(editorActionLabel(EditorActionIds.editMerge)),
  );
}

/// Each of [plan]'s pictures drawn from its rows over the whole pasteboard
/// — what lies past the canvas is the rows' too (a pan's background) — and
/// laid on its new cel where it lies.
Future<void> _layPictures(
  EditorSessionManager session,
  Cut cut,
  LayerMergePlan plan,
  void Function(double) report,
) async {
  final wall = session.pasteboardOf(cut.canvasSize);
  final renderer = ExportFrameRenderer(
    session: session,
    background: const ui.Color(0x00000000),
  );
  try {
    for (final (index, picture) in plan.pictures.indexed) {
      final drawn = EnginePicture(
        await renderer.renderPicture(
          plan.baked,
          picture.frameIndex,
          width: wall.rect.width.round(),
          region: wall.rect,
        ),
      );
      try {
        session.layerMerging.layPicture(
          cut,
          plan,
          picture,
          await layCelPicture(
            picture: drawn,
            canvas: cut.canvasSize,
            placement: GuideTransform(
              1,
              0,
              0,
              1,
              wall.left.toDouble(),
              wall.top.toDouble(),
            ),
          ),
        );
      } finally {
        drawn.dispose();
      }
      report(doneShare(index + 1, plan.pictures.length));
    }
  } finally {
    renderer.dispose();
  }
}
