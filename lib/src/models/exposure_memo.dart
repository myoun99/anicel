/// A memo attached to one EXPOSURE — the block, not the drawing.
///
/// It used to hang off [Frame], which made it a property of the PICTURE:
/// re-exposing the same cel twice shared one memo, and a linked cut (whose
/// cel bank is shared and whose timeline is local) shared it across cuts.
/// Neither is what a memo means. Living on [TimelineExposure] instead puts
/// it beside [TimelineExposure.breakdownOffsets] — data the block owns, so
/// every move and copy carries it with no re-indexing anywhere.
///
/// [actionMemo] is the storyboard layer's ACTION column. Dialogue is not
/// here: the SE blocks are its single truth (their frame name is the line,
/// their `seName` the speaker), and the conte reads them directly.
class ExposureMemo {
  const ExposureMemo({this.note = '', this.actionMemo = '', this.inkId = ''});

  const ExposureMemo.empty() : note = '', actionMemo = '', inkId = '';

  /// The general memo any row's block can carry.
  final String note;

  /// The storyboard layer's action text — what happens in this cell.
  final String actionMemo;

  /// Whose handwriting on the conte sheet is this block's: the key its row
  /// ink is kept under (`conteInkRowKey`). Empty until the block is first
  /// written on.
  ///
  /// The BLOCK's, not the drawing's (유저 2026-09-25, conte-drawing-target:
  /// 「해당 콘티레이어의 해당 콘티블록에 데이터 저장하는느낌. 다만 이는
  /// 독립적 … 같은 이름의 콘티블록이 있다면 … 서로 링크안되도록」): two
  /// exposures of one cel write on the sheet each for itself, as each has
  /// its own ACTION. ↩️It was the cel's id, so a link, a linked paste and
  /// the tail of a split block all showed one block's handwriting.
  final String inkId;

  bool get isEmpty => note.isEmpty && actionMemo.isEmpty && inkId.isEmpty;

  ExposureMemo copyWith({String? note, String? actionMemo, String? inkId}) {
    return ExposureMemo(
      note: note ?? this.note,
      actionMemo: actionMemo ?? this.actionMemo,
      inkId: inkId ?? this.inkId,
    );
  }

  Map<String, dynamic> toJson() => {
    if (note.isNotEmpty) 'note': note,
    if (actionMemo.isNotEmpty) 'action': actionMemo,
    if (inkId.isNotEmpty) 'ink': inkId,
  };

  factory ExposureMemo.fromJson(Map<String, dynamic> json) {
    return ExposureMemo(
      note: json['note'] as String? ?? '',
      actionMemo: json['action'] as String? ?? '',
      inkId: json['ink'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExposureMemo &&
          other.note == note &&
          other.actionMemo == actionMemo &&
          other.inkId == inkId;

  @override
  int get hashCode => Object.hash(note, actionMemo, inkId);

  @override
  String toString() =>
      'ExposureMemo(note: $note, action: $actionMemo, ink: $inkId)';
}
