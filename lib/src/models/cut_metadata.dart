import 'layer_mark.dart';

class CutMetadata {
  const CutMetadata({
    this.note = '',
    this.thumbnailFrameIndex,
    this.mark = LayerMark.none,
  });

  const CutMetadata.empty()
    : note = '',
      thumbnailFrameIndex = null,
      mark = LayerMark.none;

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

  /// [thumbnailFrameIndex] passes as a closure so callers can CLEAR the pin
  /// (`() => null`) — the plain-nullable convention cannot express that.
  CutMetadata copyWith({
    String? note,
    int? Function()? thumbnailFrameIndex,
    LayerMark? mark,
  }) {
    return CutMetadata(
      note: note ?? this.note,
      thumbnailFrameIndex: thumbnailFrameIndex == null
          ? this.thumbnailFrameIndex
          : thumbnailFrameIndex(),
      mark: mark ?? this.mark,
    );
  }

  Map<String, dynamic> toJson() => {
    'note': note,
    if (thumbnailFrameIndex != null) 'thumbnailFrame': thumbnailFrameIndex,
    if (!mark.isNone) 'mark': mark.toJson(),
    // The per-cut fade TARGET (FO/WO) is gone (R3b): the fade is
    // transparency toward the project backdrop, and a white-out is a
    // white cut on a lower track — legacy 'fadeTarget' keys are ignored
    // on read.
  };

  factory CutMetadata.fromJson(Map<String, dynamic> json) {
    return CutMetadata(
      note: json['note'] as String? ?? '',
      thumbnailFrameIndex: json['thumbnailFrame'] as int?,
      mark: LayerMark.fromJson(json['mark']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutMetadata &&
          other.note == note &&
          other.thumbnailFrameIndex == thumbnailFrameIndex &&
          other.mark == mark;

  @override
  int get hashCode => Object.hash(note, thumbnailFrameIndex, mark);

  @override
  String toString() =>
      'CutMetadata(note: $note, thumbnailFrame: $thumbnailFrameIndex, '
      'mark: $mark)';
}
