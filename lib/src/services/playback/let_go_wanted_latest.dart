/// THE ORDER A BUDGET LETS GO BY — playback's caches, each over its own
/// entries: the ones wanted LATEST first ([wantedAt]: how many steps on an
/// entry is next shown, null where no step shows it), the least recently
/// used among equals, until what is held ([heldBytes], less each entry's
/// [bytesOf] as it goes) is at or under [maxBytes]. With [laterThan], never
/// one wanted that soon or sooner: a picture is made only by letting go of
/// pictures wanted after it. Answers whether it got under.
///
/// [entries] are the ones that MAY go — a screen's pinned pictures are not
/// handed over at all: evicting one frees nothing (the holder's clone shares
/// the pixels) and puts the very picture on screen back on the cold path.
///
/// 🚨ONE ORDER (the reverse of the frame demand's, which the warmer makes
/// pictures in): the composites and the canvas's layer images both let go
/// by it. The second cache to take it wrote it out again, and a law the
/// budget keeps in two copies is a law that can come to mean two things
/// (playback-plays-the-screen-material, 10-09).
///
/// ⛔Not for a cache no step wants anything of — a brush's tip masks: that
/// one is an `Lru` (`core/lru.dart`), this order with nothing wanted — the
/// least recently used first, never the newest — kept by its map, with no
/// sort. ↩️A sheet's images and the storyboard's panels were `Lru`s too;
/// they are held as the viewer's pages are since 10-30 (`ShownRasters` —
/// 유저 「붙잡는 곳 하나」), wanted by no step, so by this order.
bool letGoWantedLatest<E>({
  required Iterable<E> entries,
  required int heldBytes,
  required int maxBytes,
  required int? Function(E entry) wantedAt,
  required int Function(E entry) lastUsed,
  required int Function(E entry) bytesOf,
  required void Function(E entry) letGo,
  int? laterThan,
}) {
  var held = heldBytes;
  if (held <= maxBytes) {
    return true;
  }
  final ordered = [
    for (final entry in entries) (entry, wantedAt(entry) ?? _neverWanted),
  ]..sort((a, b) {
    final latestFirst = b.$2.compareTo(a.$2);
    return latestFirst != 0
        ? latestFirst
        : lastUsed(a.$1).compareTo(lastUsed(b.$1));
  });
  for (final (entry, wanted) in ordered) {
    if (held <= maxBytes) {
      break;
    }
    if (laterThan != null && wanted <= laterThan) {
      // Latest first: everything from here on is wanted sooner still.
      break;
    }
    held -= bytesOf(entry);
    letGo(entry);
  }
  return held <= maxBytes;
}

/// Wanted by no step at all — later than any.
const int _neverWanted = 1 << 62;
