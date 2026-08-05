/// THE flip's step: one column, left or right.
///
/// A flip axis is made of COLUMNS. A block that covers frames is one
/// column however long it holds; a frame no block covers is a column of
/// its own. That single definition is what makes the two directions
/// symmetric and what lets empty space be travelled through rather than
/// jumped over — the old rule stepped between authored KEYS, so an
/// uncovered frame did not exist as a destination and the two directions
/// disagreed about it.
///
/// The axis's material is a parameter, because the app has two of them
/// and they are the same shape:
///
/// * inside a cut — the columns are a layer's drawing blocks, and the
///   frames between them;
/// * in a track GAP — the columns are the track's cuts, and the global
///   frames between them.
///
/// Costs two coverage lookups per step and allocates nothing: the column
/// list is never materialised.
library;

/// A block covering `[start, endExclusive)` on the flip axis.
typedef FlipColumn = ({int start, int endExclusive});

/// What covers [frame], or null when nothing does.
typedef FlipColumnAt = FlipColumn? Function(int frame);

/// The frame one column [direction] away from [frame].
///
/// Landing on a column always means landing on its START, which is why a
/// step from mid-hold moves by one column rather than crawling: the hold
/// belongs to its block's column, not to columns of its own.
///
/// UNBOUNDED on purpose, in both directions. Rightward there is nothing
/// to stop at — running out of blocks, or out of the cut, is not the axis
/// ending — and leftward the only real floor is the start of the film,
/// which is a fact about the film and not about columns. Callers clamp
/// (and translate a result that has left their own range) because only
/// they know which axis they were counting on.
int flipColumnStep({
  required int frame,
  required int direction,
  required FlipColumnAt columnAt,
}) {
  if (direction == 0) {
    return frame;
  }
  final covering = columnAt(frame);
  if (direction > 0) {
    // The next column starts where this one ends.
    return covering == null ? frame + 1 : covering.endExclusive;
  }
  // Leftward, the column we are IN is the one to leave — starting from
  // its own start, not from wherever inside it the cursor sits, so a
  // step out of a four-frame hold is one step and not four.
  final previous = (covering?.start ?? frame) - 1;
  return columnAt(previous)?.start ?? previous;
}
