import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// What a [AppProgressDialog] is showing right now.
///
/// [fraction] is null until the work reports for the first time — that is
/// what the spinner's indeterminate turn is for, and it is honest: nothing
/// has been counted yet.
@immutable
class AppProgress {
  const AppProgress.running(this.fraction) : done = false;
  const AppProgress.done() : fraction = 1, done = true;

  final double? fraction;
  final bool done;
}

/// The app's ONE "wait for this" window.
///
/// It is [AppWindow] with a spinner in the body and no way out: nothing to
/// answer, nothing to cancel, no close button. A window that could be shut
/// mid-write would only hide the work — the write keeps running in its
/// isolate either way — so the honest shape is one that stays until the
/// work is over and then says so.
///
/// The finished state is spelled out in WORDS rather than badged with a
/// check. A check glyph is this app's mark for a toggle that is on (see
/// [AppWindow]'s callers and the selection rules), and borrowing it here to
/// mean "over" would make the one symbol carry two jobs.
class AppProgressDialog extends StatelessWidget {
  const AppProgressDialog({
    super.key,
    required this.title,
    required this.runningLabel,
    required this.doneLabel,
    required this.progress,
    this.titleIcon,
    this.windowKey,
    this.runningStatus,
    this.onCancel,
  });

  final String title;
  final IconData? titleIcon;

  /// While the work runs, and once it is over.
  final String runningLabel;
  final String doneLabel;

  /// A running line that CHANGES — what the work is doing right now, when
  /// that is not one sentence for its whole length. An open spends its
  /// first stretch waiting for a cloud file to arrive and the rest
  /// reading it, and a single 「여는 중」 across both makes the app look
  /// slow for something the provider is doing (유저 2026-08-27:
  /// 「프로바이더가 로컬로 다운로드하는 걸 기다리고 있다고 명확히
  /// 표기하는 게 좋겠다」). Null keeps [runningLabel].
  final ValueListenable<String>? runningStatus;

  /// Stops the work, when stopping it is HONEST.
  ///
  /// ⛔Not for writes — see the class doc. A cancel that only hides a
  /// save still running in an isolate is a lie, and this window says so
  /// by having no button at all in that case. A WAIT is different: the
  /// bytes are not ours, nothing has been applied, and abandoning it
  /// leaves the app exactly where it was. Null keeps the old shape.
  final VoidCallback? onCancel;

  final ValueListenable<AppProgress> progress;
  final Key? windowKey;

