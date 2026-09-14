/// Which edge of a glued run a run-edge property hangs off.
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
/// absence of a property — never stored.
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

/// One BLOCK's share of one side of its glued run's edge property (UI-R9
/// #10, TVP-style N/H/R), stored in the block's own entry.
///
/// 🚨F-134 (유저 2026-09-14): 「프레임 복사/붙혀넣기하면 붙여넣어진 프레임의
/// +버튼이나 성질버튼이 없음」 — and 「프레임 생성하고 거기서 이름바꿔서
/// 링크프레임 작동시키면 성질 사라짐. 애초에 구조적인 문제인듯」 — 「근본/
/// 구조적으로 해결해줘」. The property used to be a spec on the LAYER that
/// named its run by the FRAME ID of one of the run's blocks. A frame id names
/// a DRAWING, and linked blocks share one: every lookup settled on the lowest
/// block showing that drawing, so a pasted link got no edge chrome of its
/// own, and a join by name moved the property onto another run or dropped
/// it with the renamed drawing. A block's own entry is the one address two
/// blocks never share, and it rides every move, copy, split and relink for
/// free — the law the inbetween dots (UI-R9 #8) and the memo already follow.
///
/// What stays as UI-R9 #10 made it: the mark stores no ghost entries and no
/// frame count. The ghosts always fill to the cut boundary;
/// `rederiveRunBehaviors` wipes and re-synthesizes them after every timeline
/// edit and every cut duration change, so the tail/lead-in re-arranges
/// automatically (live sync, and the ghost-glue guarantee: the pattern IS the
/// current run, a comma shrink can never open a gap). A carrier block that is
/// deleted takes its property with it (self-healing).
///
/// [mode]: this block CARRIES the side's property. The setter puts it on the
/// run's edge block — the end side on the LAST block, the start side on the
/// FIRST — so splitting the run keeps the property with the fragment that
/// owns that edge (UI-R10 #4). A carrier anywhere in the run still speaks for
/// the run's edge, which is what keeps a hold on while frames are glued on
/// past it. When SEVERAL blocks carry one side (two runs glued into one), the
/// carrier NEAREST that edge wins and the rederive strips the others: the
/// edge that survives a merge is the right run's end and the left run's
/// start. (The layer spec list this replaced kept the most recently set one —
/// an order nobody chose; it was the list's, 96740d91.)
///
/// [bound]: this block BOUNDS the side's selection-scoped repeat pattern
/// (UI-R19 #2) — on the END side the pattern starts at this block and runs to
/// the run end; on the START side it runs from the run start through this
/// block. A bound belongs to the winning carrier when no other carrier stands
/// between them; any other bound is stripped, and no bound reads as the whole
/// run.
class TimelineRunEdgeMark {
  const TimelineRunEdgeMark({this.mode, this.bound = false});

  /// A block that carries nothing on this side — nearly every block.
  static const none = TimelineRunEdgeMark();

  final TimelineRunEdgeMode? mode;
  final bool bound;

  bool get isNone => mode == null && !bound;

  Map<String, dynamic> toJson() => {
    if (mode != null) 'mode': mode!.toJson(),
    if (bound) 'bound': true,
  };

  factory TimelineRunEdgeMark.fromJson(Map<String, dynamic> json) =>
      TimelineRunEdgeMark(
        mode: json['mode'] == null
            ? null
            : TimelineRunEdgeMode.fromJson(json['mode']),
        bound: json['bound'] == true,
      );

  /// The mark a decoder reads from an entry's optional key — [none] when
  /// the key is absent, which is how the encoder spells [none].
  static TimelineRunEdgeMark fromJsonOrNone(Object? json) => json == null
      ? none
      : TimelineRunEdgeMark.fromJson(json as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineRunEdgeMark &&
          other.mode == mode &&
          other.bound == bound;

  @override
  int get hashCode => Object.hash(mode, bound);

  @override
  String toString() =>
      'TimelineRunEdgeMark(${mode?.name ?? 'none'}${bound ? ', bound' : ''})';
}

/// What a GHOST exposure is the ghost of: the side and the mode of the run
/// edge property that derived it.
///
/// ⚠️It names no run, and needs to name none. Ghosts are applied holds
/// first, then repeats, each in run order with the start side before the end
/// side, and a ghost fill stops at the first occupied index — so ghosts of
/// two DIFFERENT edges never touch unless their sides differ (a run's end
/// tail against the next run's start). The rederive's own lead-in and tail
/// checks, the painter's dashes, the flip's hold columns and the sheet's
/// chains all read exactly this much.
class TimelineRunEdgeGhost {
  const TimelineRunEdgeGhost({required this.side, required this.mode});

  final TimelineRunEdgeSide side;
  final TimelineRunEdgeMode mode;

  Map<String, dynamic> toJson() => {
    'side': side.toJson(),
    'mode': mode.toJson(),
  };

  factory TimelineRunEdgeGhost.fromJson(Map<String, dynamic> json) =>
      TimelineRunEdgeGhost(
        side: TimelineRunEdgeSide.fromJson(json['side']),
        mode: TimelineRunEdgeMode.fromJson(json['mode']),
      );

  /// The stamp a decoder reads from an entry's optional key — null (an
  /// authored entry) when the key is absent.
  static TimelineRunEdgeGhost? fromJsonOrNull(Object? json) => json == null
      ? null
      : TimelineRunEdgeGhost.fromJson(json as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineRunEdgeGhost && other.side == side && other.mode == mode;

  @override
  int get hashCode => Object.hash(side, mode);

  @override
  String toString() => 'ghost(${side.name} ${mode.name})';
}
