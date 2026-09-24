/// The instruction attached to one EXPOSURE — the block, not the drawing:
/// what a direction row's span SAYS (the vocabulary mark, its writing, the
/// sheet's A → B values and the memo), apart from where it sits and how long
/// it holds, which are the block's own start and length.
///
/// 🚨R27 (유저 2026-09-12, Q1): 「**블록 = 스팬, 스팬마다 제 그림 한 장**」.
/// A direction row's block IS its span, so the span lives where the block
/// lives — beside `ExposureMemo`, and for the same reason that one moved off
/// the picture: data the block owns rides every move, copy, paste and link
/// with no re-indexing anywhere.
///
/// ⛔THE SPAN DOES NOT POINT AT ITS CEL. That was the first design (09-16),
/// and the user's own follow-up closed it: 「링크는 해도되게 해서 법을 최대한
/// 통일하되 이름을 안보이게, 수정못하게」 (2026-09-12). A link is one cel
/// shown by two blocks, and a block has no identity of its own — so a span
/// holding a cel id could not say which of the two it followed, and pairing
/// them by order swaps the two instructions the moment a move reorders the
/// linked blocks. Owned by the block, each keeps its own.
///
/// ⚠️NO LENGTH HERE, on purpose: a span's length is its block's. Two fields
/// answering one question drift; `InstructionEvent.of` is the one place the
/// two meet.
class ExposureInstruction {
  const ExposureInstruction({
    required this.instructionId,
    this.text,
    this.valueA,
    this.valueB,
    this.memo,
  });

  /// See `InstructionEvent.instructionId`.
  final String instructionId;

  /// See `InstructionEvent.text`.
  final String? text;

  /// See `InstructionEvent.valueA`.
  final String? valueA;

  /// See `InstructionEvent.valueB`.
  final String? valueB;

  /// See `InstructionEvent.memo`.
  final String? memo;

  /// The keys a span writes beside its length — ONE spelling of them, which
  /// `InstructionEvent.toJson` spreads too.
  Map<String, dynamic> toJson() => {
    'instructionId': instructionId,
    if (text != null) 'text': text,
    if (valueA != null) 'valueA': valueA,
    if (valueB != null) 'valueB': valueB,
    if (memo != null) 'memo': memo,
  };

  factory ExposureInstruction.fromJson(Map<String, dynamic> json) =>
      ExposureInstruction(
        instructionId: json['instructionId'] as String,
        text: json['text'] as String?,
        valueA: json['valueA'] as String?,
        valueB: json['valueB'] as String?,
        memo: json['memo'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExposureInstruction &&
          other.instructionId == instructionId &&
          other.text == text &&
          other.valueA == valueA &&
          other.valueB == valueB &&
          other.memo == memo;

  @override
  int get hashCode => Object.hash(instructionId, text, valueA, valueB, memo);

  @override
  String toString() =>
      'ExposureInstruction($instructionId, text: $text, '
      'valueA: $valueA, valueB: $valueB, memo: $memo)';
}
