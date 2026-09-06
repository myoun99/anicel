import 'frame_id.dart';

/// Which edge of a glued run a [TimelineRunBehavior] hangs off.
enum TimelineRunEdgeSide {
  start,
  end;

  String toJson() => name;

  static TimelineRunEdgeSide fromJson(Object? value) => switch (value) {
    'start' => TimelineRunEdgeSide.start,
    'end' => TimelineRunEdgeSide.end,
    _ => throw FormatException('Unknown run edge side: $value'),
  };
}

/// What a run edge does with the free space next to it. `None` is the
/// absence of a behavior — never stored.
enum TimelineRunEdgeMode {
  /// The edge's drawing holds as ONE dim ghost block to the cut boundary.
  hold,

  /// The pattern (a selection-defined span or the whole run) cycles into
  /// the free space to the cut boundary.
  repeat;

  String toJson() => name;

  static TimelineRunEdgeMode fromJson(Object? value) => switch (value) {
    'hold' => TimelineRunEdgeMode.hold,
    'repeat' => TimelineRunEdgeMode.repeat,
    _ => throw FormatException('Unknown run edge mode: $value'),
  };
}

/// A run-edge property (UI-R9 #10, TVP-style N/H/R): a persistent LIVE
/// spec on the layer — one per (run, side), set through the edge tag.
///
/// The behavior stores no ghost entries and no frame count: it names WHAT
/// ([anchorFrameId] = identity of a block inside the run; the LIVE glued
/// run containing it is the unit) and HOW ([mode] + optional
/// [patternAnchorFrameId] for selection-scoped repeat patterns). The
/// ghosts always fill to the cut boundary; [rederiveRunBehaviors] wipes
/// and re-synthesizes them after every timeline edit and every cut
/// duration change, so the tail/lead-in re-arranges automatically (live
/// sync, and the ghost-glue guarantee: the pattern IS the current run, a
/// comma shrink can never open a gap). A vanished anchor drops the
/// behavior (self-healing).
class TimelineRunBehavior {
  const TimelineRunBehavior({
    required this.anchorFrameId,
    required this.side,
    required this.mode,
    this.patternAnchorFrameId,
  });

  /// Identity of the run: a frameId of one of its blocks (the run's first
  /// block at creation). Resolved to its lowest non-ghost index on
  /// rederive; the glued run containing that block is the behavior's run.
  final FrameId anchorFrameId;

  final TimelineRunEdgeSide side;
  final TimelineRunEdgeMode mode;

  /// Repeat with a selection: the block bounding the pattern span.
  /// - [TimelineRunEdgeSide.end]: the pattern runs from THIS block's start
  ///   to the run end (the run's last block is always included).
  /// - [TimelineRunEdgeSide.start]: the pattern runs from the run start to
  ///   THIS block's end (the first block is always included).
  /// Null (or no longer resolvable inside the run) = the whole run.
  final FrameId? patternAnchorFrameId;

  /// The marker stamped on ghost entries this behavior owns
  /// ([TimelineExposure.ghostOwnerId]).
  String get ghostOwnerId => '${anchorFrameId.value}:${side.name}';

  /// This behaviour under a new set of frame ids, or NULL when [map]
  /// cannot answer for the anchor.
  ///
  /// 🚨Run behaviours are addressed by FRAME ID (the anchor block, and the
  /// pattern block for a ranged repeat), so carrying them verbatim into a
  /// copy whose frames were all re-minted names blocks that do not exist
  /// there — `rederiveRunBehaviors` then drops the behaviour on the first
  /// edit, which is the same loss with extra steps.
  ///
  /// ⛔What happens to an UNMAPPABLE anchor is the caller's law, told by
  /// what [map] returns, not by a flag: a duplicate whose map covers every
  /// frame passes `(id) => map[id] ?? id` and never sees null; a mount
  /// that only knows the cels it linked passes the lookup itself and drops
  /// the behaviour when it comes back null. The pattern anchor follows the
  /// same answer — unmapped there means "no pattern", which is the
  /// whole-run reading.
  TimelineRunBehavior? remapFrameIds(FrameId? Function(FrameId id) map) {
    final anchor = map(anchorFrameId);
    if (anchor == null) {
      return null;
    }
    final pattern = patternAnchorFrameId;
    return TimelineRunBehavior(
      anchorFrameId: anchor,
      side: side,
      mode: mode,
      patternAnchorFrameId: pattern == null ? null : map(pattern),
    );
  }

  Map<String, dynamic> toJson() => {
    'anchor': anchorFrameId.toJson(),
    'side': side.toJson(),
    'mode': mode.toJson(),
    if (patternAnchorFrameId != null)
      'patternAnchor': patternAnchorFrameId!.toJson(),
  };

  factory TimelineRunBehavior.fromJson(Map<String, dynamic> json) =>
      TimelineRunBehavior(
        anchorFrameId: FrameId.fromJson(json['anchor'] as Map<String, dynamic>),
        side: TimelineRunEdgeSide.fromJson(json['side']),
        mode: TimelineRunEdgeMode.fromJson(json['mode']),
        patternAnchorFrameId: json['patternAnchor'] == null
            ? null
            : FrameId.fromJson(json['patternAnchor'] as Map<String, dynamic>),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineRunBehavior &&
          other.anchorFrameId == anchorFrameId &&
          other.side == side &&
          other.mode == mode &&
          other.patternAnchorFrameId == patternAnchorFrameId;

  @override
  int get hashCode =>
      Object.hash(anchorFrameId, side, mode, patternAnchorFrameId);

  @override
  String toString() =>
      'TimelineRunBehavior(anchor: $anchorFrameId, side: ${side.name}, '
      'mode: ${mode.name}'
      '${patternAnchorFrameId == null ? '' : ', pattern: $patternAnchorFrameId'})';
}
