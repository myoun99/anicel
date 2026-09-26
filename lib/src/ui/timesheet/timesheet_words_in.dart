import '../../models/app_language.dart';
import '../../models/timesheet_words.dart';
import '../text/app_strings.dart';

/// What the timesheet prints, in [notation] — the NOTATION language's string
/// table, not the program's, the conte's words' way (`conteWordsIn`).
TimesheetWords timesheetWordsIn(AppLanguage notation) {
  final strings = AppStrings.of(notation);
  return TimesheetWords(
    episode: strings.sheetPrintEpisode,
    title: strings.sheetPrintTitle,
    scene: strings.sheetPrintScene,
    cut: strings.sheetPrintCut,
    duration: strings.sheetPrintDuration,
    name: strings.sheetPrintName,
    page: strings.sheetPrintPage,
    repeat: strings.sheetPrintRepeat,
    hold: strings.sheetPrintHold,
  );
}
