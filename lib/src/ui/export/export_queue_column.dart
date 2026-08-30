import 'package:flutter/material.dart';

import 'export_job.dart';
import 'export_preset_rail.dart' show ExportPresetRail;
import '../input/control_press_claim.dart';
import '../theme/app_theme.dart' show AppShapes;

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
                    child: Text(
                      'RENDER QUEUE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                          'Render All',
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
                child: Text(
                  'Queue is empty.',
                  key: const ValueKey<String>('export-queue-empty'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
    ExportJobStatus.queued => 'Queued',
    ExportJobStatus.running => '${job.completed}/${job.total}',
    ExportJobStatus.succeeded => 'Done',
    ExportJobStatus.failed => 'Failed',
    ExportJobStatus.cancelled => 'Cancelled',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final running = job.status == ExportJobStatus.running;
    return ControlPressClaim(
      onPressed: enabled && onRestore != null ? () => onRestore!(job) : null,
      child: InkWell(
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
                    child: Text(
                      'Job ${job.id} · ${ExportPresetRail.tabLabel(job.tab)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                  if (!running && onRemove != null)
                    ControlPressClaim(
                      onPressed: enabled ? () => onRemove!(job) : null,
                      child: InkWell(
                        key: ValueKey<String>('export-queue-remove-${job.id}'),
                        onTap: silentPress(
                          enabled ? () => onRemove!(job) : null,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.close, size: 11),
                        ),
                      ),
                    ),
                ],
              ),
              if (job.message != null)
                Text(
                  job.message!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (running && job.total > 0) ...[
                const SizedBox(height: 3),
                LinearProgressIndicator(
                  value: job.completed / job.total,
                  minHeight: 3,
                ),
              ],
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
