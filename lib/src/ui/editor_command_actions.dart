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

import '../models/cut_id.dart';
import '../models/layer_kind.dart';
import 'dialogs/convert_to_linked_cut_dialog.dart';
import 'dialogs/se_name_tag_dialog.dart';
import 'editor_session_manager.dart';
import 'export/ae_keyframe_data.dart';

/// The kind-dispatched "make one here" verb: a drawing cel, a camera key,
/// an SE entry or an instruction event, whichever the active row holds. A
/// live selection wins — every selected cell gets one.
///
/// Shared rather than private to the timeline host because the toolbar
/// button is no longer its only entrance: [EditorActionIds.frameNewDrawing]
/// dispatches here too, and a custom rail slot will.
void createActiveInstance(EditorSessionManager session) {
  if (session.createInstancesForSelection()) {
    return;
  }
  final layer = session.activeLayer;
  if (layer == null) {
    return;
  }
  switch (layer.kind) {
    case LayerKind.camera:
      session.setCameraKeyframeAtCurrentFrame(session.cameraPoseAtCurrentFrame);
    case LayerKind.se:
      session.createSeEntryAtCurrentFrame(name: '', lengthFrames: 1);
    case LayerKind.instruction:
      session.createDefaultInstructionEventAtCurrentFrame();
    case LayerKind.folder:
    case LayerKind.adjustment:
      // Nothing to create on either row — a folder holds rows and an
      // adjustment holds effects; neither holds cels.
      break;
    // A text cel is born BLANK like a drawing cel (UI-R25 #2: creation
    // never opens a dialog) — double-tap types into it afterwards.
    case LayerKind.animation ||
        LayerKind.storyboard ||
        LayerKind.image ||
        LayerKind.text:
      session.createDrawingAtCurrentFrame();
  }
}

/// Places the active SE row's on-canvas name tag (R5b). The TEXT stays the
/// block's own name — this is placement and look.
Future<void> showSeNameTagEditor(
  BuildContext context,
  EditorSessionManager session,
) async {
  final layer = session.activeLayer;
  final defaultPosition = session.activeSeNameTagDefaultPosition;
  if (layer == null || defaultPosition == null) {
    return;
  }
  final result = await showDialog<SeNameTagDialogResult>(
    context: context,
    builder: (context) => SeNameTagDialog(
      storedTag: layer.seNameTag,
      defaultPosition: defaultPosition,
      rowName: layer.name,
    ),
  );
  if (!context.mounted || result == null) {
    return;
  }
  session.setActiveSeNameTag(result.tag);
}

/// Whether [showConvertActiveCutToLinked] has anywhere to go: a cut to
/// convert and at least one cut to borrow the pictures from.
bool canConvertActiveCutToLinked(EditorSessionManager session) =>
    session.activeCutOrNull != null &&
    session.convertToLinkedCutCandidates.isNotEmpty;

/// Turns the active cut into a 겸용컷 of a chosen other cut — same
/// pictures, its own timing.
Future<void> showConvertActiveCutToLinked(
  BuildContext context,
  EditorSessionManager session,
) async {
  final activeCut = session.activeCutOrNull;
  if (activeCut == null) {
    return;
  }
  final targetCutId = await showDialog<CutId>(
    context: context,
    builder: (context) => ConvertToLinkedCutDialog(
      activeCutName: activeCut.name,
      candidates: session.convertToLinkedCutCandidates,
      previewOf: session.convertToLinkedCutPreviewData,
    ),
  );
  if (!context.mounted || targetCutId == null) {
    return;
  }
  session.convertActiveCutToLinked(targetCutId);
}

/// Bakes the active cut's camera work as After Effects keyframe data on the
/// clipboard, one sample per frame; paste onto the canvas-sequence layer in
/// a camera-frame-sized comp.
void copyCameraAeKeyframes(BuildContext context, EditorSessionManager session) {
  final cut = session.activeCutOrNull;
  if (cut == null) {
    return; // Gap state: no camera work to bake.
  }
  final cameraSize = session.cameraFrameSize;
  final text = buildAeTransformKeyframeData(
    framesPerSecond: session.projectFps,
    sourceWidth: cameraSize.width,
    sourceHeight: cameraSize.height,
    samples: bakeCameraAeSamples(
      camera: cut.camera,
      canvasSize: cut.canvasSize,
      frameCount: session.activeCutPlaybackFrameCount,
    ),
  );
  unawaited(Clipboard.setData(ClipboardData(text: text)));
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(content: Text('Camera keyframes copied for After Effects.')),
  );
}