  static const double _spinnerBox = 18;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppWindow(
      windowKey: windowKey,
      title: title,
      titleIcon: titleIcon,
      width: 300,
      scrollBody: false,
      actions: [
        if (onCancel case final cancel?)
          AppWindowAction(
            label: AppText.strings.commonCancel,
            actionKey: const ValueKey<String>('app-progress-cancel'),
            onPressed: cancel,
          ),
      ],
      body: ValueListenableBuilder<AppProgress>(
        valueListenable: progress,
        builder: (context, value, _) {
          final fraction = value.fraction;
          return Row(
            children: [
              // Kept at its full size when finished so the line does not
              // shuffle sideways on the last frame it is read.
              SizedBox(
                width: _spinnerBox,
                height: _spinnerBox,
                child: value.done
                    ? null
                    : const CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable:
                      runningStatus ?? const _FixedLabel(''),
                  builder: (context, status, _) => Text(
                    value.done
                        ? doneLabel
                        : (runningStatus == null || status.isEmpty
                              ? runningLabel
                              : status),
                    key: const ValueKey<String>('app-progress-label'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: value.done
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              if (!value.done && fraction != null)
                Text(
                  '${(fraction * 100).round()}%',
                  key: const ValueKey<String>('app-progress-percent'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    // Digits that do not change width, so a bar climbing
                    // through 8 → 9 → 10 does not twitch the label beside it.
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A listenable that never changes — so the label builder has one shape
/// whether or not the caller supplied a status line.
class _FixedLabel implements ValueListenable<String> {
  const _FixedLabel(this.value);

  @override
  final String value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// How long the finished line is held up before the window leaves.
///
/// Long enough to be read on a glance away from the screen, short enough
/// that a save every few minutes never feels like it asks for a click.
const Duration appProgressDoneLinger = Duration(milliseconds: 900);

/// Runs [task] behind an [AppProgressDialog] and returns what it returns.
///
/// The window goes up IMMEDIATELY — no grace period, no "only if it takes a
/// while". The complaint this answers is "I cannot tell whether it saved",
/// and a delay that skips the fast cases would leave exactly those showing
/// nothing at all. A quick flash IS the answer: it was pressed, and it took.
///
/// ⚠️[showWhen] buys the opposite trade for a DIFFERENT question, and the
/// difference is what makes it not an exception. A save is rare, slow and
/// asked about; an OPEN is constant and usually instant, and a window that
/// blinks on every local open is noise about a thing nobody doubted.
///
/// 🚨It is a FUTURE, not a delay, and that distinction is the whole point:
/// the work itself says when it has started waiting — a materialiser that
/// has to sit and ask a provider again — instead of a stopwatch guessing
/// from outside. A stopwatch is wrong in both directions. It fires for a
/// local open that merely lost a race against the clock (every widget test
/// that opens a project went red exactly there, and users would have seen
/// the same blink on a slow frame), and it says nothing about a file that
/// is genuinely stuck but has not reached the mark yet.
///
/// A throw takes the window down and comes back out, so the caller's own
/// error path is unchanged by having been wrapped.
Future<T> runWithAppProgress<T>({
  required BuildContext context,
  required String title,
  required String runningLabel,
  required String doneLabel,
  required Future<T> Function(void Function(double) report) task,
  IconData? titleIcon,
  Key? windowKey,
  Duration doneLinger = appProgressDoneLinger,
  Future<void>? showWhen,
  ValueListenable<String>? runningStatus,
  VoidCallback? onCancel,
}) async {
  final progress = ValueNotifier<AppProgress>(const AppProgress.running(null));
  if (showWhen != null) {
    // Started before the window, and raced against the work's own signal:
    // work that finishes without ever saying 「I am waiting」 draws nothing
    // at all. No timer is involved, so nothing is left ticking for a race
    // that is already over.
    //
    // ⚠️The error arm sets `finished` rather than swallowing: the future is
    // awaited again below, so catching here would either deliver the
    // failure twice or lose it.
    final running = task(
      (fraction) => progress.value = AppProgress.running(fraction),
    );
    var finished = false;
    await Future.any<void>([
      running.then((_) => finished = true, onError: (_) => finished = true),
      showWhen,
    ]);
    if (finished) {
      progress.dispose();
      return running;
    }
    if (!context.mounted) {
      // The screen that asked went away while the work ran. Nothing to
      // draw on and nothing to close — hand the work back as it is.
      progress.dispose();
      return running;
    }
    return _awaitBehindWindow(
      context: context,
      title: title,
      titleIcon: titleIcon,
      runningLabel: runningLabel,
      doneLabel: doneLabel,
      windowKey: windowKey,
      doneLinger: doneLinger,
      progress: progress,
      runningStatus: runningStatus,
      onCancel: onCancel,
      running: running,
    );
  }
  return _awaitBehindWindow(
    context: context,
    title: title,
    titleIcon: titleIcon,
    runningLabel: runningLabel,
    doneLabel: doneLabel,
    windowKey: windowKey,
    doneLinger: doneLinger,
    progress: progress,
    runningStatus: runningStatus,
    onCancel: onCancel,
    // The window has to be BUILT before the work starts. A failure that
    // lands in the same turn as the call would otherwise beat the first
    // frame, and the close would find no context — leaving a window up
    // over an app with nothing left running to take it down. So this
    // arm hands over the task UNSTARTED and lets the helper begin it
    // after the first frame.
    start: () => task(
      (fraction) => progress.value = AppProgress.running(fraction),
    ),
  );
}

/// The window half, shared by both arms: one already-running future to
/// wait on, or one to start after the first frame.
Future<T> _awaitBehindWindow<T>({
  required BuildContext context,
  required String title,
  required IconData? titleIcon,
  required String runningLabel,
  required String doneLabel,
  required Key? windowKey,
  required Duration doneLinger,
  required ValueNotifier<AppProgress> progress,
  required ValueListenable<String>? runningStatus,
  required VoidCallback? onCancel,
  Future<T>? running,
  Future<T> Function()? start,
}) async {
  BuildContext? windowContext;
  final shown = showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dialogContext) {
      windowContext = dialogContext;
      return PopScope(
        canPop: false,
        child: AppProgressDialog(
          title: title,
          titleIcon: titleIcon,
          runningLabel: runningLabel,
          doneLabel: doneLabel,
          progress: progress,
          windowKey: windowKey,
          runningStatus: runningStatus,
          onCancel: onCancel,
        ),
      );
    },
  );
  await WidgetsBinding.instance.endOfFrame;
  try {
    final result = await (running ?? start!());
    progress.value = const AppProgress.done();
    await Future<void>.delayed(doneLinger);
    return result;
  } finally {
    // `removeRoute`, NOT `pop`. A pop takes whatever route is on TOP, and
    // this window is not guaranteed to be it — anything the app pushes
    // while the save runs (a prompt raised by a lifecycle event, a second
    // dialog) would be closed instead, leaving this one up and `shown`
    // waiting on a route nobody will now remove. Naming the route closes
    // the one this function opened, whatever is stacked over it.
    final open = windowContext;
    if (open != null && open.mounted) {
      final route = ModalRoute.of(open);
      if (route != null) {
        Navigator.of(open).removeRoute(route);
      }
    }
    await shown;
    progress.dispose();
  }
}
