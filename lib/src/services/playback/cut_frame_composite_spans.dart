import '../../models/cut.dart';
import '../../models/playback_quality.dart';
import 'cut_frame_composite_signature.dart';

/// A run of consecutive frames whose composited picture is one picture.
///
/// Every frame in `[start, endExclusive)` computes the SAME
/// [CutFrameCompositeSignature], so one composite image serves the whole
/// run — this is the unit the composite cache actually stores (today it
/// stores per-frame keys that all point at one deduplicated image; the
/// span makes that identity first-class).
class CutFrameCompositeSpan {
  const CutFrameCompositeSpan({
    required this.start,
    required this.endExclusive,
    required this.signature,
  }) : assert(endExclusive > start);

  /// First frame of the run (inclusive).
  final int start;

  /// One past the last frame of the run.
  final int endExclusive;

  /// The one identity every frame in the run shares. A run past the
  /// authored content has EMPTY [CutFrameCompositeSignature.nodes] — there
  /// is nothing to compose, which readers like the readiness bar treat as
  /// "nothing to prepare = ready by definition".
  final CutFrameCompositeSignature signature;

  int get length => endExclusive - start;

  bool contains(int frameIndex) =>
      frameIndex >= start && frameIndex < endExclusive;

  @override
  String toString() =>
      'CutFrameCompositeSpan([$start, $endExclusive), $signature)';
}

/// Cuts `[0, frameCount)` into maximal runs of frames that share one
/// composite signature.
///
/// ★Spans are DISCOVERED by signature comparison, never claimed from
/// track keyframes: a `PropertyTrack.keys` union would be a second
/// implementation of "what does this frame show" and would silently
/// diverge from the pose/exposure resolution the signature already rides
/// ([computeCutFrameCompositeSignature] and the compose loop share one
/// visit by construction — this function inherits that agreement for
/// free).
///
/// Pure and unmemoized on purpose: the caller owns the invalidation
/// signal, so the caller owns the memo. ⚠️Consumers that ask per cell
/// (the storyboard asks across 1500 cuts) MUST memoize the returned
/// table rather than calling this in a paint path.
///
/// [frameCount] is the caller's law for how many frames the cut spans —
/// this function deliberately does not derive one from the cut's
/// contents, because cut length is unrelated to what material it holds.
List<CutFrameCompositeSpan> computeCutFrameCompositeSpans({
  required Cut cut,
  required int frameCount,
  required PlaybackQuality quality,
  required BrushFrameRevisionResolver revisionOf,
}) {
  final spans = <CutFrameCompositeSpan>[];
  CutFrameCompositeSignature? current;
  var start = 0;
  for (var frameIndex = 0; frameIndex < frameCount; frameIndex++) {
    final signature = computeCutFrameCompositeSignature(
      cut: cut,
      frameIndex: frameIndex,
      quality: quality,
      revisionOf: revisionOf,
    );
    if (current == null) {
      current = signature;
      start = frameIndex;
      continue;
    }
    if (signature == current) {
      continue;
    }
    spans.add(
      CutFrameCompositeSpan(
        start: start,
        endExclusive: frameIndex,
        signature: current,
      ),
    );
    current = signature;
    start = frameIndex;
  }
  if (current != null) {
    spans.add(
      CutFrameCompositeSpan(
        start: start,
        endExclusive: frameCount,
        signature: current,
      ),
    );
  }
  return spans;
}
