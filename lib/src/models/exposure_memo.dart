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
  const ExposureMemo({this.note = '', this.actionMemo = ''});

  const ExposureMemo.empty() : note = '', actionMemo = '';

  /// The general memo any row's block can carry.
  final String note;

  /// The storyboard layer's action text — what happens in this cell.
  final String actionMemo;

  bool get isEmpty => note.isEmpty && actionMemo.isEmpty;

  ExposureMemo copyWith({String? note, String? actionMemo}) {
    return ExposureMemo(
      note: note ?? this.note,
      actionMemo: actionMemo ?? this.actionMemo,
    );
  }

  Map<String, dynamic> toJson() => {
    if (note.isNotEmpty) 'note': note,
    if (actionMemo.isNotEmpty) 'action': actionMemo,
  };

  factory ExposureMemo.fromJson(Map<String, dynamic> json) {
    return ExposureMemo(
      note: json['note'] as String? ?? '',
      actionMemo: json['action'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExposureMemo &&
          other.note == note &&
          other.actionMemo == actionMemo;

  @override
  int get hashCode => Object.hash(note, actionMemo);

  @override
  String toString() => 'ExposureMemo(note: $note, action: $actionMemo)';
}
