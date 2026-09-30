/// An SE block's DELIVERY (I-20): the speaker on screen, off it, or inside
/// their own head.
///
/// 🗣️유저 2026-09-30 (I-20): 「se 블록의 타입으로서 on off mono 타입 추가.
/// 업계용언데 on은 화면에서 캐릭터가 말할때. off는 화면밖의 캐릭터 대사,
/// mono는 속마음 대사」 · I-20-Q1: 「타입이 없는 상태는 존재하지않음.
/// 기본값은 ON」 — so there is no "none", and a block that never chose is ON.
enum SeLineType {
  on('ON'),
  off('OFF'),
  mono('MONO');

  const SeLineType(this.label);

  /// What every surface prints — the trade's own words, in every language.
  final String label;

  /// Whether the SHEETS print it — the timesheet over the name and the
  /// conte sheet's dialogue column.
  ///
  /// 🗣️유저 (I-20-Q2 덧말): 「ON일때는 타임시트 이름위랑 콘티용지에는
  /// 표시하지않음. 캔버스에는 표시. 즉 OFF거나 MONO일때만 타임시트/콘티에
  /// 표시」. ONE answer for both sheets; the canvas prints every type.
  bool get printsOnSheets => this != SeLineType.on;

  /// Read back from a file; anything unknown — and an absent field — is ON,
  /// the delivery a block that never chose has.
  static SeLineType fromJson(Object? value) => values.firstWhere(
    (type) => type.name == value,
    orElse: () => SeLineType.on,
  );
}

/// An SE block's own fields besides its dialogue — the speaker's name and
/// the delivery — written together with the dialogue, as one edit.
typedef SeEntryFields = ({String? seName, SeLineType seType});
