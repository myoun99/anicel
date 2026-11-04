import '../core/collection_equality.dart';
import 'cut_id.dart';

/// 동기컷 — ONE CUT SHOWN IN SEVERAL TIMELINES (I-150-Q3).
///
/// 🗣️유저 2026-11-03 (I-150-Q3): 「일단 다른 타임라인끼리는 단순 겸용컷
/// 작동안하게. 지금 겸용 만드는게 컷 복사하고 다른타임라인에 링크붙여넣기
/// 뿐인데 이 동작을 겸용컷이라기보다 새 시스템으로 타임라인 링크컷?으로
/// 작동하게. 이름은 뭐로할지는 맡김. 이는 겸용컷이면서 추가로 타임라인까지
/// 완벽동기화된 실질 같은컷 취급. 배지에도 겸용이란 이름이아니라 동기컷? 뭐
/// 그런식으로 따로 표시하고 인쇄물같은곳엔 동기컷은 표시안함」.
///
/// So the cuts of a sync are 겸용 cuts — their rows linked, their pictures
/// one ([LayerLinkGroup]) — that are ALSO kept one in everything else: the
/// lanes a 겸용 keeps per use (timing, keys, the eye), the direction rows,
/// the cut's length, camera, guides and papers, and the sheets' handwriting.
/// Each keeps its own place only: its name and the gap in front of it
/// (`syncedCopy`). At most one of them stands in each timeline.
class CutSync {
  CutSync({required this.id, required List<CutId> cuts})
    : cuts = List.unmodifiable(cuts) {
    if (cuts.length < 2) {
      throw ArgumentError.value(cuts, 'cuts', 'A sync holds two cuts or more.');
    }
  }

  final String id;

  /// The cuts kept one, CANONICAL first: the one whose id the sheets'
  /// handwriting is kept under (`syncedSheetInkKey`).
  final List<CutId> cuts;

  CutId get canonical => cuts.first;

  CutSync copyWith({List<CutId>? cuts}) =>
      CutSync(id: id, cuts: cuts ?? this.cuts);

  Map<String, dynamic> toJson() => {
    'id': id,
    'cuts': [for (final cut in cuts) cut.toJson()],
  };

  factory CutSync.fromJson(Map<String, dynamic> json) => CutSync(
    id: json['id'] as String,
    cuts: [
      for (final cut in json['cuts'] as List)
        CutId.fromJson(cut as Map<String, dynamic>),
    ],
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutSync && other.id == id && listEquals(other.cuts, cuts);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(cuts));

  @override
  String toString() => 'CutSync(id: $id, cuts: $cuts)';
}
