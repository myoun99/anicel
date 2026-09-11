/// What an IN/OUT pair keeps of a source [KeptSpan.new]'s `length` frames
/// (or pages) long: IN clamped into the source, OUT — null for the last —
/// clamped between IN and the last.
///
/// 🚨ONE answer for every trimmed source: a GIF's or a sequence's frames, a
/// PDF's pages, a sound's frames, the export's axis — what it runs, what
/// its label says and what its scrub bar marks — a cut's exported range,
/// and the import window's picture of what a sound keeps. It was seven
/// hand-written copies of this clamp, spelled three ways, and two of them
/// (the export's label and its bar) did not clamp at all: ends typed past
/// the axis read one span there and ran another. The preview's sound was
/// about to be the eighth. `test/architecture/one_kept_span_test.dart`
/// keeps it one.
final class KeptSpan {
  /// [length] is at least 1: every caller has a source to trim.
  factory KeptSpan({required int length, int? inFrame, int? outFrame}) {
    assert(length >= 1, 'a span of nothing');
    final last = length - 1;
    final first = (inFrame ?? 0).clamp(0, last);
    return KeptSpan._(first, (outFrame ?? last).clamp(first, last));
  }

  const KeptSpan._(this.first, this.last);

  final int first;
  final int last;

  /// How many frames the span keeps.
  int get count => last - first + 1;
}
