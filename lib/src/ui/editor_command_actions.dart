/// Editor commands that need more than a session call to run — a dialog to
/// answer, the clipboard to fill, a snackbar to raise.
///
/// A plain session verb can be handed to any surface as a tear-off, so the
/// menu bar and the timeline offer the same command by naming the same
/// method. These three could not: the flow around the session call lived
/// inside the menu bar as private methods, and the only way to offer them
/// anywhere else was to write the flow again. They live here instead, so
/// the second entrance costs one call and the flow has one author.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/cut_id.dart';
import 'dialogs/convert_to_linked_cut_dialog.dart';
import 'dialogs/se_name_tag_dialog.dart';
import 'editor_session_manager.dart';
import 'export/ae_keyframe_data.dart';

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
