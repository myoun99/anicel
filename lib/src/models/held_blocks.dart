/// THE BLOCKS A BAND HOLDS, found again wherever an edit put them — so the
/// band follows them (F-619).
library;

import 'dart:math' as math;

import 'frame_id.dart';
import 'layer.dart';
import 'layer_id.dart';
import 'timeline_coverage.dart' show TimelineDrawingBlock, drawingBlocks;
import 'timeline_repeat.dart' show ghostFreeTimeline;

/// A half-open span of frames, [start] to [endExclusive].
typedef FrameSpan = ({int start, int endExclusive});

/// The blocks a band held on one row: how many of the row's blocks came
/// BEFORE the first of them and how many AFTER the last, and the drawing
/// each of the row's blocks showed, in frame order, when they were held.
///
/// Found again by the drawings the row's blocks show ([_keptAt]) — a start
/// key is lost the moment a block moves — and two ways, because an edit
/// either acts on the band's blocks or leaves them be:
/// - [heldSpanOn], for an edit ACTING on the band. It makes and unmakes
///   blocks inside what it acts on — a "+" adds them at the edges of the
///   runs the band holds, a merge makes one of several — so the band holds
///   everything between the blocks around it that the edit kept.
/// - [keptSpanOn], for an edit BESIDE the band. It pushes the band's blocks,
///   or adds or takes blocks around them, and leaves the blocks themselves
///   be — so the band holds what is left of them.
///
/// ⚠️Which one is the edit's to say, never the row's: a "+" at the end of
/// the run in front of the band and a "+" at the head of the band's own
/// first run leave the same row — new blocks between the two runs — and
/// only the second adds them to what the band holds.
///
/// ↩️The acting edit counted the blocks before the first and after the
/// last, which an edit acting on the band was taken to leave be. A lead
/// edge of the band's last block pulled back past it takes them: it sweeps
/// the blocks behind it away (I-179), the block in front following it, and
/// the count of those behind found none of the band's — the band stayed
/// where it was swept, short of the block grown under it (🧪measured
/// 2026-11-19: on ones, a band over 1–2 and the lead edge of 2 pulled back
/// two left the band at 1–3 over a block reaching 1–4).
typedef HeldRun = ({int before, int after, List<FrameId> drawings});

/// [layer]'s real blocks — not the ghosts a run's hold or repeat derives —
/// in frame order.
List<TimelineDrawingBlock> _realBlocksOf(Layer layer) =>
    drawingBlocks(ghostFreeTimeline(layer));

/// Where the blocks starting at [starts] — in frame order, as a band's
/// collectors read them off the timeline — stand among [layer]'s blocks,
/// or null when [starts] names none of them.
HeldRun? heldRunOn(Layer layer, List<int> starts) {
  if (starts.isEmpty) {
    return null;
  }
  final blocks = _realBlocksOf(layer);
  final keys = [for (final block in blocks) block.startIndex];
  final first = keys.indexOf(starts.first);
  final last = keys.indexOf(starts.last);
  return first < 0 || last < first
      ? null
      : (
          before: first,
          after: keys.length - 1 - last,
          drawings: [for (final block in blocks) block.frameId],
        );
}

/// The span of what [layer] holds between the blocks around those [held]
/// names that it still has — the nearest before them and the nearest after
/// — for an edit acting on them; null when nothing stands between.
FrameSpan? heldSpanOn(Layer layer, HeldRun held) =>
    _spanOn(layer, held, (at, count) {
      final before = [for (var i = 0; i < held.before; i += 1) ?at[i]];
      final after = [
        for (var i = at.length - held.after; i < at.length; i += 1) ?at[i],
      ];
      final first = before.isEmpty ? 0 : before.last + 1;
      final last = after.isEmpty ? count - 1 : after.first - 1;
      return last < first ? null : (first, last);
    });

/// The span from the first to the last of the blocks [held] names that
/// [layer] still has, found by the drawings they show — an edit beside
/// them — or null when the row has none of them any more.
FrameSpan? keptSpanOn(Layer layer, HeldRun held) =>
    _spanOn(layer, held, (at, _) {
      final kept = [
        for (var i = held.before; i < at.length - held.after; i += 1) ?at[i],
      ];
      return kept.isEmpty ? null : (kept.first, kept.last);
    });

/// The span over [layer]'s blocks from the first to the last that [pick]
/// names — by their indices on the row — out of where each of [held]'s
/// blocks stands on it now ([_keptAt]) and how many blocks it has; null
/// when [pick] names none.
FrameSpan? _spanOn(
  Layer layer,
  HeldRun held,
  (int, int)? Function(List<int?> at, int count) pick,
) {
  final blocks = _realBlocksOf(layer);
  final picked = pick(
    _keptAt(held.drawings, [for (final block in blocks) block.frameId]),
    blocks.length,
  );
  if (picked == null) {
    return null;
  }
  final (first, last) = picked;
  return (
    start: blocks[first].startIndex,
    endExclusive: blocks[last].endIndexExclusive,
  );
}

