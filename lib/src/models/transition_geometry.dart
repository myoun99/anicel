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

import 'camera_instruction.dart' show CameraInstructionMarkType;

/// A transition span on the track's GLOBAL frame axis: `[start, end)`, plus
/// WHICH transition it is.
///
/// This is the shape [InstructionEvent] already has (a start key and a frame
/// count) with the term's mark carried alongside; the geometry takes plain
/// values so the sheet, the timeline and the compositor can all ask the same
/// questions without agreeing on a layer type first.
///
/// 🚨[mark] is load-bearing, not decoration: an O.L moves BOTH cuts and an
/// F.I/F.O moves only its own (user 2026-08-11 — 「자기컷일때만 발동」). Dropping
/// it — which the span reader did — made every span a symmetric cross-dissolve,
/// so placing an F.O produced an O.L.
typedef TransitionSpan = ({
  int start,
  int length,
  CameraInstructionMarkType mark,
});

/// How many cuts a span's ramp touches.
///
/// ★Read off [CameraInstructionMarkType] rather than a new stored flag: the
/// glyph a term wears ALREADY says this. The bowtie is two cuts crossing; a
/// wedge is one screen clearing or covering. One handle, and the vocabulary
/// stays as editable as it was.
enum TransitionSides {
  /// O.L: the cut whose end is crossed fades out while the cut whose start is
  /// crossed fades in, over one span. The pair IS the cross-dissolve.
  both,

  /// F.O: this cut's own alpha falls to nothing. Nothing rises to meet it, so
  /// what shows through is whatever is below — the backdrop, which is black.
  fadesOut,

  /// F.I: the mirror.
  fadesIn,
}

/// Whether a ONE-SIDED span belongs to the cut `[cutStart, cutEnd)`.
///
/// 🚨"Overlaps this cut" is the wrong test and was my first answer: a straddling
/// F.O overlaps the NEXT cut too, and using overlap faded that one out as well —
/// the very coupling the sidedness exists to remove.
///
/// The anchor is where the ramp's MEANING lands. An F.O runs 1 → 0, which reads
/// as "this picture leaves", and the picture leaving is the one on screen when
/// the fade STARTS. An F.I runs 0 → 1 — "this picture arrives" — and the one
/// arriving is on screen when the fade ENDS. So the two are mirror images about
/// the span, exactly as their ramps are: first frame for out, last for in.
bool oneSidedSpanOwnsCut({
  required TransitionSpan span,
  required int cutStart,
  required int cutEnd,
}) {
  if (span.length <= 0) {
    return false;
  }
  final anchor = switch (transitionSidesOf(span.mark)) {
    TransitionSides.fadesOut => span.start,
    TransitionSides.fadesIn => span.start + span.length - 1,
    // Two-sided spans do not answer this question.
    TransitionSides.both => null,
  };
  return anchor != null && anchor >= cutStart && anchor < cutEnd;
}

