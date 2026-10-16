import 'package:flutter/widgets.dart';

import '../dialogs/app_confirm_dialog.dart';
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart' show WarningLine;

/// THE notice an import's [warnings] are read in — a converted project's on
/// the Open door, and the import window's behind its 「경고 N가지」: each
/// thing said once, over every name it was said of — open, one line each —
/// and what was said of no one thing as lines of the sentence's own.
///
/// 🗣️F-370 (유저 2026-10-16: 「줄이 너무 한줄로되있어서 알기힘듬. 좀 더
/// 알기쉽게 줄 나누거나 해서 항목화하도록」): the notice was the warnings
/// one after another, the first six of them, and a layer named by a whole
/// paragraph buried what was said of it. F-370-Q1 (유저 2026-10-17: 「끝 줄을
/// 「경고 N가지」 버튼으로 — 누르면 같은 묶음 알림」): the import window's last
/// line was its first three warnings, joined.
Future<void> showImportWarnings(
  BuildContext context, {
  required Key windowKey,
  required List<WarningLine> warnings,
}) {
  final alone = <String>[];
  final named = <String, List<String>>{};
  for (final (:about, :says) in warnings) {
    if (about == null) {
      alone.add(says);
    } else {
      (named[says] ??= []).add(about);
    }
  }
  return showAppNotice(
    context,
    windowKey: windowKey,
    title: AppText.strings.commonNotice,
    message: [AppText.strings.imLeftBehind, ...alone].join('\n'),
    details: [
      for (final MapEntry(key: says, value: names) in named.entries)
        NoticeDetails(names, heading: says, open: true, oneLineEach: true),
    ],
  );
}
