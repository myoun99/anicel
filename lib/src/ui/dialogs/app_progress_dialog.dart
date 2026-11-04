import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/wait_window.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/ellipsis_text.dart';
import '../widgets/fixed_label.dart';

/// The app's ONE "wait for this" window.
///
/// It is [AppWindow] with a spinner in the body and no way out: nothing to
/// answer, nothing to cancel, no close button. A window that could be shut
/// mid-write would only hide the work — the write keeps running in its
/// isolate either way — so the honest shape is one that stays until the
/// work is over.
///
/// 🗣️↩️IT GOES THE MOMENT ITS WORK DOES, AND SAYS NOTHING OF THE END (유저
/// 2026-11-05, bundle-red-paste-behind-the-wait-window-Q1): 「창을 나눔.
/// 완료표시 진행창이랑 완료비표시 진행창. … 근데 이 창은 쓸데가 있나싶음.
/// 저장도 완료비표시 진행창으로 할거라서. 완료비표시 진행창은 로딩창만
/// 보여주고 끝나면 그냥 바로 사라짐」 · Q2 「셋도 「완료」 없는 창으로 —
/// 「완료」 창은 지운다」.
///
/// 🪦From 2026-08-31 to 2026-11-05 the end was said for 0.9s, with a check
/// in the spinner's slot (F-53: 「로딩 완료 시 로딩 아이콘 위치에 **체크
/// 아이콘 넣어서 완료됐단 느낌** 내고 싶음. 저장 완료 시나 그런 상황.
/// **공통적으로 사용**」 — overruling this file's earlier ⛔: a check glyph
/// is this app's mark for a toggle that is ON). That line held the window's
/// barrier over an app with nothing left to wait for, and a second Ctrl+Z
/// pressed under it went nowhere (the 11-04 bundle red).
class AppProgressDialog extends StatelessWidget {
  const AppProgressDialog({
    super.key,
    required this.title,
    required this.runningLabel,
    required this.progress,
    this.titleIcon,
    this.windowKey,
    this.runningStatus,
    this.onCancel,
    this.cancelLive,
  });

  final String title;
  final IconData? titleIcon;

  /// What the work is doing, for its whole length.
  final String runningLabel;

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

  /// Whether [onCancel] can be pressed NOW — for work whose stretches are
  /// not all waits: an import is honest to stop while a file is on its way
  /// and not while it places what came (F-282-Q1, 2026-10-08). The button
  /// stands for the window's whole life either way and only goes grey: a
  /// control that came and went would read as the window jumping
  /// (「없다가 생기는 UI 금지」). Null keeps it live throughout.
  final ValueListenable<bool>? cancelLive;

  /// The share of the work done — null until the work reports for the first
  /// time. That is what the spinner's indeterminate turn is for, and it is
  /// honest: nothing has been counted yet.
  final ValueListenable<double?> progress;
  final Key? windowKey;

  static const double _spinnerBox = 18;

  @override
  Widget build(BuildContext context) {
    final live = cancelLive;
    return live == null
        ? _window(context, cancellable: true)
        : ValueListenableBuilder<bool>(
            valueListenable: live,
            builder: (context, cancellable, _) =>
                _window(context, cancellable: cancellable),
          );
  }

