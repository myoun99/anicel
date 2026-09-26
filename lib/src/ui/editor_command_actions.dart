/// Editor commands that are more than one session call — a dialog to
/// answer, a clipboard to fill, a switch over the active row's kind.
///
/// A plain session verb can be handed to any surface as a tear-off, so two
/// surfaces offer the same command by naming the same method. These could
/// not: their flow lived as private methods inside whichever widget got
/// there first, and offering them anywhere else meant writing the flow
/// again. They live here instead, so a second entrance costs one call and
/// the flow keeps one author.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/cut.dart';
import '../models/cut_id.dart';
import '../models/layer_kind.dart';
import 'dialogs/app_confirm_dialog.dart' show showAppNotice;
import 'dialogs/convert_to_linked_cut_dialog.dart';
import 'dialogs/dialog_verb.dart';
import 'editor_session_manager.dart';
import 'text/app_strings.dart';
import 'export/ae_keyframe_data.dart';

/// The kind-dispatched "make one here" verb: a drawing cel, a camera key,
/// an SE entry or an instruction event, whichever the active row holds. A
/// live selection wins — every selected cell gets one.
///
/// Shared rather than private to the timeline host because the toolbar
/// button is no longer its only entrance: [EditorActionIds.frameNewDrawing]
/// dispatches here too, and a custom rail slot will.
void createActiveInstance(EditorSessionManager session) {
  if (session.cellInstances.createInstancesForSelection()) {
    return;
  }
  final layer = session.activeLayer;
  if (layer == null) {
    return;
  }
  switch (layer.kind) {
    case LayerKind.camera:
      session.camera.setCameraKeyframeAtCurrentFrame(session.camera.cameraPoseAtCurrentFrame);
    case LayerKind.se:
      session.seEntries.createSeEntryAtCurrentFrame(name: '', lengthFrames: 1);
    case LayerKind.instruction:
      session.instructionVerbs.createDefaultInstructionEventAtCurrentFrame();
    case LayerKind.folder:
    case LayerKind.adjustment:
      // Nothing to create on either row — a folder holds rows and an
      // adjustment holds effects; neither holds cels.
      break;
    case LayerKind.transition:
      // F-180 (유저 2026-09-25): 「타임라인패널(로컬)에서도 가능하도록」 — the
      // span is written on the global row by the storyboard's own verb; the
      // cut view only refuses where its projection already shows a mark.
      session.transitions.createTransitionSpanInCut();
    case LayerKind.animation || LayerKind.storyboard || LayerKind.image:
      session.createDrawingAtCurrentFrame();
  }
}

// `showSeNameTagEditor` opened a window to place and style the tag. It is
// gone (R5 #7): every control it held is a LANE on the SE row's Name Tag
// group now, and the placement it also did is that row's Position lane,
// which the canvas gizmo drags. A window duplicating the rail is a second
// place to change one thing.

/// Whether [showConvertActiveCutToLinked] has anywhere to go: a cut to
/// convert and at least one cut to borrow the pictures from.
bool canConvertActiveCutToLinked(EditorSessionManager session) =>
    session.activeCutOrNull != null &&
    session.cutVerbs.convertToLinkedCutCandidates.isNotEmpty;

/// Turns the active cut into a 겸용컷 of a chosen other cut — same
/// pictures, its own timing.
Future<void> showConvertActiveCutToLinked(
  BuildContext context,
  EditorSessionManager session,
) => askAboutThenCommit<Cut, CutId>(
  context,
  session.activeCutOrNull,
  dialog: (activeCut) => ConvertToLinkedCutDialog(
    activeCutName: activeCut.name,
    candidates: session.cutVerbs.convertToLinkedCutCandidates,
    previewOf: session.cutVerbs.convertToLinkedCutPreviewData,
  ),
  commit: session.cutVerbs.convertActiveCutToLinked,
);

/// Bakes the active cut's camera work as After Effects keyframe data on the
/// clipboard, one sample per frame; paste onto the canvas-sequence layer in
/// a camera-frame-sized comp.
void copyCameraAeKeyframes(BuildContext context, EditorSessionManager session) {
  final cut = session.activeCutOrNull;
  if (cut == null) {
    return; // Gap state: no camera work to bake.
  }
  final cameraSize = session.camera.cameraFrameSize;
  final text = buildAeTransformKeyframeData(
    framesPerSecond: session.projectSettings.projectFps,
    sourceWidth: cameraSize.width,
    sourceHeight: cameraSize.height,
    samples: bakeCameraAeSamples(
      camera: cut.camera,
      canvasSize: cut.canvasSize,
      frameCount: session.activeCutSpan.activeCutPlaybackFrameCount,
    ),
  );
  unawaited(Clipboard.setData(ClipboardData(text: text)));
  unawaited(
    showAppNotice(
      context,
      title: AppText.strings.commonNotice,
      message: AppText.strings.noticeCameraKeysCopied,
    ),
  );
}
