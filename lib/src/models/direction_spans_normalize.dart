import 'dart:collection';

import '../core/mapped_or_same.dart';
import 'camera_instruction.dart';
import 'cut.dart';
import 'frame.dart';
import 'frame_id.dart';
import 'layer.dart';
import 'layer_kind.dart';
import 'timeline_exposure.dart';

/// [cut] with no block carrying an instruction where its row's spans do not
/// ride its blocks ([LayerKind.spansRideBlocks], R27) — a direction block
/// pasted onto a drawing row brings its picture, not its span — and every
/// drawing named by what its block says where they do: a direction row's
/// drawings link by it ([linkNameOfWriting], read against [defById], the
/// project's vocabulary), and a name written so means nothing anywhere
/// else.
///
/// ↩️A DIRECTION row's bare block was given the vocabulary's first entry here
/// too, because a block there IS a span (유저 2026-09-12: 「블록 = 스팬」). A
/// block says nothing now until it is told something (I-72-block-without-
/// instruction, 유저 2026-10-08: 「생성시 기본값 없음」), and a bare block is
/// that span — so the verbs that know nothing of instructions (the first
/// stroke on an empty cell, a one-cell copy pasted, a division) leave it so.
///
/// ★THE NAME IS WHAT THE BLOCK SAYS, by construction (I-72-direction-link):
/// written here, it cannot drift from the writing whichever verb moved,
/// copied or undid it. ⛔The JOIN is not here: blocks coming to say the same
/// show one drawing only when the user takes the link the edit offers —
/// a join throws a picture away.
///
/// Runs as a repository-write normalization, beside the covering rows and
/// the attach mirrors, so it covers every verb at once — undo/redo replay
/// and file load included. Identity-preserving on no-ops.
Cut cutWithSpansOnTheirBlocks(
  Cut cut, {
  required CameraInstructionDef? Function(String instructionId) defById,
}) {
  final layers = mappedOrSame(
    cut.layers,
    (layer) => layer.kind.spansRideBlocks
        ? _namedByWhatTheySay(layer, defById)
        : _spansOnTheirBlocks(layer),
  );
  return identical(layers, cut.layers) ? cut : cut.copyWith(layers: layers);
}

Layer _spansOnTheirBlocks(Layer layer) {
  SplayTreeMap<int, TimelineExposure>? next;
  for (final MapEntry(key: start, value: entry) in layer.timeline.entries) {
    if (entry.ghost || entry.instruction == null) {
      continue;
    }
    (next ??= SplayTreeMap.of(layer.timeline))[start] = entry.copyWith(
      instruction: () => null,
    );
  }
  final frames = mappedOrSame(
    layer.frames,
    (frame) => isWrittenDrawingName(frame.name)
        ? frame.copyWith(name: null)
        : frame,
  );
  return next == null && identical(frames, layer.frames)
      ? layer
      : layer.copyWith(timeline: next, frames: frames);
}

/// [layer]'s drawings, each named by what the first block showing it says.
Layer _namedByWhatTheySay(
  Layer layer,
  CameraInstructionDef? Function(String instructionId) defById,
) {
  final said = <FrameId, String?>{};
  for (final entry in layer.timeline.values) {
    if (entry case TimelineExposure(ghost: false, :final frameId?)) {
      said.putIfAbsent(
        frameId,
        () => linkNameOfWriting(
          entry.instruction,
          switch (entry.instruction?.instructionId) {
            final id? => defById(id),
            null => null,
          },
        ),
      );
    }
  }
  final frames = mappedOrSame(
    layer.frames,
    (frame) => switch (said[frame.id]) {
      final name when said.containsKey(frame.id) && name != frame.name =>
        frame.copyWith(name: name),
      _ => frame,
    },
  );
  return identical(frames, layer.frames)
      ? layer
      : layer.copyWith(frames: frames);
}
