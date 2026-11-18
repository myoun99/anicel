import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../../models/movie_clock.dart' show ProjectClock;
import '../../services/media/media_facts.dart' show placedPicturesOf;
import '../../services/media/media_preset_sync.dart';
import '../dialogs/dialog_verb.dart';
import '../editor_session_manager.dart';
import '../text/place_lines.dart' show mediaAssetUseLine;
import 'media_pool_words.dart';
import 'media_sync_window.dart';

/// The project's clock as [session] holds it now.
ProjectClock _clockOf(EditorSessionManager session) => (
  rate: session.projectSettings.projectFrameRate,
  speed: session.repository.requireProject().audioSpeed,
);

/// The lengths [asset]'s preset is counted from, as far as [session] has
/// them in hand — never waiting for one: its sound's where its conform is
/// held, its pictures' where the pool has read what it needs
/// ([placedPicturesOf]). The pool's in-use mark and the sync window count
/// from these alike, so the mark turns into the sync on what the window
/// then shows.
MediaSyncLengths syncLengthsOf(
  EditorSessionManager session,
  MediaAsset asset,
) {
  final clock = _clockOf(session);
  return (
    sound: session.audioConformStore
        .heldPeaksFor(asset.path)
        ?.durationFrames(clock.rate),
    pictures: placedPicturesOf(
      asset,
      session.mediaPool.mediaFactsOf(asset.path)?.picture,
      clock,
    ),
  );
}

/// Opens the sync window over [asset]'s places and sets what it answers —
/// the pool line's in-use mark when a place parts from the file's preset
/// ([partsFromItsPreset]). ONE undo step.
Future<void> syncMediaPlaces(
  BuildContext context,
  EditorSessionManager session,
  MediaAsset asset,
) async {
  final places = syncPlacesOf(
    session.repository.requireProject(),
    asset,
    lengths: syncLengthsOf(session, asset),
  );
  final answer = await showDialogVerb<MediaSyncAnswer>(
    context,
    (_) => MediaSyncWindow(
      asset: asset,
      places: places,
      placeLines: [
        for (final place in places)
          mediaAssetUseLine(place.use, framePlace: session.framePlaceLabel),
      ],
      words: MediaPoolWords(clock: _clockOf(session)),
    ),
  );
  if (answer == null) {
    return;
  }
  session.mediaPool.syncPlaces(
    asset.path,
    fields: answer.fields,
    places: answer.places,
  );
}
