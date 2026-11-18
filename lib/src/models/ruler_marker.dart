import '../core/collection_equality.dart';
import '../core/frozen_collections.dart';
import 'block_run_move.dart';
import 'cut_id.dart';

/// The colours a ruler marker is filed under.
///
/// 🗣️I-169-Q4 (유저 2026-11-13): 「여러 색」 — the six the mock-up drew and
/// the question named (노랑 · 주황 · 분홍 · 하늘 · 보라 · 흰색), a new marker
/// standing in [yellow]. Red, green and the accent are left out: on a ruler
/// they are the cut's end, the ready bar and the playhead.
enum RulerMarkerColor {
  yellow,
  orange,
  pink,
  sky,
  violet,
  white;

  /// The colour [value] names — [yellow] where it names none, as a marker
  /// that says no colour is.
  static RulerMarkerColor named(Object? value) => values.firstWhere(
    (color) => color.name == value,
    orElse: () => yellow,
  );
}

/// One MARKER on a frame ruler: a note over [length] frames from [start],
/// in a colour (I-169).
///
/// 🗣️유저 2026-11-12: 「타임라인 룰러에 북마크? 메모 넣는기능」, named on
/// 2026-11-13 (I-169-Q1): 「마커로 명명할건데」. A point is a marker one
/// frame long, a span the same thing longer (I-169-Q3 「구간도」 · Q4
/// 「깃발이랑 동일한 모양으로 옆으로 늘린모양으로. 즉 모양 통일」) — one
/// kind, not two.
final class RulerMarker {
  /// [start] below 0 reads as 0 and [length] below 1 as 1: a marker stands
  /// on the ruler, over a frame at least.
  const RulerMarker({
    required int start,
    int length = 1,
    this.text = '',
    this.color = RulerMarkerColor.yellow,
  }) : start = start < 0 ? 0 : start,
       length = length < 1 ? 1 : length;

  /// The first frame it stands over, counted from 0 as its ruler counts.
  final int start;

  /// How many frames it stands over.
  final int length;

  /// What it says — one line, empty where nothing is written.
  final String text;

  final RulerMarkerColor color;

  int get endExclusive => start + length;

  bool covers(int frame) => frame >= start && frame < endExclusive;

  RulerMarker copyWith({
    int? start,
    int? length,
    String? text,
    RulerMarkerColor? color,
  }) => RulerMarker(
    start: start ?? this.start,
    length: length ?? this.length,
    text: text ?? this.text,
    color: color ?? this.color,
  );

  Map<String, Object> toJson() => {
    'start': start,
    if (length != 1) 'length': length,
    if (text.isNotEmpty) 'text': text,
    if (color != RulerMarkerColor.yellow) 'color': color.name,
  };

  factory RulerMarker.fromJson(Map<String, dynamic> json) => RulerMarker(
    start: (json['start'] as num?)?.toInt() ?? 0,
    length: (json['length'] as num?)?.toInt() ?? 1,
    text: '${json['text'] ?? ''}',
    color: RulerMarkerColor.named(json['color']),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RulerMarker &&
          other.start == start &&
          other.length == length &&
          other.text == text &&
          other.color == color;

  @override
  int get hashCode => Object.hash(start, length, text, color);

  @override
  String toString() => 'RulerMarker($start+$length, $color, "$text")';
}

/// WHOSE ruler a set of markers is on: [cutId]'s own, or — with none — the
/// open timeline's.
///
/// 🗣️I-169-Q2 (유저 2026-11-13): 「로컬에서 보이는거랑 글로벌에서 보이는거랑
/// 다름 … 둘이 애초에 용도가 다르기 때문」 — two holders, and a marker is on
/// one of them.
final class RulerMarkerHolder {
  const RulerMarkerHolder.cut(CutId this.cutId);

  const RulerMarkerHolder.timeline() : cutId = null;

  final CutId? cutId;

  @override
  bool operator ==(Object other) =>
      other is RulerMarkerHolder && other.cutId == cutId;

  @override
  int get hashCode => cutId.hashCode;

