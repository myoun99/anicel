/// THE BLOCKS A BAND HOLDS, found again wherever an edit put them — so the
/// band follows them (F-619).
library;

import 'dart:math' as math;

import 'layer.dart';
import 'layer_id.dart';

/// A half-open span of frames, [start] to [endExclusive].
typedef FrameSpan = ({int start, int endExclusive});

/// Where the blocks a band held on one row stand among that row's blocks:
/// how many of the row's blocks come BEFORE the first of them, and how many
/// AFTER the last.
///
/// Counted from both ends because an edit acting on the band adds and takes
/// blocks only inside what it acts on: a retime moves blocks without
/// adding any, a "+" adds them at the edges of the runs the band holds, a
/// merge makes one of several. The blocks before the first and after the
/// last are the ones it leaves be — so their count finds the first and the
/// last again, where a start key would be lost the moment the first block
/// moves.
typedef HeldRun = ({int before, int after});

/// [layer]'s real drawing blocks — no ghosts, which a run's hold or repeat
/// derives — in frame order.
List<FrameSpan> _realBlocksOf(Layer layer) => [
  for (final entry in layer.timeline.entries)
    if (entry.value.isDrawing && !entry.value.ghost)
      (start: entry.key, endExclusive: entry.key + entry.value.length!),
];

/// Where the blocks starting at [starts] stand among [layer]'s blocks, or
/// null when [starts] names none of them.
HeldRun? heldRunOn(Layer layer, List<int> starts) {
  if (starts.isEmpty) {
    return null;
  }
  final blocks = _realBlocksOf(layer);
  final firstStart = starts.reduce(math.min);
  final lastStart = starts.reduce(math.max);
  final first = blocks.indexWhere((block) => block.start == firstStart);
  final last = blocks.indexWhere((block) => block.start == lastStart);
  if (first < 0 || last < first) {
    return null;
  }
  return (before: first, after: blocks.length - 1 - last);
}

/// The span from the first to the last of the blocks [held] names on
/// [layer] — or null when the row holds none of them any more.
FrameSpan? heldSpanOn(Layer layer, HeldRun held) {
  final blocks = _realBlocksOf(layer);
  final last = blocks.length - 1 - held.after;
  if (held.before >= blocks.length || last < held.before) {
    return null;
  }
  return (
    start: blocks[held.before].start,
    endExclusive: blocks[last].endExclusive,
  );
}

/// The band [band] moved as the blocks it held moved: its start by as far
/// as the first of them now begins from where it began ([was] → [now]),
/// its end by as far as the last of them now ends. A band reaching over
/// empty frames past its blocks keeps them, and an edit that moved nothing
/// leaves the band where it stood.
FrameSpan followedBand(
  FrameSpan band, {
  required FrameSpan was,
  required FrameSpan now,
}) {
  final start = math.max(0, band.start + now.start - was.start);
  return (
    start: start,
    endExclusive: math.max(
      start + 1,
      band.endExclusive + now.endExclusive - was.endExclusive,
    ),
  );
}

/// THE band an edit acting on it found — on whichever axis it was swept —
/// and where the blocks it held stand on each row, so the band can follow
/// them wherever the edit puts them.
///
/// 🗣️F-619 (유저 2026-11-18): 「프레임블록 선택하고 코마같은거
/// 일괄조작할때 선택범위ui 사각형이 제대로 안따라감 … 다른 경우 포함해서
/// 법 통일해서 따라가게. 뭐는 따라가고 뭐는 안따라가는거같은데」. ↩️The
/// comma buttons re-snapped the band's end and nothing else did: an edge
/// dragged inside the band, a "+" added to its runs and a merge of its
/// blocks left it where it stood — or let it go, when the edit moved a
/// cut with its conte row and the cut's refresh dropped the band before
/// the buttons could re-snap it.
///
/// Every edit acting on a band holds it when it begins and asks [follow]
/// when its blocks move — each step of a drag, and once committed — and a
/// drag let go of asks [restore].
final class HeldBand {
  HeldBand({
    required FrameSpan band,
    required Map<LayerId, HeldRun> rows,
    required int Function(LayerId id) behind,
    required Layer? Function(LayerId id) committed,
    required void Function(FrameSpan span) write,
  }) : _band = band,
       _rows = rows,
       _behind = behind,
       _committed = committed,
       _write = write,
       _was = _spanOf(rows, behind, committed, const {});

  final FrameSpan _band;
  final Map<LayerId, HeldRun> _rows;

  /// How far a row's keys run ahead of the band's axis: a track-owned row
  /// is keyed on its track while a cut's band counts from the cut.
  final int Function(LayerId id) _behind;

  /// The row as the document holds it now, in the keys [_rows] counts.
  final Layer? Function(LayerId id) _committed;

  /// Writes the band, on the axis it was held on.
  final void Function(FrameSpan span) _write;

  /// The held blocks' span as the edit found them.
  final FrameSpan? _was;

  /// The band put back as the edit found it — a drag let go of.
  void restore() => _write(_band);

  /// The band over the blocks it held: [edited] stands in for the rows an
  /// edit has not written yet (a drag's preview, in the rows' own keys),
  /// and the document answers for the rest. Where none of its blocks is
  /// left, the band stays as it was found.
  void follow([Map<LayerId, Layer> edited = const {}]) {
    final was = _was;
    final now = _spanOf(_rows, _behind, _committed, edited);
    _write(
      was == null || now == null
          ? _band
          : followedBand(_band, was: was, now: now),
    );
  }

  /// The span from the first held block to the last, across [rows], on
  /// the band's axis.
  static FrameSpan? _spanOf(
    Map<LayerId, HeldRun> rows,
    int Function(LayerId id) behind,
    Layer? Function(LayerId id) committed,
    Map<LayerId, Layer> edited,
  ) {
    FrameSpan? span;
    for (final MapEntry(key: id, value: held) in rows.entries) {
      final layer = edited[id] ?? committed(id);
      final row = layer == null ? null : heldSpanOn(layer, held);
      if (row == null) {
        continue;
      }
      final offset = behind(id);
      final start = row.start - offset;
      final end = row.endExclusive - offset;
      span = span == null
          ? (start: start, endExclusive: end)
          : (
              start: math.min(span.start, start),
              endExclusive: math.max(span.endExclusive, end),
            );
    }
    return span;
  }
}
