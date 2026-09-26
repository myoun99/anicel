import '../core/collection_equality.dart';
import 'layer_mark.dart';

class CutMetadata {
  const CutMetadata({
    this.note = '',
    this.thumbnailFrameIndex,
    this.mark = LayerMark.none,
    this.staff = const {},
  });

  const CutMetadata.empty()
    : note = '',
      thumbnailFrameIndex = null,
      mark = LayerMark.none,
      staff = const {};

  final String note;

  /// The cut-local frame the storyboard block's thumbnail shows; null means
  /// the first frame. Clamped to the playback range at render time, so a
  /// later trim never breaks it.
  final int? thumbnailFrameIndex;

  /// The cut's 색 라벨 — the SAME label a layer carries, palette and all.
  ///
  /// 🗣️유저 2026-09-26: 「애초에 컷별로 우리가 정한 색라벨 적용할수있게할거거든?
  /// 정한거 그대로 사용. 겸용컷은 물론 한 컷 취급이니까 같이바뀌고 … 색라벨
  /// 정하는건 블록마다 다른거니까 컷버튼안에 있다던가. 선택범위 한상태로
  /// 조작가능한거 물론이고」 — one [LayerMark], not a cut palette of its own,
  /// so a palette change repaints cuts and layers alike. 겸용 cuts carry one
  /// label ([UpdateCutMarkCommand] writes every sibling).
  final LayerMark mark;

  /// Who does each stage's work on THIS cut, where it is not the work's —
  /// by the label's [LayerMark.keySlug], as the work's staff is
  /// (`TimesheetInfo.staff`); a stage with no name here takes the work's
  /// (`TimesheetInfo.staffForCut`). 🗣️유저 09-25: 작품 설정에는 기본값,
  /// 컷 설정에는 컷별 이름 ([[project-settings-window]]).
  final Map<String, String> staff;

  /// [mark]'s name on this cut itself, or empty when it takes the work's.
  String staffNameFor(LayerMark mark) => staff[mark.keySlug] ?? '';

  /// [mark]'s name on this cut replaced ([staffWithName]) — an empty one
  /// gives the stage back to the work's.
  CutMetadata withStaffName(LayerMark mark, String name) =>
      copyWith(staff: staffWithName(staff, mark, name));

  /// [thumbnailFrameIndex] passes as a closure so callers can CLEAR the pin
  /// (`() => null`) — the plain-nullable convention cannot express that.
  CutMetadata copyWith({
    String? note,
    int? Function()? thumbnailFrameIndex,
    LayerMark? mark,
    Map<String, String>? staff,
  }) {
    return CutMetadata(
      note: note ?? this.note,
      thumbnailFrameIndex: thumbnailFrameIndex == null
          ? this.thumbnailFrameIndex
          : thumbnailFrameIndex(),
      mark: mark ?? this.mark,
      staff: staff ?? this.staff,
    );
  }

  Map<String, dynamic> toJson() => {
    'note': note,
    if (thumbnailFrameIndex != null) 'thumbnailFrame': thumbnailFrameIndex,
    if (!mark.isNone) 'mark': mark.toJson(),
    if (staff.isNotEmpty) 'staff': {...staff},
    // The per-cut fade TARGET (FO/WO) is gone (R3b) — legacy 'fadeTarget'
    // keys are ignored on read. ↩️F-192: the black or white a fade clears
    // from or closes to is the TERM's (F.x black, W.x white —
    // `transitionScreenColorOf`), not the cut's and not the backdrop's.
  };

  factory CutMetadata.fromJson(Map<String, dynamic> json) {
    return CutMetadata(
      note: json['note'] as String? ?? '',
      thumbnailFrameIndex: json['thumbnailFrame'] as int?,
      mark: LayerMark.fromJson(json['mark']),
      staff: staffFromJson(json['staff']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutMetadata &&
          other.note == note &&
          other.thumbnailFrameIndex == thumbnailFrameIndex &&
          other.mark == mark &&
          mapEquals(other.staff, staff);

  @override
  int get hashCode => Object.hash(
    note,
    thumbnailFrameIndex,
    mark,
    Object.hashAllUnordered(
      staff.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );

  @override
  String toString() =>
      'CutMetadata(note: $note, thumbnailFrame: $thumbnailFrameIndex, '
      'mark: $mark, staff: $staff)';
}
