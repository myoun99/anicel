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

  @override
  bool operator ==(Object other) =>
      other is ConteWords &&
      other.cut == cut &&
      other.picture == picture &&
      other.action == action &&
      other.dialogue == dialogue &&
      other.seconds == seconds &&
      other.cutsSuffix == cutsSuffix &&
      other.artist == artist;

  @override
  int get hashCode =>
      Object.hash(cut, picture, action, dialogue, seconds, cutsSuffix, artist);
}
