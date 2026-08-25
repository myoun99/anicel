import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// The "answer a question" window: a sentence and the ways out of it.
///
/// The width follows the action COUNT rather than the prose, because the
/// footer splits its width evenly — a four-way exit prompt needs room its
/// two-way cousins do not.
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.actions,
    this.titleIcon,
    this.windowKey,
    this.width,
  });

  final String title;
  final IconData? titleIcon;
  final String message;

  /// Left to right; the one that answers 'yes' goes last and carries
  /// [AppWindowActionEmphasis.primary].
  final List<AppWindowAction> actions;

  final Key? windowKey;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return AppWindow(
      windowKey: windowKey,
      title: title,
      titleIcon: titleIcon,
      width: width ?? (actions.length > 2 ? 480.0 : 380.0),
      body: Text(message, style: Theme.of(context).textTheme.bodyMedium),
      actions: actions,
    );
  }
}

/// THE way a refusal or a warning reaches the user (F-10, 유저 2026-08-24).
///
/// > 「se레이어가 아닌곳에서 녹음버튼누르면 앱 최하단에 메시지 뜨는데 이 메시지
/// > ui 싹 삭제. 다른곳에서 쓰고있으면 그거도 삭제하고 이런 경고문은 공통ui창
/// > 띄우는거 사용해서 띄우도록.」
///
/// The bottom-of-window strip it replaces was Material's `SnackBar`, which is
/// the one piece of chrome in this app that nothing else looks like: it lands
/// at the far edge of a 1400px window, away from whatever the user was
/// pressing, and it leaves on a timer whether or not it was read.
///
/// ⚠️Not the same channel as [cursorNotices]. That one answers "why did
/// nothing happen" at the pointer, for a second, for things that happen
/// constantly (drawing where there is no cel). This one is for the things
/// that happen once and are worth stopping for.
Future<void> showAppNotice(
  BuildContext context, {
  required String title,
  required String message,
  IconData? titleIcon,
  Key? windowKey,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: windowKey,
      title: title,
      titleIcon: titleIcon,
      message: message,
      actions: [
        AppWindowAction(
          label: AppText.strings.commonClose,
          actionKey: const ValueKey<String>('app-notice-close'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}