  Widget _window(BuildContext context, {required bool cancellable}) {
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
            onPressed: cancellable ? cancel : null,
          ),
      ],
      body: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (context, fraction, _) {
          return Row(
            children: [
              const SizedBox(
                width: _spinnerBox,
                height: _spinnerBox,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable:
                      runningStatus ?? const FixedLabel(''),
                  builder: (context, status, _) => EllipsisText(
                    runningStatus == null || status.isEmpty
                        ? runningLabel
                        : status,
                    key: const ValueKey<String>('app-progress-label'),
                    maxLines: 1,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              if (fraction != null)
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

/// Runs [task] behind an [AppProgressDialog] and returns what it returns.
///
/// The window goes up IMMEDIATELY — no grace period, no "only if it takes a
/// while". The complaint this answers is "I cannot tell whether it saved",
/// and a delay that skips the fast cases would leave exactly those showing
/// nothing at all. A quick flash IS the answer: it was pressed, and it took.
///
/// 🪦It offered `showWhen` — a future the work completed when it started
/// WAITING on someone else's bytes, so that an open stayed silent unless a
/// provider made it wait — from 2026-08-27 to 2026-09-13, on the premise
/// that an open is instant and a window on every local open is noise about
/// a thing nobody doubted. The premise failed on a 74MB project on a cloud
/// drive: the open was not instant, said nothing, and the person could not
/// tell it from nothing (유저: 「로딩창 안 떠서 여는 중인지 아닌지 모르겠어」).
/// One law now, this one, for every wait window (F-53).
///
/// A throw takes the window down and comes back out, so the caller's own
/// error path is unchanged by having been wrapped.
///
/// Every step [task] lands stands behind this same window again when it is
/// undone or redone ([AppWaitWindow], 🗣️F-551-Q1).
Future<T> runWithAppProgress<T>({
  required BuildContext context,
  required String title,
  required String runningLabel,
  required Future<T> Function(void Function(double) report) task,
  IconData? titleIcon,
  Key? windowKey,
  ValueListenable<String>? runningStatus,
  VoidCallback? onCancel,
  ValueListenable<bool>? cancelLive,
}) async {
  final progress = ValueNotifier<double?>(null);
  final window = AppWaitWindow(
    title: title,
    runningLabel: runningLabel,
    titleIcon: titleIcon,
    windowKey: windowKey,
  );
  return _awaitBehindWindow(
    context: context,
    title: title,
    titleIcon: titleIcon,
    runningLabel: runningLabel,
    windowKey: windowKey,
    progress: progress,
    runningStatus: runningStatus,
    onCancel: onCancel,
    cancelLive: cancelLive,
    // The window has to be BUILT before the work starts. A failure that
    // lands in the same turn as the call would otherwise beat the first
    // frame, and the close would find no context — leaving a window up
    // over an app with nothing left running to take it down. So this
    // arm hands over the task UNSTARTED and lets the helper begin it
    // after the first frame.
    start: () => behindWaitWindow(
      window,
      () => task((fraction) => progress.value = fraction),
    ),
  );
}

/// The app's one wait window as a step stands behind it — what it says, so
/// an undo or a redo of the step stands behind the window its first run
/// stood behind (`StepWindows`). Each goes the moment its step does, and so
/// does its undo's and its redo's ([AppProgressDialog]).
final class AppWaitWindow implements WaitWindow {
  const AppWaitWindow({
    required this.title,
    required this.runningLabel,
    this.titleIcon,
    this.windowKey,
  });

  /// [title]'s window where the step has no words of its own for its work.
  AppWaitWindow.working(String title)
    : this(
        title: title,
        runningLabel: AppText.strings.workProgressRunning,
        windowKey: const ValueKey<String>('work-progress-dialog'),
      );

  /// [title]'s window over a paste — and over the media a paste from
  /// another project holds first (I-7).
  AppWaitWindow.pasting(String title)
    : this(
        title: title,
        titleIcon: Icons.content_paste,
        runningLabel: AppText.strings.pasteProgressRunning,
        windowKey: const ValueKey<String>('paste-progress-dialog'),
      );

  /// [title]'s window over a duplicate.
  AppWaitWindow.duplicating(String title)
    : this(
        title: title,
        runningLabel: AppText.strings.duplicateProgressRunning,
        windowKey: const ValueKey<String>('duplicate-progress-dialog'),
      );

  final String title;
  final String runningLabel;
  final IconData? titleIcon;
  final Key? windowKey;

  /// Runs [task] behind this window ([runWithAppProgress]).
  Future<T> standBehind<T>(
    BuildContext context,
    Future<T> Function(void Function(double done) report) task,
  ) => runWithAppProgress<T>(
    context: context,
    title: title,
    runningLabel: runningLabel,
    titleIcon: titleIcon,
    windowKey: windowKey,
    task: task,
  );
}

/// The window half: the window goes up, and the work starts after the
/// first frame.
///
/// 🚨F-304 (유저 2026-10-06): 「무거운 상태에서 저장버튼누르면 화면이 멈추고,
/// 그 상태에서 시간 지나면 저장창 뜨는데 … 멈추는게 아니라 뭔가 하고있다
/// 라는걸 제대로 표시하기위해」. So the window comes up WHOLE on its first
/// frame, with no fade: a dialog fades in from nothing, and the work starts
/// right after that first frame — so it started under a window drawn at
/// opacity 0, and work that holds the main isolate from its first line (a
/// save gathering a heavy session's cels) froze the screen with nothing on
/// it until it let go.
Future<T> _awaitBehindWindow<T>({
  required BuildContext context,
  required String title,
  required IconData? titleIcon,
  required String runningLabel,
  required Key? windowKey,
  required ValueNotifier<double?> progress,
  required ValueListenable<String>? runningStatus,
  required VoidCallback? onCancel,
  required ValueListenable<bool>? cancelLive,
  required Future<T> Function() start,
}) async {
  BuildContext? windowContext;
  final shown = showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    animationStyle: AnimationStyle.noAnimation,
    builder: (dialogContext) {
      windowContext = dialogContext;
      return PopScope(
        canPop: false,
        child: AppProgressDialog(
          title: title,
          titleIcon: titleIcon,
          runningLabel: runningLabel,
          progress: progress,
          windowKey: windowKey,
          runningStatus: runningStatus,
          onCancel: onCancel,
          cancelLive: cancelLive,
        ),
      );
    },
  );
  await WidgetsBinding.instance.endOfFrame;
  try {
    return await start();
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
