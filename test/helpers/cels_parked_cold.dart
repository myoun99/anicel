import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';

/// [cels] parked in [store] as a cooled cel is parked: each encoded to the
/// blob it cools into, held in RAM, cold until it is read
/// ([BrushFrameStore.restoreBaked]). Answers the blobs.
///
/// ⚠️Like the store's own entrance it replaces the WHOLE store, so every
/// cel a test parks goes in one call — behind [pasteboardReach], the wall
/// of the project they are parked for.
///
/// ★One spelling for every test that parks a cel
/// (`test/architecture/a_test_keeps_a_cel_through_one_helper_test.dart`).
Map<BrushFrameKey, AnicelCelBlob> parkCold(
  BrushFrameStore store,
  Map<BrushFrameKey, BitmapSurface> cels, {
  PasteboardReach pasteboardReach = PasteboardReach.whole,
}) {
  final blobs = {
    for (final MapEntry(:key, value: surface) in cels.entries)
      key: coldBlobOf(key, surface),
  };
  store.restoreBaked(blobs, pasteboardReach: pasteboardReach);
  return blobs;
}

/// The blob [surface] cools into as the cel [key] — what [parkCold] parks,
/// and what a cel kept in a file holds (`keepInAFile`).
AnicelCelBlob coldBlobOf(BrushFrameKey key, BitmapSurface surface) =>
    AnicelCelBlob.encode(AnicelCelEntry.fromSurface(key, surface));