/// Where each of [was]'s blocks stands in [now] — its index there — by the
/// drawing it shows: the longest run of drawings both rows show in the
/// same order, which is what an edit left be. Null for a block [now] has
/// no more.
///
/// The ends the two rows share are matched first, one block at a time: an
/// edit reaches a stretch of a row, so what is left between them is short,
/// and only that is weighed whole ([_matchBetween]).
List<int?> _keptAt(List<FrameId> was, List<FrameId> now) {
  final at = List<int?>.filled(was.length, null);
  var head = 0;
  while (head < was.length && head < now.length && was[head] == now[head]) {
    at[head] = head;
    head += 1;
  }
  var tail = 0;
  while (head + tail < was.length &&
      head + tail < now.length &&
      was[was.length - 1 - tail] == now[now.length - 1 - tail]) {
    at[was.length - 1 - tail] = now.length - 1 - tail;
    tail += 1;
  }
  _matchBetween(
    was.sublist(head, was.length - tail),
    now.sublist(head, now.length - tail),
    (i, j) => at[head + i] = head + j,
  );
  return at;
}

/// The longest run of drawings [was] and [now] show in the same order,
/// each pair handed to [match] as (index in [was], index in [now]).
void _matchBetween(
  List<FrameId> was,
  List<FrameId> now,
  void Function(int i, int j) match,
) {
  final width = now.length + 1;
  // longest[i * width + j]: the longest such run was[i..] and now[j..] show.
  final longest = List<int>.filled((was.length + 1) * width, 0);
  for (var i = was.length - 1; i >= 0; i -= 1) {
    for (var j = now.length - 1; j >= 0; j -= 1) {
      longest[i * width + j] = was[i] == now[j]
          ? longest[(i + 1) * width + j + 1] + 1
          : math.max(longest[(i + 1) * width + j], longest[i * width + j + 1]);
    }
  }
  var i = 0;
  var j = 0;
  while (i < was.length && j < now.length) {
    if (was[i] == now[j]) {
      match(i, j);
      i += 1;
      j += 1;
    } else if (longest[(i + 1) * width + j] >= longest[i * width + j + 1]) {
      i += 1;
    } else {
      j += 1;
    }
  }
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

/// THE band an edit found — on whichever axis it was swept — and where the
/// blocks it held stand on each row, so the band can follow them wherever
/// the edit puts them.
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
/// 🗣️F-619-Q1 (유저 2026-11-19): 「따라간다 — 어떤 조작이든 선택한 블록이
/// 움직이면」. ↩️Until then only an edit acting on the band held it, and an
/// edge or a "+" in front of the band pushed its blocks out from under it:
/// the rectangle stayed, over the blocks pushed into its place.
///
/// Every edit that can move a band's blocks holds it when it begins —
/// [find] says how the blocks are found again, [heldSpanOn] for an edit
/// acting on them and [keptSpanOn] for one beside them — and asks [follow]
/// when they move, each step of a drag and once committed; a drag let go
/// of asks [restore].
final class HeldBand {
  HeldBand({
    required FrameSpan band,
    required Map<LayerId, HeldRun> rows,
    required FrameSpan? Function(Layer layer, HeldRun held) find,
    required int Function(LayerId id) behind,
    required Layer? Function(LayerId id) committed,
    required void Function(FrameSpan span) write,
  }) : _band = band,
       _rows = rows,
       _find = find,
       _behind = behind,
       _committed = committed,
       _write = write {
    _was = _spanOf(const {});
  }

  final FrameSpan _band;
  final Map<LayerId, HeldRun> _rows;

  /// How the held blocks are found again on a row the edit wrote.
  final FrameSpan? Function(Layer layer, HeldRun held) _find;

  /// How far a row's keys run ahead of the band's axis: a track-owned row
  /// is keyed on its track while a cut's band counts from the cut.
  final int Function(LayerId id) _behind;

  /// The row as the document holds it now, in the keys [_rows] counts.
  final Layer? Function(LayerId id) _committed;

  /// Writes the band, on the axis it was held on.
  final void Function(FrameSpan span) _write;

  /// The held blocks' span as the edit found them — read as the band is
  /// held, before the edit writes a thing: ⛔never on first asking.
  late final FrameSpan? _was;

  /// The band put back as the edit found it — a drag let go of.
  void restore() => _write(_band);

  /// The band over the blocks it held: [edited] stands in for the rows an
  /// edit has not written yet (a drag's preview, in the rows' own keys),
  /// and the document answers for the rest. Where none of its blocks is
  /// left, the band stays as it was found.
  void follow([Map<LayerId, Layer> edited = const {}]) {
    final was = _was;
    final now = _spanOf(edited);
    _write(
      was == null || now == null
          ? _band
          : followedBand(_band, was: was, now: now),
    );
  }

  /// The span from the first held block to the last, across [_rows], on
  /// the band's axis — [edited] standing in for the rows it holds.
  FrameSpan? _spanOf(Map<LayerId, Layer> edited) {
    FrameSpan? span;
    for (final MapEntry(key: id, value: held) in _rows.entries) {
      final layer = edited[id] ?? _committed(id);
      final row = layer == null ? null : _find(layer, held);
      if (row == null) {
        continue;
      }
      final offset = _behind(id);
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
