/// What the XDTS Viewer writes in the rows of a cel column, from the values
/// a track gives its frames (I-162-Q1, 유저 2026-11-05: 「XDTS 서식에서만
/// 뷰어 표기」 — 「최대한 서식대로 보여주는게 목표. 보이는그대로 출력이
/// 목표」): where a value's line lasts down, how far, where a run that
/// repeats is written as 止メ or リピート, and nothing else.
///
/// ⛔The viewer's code is not ours to copy (opentoonz/xdts_viewer v1.3.0,
/// BSD-3, `XSheetPDFTemplate::drawXsheetContents` and `checkRepeatColumns`):
/// what is kept is its rules and their numbers; the code is our own.
library;

import 'dart:math' as math;

import 'inbetween_mark.dart';
import 'timesheet_document.dart';

/// The value the viewer reads as the null cell — a run of nothing starting,
/// written ×.
const Object xdtsViewerNullCell = _XdtsViewerNullCell();

final class _XdtsViewerNullCell {
  const _XdtsViewerNullCell();
}

/// A value's line starts only where this many frames after it hold on — the
/// viewer's default, 「3コマ以上」.
const int xdtsViewerLineAfter = 3;

/// How many rows a line reaches down the key (原画) block from the value
/// it lasts from, that row included — the viewer's 「原画欄の継続線の最長
/// 長さ」. A repeat's line reaches as far.
const int xdtsViewerKeyLineReach = 9;

/// The fewest frames past its first round a run must repeat for the viewer
/// to write it as one — its default, 24.
const int xdtsViewerShortestRepeat = 24;

/// What the viewer writes in one row.
enum XdtsViewerInk {
  /// Nothing: a row a line no longer reaches, or a row inside a 止メ.
  none,

  /// The frame's own value: its number, its mark, or the null cell's ×.
  value,

  /// The frame's value in blue: where a repeat starts its next round, past
  /// the column's first two frames — a number or ×, never a mark.
  repeatValue,

  /// The line a value lasts down.
  line,

  /// The line a null cell lasts down, a wave.
  wave,

  /// A repeat's blue dashed line.
  repeat,
}

/// A run the key block writes as repeating: its first round from [start],
/// [round] frames long, repeated up to [end] — a round of one frame is a
/// 止メ.
typedef XdtsViewerRepeat = ({int start, int round, int end});

/// One column as the viewer writes it: an ink a frame, and where its words
/// stand — the frame a 止メ's or a リピート's word starts its top on.
typedef XdtsViewerNotation = ({
  List<XdtsViewerInk> inks,
  List<({int frame, bool repeat})> words,
});

/// The values the viewer reads off a sheet column's data [cells] (the
/// sheet's DATA reading), its first [duration] frames: a drawing's number
/// or mark where it starts, a breakdown mark where its block wears one,
/// the null cell where a run of nothing starts — and null where the frame
/// before holds on. The XDTS file writes these values (`xdts_builder.dart`
/// reads them here), so the sheet shows what the viewer reads.
///
/// ⚠️Mine: a run of nothing writes its × up to the drawn end — the rows
/// the XDTS is handed — where our own sheets write it up to the conte end
/// alone (`markEmptyRuns`).
List<Object?> xdtsViewerFramesOf(
  List<TimesheetCell> cells, {
  required int duration,
}) {
  final frames = <Object?>[];
  var covered = true;
  for (var frame = 0; frame < duration; frame += 1) {
    final cell = frame < cells.length ? cells[frame] : TimesheetCell.blank;
    final empty = switch (cell.kind) {
      TimesheetCellKind.empty ||
      TimesheetCellKind.emptyRunStart ||
      TimesheetCellKind.emptyRunSpan => true,
      _ => false,
    };
    frames.add(switch (cell.kind) {
      _ when empty => covered ? xdtsViewerNullCell : null,
      TimesheetCellKind.drawing => cell.mark ?? cell.label,
      TimesheetCellKind.mark => cell.mark,
      _ => null,
    });
    covered = !empty;
  }
  return frames;
}

/// The viewer's notation of [frames] — a track's values a frame: a number
/// (a `String`), a mark ([InbetweenMark]), [xdtsViewerNullCell], or null
/// where the frame before holds on. [keyBlock] is the 原画 block's, which
/// alone writes repeats and caps its lines; a page holds [pageFrames]
/// frames, and a page that opens on a held frame takes its line from the
/// value it holds — however short the run.
XdtsViewerNotation xdtsViewerNotation(
  List<Object?> frames, {
  required bool keyBlock,
  required int pageFrames,
}) {
  final repeats = keyBlock ? xdtsViewerRepeats(frames) : <XdtsViewerRepeat>[];
  final inks = List.filled(frames.length, XdtsViewerInk.none);
  for (var page = 0; page < frames.length; page += pageFrames) {
    var lineFrom = page == 0 || frames[page] != null
        ? null
        : _lastValueBefore(frames, page);
    final pageEnd = math.min(page + pageFrames, frames.length);
    for (var frame = page; frame < pageEnd; frame += 1) {
      final repeat = _repeatAt(repeats, frame);
      final restart = repeat == null ? null : repeat.start + repeat.round;
      final value = frames[frame];
      if (repeat != null && frame != restart) {
        inks[frame] =
            repeat.round > 1 && frame - restart! < xdtsViewerKeyLineReach
            ? XdtsViewerInk.repeat
            : XdtsViewerInk.none;
      } else if (value == null) {
        inks[frame] = _lineInk(frames, frame, lineFrom, keyBlock: keyBlock);
      } else {
        inks[frame] =
            restart != null && restart >= 2 && value is! InbetweenMark
            ? XdtsViewerInk.repeatValue
            : XdtsViewerInk.value;
        lineFrom = _lastsOn(frames, frame) ? frame : null;
      }
    }
  }
  return (
    inks: inks,
    words: [
      for (final repeat in repeats)
        if (repeat.round > 1)
          (frame: repeat.start + repeat.round + 1, repeat: true)
        else
          (frame: repeat.start + repeat.round, repeat: false),
    ],
  );
}

