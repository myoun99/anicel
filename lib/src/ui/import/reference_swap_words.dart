import '../../models/project.dart';
import '../../models/reference_swap.dart';
import '../text/app_strings.dart';

/// What a person reads when a file let go on a reference row did not come
/// in (I-47) — or a row of a file carried anew was not drawn again
/// (F-550-Q3): the program language's sentence for why, or null when there
/// is nothing to say, the file in or the row left as it was.
///
/// 🗣️I-68 「가」 ⓐ (유저 2026-10-10 「추천대로가자」): a file that reads, and
/// only lacks the picture the row's cel shows, says that — 「bg.png에는
/// 2번째 그림이 없습니다」. ↩️It was told 「could not read the file」, and so
/// was a row that changed while its file was read.
///
/// The file is named as [project]'s pool shows it (F-376).
String? referenceSwapWords(
  ReferenceRedraw answer,
  String path,
  Project project,
) => switch (answer) {
  ReferenceLaid() || ReferenceLeftAlone() => null,
  ReferenceUnreadable() => AppText.strings.imUnreadable(
    project.shownNameOfMedia(path),
  ),
  ReferenceLacksPicture(:final picture) => AppText.strings.imLacksPicture(
    project.shownNameOfMedia(path),
    picture + 1,
  ),
};
