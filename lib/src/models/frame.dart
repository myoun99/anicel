import '../core/collection_equality.dart';
import 'frame_id.dart';
import '../core/copy_with_sentinel.dart';
import 'stroke.dart';
import 'text_cel_style.dart';

/// The in-between division mark (中割) — the one glyph both of its uses
/// print: a drawing without a cel number, and the dot inside a block.
///
/// 🚨★★F-149 (유저 2026-09-16): 「프레임 이름 없는 기본 상태도 중간나누기
/// 마크(속이 빈 동그라미)고, 중간나누기 마크(속이 찬 동그라미)도 중간나누기
/// 마크인건 맞는데, 중간나누기 설정은 2개로 두고싶지만, 일단 이름 없는
/// 기본상태를 속이 찬 동그라미로 통일적용. 추후 두번째 중간나누기
/// 마크(속이 빈)를 활용할지도 모르겠지만 당장은 제거」.
///
/// ⇒ TWO names below, ONE glyph here. The hollow ○ the unnamed drawing
/// printed until now is retired; the day 유저 wants a second mark back,
/// [unnamedDrawingMark] gets its own glyph and nothing else moves.
const String inbetweenMark = '●';

/// What a drawing without a cel number prints where the number would stand
/// — the in-between mark, the same on the sheet, the timeline, the flip
/// HUD, the storyboard and a save's notice.
const String unnamedDrawingMark = inbetweenMark;

/// The cel number a drawing named [name] prints: [name] trimmed, or null
/// when nothing is left of it.
///
/// 🚨★★ONE ANSWER TO 「DOES THIS DRAWING HAVE A NAME」 (C-save-percent,
/// 2026-09-15). The sheet and the cel export asked [Frame.celNumber], where
/// a blank name is no name; seven places on screen asked again with
/// `name.isEmpty`, so a name of spaces printed as spaces on the timeline and
/// as the mark on the sheet. A painter holds a name, not a frame — so the
/// answer is a function of the name, and the getter asks it too.
String? celNumberOf(String? name) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// What a drawing named [name] prints where its block starts: its cel
/// number, or [unnamedDrawingMark].
String celNumberOrMark(String? name) =>
    celNumberOf(name) ?? unnamedDrawingMark;

/// One DRAWING in a layer's cel bank.
///
/// Memos are deliberately NOT here: a frame is the picture, and the same
/// picture may be exposed twice in a cut and shared across linked cuts, so
/// a memo hanging off it would be shared by everything that draws it. They
/// live on the exposure instead ([TimelineExposure.memo]).
class Frame {
  Frame({
    required this.id,
    required this.duration,
    required List<Stroke> strokes,
    this.name,
    this.seName,
    this.textContent,
  }) : strokes = List.unmodifiable(strokes);

  final FrameId id;
  final int duration;
  final List<Stroke> strokes;
  final String? name;

  /// The printed cel number, or null when this drawing is an in-between
  /// division mark (中割).
  ///
  /// 🚨ONE RULE FOR THE SHEET AND THE EXPORT. A drawing without a name is
  /// not "cel N by position" — it is the mark. 유저 2026-09-09: 「프레임
  /// 이름을 그대로 셀 번호 이름으로 출력시키고, 프레임 이름 없으면 그냥
  /// 출력 안 하도록. 이름 없으면 중간나누기 마크인 거니까」. The timesheet
  /// already printed it that way (R5-④, 「never an invented number」) while
  /// the cel export invented `index + 1`, so one drawing was ○ on the sheet
  /// and `A2.png` on disk. Both ask here now; a blank name is no name.
  String? get celNumber => celNumberOf(name);

  /// SE rows only: the speaker/effect name shown in the accent box at the
  /// block start. [name] stays the dialogue there (it predates this field,
  /// so legacy SE labels keep reading as dialogue).
  final String? seName;

  /// Text rows only (R5, §6-s): the cel's PICTURE as parameters — the
  /// baked raster in the brush store is a projection re-baked on edit.
  /// Being a Frame field it shares across linked cuts and rides paste/
  /// duplicate exactly like the drawing it stands for.
  final TextCelContent? textContent;

  Frame copyWith({
    FrameId? id,
    int? duration,
    List<Stroke>? strokes,
    Object? name = copyWithSentinel,
    Object? seName = copyWithSentinel,
    Object? textContent = copyWithSentinel,
  }) {
    return Frame(
      id: id ?? this.id,
      duration: duration ?? this.duration,
      strokes: strokes ?? this.strokes,
      name: identical(name, copyWithSentinel) ? this.name : name as String?,
      seName: identical(seName, copyWithSentinel)
          ? this.seName
          : seName as String?,
      textContent: identical(textContent, copyWithSentinel)
          ? this.textContent
          : textContent as TextCelContent?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'duration': duration,
    'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
    if (name != null) 'name': name,
    if (seName != null) 'seName': seName,
    if (textContent != null) 'textContent': textContent!.toJson(),
  };

  factory Frame.fromJson(Map<String, dynamic> json) {
    return Frame(
      id: FrameId.fromJson(json['id'] as Map<String, dynamic>),
      duration: json['duration'] as int,
      strokes: (json['strokes'] as List<dynamic>)
          .map((stroke) => Stroke.fromJson(stroke as Map<String, dynamic>))
          .toList(),
      name: json['name'] as String?,
      seName: json['seName'] as String?,
      textContent: json['textContent'] is Map<String, dynamic>
          ? TextCelContent.fromJson(json['textContent'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Frame &&
          other.id == id &&
          other.duration == duration &&
          other.name == name &&
          other.seName == seName &&
          other.textContent == textContent &&
          listEquals(other.strokes, strokes);

  @override
  int get hashCode => Object.hash(
    id,
    duration,
    name,
    seName,
    textContent,
    Object.hashAll(strokes),
  );

  @override
  String toString() =>
      'Frame(id: $id, duration: $duration, name: $name, '
      'seName: $seName, textContent: $textContent, strokes: $strokes)';
}