/// The ink of a held [frame]: the line from [lineFrom] — a wave from a
/// null cell — while it reaches, nothing past it.
XdtsViewerInk _lineInk(
  List<Object?> frames,
  int frame,
  int? lineFrom, {
  required bool keyBlock,
}) {
  if (lineFrom == null ||
      keyBlock && frame - lineFrom >= xdtsViewerKeyLineReach) {
    return XdtsViewerInk.none;
  }
  return frames[lineFrom] == xdtsViewerNullCell
      ? XdtsViewerInk.wave
      : XdtsViewerInk.line;
}

/// Whether the value at [frame] lasts on long enough to draw its line: the
/// next [xdtsViewerLineAfter] frames all hold on, inside the track.
bool _lastsOn(List<Object?> frames, int frame) {
  for (var next = frame + 1; next <= frame + xdtsViewerLineAfter; next += 1) {
    if (next >= frames.length || frames[next] != null) {
      return false;
    }
  }
  return true;
}

/// The last frame before [frame] that holds a value, or null.
int? _lastValueBefore(List<Object?> frames, int frame) {
  for (var before = frame - 1; before >= 0; before -= 1) {
    if (frames[before] != null) {
      return before;
    }
  }
  return null;
}

/// The repeat [frame] stands in, from its first round's end to its own.
XdtsViewerRepeat? _repeatAt(List<XdtsViewerRepeat> repeats, int frame) {
  for (final repeat in repeats) {
    if (frame < repeat.end && frame >= repeat.start + repeat.round) {
      return repeat;
    }
  }
  return null;
}

/// Whether the viewer counts [value] as written — anything but a held
/// frame and a mark; the null cell counts.
bool _written(Object? value) => value != null && value is! InbetweenMark;

/// The runs of [frames] the key block writes as repeats, in frame order: a
/// column of one value throughout is one 止メ from its second frame; any
/// other repeats a round of two frames or more, its first value appearing
/// once in it, at least twice over and [xdtsViewerShortestRepeat] frames
/// past its first round, to the last frame that writes something while
/// the round still holds — so the frame after it is written.
List<XdtsViewerRepeat> xdtsViewerRepeats(List<Object?> frames) {
  final count = frames.length;
  if (count == 0) {
    return [];
  }
  // Each frame's value, a held frame reading the value it holds.
  final shown = <Object?>[];
  for (final value in frames) {
    shown.add(value ?? (shown.isEmpty ? xdtsViewerNullCell : shown.last));
  }
  if (shown.every((value) => value == shown.first)) {
    // 「×止メ」という書き方はしない.
    return shown.first == xdtsViewerNullCell
        ? []
        : [(start: 0, round: 1, end: count)];
  }
  final repeats = <XdtsViewerRepeat>[];
  var lastEnd = 0;
  for (var start = 0; start < count - 4; start += 1) {
    if (start != 0 && frames[start] == null) {
      continue;
    }
    final first = shown[start];
    if (shown.sublist(lastEnd, start).contains(first)) {
      continue;
    }
    final found = _repeatFrom(frames, shown, start);
    if (found != null) {
      repeats.add(found);
      lastEnd = found.end;
      start = found.end - 1;
    }
  }
  return repeats;
}

/// The repeat whose first round starts at [start], or null: each round
/// end in turn, up to the first that writes [start]'s value again.
XdtsViewerRepeat? _repeatFrom(
  List<Object?> frames,
  List<Object?> shown,
  int start,
) {
  final count = frames.length;
  var end = start + 1;
  while (end < count - 3 && frames[end] == null) {
    end += 1;
  }
  for (; end < count - 3; end += 1) {
    if (shown[end] == shown[start]) {
      return null;
    }
    final round = end - start + 1;
    final reach = _roundReach(frames, shown, start, round);
    if (reach == null) {
      continue;
    }
    final length = reach - start;
    if (length >= round * 2 && length >= xdtsViewerShortestRepeat + round) {
      return (start: start, round: round, end: reach);
    }
  }
  return null;
}

/// How far the round of [round] frames from [start] repeats: the last
/// frame that writes something before the first that breaks it — or the
/// track's end — or null where nothing follows the round.
int? _roundReach(
  List<Object?> frames,
  List<Object?> shown,
  int start,
  int round,
) {
  final count = frames.length;
  var lastWritten = start + round;
  for (var frame = start + round; frame < count; frame += 1) {
    final repeats = shown[(frame - start) % round + start] == shown[frame];
    if (repeats && frame < count - 1) {
      if (_written(frames[frame])) {
        lastWritten = frame;
      }
      continue;
    }
    if (repeats) {
      return frame + 1;
    }
    return _written(frames[frame]) ? frame : lastWritten;
  }
  return null;
}
