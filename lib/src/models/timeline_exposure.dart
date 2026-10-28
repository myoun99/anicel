import '../core/collection_equality.dart';
import 'exposure_instruction.dart';
import 'exposure_memo.dart';
import 'frame.dart' show InbetweenMark;
import 'frame_id.dart';
import 'timeline_exposure_type.dart';
import 'timeline_run_behavior.dart';

/// One authored timeline entry: a drawing block start (frame + an explicit
/// hold length in frames).
///
/// The hold length lives HERE, not on `Frame.duration`: linked uses of the
/// same frame at different timeline positions can hold for different
/// lengths. A drawing at index `s` covers `[s, s + length)`; indexes not
/// covered by any drawing are empty ("X" cells) without any entry existing.
///
/// UI-R9 #8: the inbetween DOTS (중간나누기 ○ ●) are BLOCK-OWNED now —
/// [breakdownMarks] inside the entry, so they ride every move/copy of
/// the block for free. The standalone `mark` entry type is retired
/// (free-floating dots on empty cells are no longer a thing; want one
/// there, author an unnamed frame). Legacy mark entries migrate on load:
/// covered marks fold into their block's offsets, free marks drop.
class TimelineExposure {
  const TimelineExposure.drawing(
    FrameId this.frameId, {
    required int this.length,
    this.ghostOf,
    this.breakdownMarks = const {},
    this.memo,
    this.instruction,
    this.startEdge = TimelineRunEdgeMark.none,
    this.endEdge = TimelineRunEdgeMark.none,
  }) : type = TimelineExposureType.drawing,
       assert(length >= 1, 'Drawing exposure length must be at least 1.');

  final TimelineExposureType type;
  final FrameId? frameId;

  /// Hold length in frames; non-null iff [type] is drawing.
  final int? length;

  /// A DERIVED exposure (UI-R8/UI-R9, TVP-style hold/repeat edges):
  /// synthesized by the run-behavior rederive pass — never authored
  /// directly, wiped and rebuilt on every timeline edit. Ghosts share the
  /// source's frameId (drawing at a ghost index edits the source) and
  /// render dimmed on the timeline cells only; playback and the canvas
  /// treat them as ordinary exposures.
  bool get ghost => ghostOf != null;

  /// The edge property this ghost was derived from; null on an authored
  /// entry — the one field says both whether and what.
  final TimelineRunEdgeGhost? ghostOf;

  /// The inbetween DOTS (중간나누기) inside this block: the mark each wears,
  /// by its offset from the block start — ascending, each in `1..length-1`
  /// (offset 0 is the drawing itself), one mark to a cell (I-130: 「모양이
  /// 다를뿐인 같은 중간나누기」). Owned by the block: moves/copies carry
  /// them, and a length shrink through [copyWith] drops the offsets it cut
  /// off ([copyWith] and [fromJson] normalize; direct const construction
  /// trusts the caller).
  final Map<int, InbetweenMark> breakdownMarks;

  /// Where [breakdownMarks]' dots stand, ascending — whatever they wear.
  List<int> get breakdownOffsets => [...breakdownMarks.keys];

  /// A block's [marks] as they stand on a block that starts [cut] cells into
  /// it: each moved back [cut], each wearing its mark, and the ones at or
  /// before the cut gone — offset 0 is the drawing itself.
  ///
  /// THE one shift for every block that loses its head: the tail a band's X
  /// leaves, the back half of a split, a repeat's part a wall cuts into.
  /// ↩️Each of the three spelled it (I-130 found them carrying the mark).
  static Map<int, InbetweenMark> marksPastCut(
    Map<int, InbetweenMark> marks,
    int cut,
  ) => {
    for (final MapEntry(key: offset, value: mark) in marks.entries)
      if (offset > cut) offset - cut: mark,
  };

  /// This block's memo, or null when it carries none. BLOCK-OWNED like
  /// [breakdownMarks] — moves and copies carry it, re-exposing the same
  /// drawing gets its own, and a linked cut's local timeline keeps its own
  /// without any mirroring rule. Ghost entries never hold one: they are
  /// rederived from a run behaviour on every edit, so there is nothing
  /// there to author against.
  final ExposureMemo? memo;

  /// This block's instruction — the span a DIRECTION row's block is (R27,
  /// [ExposureInstruction]) — or null on every other row. BLOCK-OWNED like
  /// [memo]: moves, copies and links carry it, so a linked block keeps its
  /// own. Ghost entries never hold one — a ghost is a hold's projection, not
  /// a span.
  final ExposureInstruction? instruction;

  /// This block's share of its glued run's START-side and END-side edge
  /// properties (F-134 — see [TimelineRunEdgeMark]). BLOCK-OWNED like
  /// [breakdownMarks] and [memo]: moves, copies and relinks carry them.
  /// Ghost entries never hold one — a ghost is a property's output, not a
  /// block of the run.
  final TimelineRunEdgeMark startEdge;
  final TimelineRunEdgeMark endEdge;

  /// The mark on [side].
  TimelineRunEdgeMark edgeMark(TimelineRunEdgeSide side) =>
      side == TimelineRunEdgeSide.start ? startEdge : endEdge;

  static Map<int, InbetweenMark> _normalizedMarks(
    Map<int, InbetweenMark> marks,
    int length,
  ) {
    if (marks.isEmpty) {
      return const {};
    }
    final kept = [
      for (final offset in marks.keys)
        if (offset >= 1 && offset < length) offset,
    ]..sort();
    return Map.unmodifiable({for (final offset in kept) offset: marks[offset]});
  }

