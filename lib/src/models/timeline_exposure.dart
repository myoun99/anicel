import '../core/collection_equality.dart';
import 'exposure_memo.dart';
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
/// UI-R9 #8: the inbetween DOTS (중간나누기 ●) are BLOCK-OWNED now —
/// [breakdownOffsets] inside the entry, so they ride every move/copy of
/// the block for free. The standalone `mark` entry type is retired
/// (free-floating dots on empty cells are no longer a thing; want one
/// there, author an unnamed frame). Legacy mark entries migrate on load:
/// covered marks fold into their block's offsets, free marks drop.
class TimelineExposure {
  const TimelineExposure.drawing(
    FrameId this.frameId, {
    required int this.length,
    this.ghostOf,
    this.breakdownOffsets = const [],
    this.memo,
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

  /// The inbetween DOTS (중간나누기 ●) inside this block, as offsets from
  /// the block start — sorted, unique, each in `1..length-1` (offset 0 is
  /// the drawing itself). Owned by the block: moves/copies carry them,
  /// and a length shrink through [copyWith] drops the offsets it cut off
  /// ([copyWith] and [fromJson] normalize; direct const construction
  /// trusts the caller).
  final List<int> breakdownOffsets;

  /// This block's memo, or null when it carries none. BLOCK-OWNED like
  /// [breakdownOffsets] — moves and copies carry it, re-exposing the same
  /// drawing gets its own, and a linked cut's local timeline keeps its own
  /// without any mirroring rule. Ghost entries never hold one: they are
  /// rederived from a run behaviour on every edit, so there is nothing
  /// there to author against.
  final ExposureMemo? memo;

  /// This block's share of its glued run's START-side and END-side edge
  /// properties (F-134 — see [TimelineRunEdgeMark]). BLOCK-OWNED like
  /// [breakdownOffsets] and [memo]: moves, copies and relinks carry them.
  /// Ghost entries never hold one — a ghost is a property's output, not a
  /// block of the run.
  final TimelineRunEdgeMark startEdge;
  final TimelineRunEdgeMark endEdge;

  /// The mark on [side].
  TimelineRunEdgeMark edgeMark(TimelineRunEdgeSide side) =>
      side == TimelineRunEdgeSide.start ? startEdge : endEdge;

  static List<int> _normalizedOffsets(List<int> offsets, int length) {
    if (offsets.isEmpty) {
      return const [];
    }
    final kept = offsets.where((offset) => offset >= 1 && offset < length)
        .toSet()
        .toList()
      ..sort();
    return List.unmodifiable(kept);
  }

  bool get isDrawing => type == TimelineExposureType.drawing;

  bool hasBreakdownAt(int offset) => breakdownOffsets.contains(offset);

  TimelineExposure copyWith({
    FrameId? frameId,
    int? length,
    List<int>? breakdownOffsets,
    ExposureMemo? Function()? memo,
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
      breakdownOffsets: _normalizedOffsets(
        breakdownOffsets ?? this.breakdownOffsets,
        nextLength,
      ),
      memo: memo == null ? this.memo : memo(),
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
    if (breakdownOffsets.isNotEmpty) 'breakdown': breakdownOffsets,
    if (memo != null && !memo!.isEmpty) 'memo': memo!.toJson(),
    if (!startEdge.isNone) 'startEdge': startEdge.toJson(),
    if (!endEdge.isNone) 'endEdge': endEdge.toJson(),
  };

  /// Decodes the CURRENT format only. Legacy entries (`blank`/`mark`
  /// types, drawing entries without `length`) are migrated in
  /// `Layer.fromJson`, which needs whole-timeline context.
  factory TimelineExposure.fromJson(Map<String, dynamic> json) {
    final type = TimelineExposureType.fromJson(json['type']);
    if (type != TimelineExposureType.drawing) {
      throw const FormatException(
        'Standalone mark timeline entries are legacy; Layer.fromJson '
        'migrates them into block breakdown offsets.',
      );
    }

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
      breakdownOffsets: _normalizedOffsets([
        for (final offset in (json['breakdown'] as List<dynamic>? ?? const []))
          offset as int,
      ], length),
      memo: json['memo'] == null
          ? null
          : ExposureMemo.fromJson(json['memo'] as Map<String, dynamic>),
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
          other.startEdge == startEdge &&
          other.endEdge == endEdge &&
          listEquals(other.breakdownOffsets, breakdownOffsets);

  @override
  int get hashCode => Object.hash(
    type,
    frameId,
    length,
    ghostOf,
    Object.hashAll(breakdownOffsets),
    memo,
    startEdge,
    endEdge,
  );

  @override
  String toString() =>
      'TimelineExposure(type: $type, frameId: $frameId, length: $length'
      '${ghostOf == null ? '' : ', $ghostOf'}'
      '${breakdownOffsets.isEmpty ? '' : ', breakdown: $breakdownOffsets'}'
      '${memo == null ? '' : ', memo: $memo'}'
      '${startEdge.isNone ? '' : ', start: $startEdge'}'
      '${endEdge.isNone ? '' : ', end: $endEdge'})';
}
