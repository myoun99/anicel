import '../../models/app_language.dart';
import '../../models/conte/conte_words.dart';
import '../text/app_strings.dart';

/// What the conte prints, in [notation] — the NOTATION language's string
/// table, not the program's, the way the timesheet prints (유저 2026-09-25:
/// 「출력용 언어설정있잖아. 그거따르게하고」).
ConteWords conteWordsIn(AppLanguage notation) {
  final strings = AppStrings.of(notation);
  return ConteWords(
    cut: strings.cnHeadCut,
    picture: strings.cnHeadPicture,
    action: strings.cnHeadAction,
    dialogue: strings.cnHeadDialogue,
    seconds: strings.cnHeadSeconds,
    cutsSuffix: strings.cnCoverCuts,
    artist: strings.cnCoverArtist,
  );
}
