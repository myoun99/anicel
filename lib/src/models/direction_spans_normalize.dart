import 'dart:collection';

import '../core/mapped_or_same.dart';
import 'cut.dart';
import 'layer.dart';
import 'layer_kind.dart';
import 'timeline_exposure.dart';

/// [cut] with no block carrying an instruction where its row's spans do not
/// ride its blocks ([LayerKind.spansRideBlocks], R27) — a direction block
/// pasted onto a drawing row brings its picture, not its span.
///
/// ↩️A DIRECTION row's bare block was given the vocabulary's first entry here
/// too, because a block there IS a span (유저 2026-09-12: 「블록 = 스팬」). A
/// block says nothing now until it is told something (I-72-block-without-
/// instruction, 유저 2026-10-08: 「생성시 기본값 없음」), and a bare block is
/// that span — so the verbs that know nothing of instructions (the first
/// stroke on an empty cell, a one-cell copy pasted, a division) leave it so.
///
/// Runs as a repository-write normalization, beside the covering rows and
/// the attach mirrors, so it covers every verb at once — undo/redo replay
/// and file load included. Identity-preserving on no-ops.
Cut cutWithSpansOnTheirBlocks(Cut cut) {
  final layers = mappedOrSame(cut.layers, _spansOnTheirBlocks);
  return identical(layers, cut.layers) ? cut : cut.copyWith(layers: layers);
}

Layer _spansOnTheirBlocks(Layer layer) {
  if (layer.kind.spansRideBlocks) {
    return layer;
  }
  SplayTreeMap<int, TimelineExposure>? next;
  for (final MapEntry(key: start, value: entry) in layer.timeline.entries) {
    if (entry.ghost || entry.instruction == null) {
      continue;
    }
    (next ??= SplayTreeMap.of(layer.timeline))[start] = entry.copyWith(
      instruction: () => null,
    );
  }
  return next == null ? layer : layer.copyWith(timeline: next);
}
