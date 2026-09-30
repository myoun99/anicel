import '../../models/attached_layer_resolve.dart' show isSyncedAttachedLayer;
import '../../models/cut_id.dart';
import '../../models/first_appearance_names.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/pill_subject.dart';
import '../../models/timeline_coverage.dart' show coveringDrawingBlockAt;
import '../../models/track_id.dart';
import '../text/place_lines.dart' show drawingPlaceLines;
import 'active_cut_controllers.dart';
import 'cut_verbs.dart';
import 'lane_verbs.dart';
import 'layer_verbs.dart';
import 'project_settings.dart';
import 'range_selections.dart';
import 'session_roles.dart';

/// Whether [layer]'s drawings are what 자동 이름 지정 numbers (I-18): its
/// kind's answer ([LayerKind.numbersItsDrawings]), on a row whose drawings
/// carry names of their own.
///
/// ⛔A SYNCED attach row's do not. Its cels are mirrors whose name follows
/// the base's — the row PRINTS its base's names (UI-R24 #2) — so numbering
/// the base is what numbers what the mirror shows, and a number of the
/// mirror's own would be written where nothing reads it.
bool rowNumbersItsDrawings(Layer layer) =>
    layer.kind.numbersItsDrawings && !isSyncedAttachedLayer(layer);

/// One row's part of an auto-name press: the drawings its real blocks show,
/// in order — a drawing shown by two blocks is listed twice, which is what
/// lets the second read the first one's number.
typedef AutoNameRow = ({LayerId layerId, List<FrameId> shown});

/// WHAT an auto-name press numbers (I-18), resolved once per panel so the
/// button's gate, the window's apply and the key read one answer (T25's
/// law).
sealed class AutoNameTargets {
  const AutoNameTargets();
}

/// Drawings, row by row — the timeline's noun.
final class AutoNameFrames extends AutoNameTargets {
  const AutoNameFrames(this.rows);

  final List<AutoNameRow> rows;
}

/// Cuts, in track order — the storyboard's noun.
final class AutoNameCuts extends AutoNameTargets {
  const AutoNameCuts(this.cutIds);

  final List<CutId> cutIds;
}

/// One row's writing: the names its drawings take, and the drawings that
/// JOIN the one already holding their new name instead of taking it.
typedef AutoNameRowPlan = ({
  LayerId layerId,
  Map<FrameId, String> names,
  Map<FrameId, FrameId> joins,
});

/// What a press will write, worked out before anything is — so a join can
/// be asked about first, and the answer writes exactly what was asked.
class AutoNamePlan {
  const AutoNamePlan({
    this.rows = const [],
    this.cutNames = const {},
    this.joinLines = const [],
  });

  final List<AutoNameRowPlan> rows;
  final Map<CutId, String> cutNames;

  /// The drawings a join discards, one line each ([drawingPlaceLines]) —
  /// what the link notice lists. Shown, never decided on: whether to ask is
  /// [hasJoins].
  final List<String> joinLines;

  /// Whether a new name is already held outside the press, so the press
  /// has to ask before it writes.
  bool get hasJoins => rows.any((row) => row.joins.isNotEmpty);
}

