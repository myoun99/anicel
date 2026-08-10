/// How a cut's own frames relate to the transition spans that touch it.
///
/// The 撮ま! accounting the app follows puts the CONTE boundary at the
/// middle of an O.L, so a transition never moves a cut block and never
/// changes a total: `Cut.duration` is the conte 尺 and stays exactly as
/// authored. What a transition adds is MATERIAL — のりしろ — the frames a
/// cut has to draw outside its own conte length so the two ramps have
/// something to cross-fade.
///
/// Everything here is derived. Nothing in this file is stored.
library;

/// A transition span on the track's GLOBAL frame axis: `[start, end)`.
///
/// This is the shape [InstructionEvent] already has (a start key and a
/// frame count); the geometry takes plain numbers so the sheet, the
/// timeline and the compositor can all ask the same questions without
/// agreeing on a layer type first.
typedef TransitionSpan = ({int start, int length});

/// The frames a cut draws OUTSIDE its conte length, one side at a time.
class CutTransitionHandles {
  const CutTransitionHandles({required this.head, required this.tail});

  static const CutTransitionHandles none = CutTransitionHandles(
    head: 0,
    tail: 0,
  );

  /// Material before the cut's conte START — supplied because a span
  /// straddles that boundary and this cut is the INCOMING side of it.
  final int head;

  /// Material after the cut's conte END — this cut is the OUTGOING side.
  final int tail;

  bool get isEmpty => head == 0 && tail == 0;

  /// What the sheet prints in parentheses and how many rows it draws:
  /// `2+0 (2+12)`. The plain number stays [conteFrames].
  int drawnFrames(int conteFrames) => conteFrames + head + tail;

  @override
  bool operator ==(Object other) =>
      other is CutTransitionHandles && other.head == head && other.tail == tail;

  @override
  int get hashCode => Object.hash(head, tail);

  @override
  String toString() => 'CutTransitionHandles(head: $head, tail: $tail)';
}

/// Whether [span] fires at all for a cut occupying `[cutStart, cutEnd)`.
///
/// ★ The rule is geometric, which is the whole point of storing a span and
/// nothing else: it has to CROSS one of this cut's own boundaries. A span
/// that sits entirely inside the cut does nothing — no のりしろ, no
/// compositing, no mark ("컷 안에만 있으면 진짜 아무것도").
///
/// What is on the other side of the boundary is not asked. A neighbouring
/// cut and an empty gap are equally valid partners: a gap already plays as
/// black, so an O.L into one simply reads as a fade to black — which is
/// also how a cut at the very start of a project gets its のりしろ.
bool transitionSpanFires({
  required TransitionSpan span,
  required int cutStart,
  required int cutEnd,
}) {
  final spanEnd = span.start + span.length;
  final crossesStart = span.start < cutStart && spanEnd > cutStart;
  final crossesEnd = span.start < cutEnd && spanEnd > cutEnd;
  return crossesStart || crossesEnd;
}

/// The のりしろ a cut owes to every transition span that crosses one of its
/// boundaries.
///
/// A cut can be on both sides at once (an O.L into it and another out of
/// it), so the two sides are collected independently; when several spans
/// cross the same boundary the largest reach wins, since the material has
/// to satisfy all of them.
CutTransitionHandles cutTransitionHandles({
  required int cutStart,
  required int cutEnd,
  required Iterable<TransitionSpan> spans,
}) {
  var head = 0;
  var tail = 0;
  for (final span in spans) {
    final spanEnd = span.start + span.length;
    if (span.start < cutStart && spanEnd > cutStart) {
      final reach = cutStart - span.start;
      if (reach > head) {
        head = reach;
      }
    }
    if (span.start < cutEnd && spanEnd > cutEnd) {
      final reach = spanEnd - cutEnd;
      if (reach > tail) {
        tail = reach;
      }
    }
  }
  return CutTransitionHandles(head: head, tail: tail);
}

/// A cut's MEDIA range on the global axis: its conte range widened by the
/// のりしろ on each side.
///
/// ★ The conte range itself — the cut BLOCK — is untouched, and that is the
/// invariant the whole design rests on. Consumers that ask "which cut owns
/// this frame" keep reading the conte range and stay correct; only the
/// compositor, the sheet and the ruler widen to this one.
({int start, int end}) cutMediaRange({
  required int cutStart,
  required int cutEnd,
  required CutTransitionHandles handles,
}) => (start: cutStart - handles.head, end: cutEnd + handles.tail);

/// The alpha a cut's picture carries at [globalFrame] — 1 when nothing is
/// happening, ramping while a transition crosses one of its boundaries, and
/// 0 outside the frames it has material for.
///
/// ★ This is the whole compositing contract, and it is why an O.L needed no
/// new kind of effect. The span asks each side the SAME question and the
/// two answers are mirror images: the cut whose END is crossed fades out by
/// the progress, the cut whose START is crossed fades in by it. Play both
/// and you have a cross-dissolve; the pair IS the O.L. A lone F.I on a cut
/// with nothing before it runs through the identical code and simply has no
/// partner to cross with.
///
/// It is also what makes per-cut opacity possible at all. The old fade lived
/// on one lane per TRACK, so two cuts sharing a frame necessarily read the
/// same value; a function of (cut, frame) can hand them different ones.
double cutOpacityAt({
  required int cutStart,
  required int cutEnd,
  required Iterable<TransitionSpan> spans,
  required int globalFrame,
}) {
  final handles = cutTransitionHandles(
    cutStart: cutStart,
    cutEnd: cutEnd,
    spans: spans,
  );
  final media = cutMediaRange(
    cutStart: cutStart,
    cutEnd: cutEnd,
    handles: handles,
  );
  if (globalFrame < media.start || globalFrame >= media.end) {
    return 0;
  }

  var alpha = 1.0;
  for (final span in spans) {
    final progress = transitionProgressAt(span, globalFrame);
    if (progress == null) {
      continue;
    }
    final spanEnd = span.start + span.length;
    if (span.start < cutEnd && spanEnd > cutEnd) {
      alpha *= 1 - progress; // this cut is the outgoing side
    }
    if (span.start < cutStart && spanEnd > cutStart) {
      alpha *= progress; // …and the incoming side of the one before it
    }
  }
  return alpha;
}

/// How far a transition has progressed at [globalFrame], as 0 → 1 across
/// the span, or null when the frame is outside it.
///
/// This is the ramp both participating cuts read: the outgoing side fades
/// out by it and the incoming side fades in by it, over the SAME span —
/// which is what makes the pair an O.L rather than two separate fades.
/// It is computed, never keyed: the span's length is the only input.
/// ★ It reaches 1 ON the span's LAST frame, not one frame after it — the
/// canonical shape [trackFadeLengthsInWindow] already pins for the cut fade
/// ("the fade bottoms out ON the window's final frame"). So a 1+0 O.L is 24
/// frames that run from wholly the outgoing picture to wholly the incoming
/// one, inclusive, and the frame after the span is simply the new cut.
double? transitionProgressAt(TransitionSpan span, int globalFrame) {
  if (span.length <= 0) {
    return null;
  }
  final offset = globalFrame - span.start;
  if (offset < 0 || offset >= span.length) {
    return null;
  }
  if (span.length == 1) {
    // Degenerate: a one-frame transition is already over on its only frame.
    return 1;
  }
  return offset / (span.length - 1);
}