  /// The key a file writes [mark]'s dots under, as a list of offsets.
  ///
  /// ↩️`breakdown` held the one mark there was before I-130, the filled ●
  /// — mark 2 now — so it goes on holding it: a file written before reads
  /// as it showed.
  static String _breakdownKey(InbetweenMark mark) => switch (mark) {
    InbetweenMark.one => 'breakdown1',
    InbetweenMark.two => 'breakdown',
  };

  /// Where the dots that wear [mark] stand, ascending.
  List<int> _offsetsWearing(InbetweenMark mark) => [
    for (final MapEntry(key: offset, value: wears) in breakdownMarks.entries)
      if (wears == mark) offset,
  ];

  /// The dots an entry's [json] writes, as they are written — the ONE
  /// reader of them, for [fromJson] and the layer's own timeline decoder.
  /// What its length cuts off is [copyWith]'s to drop.
  static Map<int, InbetweenMark> breakdownMarksFromJson(
    Map<String, dynamic> json,
  ) => {
    for (final mark in InbetweenMark.values)
      for (final offset
          in json[_breakdownKey(mark)] as List<dynamic>? ?? const [])
        offset as int: mark,
  };

  bool get isDrawing => type == TimelineExposureType.drawing;

  TimelineExposure copyWith({
    FrameId? frameId,
    int? length,
    Map<int, InbetweenMark>? breakdownMarks,
    ExposureMemo? Function()? memo,
    ExposureInstruction? Function()? instruction,
    TimelineRunEdgeMark? startEdge,
    TimelineRunEdgeMark? endEdge,
  }) {
    final nextLength = length ?? this.length!;
    return TimelineExposure.drawing(
      frameId ?? this.frameId!,
      length: nextLength,
      ghostOf: ghostOf,
      // Normalization clamps offsets to the (possibly new) length — a
      // shrink drops what it cut off.
      breakdownMarks: _normalizedMarks(
        breakdownMarks ?? this.breakdownMarks,
        nextLength,
      ),
      memo: memo == null ? this.memo : memo(),
      instruction: instruction == null ? this.instruction : instruction(),
      startEdge: startEdge ?? this.startEdge,
      endEdge: endEdge ?? this.endEdge,
    );
  }

  /// This entry with [mark] on [side].
  TimelineExposure withEdgeMark(
    TimelineRunEdgeSide side,
    TimelineRunEdgeMark mark,
  ) => side == TimelineRunEdgeSide.start
      ? copyWith(startEdge: mark)
      : copyWith(endEdge: mark);

  Map<String, dynamic> toJson() => {
    'type': type.toJson(),
    if (frameId != null) 'frameId': frameId!.toJson(),
    if (length != null) 'length': length,
    if (ghostOf != null) 'ghostOf': ghostOf!.toJson(),
    for (final mark in InbetweenMark.values)
      if (_offsetsWearing(mark) case final offsets when offsets.isNotEmpty)
        _breakdownKey(mark): offsets,
    if (memo != null && !memo!.isEmpty) 'memo': memo!.toJson(),
    if (instruction != null) 'instruction': instruction!.toJson(),
    if (!startEdge.isNone) 'startEdge': startEdge.toJson(),
    if (!endEdge.isNone) 'endEdge': endEdge.toJson(),
  };

  factory TimelineExposure.fromJson(Map<String, dynamic> json) {
    // A drawing is the one kind of entry: anything else is refused here.
    TimelineExposureType.fromJson(json['type']);
    final frameIdJson = json['frameId'];
    final length = json['length'];
    if (frameIdJson == null || length is! int || length < 1) {
      throw const FormatException(
        'Drawing timeline entry requires frameId and a positive length.',
      );
    }
    return TimelineExposure.drawing(
      FrameId.fromJson(frameIdJson as Map<String, dynamic>),
      length: length,
      ghostOf: TimelineRunEdgeGhost.fromJsonOrNull(json['ghostOf']),
      breakdownMarks: _normalizedMarks(breakdownMarksFromJson(json), length),
      memo: json['memo'] == null
          ? null
          : ExposureMemo.fromJson(json['memo'] as Map<String, dynamic>),
      instruction: json['instruction'] == null
          ? null
          : ExposureInstruction.fromJson(
              json['instruction'] as Map<String, dynamic>,
            ),
      startEdge: TimelineRunEdgeMark.fromJsonOrNone(json['startEdge']),
      endEdge: TimelineRunEdgeMark.fromJsonOrNone(json['endEdge']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimelineExposure &&
          other.type == type &&
          other.frameId == frameId &&
          other.length == length &&
          other.ghostOf == ghostOf &&
          other.memo == memo &&
          other.instruction == instruction &&
          other.startEdge == startEdge &&
          other.endEdge == endEdge &&
          mapEquals(other.breakdownMarks, breakdownMarks);

  @override
  int get hashCode => Object.hash(
    type,
    frameId,
    length,
    ghostOf,
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in breakdownMarks.entries)
        Object.hash(key, value),
    ]),
    memo,
    instruction,
    startEdge,
    endEdge,
  );

  @override
  String toString() =>
      'TimelineExposure(type: $type, frameId: $frameId, length: $length'
      '${ghostOf == null ? '' : ', $ghostOf'}'
      '${breakdownMarks.isEmpty ? '' : ', breakdown: $breakdownMarks'}'
      '${memo == null ? '' : ', memo: $memo'}'
      '${instruction == null ? '' : ', instruction: $instruction'}'
      '${startEdge.isNone ? '' : ', start: $startEdge'}'
      '${endEdge.isNone ? '' : ', end: $endEdge'})';
}