TransitionSides transitionSidesOf(CameraInstructionMarkType mark) =>
    switch (mark) {
      CameraInstructionMarkType.ol => TransitionSides.both,
      CameraInstructionMarkType.fo => TransitionSides.fadesOut,
      CameraInstructionMarkType.fi => TransitionSides.fadesIn,
      // A `bar` term is camera work, not a 場面転換, and never reaches the
      // transition row ([cameraInstructionIsTransition]). Treated as two-sided
      // so a hand-edited file cannot make it silently invisible.
      CameraInstructionMarkType.bar => TransitionSides.both,
    };

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
  if (transitionSidesOf(span.mark) != TransitionSides.both) {
    // 🚨A ONE-SIDED span needs no partner, so it needs no boundary — it fires
    // for the cut it BELONGS to, straddling or not. Requiring a straddle is the
    // O.L rule, and applied to an F.O it is actively wrong: an F.O sitting
    // inside its own cut is where it belongs and used to do nothing at all.
    return oneSidedSpanOwnsCut(
      span: span,
      cutStart: cutStart,
      cutEnd: cutEnd,
    );
  }
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
    final sides = transitionSidesOf(span.mark);
    final spanEnd = span.start + span.length;
    // A one-sided span only owes material to the cut it BELONGS to, and only on
    // the side its own ramp reaches past: an F.O overhanging this cut's end is
    // this cut fading out, and the cut after it takes no part, so it draws no
    // のりしろ for it. (A two-sided O.L asks both questions, as it always did.)
    final owns =
        sides == TransitionSides.both ||
        oneSidedSpanOwnsCut(span: span, cutStart: cutStart, cutEnd: cutEnd);
    if (!owns) {
      continue;
    }
    if (sides != TransitionSides.fadesOut &&
        span.start < cutStart &&
        spanEnd > cutStart) {
      final reach = cutStart - span.start;
      if (reach > head) {
        head = reach;
      }
    }
    if (sides != TransitionSides.fadesIn &&
        span.start < cutEnd &&
        spanEnd > cutEnd) {
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

/// Where a span's mark is DRAWN inside one cut's local timeline, or null
/// when the span does not fire for this cut.
///
/// 🚨 This is a PROJECTION, not a window, and the difference is the whole
/// rule: a windowed span would show each cut the half that overlaps it,
/// and half a bowtie tells an animator nothing. Both sides see the mark at
/// its FULL length — the outgoing cut at its tail, overhanging its own end
/// by the のりしろ; the incoming cut at its head, starting at local 0.
///
/// So the global row and a cut's row deliberately disagree about where the
/// mark sits, and that is the design ("글로벌↔로컬은 다르게 그린다"). The
/// global row is the one that is edited; a cut's row is for reading, and
/// what it has to say is "a 1+0 O.L happens at this end of you".
({int start, int length})? transitionMarkInCut({
  required TransitionSpan span,
  required int cutStart,
  required int cutEnd,
}) {
  if (!transitionSpanFires(span: span, cutStart: cutStart, cutEnd: cutEnd)) {
    return null;
  }
  final localStart = span.start - cutStart;
  // Negative means the span opened before this cut did — the incoming side.
  // Pull the whole mark to the head rather than clipping off its front.
  return (start: localStart < 0 ? 0 : localStart, length: span.length);
}

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
  return cutTransitionRampAt(
    cutStart: cutStart,
    cutEnd: cutEnd,
    spans: spans,
    globalFrame: globalFrame,
  );
}

/// The RAMP half of [cutOpacityAt], without the material clamp: 1 wherever
/// no span covers [globalFrame], thinning only while a transition actually
/// crosses one of this cut's boundaries.
///
/// 🚨Two questions live in [cutOpacityAt] and only one of them is about
/// compositing MATERIAL. "0 outside the frames it has material for" is the
/// compositor's term: a playlist must not draw a picture where the cut has
/// nothing to show. The EDITING canvas asks the other question — how thin
/// does the transition make the frame I am STANDING on — and standing is
/// not compositing. The playhead is unclamped (T12: 컷 길이는 소재와 관계가
/// 없다 — past the end line is ordinary space), so feeding it the material
/// term turned every frame past the media end into an opaque backdrop wash:
/// the canvas "abandoned the paper" exactly the way the unclamped `isGap`
/// term did, one law over.
double cutTransitionRampAt({
  required int cutStart,
  required int cutEnd,
  required Iterable<TransitionSpan> spans,
  required int globalFrame,
}) {
  var alpha = 1.0;
  for (final span in spans) {
    final progress = transitionProgressAt(span, globalFrame);
    if (progress == null) {
      continue;
    }
    final spanEnd = span.start + span.length;
    switch (transitionSidesOf(span.mark)) {
      case TransitionSides.both:
        // O.L: the span asks each side the SAME question and the two answers
        // are mirror images. Play both and you have the cross-dissolve.
        if (span.start < cutEnd && spanEnd > cutEnd) {
          alpha *= 1 - progress; // this cut is the outgoing side
        }
        if (span.start < cutStart && spanEnd > cutStart) {
          alpha *= progress; // …and the incoming side of the one before it
        }
      case TransitionSides.fadesOut:
        // F.O: only the cut this span BELONGS to moves. No mirror term, so
        // nothing rises to meet it — the picture falls to whatever is below,
        // which is black.
        if (oneSidedSpanOwnsCut(
          span: span,
          cutStart: cutStart,
          cutEnd: cutEnd,
        )) {
          alpha *= 1 - progress;
        }
      case TransitionSides.fadesIn:
        if (oneSidedSpanOwnsCut(
          span: span,
          cutStart: cutStart,
          cutEnd: cutEnd,
        )) {
          alpha *= progress;
        }
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
