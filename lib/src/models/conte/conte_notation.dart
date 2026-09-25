import '../app_language.dart';

/// What the conte PRINTS in words — the head of the body's table and the
/// cover's closing lines — in the NOTATION language (the language setting
/// for what prints on submissions, default Japanese), never the program's
/// (유저 2026-09-25: 「액션/다이얼로그 이런거 고정이아니라 출력용
/// 언어설정있잖아. 그거따르게하고 일본어는 内容, セリフ로 가자. 한국어는
/// 내용 대사, 영어는 액션 다이얼로그」).
///
/// The timesheet's vocabulary under the same setting is its own table
/// (`TimesheetNotation`): the two documents print different words.
enum ConteNotation {
  ja._(
    cut: 'カット',
    picture: '画面',
    action: '内容',
    dialogue: 'セリフ',
    seconds: '秒',
    cutsSuffix: 'cut',
    artist: 'コンテ',
  ),
  ko._(
    cut: '컷',
    picture: '화면',
    action: '내용',
    dialogue: '대사',
    seconds: '초',
    cutsSuffix: '컷',
    artist: '콘티',
  ),
  en._(
    cut: 'CUT',
    picture: 'PICTURE',
    action: 'ACTION',
    dialogue: 'DIALOGUE',
    seconds: 'TIME',
    cutsSuffix: ' cuts',
    artist: 'Storyboard',
  ),
  fr._(
    cut: 'PLAN',
    picture: 'IMAGE',
    action: 'ACTION',
    dialogue: 'DIALOGUE',
    seconds: 'DURÉE',
    cutsSuffix: ' plans',
    artist: 'Storyboard',
  ),
  zhHans._(
    cut: '镜头',
    picture: '画面',
    action: '内容',
    dialogue: '台词',
    seconds: '秒',
    cutsSuffix: '个镜头',
    artist: '分镜',
  );

  const ConteNotation._({
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

  static ConteNotation of(AppLanguage language) => switch (language) {
    AppLanguage.ja => ja,
    AppLanguage.ko => ko,
    AppLanguage.en => en,
    AppLanguage.fr => fr,
    AppLanguage.zhHans => zhHans,
  };
}
