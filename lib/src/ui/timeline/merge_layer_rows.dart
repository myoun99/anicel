import 'dart:ui' as ui;

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';

import '../../core/progress_share.dart';
import '../../models/cut.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/pasteboard_bounds.dart' show PasteboardWall;
import '../../models/pill_subject.dart';
import '../../services/editing/layer_merge_plan.dart';
import '../../services/guide_geometry.dart' show GuideTransform;
import '../../services/import/cel_picture.dart' show EnginePicture;
import '../../services/import/raster_cel_import.dart' show layCelPicture;
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/app_progress_dialog.dart';
import '../editor_session_manager.dart';
import '../export/export_frame_renderer.dart';
import '../export/offscreen_raster.dart' show rasterizeOffscreen;
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
  final plan = session.layerMerging.planOfSelection();
  if (plan == null) {
    return;
  }
  final strings = AppText.strings;
  await bakeAfterAsking<LayerMergeChange>(context, session, (
    run: (
      title: plan.result.name,
      icon: Icons.merge,
      windowKey: 'layer-merge-progress',
      pictures: plan.pictures,
      land: () => session.layerMerging.land(plan),
    ),
    question: (
      slug: 'layer-merge-changes',
      title: strings.tlMergeChangesTitle,
      body: strings.tlMergeChangesBody,
      accept: editorActionLabel(EditorActionIds.editMerge),
    ),
    changes: plan.changes,
    lineOf: (change) => switch (change) {
      LayerMergeChange.blend => strings.tlMergeChangeBlend,
      LayerMergeChange.clip => strings.tlMergeChangeClip,
      LayerMergeChange.folder => strings.tlMergeChangeFolder,
      LayerMergeChange.riderOver => strings.tlMergeChangeRiderOver,
      LayerMergeChange.riderUnder => strings.tlMergeChangeRiderUnder,
      LayerMergeChange.wall => strings.tlMergeChangeWall,
    },
  ));
}

/// What a bake asks before it changes how its rows look: its window's
/// [title] and [body] — keyed [confirmDialogKeys] of [slug] — answered
/// with [accept].
typedef BakeQuestion = ({
  String slug,
  String title,
  String body,
  String accept,
});

/// A bake as its press runs it ([bakeBehindTheWaitWindow]) — a MERGE's
/// (I-78), an fx RASTERIZE's (I-120): its wait window's [title] under
/// [icon], keyed [windowKey]; the [pictures] it lays, and how it [land]s.
typedef BakeRun = ({
  String title,
  IconData icon,
  String windowKey,
  List<LayerMergePicture> pictures,
  void Function() land,
});

/// A bake asked first ([bakeAfterAsking]) — a MERGE's: how it [run]s, what
/// it asks first ([question]), and a line for each of the [changes] it
/// makes to how the rows look ([lineOf]).
typedef Bake<C extends Enum> = ({
  BakeRun run,
  BakeQuestion question,
  Set<C> changes,
  String Function(C change) lineOf,
});

/// [bake] pressed: asked first where it changes how the rows look — its
/// changes in their order; none, and it goes ahead unasked — and run
/// ([bakeBehindTheWaitWindow]).
Future<void> bakeAfterAsking<C extends Enum>(
  BuildContext context,
  EditorSessionManager session,
  Bake<C> bake,
) async {
  final lines = [
    for (final change in bake.changes.sortedBy<num>((c) => c.index))
      bake.lineOf(change),
  ];
  if (lines.isNotEmpty &&
      await _accepts(context, bake.question, bake.run.icon, lines) != true) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  await bakeBehindTheWaitWindow(context, session, bake.run);
}

/// [run]: each of its pictures drawn as the rows show it behind the one
/// wait window heavy work shows ([runWithAppProgress]), and landed as one
/// undo step — asked nothing first (an fx RASTERIZE's, 🗣️I-120-Q21 「경고
/// 창을 없앤다 — 묻지 않고 굽는다」), or once [bakeAfterAsking] has asked.
Future<void> bakeBehindTheWaitWindow(
  BuildContext context,
  EditorSessionManager session,
  BakeRun run,
) {
  final strings = AppText.strings;
  return runWithAppProgress<void>(
    context: context,
    title: run.title,
    titleIcon: run.icon,
    runningLabel: strings.bakeProgressRunning,
    windowKey: ValueKey<String>(run.windowKey),
    task: (report) async {
      await layBakedPictures(session, run.pictures, report);
      run.land();
    },
  );
}

/// Whether the bake goes ahead over the [lines] it changes how the rows
/// look by — null for a window walked away from.
Future<bool?> _accepts(
  BuildContext context,
  BakeQuestion question,
  IconData icon,
  List<String> lines,
) => askConfirm(
  context,
  ConfirmQuestion(
    keys: confirmDialogKeys(question.slug),
    title: question.title,
    message: question.body,
    titleIcon: icon,
    details: [
      NoticeDetails(
        heading: AppText.strings.tlMergeChanges,
        open: true,
        lines,
      ),
    ],
  ),
  accept: ConfirmChoice(question.accept),
);

