import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  });

  final String title;
  final IconData? titleIcon;

  /// While the work runs, and once it is over.
  final String runningLabel;
  final String doneLabel;

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
                child: Text(
                  value.done ? doneLabel : runningLabel,
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
}) async {
  final progress = ValueNotifier<AppProgress>(const AppProgress.running(null));
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
        ),
      );
    },
  );
  // The window has to be BUILT before the work starts. A failure that lands
  // in the same turn as the call would otherwise beat the first frame, and
  // the close below would find no context to close — leaving a window up
  // over an app with nothing left running to take it down.
  await WidgetsBinding.instance.endOfFrame;
  try {
    final result = await task(
      (fraction) => progress.value = AppProgress.running(fraction),
    );
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
