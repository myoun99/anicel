import '../../models/app_language.dart';

/// NOTATION-language strings (UI-R10 #7): what PRINTS on the timesheet —
/// the header box labels and the sheet vocabulary (the repeat word,
/// UI-R10 #6). Independent of the program language: submissions follow
/// the studio's paper convention (default Japanese).
enum TimesheetNotation {
  /// The pre-UI-R10 wording (the reference forms' English, R7-⑥) — the
  /// painter's default so focused tests stay wording-stable.
  english._(
    episode: 'Ep.no',
    title: 'Title',
    scene: 'Scene',
    cut: 'Cut.no',
    duration: 'Duration',
    name: 'Name',
    page: 'Page',
    repeat: 'REPEAT',
    hold: 'HOLD',
  ),
  _ja._(
    episode: '話数',
    title: 'タイトル',
    scene: 'シーン',
    cut: 'カット',
    duration: 'タイム',
    name: '原画',
    page: 'シート',
    repeat: 'リピート',
    hold: '止め',
  ),
  _ko._(
    episode: '화수',
    title: '제목',
    scene: '씬',
    cut: '컷',
    duration: '타임',
    name: '원화',
    page: '시트',
    repeat: '리피트',
    hold: '홀드',
  ),
  _fr._(
    episode: 'Ép.',
    title: 'Titre',
    scene: 'Scène',
    cut: 'Plan',
    duration: 'Durée',
    name: 'Animateur',
    page: 'Feuille',
    repeat: 'RÉPÉT.',
    hold: 'FIXE',
  ),
  _zhHans._(
    episode: '话数',
    title: '标题',
    scene: '场景',
    cut: '镜头',
    duration: '时间',
    name: '原画',
    page: '摄影表',
    repeat: '重复',
    hold: '停格',
  );

  const TimesheetNotation._({
    required this.episode,
    required this.title,
    required this.scene,
    required this.cut,
    required this.duration,
    required this.name,
    required this.page,
    required this.repeat,
    required this.hold,
  });

  final String episode;
  final String title;
  final String scene;
  final String cut;
  final String duration;
  final String name;
  final String page;

  /// The word a repeat ghost span prints instead of re-listing its cel
  /// numbers (UI-R10 #6) — display only, the underlying data keeps the
  /// expanded 1,2,3,1,2,3 for XDTS/TDTS export. Printed VERTICALLY, one
  /// character per row (UI-R11 #14).
  final String repeat;

  /// The word a whole-cut hold prints (UI-R11 #15, the sheet's 止め):
  /// shown when the layer displays as ONE cel from row 1 held to the
  /// end. Vertical like [repeat].
  final String hold;

  static TimesheetNotation of(AppLanguage language) => switch (language) {
    AppLanguage.en => english,
    AppLanguage.ja => _ja,
    AppLanguage.ko => _ko,
    AppLanguage.fr => _fr,
    AppLanguage.zhHans => _zhHans,
  };
}