  @override
  String toString() => switch (cutId) {
    null => "the timeline's ruler",
    final cutId => 'the ruler of $cutId',
  };
}

/// The markers of ONE ruler, in frame order, none over another.
///
/// 🗣️I-169-Q1 (유저 2026-11-13): 「마커끼리 겹치는건 불가능하고 어떻게
/// 움직일지는 프레임블록 규칙이랑 동일하게」. So there is no way to hold two
/// over one frame: every set is made by [RulerMarkers.settled], which lays
/// a marker another reaches just past it — the push a frame block's
/// insertion makes ([startsClearingFrontier]) — and a drag moves one by the
/// frame blocks' own plan ([planBlockRunMove]).
///
/// 🗣️I-169-Q2: 「컷(로컬)이랑 콘티(글로벌)이랑 마커 독립적으로 하고싶음 …
/// 따로따로 설정한단느낌. 뭐 움직인다고 동기화되서 같이움직이지도않음」 — a
/// cut holds its own (`CutMetadata.rulerMarkers`, counted in the cut's
/// frames) and a timeline its own (`ProjectTimeline.rulerMarkers`, counted
/// in the movie's), and nothing carries one into the other.
final class RulerMarkers {
  const RulerMarkers.none() : inOrder = const [];

  RulerMarkers._(List<RulerMarker> markers) : inOrder = frozenList(markers);

  /// [markers] in frame order, each clear of the one before it: one that
  /// starts under another is laid just past it, and the ones after give way
  /// in turn. Markers that start on one frame keep the order they came in.
  factory RulerMarkers.settled(Iterable<RulerMarker> markers) {
    final ordered = [
      for (final (place, marker) in markers.indexed) (place, marker),
    ]..sort(_byStartThenPlace);
    final starts = startsClearingFrontier([
      for (final (_, marker) in ordered)
        (start: marker.start, length: marker.length),
    ], frontier: 0);
    return RulerMarkers._([
      for (final (position, (_, marker)) in ordered.indexed)
        marker.copyWith(start: starts[position]),
    ]);
  }

  static int _byStartThenPlace(
    (int, RulerMarker) a,
    (int, RulerMarker) b,
  ) => switch (a.$2.start.compareTo(b.$2.start)) {
    0 => a.$1.compareTo(b.$1),
    final byStart => byStart,
  };

  /// Every marker, first frame first.
  final List<RulerMarker> inOrder;

  bool get isEmpty => inOrder.isEmpty;

  /// Which marker stands over [frame], as its place in [inOrder] — null
  /// where none does.
  int? indexAt(int frame) {
    for (final (index, marker) in inOrder.indexed) {
      if (marker.covers(frame)) {
        return index;
      }
    }
    return null;
  }

  /// These with [marker] set — in place of the one at [replacing], or as
  /// one more. A marker it now reaches gives way ([RulerMarkers.settled]):
  /// a span made longer in its window pushes what follows, as a block made
  /// longer does.
  RulerMarkers withMarker(RulerMarker marker, {int? replacing}) =>
      RulerMarkers.settled([
        for (final (index, held) in inOrder.indexed)
          if (index == replacing) marker else held,
        if (replacing == null) marker,
      ]);

  /// These without the marker at [index].
  RulerMarkers without(int index) => RulerMarkers._([
    for (final (at, held) in inOrder.indexed)
      if (at != index) held,
  ]);

  /// These with the marker at [index] dragged [frameDelta] frames — THE
  /// frame blocks' move ([planBlockRunMove]): it stops where it touches a
  /// neighbour, trades places with one whose seat the hand has reached, and
  /// a neighbour it has passed goes back to where it stood.
  RulerMarkers moved(int index, int frameDelta) {
    final lengths = [for (final marker in inOrder) marker.length];
    final gaps = leadingGapsOf(
      starts: [for (final marker in inOrder) marker.start],
      lengths: lengths,
    );
    final layout = planBlockRunMove(
      slots: [
        for (final (slot, length) in lengths.indexed)
          (leadingGap: gaps[slot], length: length),
      ],
      runStart: index,
      runEnd: index,
      frameDelta: frameDelta,
    );
    return RulerMarkers._([
      for (final (position, slot) in layout.order.indexed)
        inOrder[slot].copyWith(start: layout.starts[position]),
    ]);
  }

  List<Map<String, Object>> toJson() => [
    for (final marker in inOrder) marker.toJson(),
  ];

  /// The markers [json] lists — none where it lists none — settled, so a
  /// file cannot say two over one frame either.
  factory RulerMarkers.fromJson(Object? json) => json is! List || json.isEmpty
      ? const RulerMarkers.none()
      : RulerMarkers.settled([
          for (final marker in json)
            RulerMarker.fromJson(marker as Map<String, dynamic>),
        ]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RulerMarkers && listEquals(other.inOrder, inOrder);

  @override
  int get hashCode => Object.hashAll(inOrder);

  @override
  String toString() => 'RulerMarkers($inOrder)';
}
