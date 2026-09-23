import 'dart:collection';

import '../core/mapped_or_same.dart';
import 'cut.dart';
import 'exposure_instruction.dart';
import 'layer.dart';
import 'layer_kind.dart';
import 'timeline_exposure.dart';

/// [cut] with every block carrying an instruction exactly when its row's
/// spans ride its blocks ([LayerKind.spansRideBlocks], R27).
///
///  · A DIRECTION row's block with none gets [defaultInstructionId] — the
///    span the ＋ makes on an empty cell (UI-R25 #2: the vocabulary's first
///    entry), because a block there IS a span (유저 2026-09-12: 「블록 =
///    스팬」). A block reaches that row bare whenever a verb that knows
///    nothing of instructions makes one: the first stroke on an empty cell,
///    a one-cell copy pasted, a division.
///  · Any OTHER row's block drops the one it carries — a direction block
///    pasted onto a drawing row brings its picture, not its span.
///
/// ⚠️[defaultInstructionId] null (an emptied vocabulary) leaves a bare
/// direction block bare: there is no first entry to give it.
///
/// Runs as a repository-write normalization, beside the covering rows and
/// the attach mirrors, so it covers every verb at once — undo/redo replay
/// and file load included. Identity-preserving on no-ops.
Cut cutWithSpansOnTheirBlocks(
  Cut cut, {
  required String? defaultInstructionId,
}) {
  final layers = mappedOrSame(
    cut.layers,
    (layer) => _spansOnTheirBlocks(layer, defaultInstructionId),
  );
  return identical(layers, cut.layers) ? cut : cut.copyWith(layers: layers);
}

Layer _spansOnTheirBlocks(Layer layer, String? defaultInstructionId) {
  final rides = layer.kind.spansRideBlocks;
  SplayTreeMap<int, TimelineExposure>? next;
  for (final MapEntry(key: start, value: entry) in layer.timeline.entries) {
    if (entry.ghost) {
      continue;
    }
    final fixed = switch ((rides, entry.instruction, defaultInstructionId)) {
      (true, null, final id?) => entry.copyWith(
        instruction: () => ExposureInstruction(instructionId: id),
      ),
      (false, _?, _) => entry.copyWith(instruction: () => null),
      _ => null,
    };
    if (fixed != null) {
      (next ??= SplayTreeMap.of(layer.timeline))[start] = fixed;
    }
  }
  return next == null ? layer : layer.copyWith(timeline: next);
}
