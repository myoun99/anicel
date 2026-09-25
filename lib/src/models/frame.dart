import '../core/collection_equality.dart';
import 'frame_id.dart';
import '../core/copy_with_sentinel.dart';
import 'layer_kind.dart';
import 'stroke.dart';
import 'text_cel_style.dart';

/// The in-between division mark (中割) written as TEXT — mark 1's glyph
/// ([InbetweenMark.glyph]), for both of its uses: a drawing without a cel
/// number, and the dot inside a block.
///
/// 🚨★★F-149 (유저 2026-09-16): 「프레임 이름 없는 기본 상태도 중간나누기
/// 마크(속이 빈 동그라미)고, 중간나누기 마크(속이 찬 동그라미)도 중간나누기
/// 마크인건 맞는데, 중간나누기 설정은 2개로 두고싶지만, 일단 이름 없는
/// 기본상태를 속이 찬 동그라미로 통일적용. 추후 두번째 중간나누기
/// 마크(속이 빈)를 활용할지도 모르겠지만 당장은 제거」.
///
/// ⇒ ONE glyph here. The hollow ○ the unnamed drawing printed until F-149
/// is retired; the second mark 유저 has in mind arrives as a second
/// [InbetweenMark] (2026-09-24), with a glyph of its own.
const String inbetweenMark = '●';

/// THE in-between marks as DATA — what a cell carries, not a glyph it prints.
///
/// 🗣️유저 2026-09-24: 「데이터적으로도 같은 취급시키는거 맞지? 중간나누기
/// 마크1로서 작동했으면하는데. 마크2는 토에이 타임시트에 속이 빈 동그라미가
/// 있어서 그게 될 예정이고, 아무튼 중간나누기는 마크1이랑 마크2 두개로
/// 나눌예정」. ↩️F-149 had made the two share a GLYPH only: a drawing with no
/// cel number printed [inbetweenMark] as its name, while the dot inside a
/// block was a mark — so every surface drew the two apart, the sheet at two
/// sizes. They are one mark now, [one], from the model up; mark 2 (the Toei
/// sheet's hollow ○) arrives as a second value here.
enum InbetweenMark {
  /// Mark 1 — the filled ●.
  one;

  /// The mark written as TEXT — a file name, a menu, a notice. Surfaces that
  /// draw draw its shape instead.
  String get glyph => switch (this) {
    InbetweenMark.one => inbetweenMark,
  };
}

/// The mark a drawing without a cel number wears where the number would
/// stand — mark 1, the same mark as the dot inside a block (유저
/// 2026-09-24), on the sheet, the timeline, the flip HUD, the storyboard and
/// in a save's notice — on every row but one whose picture is the layer
/// ([drawingHeadOf]).
const InbetweenMark unnamedDrawingMark = InbetweenMark.one;

/// The mark the dot inside a block wears (its breakdown offsets) — mark 1,
/// the same mark as [unnamedDrawingMark]. The mark-2 round is where a block
/// says which.
const InbetweenMark breakdownMark = InbetweenMark.one;

/// What a drawing's head wears where its block starts: a [word] — its cel
/// number — or, with none, a [mark].
typedef DrawingHead = ({String word, InbetweenMark? mark});

/// What a drawing named [name] on a row of [kind] wears where its block
/// starts, as DATA: its cel number, or — with none — no word and
/// [unnamedDrawingMark]; nothing at all where the unnamed cel is the layer's
/// own picture ([LayerKind.unnamedCelIsTheLayer], 유저 2026-09-25: 「중간나누기
/// 마크가아니라 이름을 안보이게」).
///
/// 🚨ONE ANSWER for every surface that shows a drawing's head — the
/// timeline's rows, the flip window, the folded strip, the storyboard's
/// panels, the sheet — so the mark it wears is the mark of the dot inside a
/// block, drawn by the same code (유저 2026-09-24). The [kind] is required
/// so that no surface can answer for an image row without asking.
DrawingHead drawingHeadOf(String? name, {required LayerKind kind}) =>
    switch (celNumberOf(name)) {
      final celNumber? => (word: celNumber, mark: null),
      null when kind.unnamedCelIsTheLayer => (word: '', mark: null),
      null => (word: '', mark: unnamedDrawingMark),
    };

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

/// What a drawing named [name] on a row of [kind] WRITES where its block
/// starts, as TEXT — a file name, a notice: [drawingHeadOf], its mark
/// spelled as its glyph. A surface that draws asks [drawingHeadOf] and
/// draws the mark.
String celNumberOrMark(String? name, {required LayerKind kind}) {
  final head = drawingHeadOf(name, kind: kind);
  return head.mark?.glyph ?? head.word;
}

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

  /// ↩️A TEXT row's picture as parameters (R5, §6-s) until F-154 removed
  /// the kind: nothing writes it any more. It still reads from an old file
  /// and rides copies until the save format drops it — the save lane's
  /// half of F-154, left to it on purpose.
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
