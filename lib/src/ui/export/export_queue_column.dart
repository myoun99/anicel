import 'package:flutter/material.dart';

import '../widgets/ellipsis_text.dart';
import 'export_job.dart';
import 'export_preset_rail.dart' show ExportPresetRail;
import '../text/app_strings.dart';
import '../input/control_press_claim.dart';
import '../theme/app_theme.dart' show AppCursors, AppShapes;
import '../widgets/empty_state_text.dart';

/// The right drawer: the render queue. EX2 ships the column and its
/// collapsed strip; the executor (and the enabled Add to Queue) lands
/// with EX7 — until then the column renders whatever the model holds
/// (normally the empty state).
class ExportQueueColumn extends StatelessWidget {
  const ExportQueueColumn({
    super.key,
    required this.queue,
    required this.enabled,
    this.onRemove,
    this.onRestore,
    this.onRenderAll,
  });

  final ExportQueueModel queue;
  final bool enabled;
  final ValueChanged<ExportJob>? onRemove;
  final ValueChanged<ExportJob>? onRestore;

  /// The header's Render All (EX7); null renders it disabled.
  final VoidCallback? onRenderAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: queue,
      builder: (context, _) {
        final jobs = queue.jobs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 6, 4),
              child: Row(
                children: [
                  Expanded(
                    child: EllipsisText(
                      AppText.strings.exRenderQueue.toUpperCase(),
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        letterSpacing: 1.1,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ControlPressClaim(
                    onPressed: onRenderAll,
                    child: InkWell(
                      mouseCursor: AppCursors.press,
                      key: const ValueKey<String>('export-queue-render-all'),
                      onTap: silentPress(onRenderAll),
                      customBorder: AppShapes.container(AppShapes.wellRadius),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: ShapeDecoration(
                          shape: AppShapes.container(
                            AppShapes.wellRadius,
                            side: BorderSide(
                              color: onRenderAll != null
                                  ? theme.dividerColor
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Text(
                          AppText.strings.exRenderAll,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            color: onRenderAll != null
                                ? theme.colorScheme.onSurface
                                : theme.disabledColor.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (jobs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: EmptyStateText(
                  AppText.strings.exportQueueEmpty,
                  key: const ValueKey<String>('export-queue-empty'),
                  place: EmptyStatePlace.list,
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  children: [
                    for (final job in jobs)
                      _JobCard(
                        job: job,
                        enabled: enabled,
                        onRemove: onRemove,
                        onRestore: onRestore,
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.enabled,
    this.onRemove,
    this.onRestore,
  });

  final ExportJob job;
  final bool enabled;
  final ValueChanged<ExportJob>? onRemove;
  final ValueChanged<ExportJob>? onRestore;

  String get _statusLabel => switch (job.status) {
    ExportJobStatus.queued => AppText.strings.exJobQueued,
    ExportJobStatus.running => '${job.completed}/${job.total}',
    ExportJobStatus.succeeded => AppText.strings.exJobDone,
    ExportJobStatus.failed => AppText.strings.exJobFailed,
    ExportJobStatus.cancelled => AppText.strings.exJobCancelled,
  };

  /// The bar's place, held whatever the job is doing; the bar stands in it
  /// while the job runs, as the footer's does (유저 2026-10-06: 「출력때만
  /// 보이게」) — moving with no end while the job has not yet said how much
  /// it makes, as it gets ready (its sound mix comes before its first
  /// frame).
  ///
  /// 🗣️검증/서피스 2026-11-25 (the-export-sound-blocks-the-ui-isolate): for
  /// the 1.3 s of a 46 s sound mix the row said 「0/0」 with no bar, and
  /// whether the window was alive could not be told.
  Widget get _bar => SizedBox(
    height: _barHeight,
    child: job.status == ExportJobStatus.running
        ? LinearProgressIndicator(
            key: ValueKey<String>('export-queue-bar-${job.id}'),
            value: job.total > 0 ? job.completed / job.total : null,
            minHeight: _barHeight,
          )
        : null,
  );

  static const double _barHeight = 3;

  /// The ✕ that takes the job off the queue — in its place, dimmed, while
  /// the job runs (as a tool's setting it does not take stays, 10-10).
  Widget _removeButton(ThemeData theme, {required bool removable}) =>
      ControlPressClaim(
        onPressed: removable ? () => onRemove!(job) : null,
        child: InkWell(
          mouseCursor: removable ? AppCursors.press : null,
          key: ValueKey<String>('export-queue-remove-${job.id}'),
          onTap: silentPress(removable ? () => onRemove!(job) : null),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.close,
              size: 11,
              color: removable ? null : theme.disabledColor,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final running = job.status == ExportJobStatus.running;
    return ControlPressClaim(
      onPressed: enabled && onRestore != null ? () => onRestore!(job) : null,
      child: InkWell(
        mouseCursor: AppCursors.press,
        key: ValueKey<String>('export-queue-job-${job.id}'),
        onTap: silentPress(
          enabled && onRestore != null ? () => onRestore!(job) : null,
        ),
        customBorder: AppShapes.container(AppShapes.wellRadius),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(7, 4, 4, 5),
          decoration: ShapeDecoration(
            shape: AppShapes.container(
              AppShapes.wellRadius,
              side: BorderSide(color: running ? accent : theme.dividerColor),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: EllipsisText(
                      AppText.strings.exJob(
                        job.id,
                        ExportPresetRail.tabLabel(job.tab),
                      ),
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _statusLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 9.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (onRemove != null)
                    _removeButton(theme, removable: enabled && !running),
                ],
              ),
              // Every line the row can say has its place from the first
              // frame (⛔없다가 생기는 UI): the message once it is finished,
              // the bar while it runs.
              EllipsisText(
                job.message ?? '',
                maxLines: 1,
                // One line's height whatever it says: an empty line and one
                // in a fallback face stood a pixel apart.
                strutStyle: const StrutStyle(
                  fontSize: 9.5,
                  forceStrutHeight: true,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 9.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              _bar,
            ],
          ),
        ),
      ),
    );
  }
}

/// A collapsed drawer strip: chevron + optional count badge + vertical
/// caption. Shared by both drawers.
class ExportDrawerStrip extends StatelessWidget {
  const ExportDrawerStrip({
    super.key,
    required this.caption,
    required this.chevron,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String caption;
  final IconData chevron;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ControlPressClaim(
      onPressed: onTap,
      child: InkWell(
        mouseCursor: AppCursors.press,
        onTap: silentPress(onTap),
        child: SizedBox(
          width: 22,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Icon(
                chevron,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              if (badgeCount > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  // ⚠️A PILL, and it says so now. `circular(999)` clamps to
                  // half the shorter side, which IS a stadium — the shape
                  // ledger reads corner radii and could not tell that this
                  // one was never a corner. Same pixels, stated instead of
                  // implied.
                  decoration: ShapeDecoration(
                    color: theme.colorScheme.primary,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 8.5,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              RotatedBox(
                quarterTurns: 1,
                child: Text(
                  caption.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 8,
                    letterSpacing: 1.2,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
