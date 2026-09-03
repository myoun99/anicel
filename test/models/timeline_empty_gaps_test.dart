// THE EMPTY RUNS INSIDE A RANGE — the walk the range verbs and #16's track
// rung share. It lived in the session manager until 2026-09-03 without pins
// of its own; these say what it answers, ghosts included (D20: a ghost is
// authoring room, so it counts as empty).
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_empty_gaps.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// `AAB.C` → a 2-frame A, a 1-frame B, an empty cell, a 1-frame C; a
/// lowercase letter is a GHOST exposure of that drawing.
Layer _row(String cells) {
  final timeline = <int, TimelineExposure>{};
  var index = 0;
  while (index < cells.length) {
    final symbol = cells[index];
    if (symbol == '.') {
      index += 1;
      continue;
    }
    var length = 1;
    while (index + length < cells.length && cells[index + length] == symbol) {
      length += 1;
    }
    timeline[index] = TimelineExposure.drawing(
      FrameId(symbol.toUpperCase()),
      length: length,
      ghost: symbol == symbol.toLowerCase(),
    );
    index += length;
  }
  return Layer(
    id: const LayerId('l'),
    name: 'L',
    frames: const [],
    timeline: timeline,
  );
}

void main() {
  test('reports each maximal empty run inside the range', () {
    expect(emptyGapsBetween(_row('AA..B.'), 0, 6), [
      (startIndex: 2, length: 2),
      (startIndex: 5, length: 1),
    ]);
  });

  test('a fully drawn range has no gaps, an undrawn one is a single gap', () {
    expect(emptyGapsBetween(_row('AAAA'), 0, 4), isEmpty);
    expect(emptyGapsBetween(_row(''), 0, 3), [(startIndex: 0, length: 3)]);
  });

  test('the range clips the walk: cells outside it are not gaps', () {
    expect(emptyGapsBetween(_row('A..B'), 1, 3), [(startIndex: 1, length: 2)]);
    expect(emptyGapsBetween(_row('.AA.'), 1, 3), isEmpty);
  });

  test('a ghost exposure is authoring room and counts as empty (D20)', () {
    expect(emptyGapsBetween(_row('AAaa'), 0, 4), [(startIndex: 2, length: 2)]);
  });
}
