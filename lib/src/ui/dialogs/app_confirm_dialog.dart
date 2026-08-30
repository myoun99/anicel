import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../input/control_press_claim.dart';

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
    this.details = const [],
  });

  final String title;
  final IconData? titleIcon;
  final String message;

  /// Lines the sentence is ABOUT — file paths, names — behind a disclosure
  /// so one of them and forty read the same.
  ///
  /// 유저 2026-08-29: 「두번째줄에 해당 파일들이라는 항목으로 접기 펼치기
  /// 가능하게 그 안에 파일주소,이름들 표시」. ⛔They do not go in [message]:
  /// a sentence that grows with the list pushes the buttons off a small
  /// window, and the count is not what the reader is there for.
  final List<String> details;

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
      body: details.isEmpty
          ? Text(message, style: Theme.of(context).textTheme.bodyMedium)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 8),
                _DetailsDisclosure(lines: details),
              ],
            ),
      actions: actions,
    );
  }
}

/// The 「해당 파일들」 section: a heading that folds, and the lines under it.
///
/// ⛔Starts CLOSED. The notice's job is the sentence; the list is what you
/// open when you want to know which ones, and forty paths opening by
/// themselves would bury the sentence that explains them.
class _DetailsDisclosure extends StatefulWidget {
  const _DetailsDisclosure({required this.lines});

  final List<String> lines;

  @override
  State<_DetailsDisclosure> createState() => _DetailsDisclosureState();
}

class _DetailsDisclosureState extends State<_DetailsDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ControlPressClaim(child: InkWell(
          key: const ValueKey<String>('app-notice-details-toggle'),
          onTap: () => setState(() => _open = !_open),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                size: 18,
              ),
              Text(
                '${AppText.strings.commonAffectedFiles} (${widget.lines.length})',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        )),
        // ⛔The space is NOT reserved when closed: this is a dialog that
        // sizes to its content, and an empty box under the heading would
        // make every notice taller for a list nobody opened. The rule it
        // looks like (「없다가 생기는 UI 금지」) is about a LAYOUT holding
        // still while its contents change; a disclosure IS the control
        // whose whole purpose is to change the height.
        if (_open)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const ValueKey<String>('app-notice-details-list'),
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final line in widget.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          line,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
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
  /// The lines this notice is ABOUT — see [AppConfirmDialog.details].
  List<String> details = const [],
  Key? windowKey,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: windowKey,
      title: title,
      titleIcon: titleIcon,
      message: message,
      details: details,
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
