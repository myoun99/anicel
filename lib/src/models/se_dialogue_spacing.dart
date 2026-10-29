/// Where an SE block's dialogue starts and how many frames each glyph takes
/// (F-496 ③).
///
/// 🗣️유저 2026-10-28 (F-496): 「대사 오프셋/글자별 코마 기능 … 왼쪽정렬로
/// 둬서 1코마부터 첫번째 글자가 시작되도록. 대사 오프셋은 이 시작되는
/// 위치를 변경함. 1코마기준으로 움직임. 글자별 코마는 … 3코마로 설정하면
/// 글자 하나당 3코마의 공간을 차지하는느낌 … 참고로 띄어쓰기도 동일하게
/// 코마 적용됨 … 글자별 코마는 기본값 3코마, 오프셋은 기본값 0(1코마째부터
/// 시작)」.
final class SeDialogueSpacing {
  /// [offset] below 0 reads as 0 and [komaPerGlyph] below 1 as 1: a line
  /// starts on its block and a glyph takes a frame at least.
  const SeDialogueSpacing({int offset = 0, int komaPerGlyph = 3})
    : offset = offset < 0 ? 0 : offset,
      komaPerGlyph = komaPerGlyph < 1 ? 1 : komaPerGlyph;

  /// A block that never set them: from its first frame, three a glyph.
  static const standard = SeDialogueSpacing();

  /// How many frames into its block the line's first glyph stands.
  final int offset;

  /// How many frames each glyph — a space too — takes.
  final int komaPerGlyph;

  SeDialogueSpacing copyWith({int? offset, int? komaPerGlyph}) =>
      SeDialogueSpacing(
        offset: offset ?? this.offset,
        komaPerGlyph: komaPerGlyph ?? this.komaPerGlyph,
      );

  /// The fields a drawing writes — none for [standard], the absent fields
  /// every drawing reads back as.
  Map<String, Object> toJson() => {
    if (offset != standard.offset) 'seDialogueOffset': offset,
    if (komaPerGlyph != standard.komaPerGlyph) 'seKomaPerGlyph': komaPerGlyph,
  };

  static SeDialogueSpacing fromJson(Map<String, dynamic> json) =>
      SeDialogueSpacing(
        offset: (json['seDialogueOffset'] as num?)?.toInt() ?? 0,
        komaPerGlyph: (json['seKomaPerGlyph'] as num?)?.toInt() ?? 3,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeDialogueSpacing &&
          other.offset == offset &&
          other.komaPerGlyph == komaPerGlyph;

  @override
  int get hashCode => Object.hash(offset, komaPerGlyph);

  @override
  String toString() => 'SeDialogueSpacing($offset, $komaPerGlyph)';
}
