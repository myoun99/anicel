import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../../services/media/media_preset_sync.dart';
import '../dialogs/dialog_verb.dart';
import '../editor_session_manager.dart';
import '../text/place_lines.dart' show mediaAssetUseLine;
import 'media_pool_words.dart';
import 'media_sync_window.dart';

/// Opens the sync window over [asset]'s sound places and sets what it
/// answers — the pool line's in-use mark when a place parts from the
/// file's preset ([soundPartsFromItsPreset]). ONE undo step.
///
/// The sound's length is the one the pool already holds — the mark turned
/// into the sync on it, so it is held here too.
Future<void> syncMediaPlaces(
  BuildContext context,
  EditorSessionManager session,
  MediaAsset asset,
) async {
  final rate = session.projectSettings.projectFrameRate;
  final preset = soundPresetOf(
    asset,
    soundFrames: session.audioConformStore
        .heldPeaksFor(asset.path)
        ?.durationFrames(rate),
  );
  final places = soundPlacesOf(
    session.repository.requireProject(),
    asset.path,
  );
  final answer = await showDialogVerb<MediaSyncAnswer>(
    context,
    (_) => MediaSyncWindow(
      asset: asset,
      preset: preset,
      places: places,
      placeLines: [
        for (final place in places)
          mediaAssetUseLine(place.use, framePlace: session.framePlaceLabel),
      ],
      words: MediaPoolWords(
        clock: (
          rate: rate,
          speed: session.repository.requireProject().audioSpeed,
        ),
      ),
    ),
  );
  if (answer == null) {
    return;
  }
  session.mediaPool.syncSoundPlaces(
    asset.path,
    preset: preset,
    fields: answer.fields,
    places: answer.places,
  );
}
