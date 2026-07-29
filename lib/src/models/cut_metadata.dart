class CutMetadata {
  const CutMetadata({this.note = '', this.thumbnailFrameIndex});

  const CutMetadata.empty() : note = '', thumbnailFrameIndex = null;

  final String note;

  /// The cut-local frame the storyboard block's thumbnail shows; null means
  /// the first frame. Clamped to the playback range at render time, so a
  /// later trim never breaks it.
  final int? thumbnailFrameIndex;

  /// [thumbnailFrameIndex] passes as a closure so callers can CLEAR the pin
  /// (`() => null`) — the plain-nullable convention cannot express that.
  CutMetadata copyWith({String? note, int? Function()? thumbnailFrameIndex}) {
    return CutMetadata(
      note: note ?? this.note,
      thumbnailFrameIndex: thumbnailFrameIndex == null
          ? this.thumbnailFrameIndex
          : thumbnailFrameIndex(),
    );
  }

  Map<String, dynamic> toJson() => {
    'note': note,
    if (thumbnailFrameIndex != null) 'thumbnailFrame': thumbnailFrameIndex,
    // The per-cut fade TARGET (FO/WO) is gone (R3b): the fade is
    // transparency toward the project backdrop, and a white-out is a
    // white cut on a lower track — legacy 'fadeTarget' keys are ignored
    // on read.
  };

  factory CutMetadata.fromJson(Map<String, dynamic> json) {
    return CutMetadata(
      note: json['note'] as String? ?? '',
      thumbnailFrameIndex: json['thumbnailFrame'] as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CutMetadata &&
          other.note == note &&
          other.thumbnailFrameIndex == thumbnailFrameIndex;

  @override
  int get hashCode => Object.hash(note, thumbnailFrameIndex);

  @override
  String toString() =>
      'CutMetadata(note: $note, thumbnailFrame: $thumbnailFrameIndex)';
}
