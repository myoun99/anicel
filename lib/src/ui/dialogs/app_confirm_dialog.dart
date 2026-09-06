import 'dart:async';

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
        ControlPressClaim(onPressed: () => setState(() => _open = !_open), child: InkWell(
          key: const ValueKey<String>('app-notice-details-toggle'),
          onTap: silentPress(() => setState(() => _open = !_open)),
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
            // ⛔NO SCROLLBAR BY HAND. `AppScrollBehavior` already gives
            // every scrollable in the app the same one, so a framework
            // `Scrollbar` here drew a SECOND bar over it — 유저 answered
            // ARCH-audit-Q2 「unify」 and this is what unifying means: not
            // swapping the widget, but deleting the one that was doubled.
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
  /// The lines this notice is ABOUT — see [AppConfirmDialog.details].
  List<String> details = const [],
  Key? windowKey,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: windowKey,
      title: title,
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

/// A caught file error, reported the way every file error in this app is:
/// a [showAppNotice] under the common notice title, carrying the error's
/// own text.
///
/// 🚨ONE law for reporting a caught file error. It was written out three
/// times in the top strip alone — a private method on the strip's State,
/// which the two module-level save/export functions in the same file could
/// not call, so they re-typed its body.
///
/// ⚠️The `context.mounted` check stays at the CALLER, not in here: a
/// caught error always arrives after an await, and `use_build_context_
/// synchronously` proves that gap at the call site or nowhere. A guard in
/// here would be a second, invisible one that the analyzer cannot read.
///
/// Fire-and-forget on purpose: the caller is on its way out of a failed
/// operation and does not wait for the notice to be dismissed.
void showFileError(BuildContext context, Object error) => unawaited(
  showAppNotice(
    context,
    title: AppText.strings.commonNotice,
    message: '$error',
  ),
);

/// One of the two answers a yes/no window offers: what the button SAYS
/// and how loudly it says it.
///
/// ⚠️The key it wears and the value it pops are NOT here. Those belong to
/// the window — [confirmActions] puts them on — so no caller can hand the
/// accept button the decline's key, or pop the wrong answer.
class ConfirmChoice {
  const ConfirmChoice(this.label, {this.emphasis, this.tooltip});

  final String label;

  /// Null wears the ink the ROLE gives it: accent for the accept, quiet
  /// for the decline. Spelled out only where the confirm is destructive
  /// (the recovery gate's "open the saved one" throws work away).
  final AppWindowActionEmphasis? emphasis;

  /// The consequence the label cannot hold — see [AppWindowAction.tooltip]
  /// for why it is never the only line of defence.
  final String? tooltip;
}

/// What a yes/no window ASKS: the name it wears and the sentence it puts
/// to the user.
class ConfirmQuestion {
  const ConfirmQuestion({
    required this.keys,
    required this.title,
    required this.message,
    this.titleIcon,
  });

  /// ⛔THE THREE KEYS ARE ONE NAME (see [confirmDialogKeys]), so they ride
  /// with the question rather than with the two answers: the prefix that
  /// spells all three IS the question's name.
  final ConfirmDialogKeys keys;

  final String title;
  final String message;
  final IconData? titleIcon;
}

/// Asks a yes/no question in the app's own window and answers what the
/// user did: `true` accepted, `false` declined, **null** dismissed — the
/// barrier or escape.
///
/// 🚨THE DOOR into the two-button confirm, the way [showAppNotice] is the
/// door into the one-button one. Eight sites opened it by hand
/// (`showDialog<bool>` → `AppConfirmDialog` → [confirmActions]), varying
/// only in labels, keys, icon, emphasis and tooltip — all values.
///
/// ⚠️The RAW `bool?` comes back on purpose. The three answers are not the
/// same everywhere: most sites read `!= true`, the selection move reads
/// `== false` (dismissing keeps the move rather than reverting it), and
/// the autosave-recovery gate treats null as "close the whole flow". A
/// helper that folded null into false would have quietly changed all
/// three.
///
/// ⛔Not for a dialog that is its OWN widget — `delete_layer_dialog.dart`
/// and `frame_name_conflict_dialog.dart` are built on [AppConfirmDialog]
/// as widgets, which is a different thing from this recipe.
Future<bool?> askConfirm(
  BuildContext context,
  ConfirmQuestion question, {
  required ConfirmChoice accept,
  ConfirmChoice? decline,
}) => showDialog<bool>(
  context: context,
  builder: (context) => AppConfirmDialog(
    windowKey: question.keys.window,
    title: question.title,
    titleIcon: question.titleIcon,
    message: question.message,
    actions: confirmActions(
      context,
      keys: question.keys,
      decline: decline ?? ConfirmChoice(AppText.strings.commonCancel),
      accept: accept,
    ),
  ),
);

/// The two ways out of a yes/no window: the decline action pops `false`,
/// the accept action pops `true`.
///
/// 🚨ONE law for every two-button confirm (the audit's clone scan,
/// 2026-09-03) — ten sites used to type both pops themselves. [askConfirm]
/// is the door: it is what a caller asking a yes/no question reaches for,
/// and this is the pair of actions inside it.
List<AppWindowAction> confirmActions(
  BuildContext context, {
  required ConfirmDialogKeys keys,
  required ConfirmChoice decline,
  required ConfirmChoice accept,
}) => [
  AppWindowAction(
    label: decline.label,
    actionKey: keys.decline,
    emphasis: decline.emphasis ?? AppWindowActionEmphasis.quiet,
    tooltip: decline.tooltip,
    onPressed: () => Navigator.of(context).pop(false),
  ),
  AppWindowAction(
    label: accept.label,
    actionKey: keys.accept,
    emphasis: accept.emphasis ?? AppWindowActionEmphasis.primary,
    tooltip: accept.tooltip,
    onPressed: () => Navigator.of(context).pop(true),
  ),
];

/// The three keys a confirm window wears, all derived from ONE name:
/// `<prefix>-dialog`, `<prefix>-cancel-button`, `<prefix>-confirm-button`.
typedef ConfirmDialogKeys = ({
  ValueKey<String> window,
  ValueKey<String> decline,
  ValueKey<String> accept,
});

/// ⛔THE THREE KEYS ARE ONE NAME. Six confirm windows spelled their trio
/// out by hand — eighteen string literals for six names — and a window
/// renamed without its buttons leaves a test that finds the window and
/// not its confirm button, which reads as "the button is missing" rather
/// than "the key drifted".
///
/// ⚠️A window whose accept is not `-confirm-button` (the instance editor
/// answers `-ok-button`) is NOT this convention and keeps its own keys.
ConfirmDialogKeys confirmDialogKeys(String prefix) => (
  window: ValueKey<String>('$prefix-dialog'),
  decline: ValueKey<String>('$prefix-cancel-button'),
  accept: ValueKey<String>('$prefix-confirm-button'),
);
