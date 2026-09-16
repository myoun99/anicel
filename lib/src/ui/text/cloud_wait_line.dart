import '../../services/persistence/folder_grant.dart' show FileArrival;

import 'app_strings.dart';

/// After this long with NOTHING of the file arrived, the line stops
/// counting quietly and says that nothing has come — which is when a
/// person starts deciding.
///
/// 🚨It is a floor under an ARRIVAL, not a deadline on a clock. A wait
/// that changed its words purely because ten seconds passed said 「받지
/// 못했습니다」 about a file that was arriving perfectly well, just slowly
/// (F-141, 유저 2026-09-16: 「그냥 오래걸리고있는거면 갑자기 표현 다르게
/// 두지말것」).
const Duration cloudWaitSaysNothingAfter = Duration(seconds: 10);

/// THE sentence a cloud wait shows, wherever it is drawn.
///
/// 🚨★★★ONE LAW, ONE PLACE (F-141). The top strip's open window and the
/// import window each wrote this out — the same threshold, the same two
/// templates, the same `{sec}` substitution, in two files. Two spellings
/// of one law drift, and the one that drifts is the one nobody is
/// looking at.
///
/// [arrival] is what the wait has actually seen, so the words can be
/// true: only 「nothing」 may say nothing arrived. A file coming down
/// slowly keeps counting, because that is what is happening.
String cloudWaitLine(Duration waited, FileArrival arrival) {
  final strings = AppText.strings;
  final template =
      arrival == FileArrival.nothing && waited >= cloudWaitSaysNothingAfter
      ? strings.openWaitingStalledTemplate
      : strings.openWaitingCloudTemplate;
  return template.replaceAll('{sec}', '${waited.inSeconds}');
}
