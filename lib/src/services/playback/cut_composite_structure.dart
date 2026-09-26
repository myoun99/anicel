import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/cut.dart';
import '../../models/cut_warm_extent.dart';
import '../../models/frame_id.dart';
import '../../models/layer_id.dart';
import '../../models/playback_quality.dart';
import 'cut_frame_composite_signature.dart';
import 'cut_frame_composite_spans.dart';

/// [cut]'s frames in `[start, end)` as spans that each composite to ONE
/// tree, clipped to the range — named by their STRUCTURE: the composite
/// signature with every source revision read as 0, at one fixed quality.
///
/// Why structure and not the signature itself: a stroke moves revisions,
/// never where one picture ends and the next begins. Frames with the same
/// structure show the same cels, so they share one full signature too —
/// whoever needs that asks once per span, not once per frame.
///
/// ★Why this exists (I-22, measured 2026-09-26 on the device): the rulers
/// asked readiness PER FRAME, and zoomed out to ten minutes a window is
/// ~15,000 frames — 94% of a playback tick went to resolving those trees
/// one frame at a time. A held drawing is one span however long it holds,
/// and every frame past the cut's authored extent composes to nothing
/// ([cutAuthoredExtent]), so the tail is ONE span whatever its length.
///
/// Memoized per cut INSTANCE, held weakly (models are immutable — an edit
/// is a new cut, so the instance is the whole invalidation story), and
/// discovered lazily in chunks of [_chunkFrames] so a query costs about the
/// frames it asks for, not the whole cut.
List<CutFrameCompositeSpan> compositeStructureSpansIn(
  Cut cut, {
  required int start,
  required int end,
}) => (_tables[cut] ??= _StructureTable(cut)).spansIn(math.max(0, start), end);

/// How many frames the structure tables have resolved so far — the work a
/// span table exists to save, read by the tests that pin it.
@visibleForTesting
int get debugCompositeStructureFramesResolved => _framesResolved;

int _framesResolved = 0;

/// Frames per lazily discovered chunk.
const int _chunkFrames = 64;

/// The quality structure is read at — any one serves: quality rides the
/// signature as a field, never the tree.
const PlaybackQuality _structureQuality = PlaybackQuality.full;

int _noRevision(LayerId layerId, FrameId frameId) => 0;

final Expando<_StructureTable> _tables = Expando<_StructureTable>(
  'compositeStructureSpans',
);

class _StructureTable {
  _StructureTable(this.cut) : _extent = cutAuthoredExtent(cut) {
    assert(
      computeCutFrameCompositeSignature(
        cut: cut,
        frameIndex: _extent,
        quality: _structureQuality,
        revisionOf: _noRevision,
      ).nodes.isEmpty,
      'past the authored extent every frame must compose to nothing — a row '
      'that paints without a covering block breaks the one-span tail',
    );
  }

  final Cut cut;

  /// Where the cut's drawings end: from here on every frame is [_nothing].
  final int _extent;

  final Map<int, List<CutFrameCompositeSpan>> _chunks = {};

  late final CutFrameCompositeSignature _nothing = CutFrameCompositeSignature(
    canvasSize: cut.canvasSize,
    quality: _structureQuality,
    nodes: const [],
  );

  List<CutFrameCompositeSpan> _chunk(int index) =>
      _chunks[index] ??= _discover(index);

  List<CutFrameCompositeSpan> _discover(int index) {
    final from = index * _chunkFrames;
    final to = math.min(from + _chunkFrames, _extent);
    _framesResolved += to - from;
    return computeCutFrameCompositeSpans(
      cut: cut,
      startFrame: from,
      frameCount: to,
      quality: _structureQuality,
      revisionOf: _noRevision,
    );
  }

  List<CutFrameCompositeSpan> spansIn(int start, int end) {
    final spans = <CutFrameCompositeSpan>[];
    // Joins [from, to) onto the last span when it continues it — a chunk
    // seam or the tail meeting a last stretch that already shows nothing.
    void add(int from, int to, CutFrameCompositeSignature structure) {
      final clippedFrom = math.max(from, start);
      final clippedTo = math.min(to, end);
      if (clippedFrom >= clippedTo) {
        return;
      }
      final last = spans.isEmpty ? null : spans.last;
      if (last != null &&
          last.endExclusive == clippedFrom &&
          last.signature == structure) {
        spans.last = CutFrameCompositeSpan(
          start: last.start,
          endExclusive: clippedTo,
          signature: structure,
        );
        return;
      }
      spans.add(
        CutFrameCompositeSpan(
          start: clippedFrom,
          endExclusive: clippedTo,
          signature: structure,
        ),
      );
    }

    final drawnEnd = math.min(end, _extent);
    for (
      var index = start ~/ _chunkFrames;
      index * _chunkFrames < drawnEnd;
      index += 1
    ) {
      for (final span in _chunk(index)) {
        add(span.start, span.endExclusive, span.signature);
      }
    }
    add(_extent, end, _nothing);
    return spans;
  }
}
