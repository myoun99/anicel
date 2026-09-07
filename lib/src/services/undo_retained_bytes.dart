import '../models/bitmap_surface.dart';

/// WHAT AN UNDO ENTRY WEIGHS. One law, one implementation.
///
/// Five commands each answered this question their own way and three of
/// them answered it wrong: a stroke counted its pre-image twice, a
/// selection move counted the STAMP rectangle (which has nothing to do
/// with what it holds — 2048× under a 64×64 stamp, and zero when the
/// stamp was null), and a composite counted nothing at all. The byte
/// budget therefore never fired: measured 2026-09-07, the only bound on
/// undo pixels was the entry count, and 200 entries of full-canvas
/// transforms is 12.5 GiB.
///
/// [BitmapSurface] is an immutable tile map with structural sharing: a
/// snapshot and the live surface hold the SAME tile objects wherever the
/// edit did not reach. Those tiles cost the history stack nothing — the
/// live surface keeps them alive on its own. Only the tiles the live
/// surface no longer holds are this entry's to pay for.
///
/// ⛔Counting the whole snapshot instead is not "conservative", it is
/// wrong in the expensive direction: one large top-left grow (which
/// shares every tile) once evicted the entire real undo history with
/// phantom bytes — that is why the resize command already counted this
/// way, and why the rest now do too.
int uniquelyRetainedTileBytes(BitmapSurface snapshot, BitmapSurface? live) {
  final liveTiles = Set<Object>.identity();
  if (live != null) {
    liveTiles.addAll(live.tiles.values);
  }
  var uniqueTiles = 0;
  for (final tile in snapshot.tiles.values) {
    if (!liveTiles.contains(tile)) {
      uniqueTiles += 1;
    }
  }
  return uniqueTiles * snapshot.tileBytes;
}
