import 'package:flutter/foundation.dart';

import '../../../models/frame_id.dart';
import '../../../models/layer.dart';
import '../../../models/layer_id.dart';
import '../../../models/timeline_repeat.dart';
import '../../../models/timeline_run_edit.dart';
import '../../../services/editing/run_id_mint.dart';
import '../../timeline/timeline_drag_preview.dart';
import 'editor_drag_session.dart';

/// The "+ add frames" drag at a run edge (UI-R8): its input is the COUNT of
/// new one-frame drawings at the edge of every run the press acts on,
/// absolute like the audio slide's offset (0 shows the committed state).
///
/// 🗣️F-410 (유저 2026-10-19: 「… 선택된 여러 프레임에 성질 바꾸는거
/// 적용되도록. 프레임추가도.」): the runs are the press's
/// (`RangeSelections.runsActedOnBy`) — every run a live band holds when the
/// pressed one is among them, that one alone when it is not — and ONE drag
/// answers either, rows and runs alike.
class RunFramesAddDrag implements EditorDragSession {
  RunFramesAddDrag._({
    required List<({Layer before, List<int> runs})> rows,
    required bool atEnd,
    required int Function() drawnFrameCount,
    required ValueNotifier<TimelineDragPreview?> preview,
    required void Function(List<({Layer before, Layer after})> edits)
    commitLayerDrags,
  }) : _rows = rows,
       _atEnd = atEnd,
       _drawnFrameCount = drawnFrameCount,
       _preview = preview,
       _commitLayerDrags = commitLayerDrags;

  /// Starts the drag at the edge of [runs] — each row's runs named by their
  /// first block's start; null when no row of them stands — no object, no
  /// drag.
  static RunFramesAddDrag? begin({
    required Map<LayerId, List<int>> runs,
    required bool atEnd,
    required Layer? Function(LayerId) layerById,
    required int Function() drawnFrameCount,
    required ValueNotifier<TimelineDragPreview?> preview,
    required void Function(List<({Layer before, Layer after})> edits)
    commitLayerDrags,
  }) {
    final rows = [
      for (final MapEntry(key: id, value: starts) in runs.entries)
        if (layerById(id) case final layer?)
          // Right to left: a run's new frames push what comes after it, so
          // the runs still to take theirs keep their starts.
          (before: layer, runs: starts.reversed.toList()),
    ];
    if (rows.isEmpty) {
      return null;
    }
    return RunFramesAddDrag._(
      rows: rows,
      atEnd: atEnd,
      drawnFrameCount: drawnFrameCount,
      preview: preview,
      commitLayerDrags: commitLayerDrags,
    );
  }

  final List<({Layer before, List<int> runs})> _rows;
  final bool _atEnd;

  /// The rows as this drag would leave them; empty while the count shows
  /// "no change". The commit reads THIS, never [_preview].
  List<({Layer before, Layer after})> _edits = const [];

  /// The ids reserved so far, by row, run and ordinal — drag-scoped,
  /// discarded with the object.
  final Map<(LayerId, int, int), FrameId> _reservedIds = {};

  /// The run-behavior fill boundary (hold/repeat edges fill to the cut's
  /// DRAWN end, F-227); read per update.
  final int Function() _drawnFrameCount;

  final ValueNotifier<TimelineDragPreview?> _preview;

  /// The session's committer: the rows' timeline edits through the
  /// controller as ONE undo step, with the warm + notify epilogue behind it.
  final void Function(List<({Layer before, Layer after})> edits)
  _commitLayerDrags;

  /// Reserves the drag's new frame ids, deterministically: the same row,
  /// run and ordinal always resolve the same id, so every preview step and
  /// the commit agree.
  ///
  /// 🚨From the RUN, not the project's first free `frame-N`: a drawing
  /// undone keeps its picture in the session under its id for the redo, and
  /// the next drag given that id showed it on a blank cel (card
  /// `undone-paste-reuses-ids`).
  FrameId _reservedNewFrameId(LayerId row, int run, int ordinal) =>
      _reservedIds.putIfAbsent((row, run, ordinal), () => mintFrameId(row));

  /// Live preview: [count] new one-frame drawings at the edge of every run
  /// (0 shows the committed state).
  @override
  void update(int count) {
    _edits = [
      if (count >= 1)
        for (final row in _rows)
          if (_withNewFrames(row, count) case final after?)
            (before: row.before, after: after),
    ];
    // The rows' layers as the preview every multi-row edit shows (the bulk
    // retime's too) — one row is a map of one.
    _preview.value = _edits.isEmpty
        ? null
        : BlockMoveDragPreview(
            previewLayers: {
              for (final edit in _edits) edit.after.id: edit.after,
            },
          );
  }

  /// [row] with [count] new one-frame drawings at the edge of each of its
  /// runs and its ghosts derived again — null when no run of it takes one.
  Layer? _withNewFrames(({Layer before, List<int> runs}) row, int count) {
    var layer = row.before;
    for (final (run, start) in row.runs.indexed) {
      final result = layerWithNewFramesAtRunEdge(
        layer,
        blockStartIndex: start,
        atEnd: _atEnd,
        count: count,
        frameIdAt: (ordinal) =>
            _reservedNewFrameId(row.before.id, run, ordinal),
      );
      if (result != null) {
        layer = result.layer;
      }
    }
    return identical(layer, row.before)
        ? null
        : rederiveRunBehaviors(layer, drawnFrameCount: _drawnFrameCount());
  }

  /// Commits the added frames as ONE undo step.
  @override
  void commit() {
    final edits = _edits;
    _preview.value = null;
    if (edits.isEmpty) {
      return;
    }
    _commitLayerDrags(edits);
  }

  @override
  void cancel() {
    _preview.value = null;
  }
}