/// 자동 이름 지정 (I-18) — which blocks a press numbers, the plan it will
/// write, and writing it.
///
/// 🗣️I-18 (유저): 「타임라인 공용 알약에 새 버튼 신설. 내용은 블록 이름
/// 자동편집으로, 첫번째는 블록의 이름(프레임이름, 컷이름) 을 순서대로 지정.
/// 대상은 선택된 블록들(컷이나 프레임)이 있으면 선택한 대상만. 없으면 현재
/// 인덱스에 위치한 블록부터 해당 행에서 마지막 존재하는 블록까지」.
///
/// A collaborator of the session (G0's shape): it names the roles and the
/// siblings it reads in its constructor.
class BlockNaming {
  BlockNaming({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required ActiveCutControllers controllers,
    required LaneVerbs laneVerbs,
    required RangeSelections rangeSelections,
    required LayerVerbs layerVerbs,
    required CutVerbs cutVerbs,
    required ProjectSettings projectSettings,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _controllers = controllers,
       _laneVerbs = laneVerbs,
       _rangeSelections = rangeSelections,
       _layerVerbs = layerVerbs,
       _cutVerbs = cutVerbs,
       _projectSettings = projectSettings;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final ActiveCutControllers _controllers;
  final LaneVerbs _laneVerbs;
  final RangeSelections _rangeSelections;
  final LayerVerbs _layerVerbs;
  final CutVerbs _cutVerbs;
  final ProjectSettings _projectSettings;

  // --- which blocks ----------------------------------------------------------

  /// What the TIMELINE's press numbers — the shared pill's one ladder
  /// ([pillSubjectOn]) with this verb's rungs: the selected rows, each from
  /// the block at the playhead to its last (targets-Q3 「선택한 행마다 현재
  /// 인덱스 블록부터 끝까지」), then the frame axis. Cuts are the
  /// storyboard's noun (R5q1), so there is no cuts rung here.
  AutoNameTargets? get timelineTargets {
    final rows = switch (pillSubjectOn(
      cuts: false,
      layers: () => _selectedRows().isNotEmpty,
      cells: () => _frameAxisRows().isNotEmpty,
    )) {
      PillSubject.layers => _selectedRows(),
      PillSubject.cells => _frameAxisRows(),
      PillSubject.cuts || PillSubject.nothing => const <AutoNameRow>[],
    };
    return rows.isEmpty ? null : AutoNameFrames(rows);
  }

  /// The selected rail rows, each from the block at the playhead.
  List<AutoNameRow> _selectedRows() => [
    for (final layerId in _layerVerbs.selectedLayerIdsWhere(
      rowNumbersItsDrawings,
    ))
      ?_fromThePlayhead(_project.layerById(layerId)),
  ];

  /// The frame axis, claimed in the order the pill's frame verbs claim it
  /// (링크 독립's, I-45): a LANE row takes the press and holds no drawings
  /// (F-87); a band means its own rows, and a band holding none leaves the
  /// press with nothing — never a redirect onto the active row; with no
  /// band, the active row from the block at the playhead.
  List<AutoNameRow> _frameAxisRows() {
    if (_laneVerbs.laneVerbRange != null) {
      return const [];
    }
    if (_selection.frameRangeSelection.value != null) {
      return _bandRows();
    }
    return [?_fromThePlayhead(_selection.activeLayer)];
  }

  /// The band's rows, each with what its real blocks INSIDE the band show.
  ///
  /// ⛔Not [RangeSelections.selectionBlockStartsByLayer]: that one stands
  /// down every row whose TIMING is not its own
  /// ([RetimeLaw.standsDownFromRetime]) — the image row among them — a
  /// retiming rule, where this press renames, and the image row is one of
  /// the three it numbers (targets-Q1).
  List<AutoNameRow> _bandRows() {
    final shownByRow = _selection.bandRowsForSelection(
      rowNumbersItsDrawings,
      (ids, band) => {
        for (final id in ids)
          if (_project.rangeLayerById(id) case final layer?)
            id: _shownIn(layer, band.startIndex, band.endIndexExclusive),
      },
    );
    return [
      for (final MapEntry(key: layerId, value: shown) in shownByRow.entries)
        if (shown.isNotEmpty) (layerId: layerId, shown: shown),
    ];
  }

  /// [layer] from the block under the playhead to its last block — or
  /// nothing on an empty cell, and nothing on a GHOST: 「블록으로 치지
  /// 않는다」 (targets-Q2) — a hold's or a repeat's cell is its source going
  /// on, not a block of its own.
  AutoNameRow? _fromThePlayhead(Layer? layer) {
    if (layer == null || !rowNumbersItsDrawings(layer)) {
      return null;
    }
    final block = coveringDrawingBlockAt(
      layer.timeline,
      _selection.currentFrameIndex,
    );
    if (block == null || block.entry.ghost) {
      return null;
    }
    final end = layer.timeline.lastKey()! + 1;
    return (layerId: layer.id, shown: _shownIn(layer, block.startIndex, end));
  }

  /// The drawings [layer]'s blocks starting in [start, endExclusive) show,
  /// in order — the placed blocks Delete takes
  /// ([RangeSelections.selectionBlockStarts]), never a ghost. A ghost reads
  /// its source's number by showing its source.
  List<FrameId> _shownIn(Layer layer, int start, int endExclusive) => [
    for (final blockStart in _rangeSelections.selectionBlockStarts(
      layer,
      start,
      endExclusive,
    ))
      ?layer.timeline[blockStart]?.frameId,
  ];

  /// The cuts of [trackId] from the one under the playhead to the track's
  /// last — the storyboard's V row with nothing selected, the same sentence
  /// said of cuts. Nothing in a gap, where no cut stands.
  AutoNameCuts? cutsFromThePlayhead(TrackId trackId) {
    final axis = _projectSettings.axisForTrack(trackId);
    final frame = _selection.editingGlobalFrame;
    final owner = axis.ownerOf(frame);
    if (owner == null || axis.isGap(frame)) {
      return null;
    }
    return AutoNameCuts([
      for (final entry in axis.entries.skip(axis.entries.indexOf(owner)))
        entry.cutId,
    ]);
  }

  // --- the plan -------------------------------------------------------------

  /// What numbering [targets] from [from] will write.
  AutoNamePlan plan(AutoNameTargets targets, {required int from}) =>
      switch (targets) {
        // targets-Q4 「컷마다 따로 연번」: a cut is shown once, so first
        // appearance simply counts up — no cut shares a number, and a cut's
        // name clashes with nothing (duplicate cut names are allowed).
        AutoNameCuts(:final cutIds) => AutoNamePlan(
          cutNames: namesByFirstAppearance(cutIds, from: from),
        ),
        AutoNameFrames(:final rows) => _framesPlan(rows, from),
      };

  /// Rows sharing one cel BANK — the two members of a link pair in one cut
  /// — are numbered as ONE: a drawing never takes two numbers in one press.
  /// Every bank counts from [from] on its own (「그림마다 번호」 is said of a
  /// row's drawings).
  AutoNamePlan _framesPlan(List<AutoNameRow> rows, int from) {
    final banks = <Object, List<AutoNameRow>>{};
    for (final row in rows) {
      banks.putIfAbsent(_bankOf(row.layerId), () => []).add(row);
    }
    final project = _project.repository.requireProject();
    final planned = <AutoNameRowPlan>[];
    final joinLines = <String>[];
    for (final bank in banks.values) {
      final layer = _project.layerById(bank.first.layerId);
      if (layer == null) {
        continue;
      }
      final names = namesByFirstAppearance([
        for (final row in bank) ...row.shown,
      ], from: from);
      final joins = _controllers.timelineController.nameConflicts(
        layer,
        names,
      );
      joinLines.addAll(drawingPlaceLines(project, layer.id, joins.keys));
      for (final row in bank) {
        planned.add((layerId: row.layerId, names: names, joins: joins));
      }
    }
    return AutoNamePlan(rows: planned, joinLines: joinLines);
  }

  /// The bank [layerId]'s cels live in: its link group's, else its own.
  Object _bankOf(LayerId layerId) {
    final cutId = _project.activeCutId;
    final group = cutId == null
        ? null
        : _project.repository.requireProject().linkRegistry.groupOf(
            cutId: cutId,
            layerId: layerId,
          );
    return group?.id ?? layerId;
  }

  // --- writing it ------------------------------------------------------------

  /// Writes [plan] — the names, and the joins the link notice was answered
  /// with — as ONE undo step.
  void apply(AutoNamePlan plan) {
    if (plan.cutNames.isNotEmpty) {
      _cutVerbs.renameCuts(plan.cutNames);
      return;
    }
    if (plan.rows.isEmpty) {
      return;
    }
    _project.historyManager.runAsOneStep('Auto name', () {
      for (final row in plan.rows) {
        _controllers.timelineController.nameFramesForLayer(
          layerId: row.layerId,
          names: row.names,
          joins: row.joins,
        );
      }
    });
    _changes.notifyChanged();
  }
}