/// MERGE as the shared pill's button and its key press it: whatever
/// [subject] names — the panel's ladder ([ToolbarPanelContext.mergeSubject])
/// — so the press does what its light said.
Future<void> mergeSelectionSubject(
  BuildContext context,
  EditorSessionManager session,
  PillSubject subject,
) => switch (subject) {
  PillSubject.layers => mergeLayerRows(context, session),
  PillSubject.cells => mergeBlocks(context, session),
  PillSubject.cuts || PillSubject.nothing => Future.value(),
};

/// MERGE on the frame axis (I-78 round ③, Q4): each row's blocks the band
/// holds made one block over one cel, laid of their cels as they are
/// behind the one wait window heavy work shows ([runWithAppProgress]), and
/// landed as one undo step ([LayerMerging.landBlocks]).
Future<void> mergeBlocks(
  BuildContext context,
  EditorSessionManager session,
) async {
  final plan = session.layerMerging.planOfBand();
  if (plan == null) {
    return;
  }
  final strings = AppText.strings;
  await runWithAppProgress<void>(
    context: context,
    title: editorActionLabel(EditorActionIds.editMerge),
    titleIcon: Icons.merge,
    runningLabel: strings.bakeProgressRunning,
    windowKey: const ValueKey<String>('layer-merge-progress'),
    task: (report) async {
      await _layBlockPictures(session, plan, report);
      session.layerMerging.landBlocks(plan);
    },
  );
}

/// Each of [pictures] drawn of the cut it is made from, laid on its new
/// cel in the cut that keeps it ([LayerMergePicture.into]) — a merge of a
/// track's conte rows lays each cut's own (I-78-Q20), one cut's after
/// another's. A merge's pictures, and an fx RASTERIZE's (I-120).
Future<void> layBakedPictures(
  EditorSessionManager session,
  List<LayerMergePicture> pictures,
  void Function(double) report,
) async {
  var laid = 0;
  for (final ofCut in pictures
      .groupListsBy((picture) => picture.into.id)
      .values) {
    final laying = _Laying(session, ofCut.first.into);
    try {
      for (final picture in ofCut) {
        await laying.lay(
          picture.rowId,
          picture.frameId,
          await laying.draw(picture.from, picture.frameIndex),
        );
        laid += 1;
        report(doneShare(laid, pictures.length));
      }
    } finally {
      laying.dispose();
    }
  }
}

/// Each of [plan]'s new cels laid of the cels it is made of, each drawn
/// alone and then laid over the one under it.
Future<void> _layBlockPictures(
  EditorSessionManager session,
  BlockMergePlan plan,
  void Function(double) report,
) async {
  final laying = _Laying(session, plan.cut);
  try {
    for (final (index, picture) in plan.pictures.indexed) {
      final layers = [
        for (final layer in picture.layers) await laying.draw(layer, 0),
      ];
      try {
        await laying.lay(
          picture.rowId,
          picture.frameId,
          await rasterizeOffscreen(
            width: layers.first.width,
            height: layers.first.height,
            paint: (canvas) {
              // 1:1 — each drawn over the same wall, one texel to a pixel.
              final blit = Paint()..filterQuality = FilterQuality.none;
              for (final layer in layers) {
                canvas.drawImage(layer, Offset.zero, blit);
              }
            },
          ),
        );
      } finally {
        for (final layer in layers) {
          layer.dispose();
        }
      }
      report(doneShare(index + 1, plan.pictures.length));
    }
  } finally {
    laying.dispose();
  }
}

/// What a merge lays its pictures with: each drawn over [cut]'s whole
/// pasteboard — what lies past the canvas is the rows' too (a pan's
/// background) — on a clear ground, and laid on its new cel where it lies.
final class _Laying {
  _Laying(this.session, this.cut)
    : wall = session.pasteboardOf(cut.canvasSize),
      _renderer = ExportFrameRenderer(
        session: session,
        background: const ui.Color(0x00000000),
      );

  final EditorSessionManager session;
  final Cut cut;
  final PasteboardWall wall;
  final ExportFrameRenderer _renderer;

  /// [from] at [frameIndex], over the whole wall.
  Future<ui.Image> draw(Cut from, int frameIndex) => _renderer.renderPicture(
    from,
    frameIndex,
    width: wall.rect.width.round(),
    region: wall.rect,
  );

  /// [image] laid as [cut]'s cel [frameId] of [rowId], where it lies.
  Future<void> lay(LayerId rowId, FrameId frameId, ui.Image image) async {
    final drawn = EnginePicture(image);
    try {
      session.layerMerging.layPicture(
        cut,
        rowId,
        frameId,
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
  }

  void dispose() => _renderer.dispose();
}
