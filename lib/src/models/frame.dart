import '../core/collection_equality.dart';
import 'frame_id.dart';
import '../core/copy_with_sentinel.dart';
import 'layer_kind.dart';
import 'se_line_type.dart';
import 'stroke.dart';

/// THE in-between marks (中割) as DATA — what a cell carries, not a glyph it
/// prints: two marks, one in-between. 🗣️I-130 (유저 2026-10-25): 「지금의
/// 속이 찬 점을 마크2, 속이 빈 그냥 선으로 된 원을 마크1. 이 순서는 토에이
/// 디지털 타임시트, 클튜를 기반으로 확인했음 … 현재로서 두 마크가 다른
/// 기능한다거나 그런건없음. 일단은 모양이 다를뿐인 같은 중간나누기임」.
///
/// ↩️유저 2026-09-24 had named them the other way round — 「중간나누기
/// 마크1로서 작동했으면 … 마크2는 토에이 타임시트에 속이 빈 동그라미」 — and
/// until I-130 there was the one value, the filled ●. ↩️F-149 (유저
/// 2026-09-16: 「일단 이름 없는 기본상태를 속이 찬 동그라미로 통일적용. 추후
/// 두번째 중간나누기 마크(속이 빈)를 활용할지도 모르겠지만 당장은 제거」)
/// retired the hollow ○ the unnamed drawing printed; it is back as mark 1.
enum InbetweenMark {
  /// Mark 1 — the hollow ○, a line round it.
  one,

  /// Mark 2 — the filled ●.
  two;

  /// The mark written as TEXT — a file name, a menu, a notice. Surfaces that
  /// draw draw its shape instead. The one place either glyph is spelled.
  String get glyph => switch (this) {
    InbetweenMark.one => '○',
    InbetweenMark.two => '●',
  };
}

/// The mark a drawing without a cel number wears where the number would
/// stand — mark 2, the filled ● (F-149), drawn as the dot inside a block is
/// (유저 2026-09-24), on the sheet, the timeline, the flip HUD, the
/// storyboard and in a save's notice — on every row but one whose picture
/// is the layer ([drawingHeadOf]).
const InbetweenMark unnamedDrawingMark = InbetweenMark.two;

/// What a drawing's head wears where its block starts: a [word] — its cel
/// number — or, with none, a [mark].
typedef DrawingHead = ({String word, InbetweenMark? mark});

/// What a drawing named [name] on a row of [kind] wears where its block
/// starts, as DATA: its cel number, or — with none — no word, and
/// [unnamedDrawingMark] on the one kind whose unnamed drawing is an
/// in-between ([LayerKind.unnamedDrawingIsInbetween], animation); nothing at
/// all on every other kind (유저 2026-09-26: 「애니메이션 이외 레이어는
/// 이름없으면 진짜 이름없도록 통일」 — 09-25 the image layer first: 「중간나누기
/// 마크가아니라 이름을 안보이게」).
///
/// 🚨ONE ANSWER for every surface that shows a drawing's head — the
/// timeline's rows, the flip window, the folded strip, the storyboard's
/// panels, the sheet — so the mark it wears is the mark of the dot inside a
/// block, drawn by the same code (유저 2026-09-24). The [kind] is required
/// so that no surface can answer for a row without asking what it is.
DrawingHead drawingHeadOf(String? name, {required LayerKind kind}) =>
    switch (celNumberOf(name)) {
      final celNumber? => (word: celNumber, mark: null),
      null when kind.unnamedDrawingIsInbetween => (
        word: '',
        mark: unnamedDrawingMark,
      ),
      null => (word: '', mark: null),
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
    this.seTypes = SeLineTypes.allOn,
    this.filePicture,
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

  /// SE rows only: the line's delivery in each cut it plays in — ON / OFF /
  /// MONO (I-20, F-386). ON when a block never chose, which is also what a
  /// drawing carries and ignores. ⛔There is no cut-less delivery to read:
  /// a surface says which cut it shows ([SeLineTypes.inCut]).
  final SeLineTypes seTypes;

  /// REFERENCE rows only: which picture of the row's file this cel is — a
  /// still's one, a GIF's frame, a PDF's page — counted in the FILE, so the
  /// cel can be made from it again where the row's reference fx stands it
  /// (I-68 — 유저 2026-10-10 「가」: 칸마다 「파일의 몇 번째 그림」을
  /// 기록한다). Null for a cel drawn by hand, and for a movie row's held cel,
  /// whose pictures are decoded as they are shown.
  ///
  /// ⚠️It is the reference's: a row that lets go of its file (rasterized)
  /// lets go of these with it.
  final int? filePicture;

  Frame copyWith({
    FrameId? id,
    int? duration,
    List<Stroke>? strokes,
    Object? name = copyWithSentinel,
    Object? seName = copyWithSentinel,
    SeLineTypes? seTypes,
    Object? filePicture = copyWithSentinel,
  }) {
    return Frame(
      id: id ?? this.id,
      duration: duration ?? this.duration,
      strokes: strokes ?? this.strokes,
      name: identical(name, copyWithSentinel) ? this.name : name as String?,
      seName: identical(seName, copyWithSentinel)
          ? this.seName
          : seName as String?,
      seTypes: seTypes ?? this.seTypes,
      filePicture: identical(filePicture, copyWithSentinel)
          ? this.filePicture
          : filePicture as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id.toJson(),
    'duration': duration,
    'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
    if (name != null) 'name': name,
    if (seName != null) 'seName': seName,
    // ON is the absent field — every drawing, and every block that never
    // chose, reads back as ON.
    ...seTypes.toJson(),
    if (filePicture != null) 'filePicture': filePicture,
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
      seTypes: SeLineTypes.fromJson(json),
      filePicture: json['filePicture'] as int?,
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
          other.seTypes == seTypes &&
          other.filePicture == filePicture &&
          listEquals(other.strokes, strokes);

  @override
  int get hashCode => Object.hash(
    id,
    duration,
    name,
    seName,
    seTypes,
    filePicture,
    Object.hashAll(strokes),
  );

  @override
  String toString() =>
      'Frame(id: $id, duration: $duration, name: $name, '
      'seName: $seName, seTypes: $seTypes, '
      'strokes: $strokes)';
}
