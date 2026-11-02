/// The words the conte PRINTS — the head of the body's five columns and
/// the cover's closing lines — handed in already in the NOTATION language
/// (유저 2026-09-25: 「액션/다이얼로그 이런거 고정이아니라 출력용
/// 언어설정있잖아. 그거따르게하고 일본어는 内容, セリフ로 가자. 한국어는
/// 내용 대사, 영어는 액션 다이얼로그」).
///
/// ⛔A model keeps no words per language: the string tables hold them, and
/// the screen reads the notation language's table into one of these.
class ConteWords {
  const ConteWords({
    required this.cut,
    required this.picture,
    required this.action,
    required this.dialogue,
    required this.seconds,
    required this.cutsSuffix,
    required this.artist,
    required this.linked,
    required this.cutHead,
    required this.cutTail,
    required this.wholeCut,
  });

  /// The head of the body's five columns.
  final String cut;
  final String picture;
  final String action;
  final String dialogue;
  final String seconds;

  /// What follows the cover's cut count — 「324cut」 on the reference cover.
  final String cutsSuffix;

  /// The cover's staff line's name for the conte artist.
  final String artist;

  /// What opens the line naming a cut's 겸용 cuts — 「겸용 c100,c102」
  /// (`SheetFixedLines.writtenIn`, F-531).
  final String linked;

  /// What opens the line of a fade on a cut's head — 「カット頭 FI (0+6)」 —
  /// and of one on its tail, 「カット尻」 (`SheetFixedLines.writtenIn`, F-540).
  final String cutHead;
  final String cutTail;

  /// What a timesheet page writes after a camera move that runs the whole
  /// cut — 「A-B PAN (全尺)」 (`sheetCameraLine`, F-542).
  final String wholeCut;

  @override
  bool operator ==(Object other) =>
      other is ConteWords &&
      other.cut == cut &&
      other.picture == picture &&
      other.action == action &&
      other.dialogue == dialogue &&
      other.seconds == seconds &&
      other.cutsSuffix == cutsSuffix &&
      other.artist == artist &&
      other.linked == linked &&
      other.cutHead == cutHead &&
      other.cutTail == cutTail &&
      other.wholeCut == wholeCut;

  @override
  int get hashCode => Object.hash(
    cut,
    picture,
    action,
    dialogue,
    seconds,
    cutsSuffix,
    artist,
    linked,
    cutHead,
    cutTail,
    wholeCut,
  );
}
