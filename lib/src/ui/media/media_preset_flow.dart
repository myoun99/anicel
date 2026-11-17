import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../dialogs/dialog_verb.dart';
import '../editor_session_manager.dart';
import '../import/import_preview.dart';
import 'media_pool_pictures.dart';
import 'media_preset_window.dart';

/// Opens [asset]'s 배치 프리셋 window and writes what it answers into the
/// pool — the pool line's 「배치 프리셋…」 (asset-placement-presets Q6).
///
/// 🚨Start and end are the IMPORT WINDOW'S IN/OUT over the file
/// ([ImportPreview]): a preset's span is the span that window places
/// (`MediaPreset.inFrame`), counted as it counts — a movie on the project's
/// clock, a sound in project frames, a PDF and a GIF in pages. A strip of
/// its own would have been a second count of the same frames.
Future<void> editMediaPreset(
  BuildContext context,
  EditorSessionManager session,
  MediaAsset asset, {
  MediaPoolPictures? pictures,
}) async {
  final rate = session.projectSettings.projectFrameRate;
  final project = session.repository.requireProject();
  final answer = await showDialogVerb<MediaPresetAnswer>(
    context,
    (_) => MediaPresetWindow(
      asset: asset,
      canvas: session.activeCutOrNull?.canvasSize ?? project.cameraSize,
      picture: session.mediaPool.mediaFactsOf(asset.path)?.picture?.size,
      pictures: pictures,
      soundFrames: session.audioConformStore
          .heldPeaksFor(asset.path)
          ?.durationFrames(rate),
      spanEditor: (inFrame, outFrame, onChanged) => ImportPreview(
        session: session,
        path: asset.path,
        inFrame: inFrame,
        outFrame: outFrame,
        onRangeChanged: onChanged,
        rangeEditable: true,
        soundPeaks: session.audioConformStore.ensurePeaksFor,
        holdBytes: session.projectFile.holdMediaBytes,
        frameRate: rate,
        audioSpeed: project.audioSpeed,
      ),
    ),
  );
  if (answer == null) {
    return;
  }
  session.mediaPool.editMediaPreset(
    asset.path,
    name: answer.name,
    preset: answer.preset,
  );
}
