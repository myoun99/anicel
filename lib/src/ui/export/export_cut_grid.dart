import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/cut_id.dart';
import '../input/control_press_claim.dart';
import '../theme/app_theme.dart' show AppShapes;

/// One scope cut for the grid: its number and identity.
typedef ExportCutEntry = ({CutId id, int number});

/// The v10 cut grid (Cels·Timesheet의 Scope 모듈 전용): 10 columns of
/// micro number cells — selected = teal fill, excluded = hatching, click
/// toggles. All (reset-style) + count + a "1-200" range field; a
/// theatrical 1500-cut list stays usable through a height-capped
/// scrolling grid (cells build lazily).
class ExportCutGrid extends StatefulWidget {
  const ExportCutGrid({
    super.key,
    required this.cuts,
    required this.isIncluded,
    required this.onToggle,
    required this.onAllIncluded,
    required this.onRangeSelected,
    required this.enabled,
  });

  final List<ExportCutEntry> cuts;
  final bool Function(CutId id) isIncluded;
  final void Function(CutId id, bool included) onToggle;

  /// The All button: every cut back in scope (reset semantics — enabled
  /// only while something is excluded).
  final VoidCallback onAllIncluded;

  /// "1-200" ⏎ = scope becomes exactly that range (deterministic bulk).
  final void Function(int start, int end) onRangeSelected;

  final bool enabled;

  @override
  State<ExportCutGrid> createState() => _ExportCutGridState();
}

class _ExportCutGridState extends State<ExportCutGrid> {
  final TextEditingController _rangeController = TextEditingController();

  @override
  void dispose() {
    _rangeController.dispose();
    super.dispose();
  }

  void _applyRange() {
    final raw = _rangeController.text.trim();
    final match = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(raw);
    if (match == null) {
      final single = int.tryParse(raw);
      if (single != null) {
        widget.onRangeSelected(single, single);
      }
      return;
    }
    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2)!);
    if (start <= end) {
      widget.onRangeSelected(start, end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final included = widget.cuts
        .where((cut) => widget.isIncluded(cut.id))
        .length;
    final anyExcluded = included < widget.cuts.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ControlPressClaim(
              onPressed: widget.enabled && anyExcluded
                  ? widget.onAllIncluded
                  : null,
              child: InkWell(
                key: const ValueKey<String>('export-cut-grid-all'),
                onTap: silentPress(
                  widget.enabled && anyExcluded ? widget.onAllIncluded : null,
                ),
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
                        color: anyExcluded
                            ? theme.dividerColor
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    'All',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: anyExcluded
                          ? theme.colorScheme.onSurface
                          : theme.disabledColor.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$included / ${widget.cuts.length} cuts',
                key: const ValueKey<String>('export-cut-grid-count'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 9.5,
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 68,
              child: TextField(
                key: const ValueKey<String>('export-cut-grid-range'),
                controller: _rangeController,
                enabled: widget.enabled,
                style: theme.textTheme.labelSmall,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\-\s]')),
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '1-200',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _applyRange(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ConstrainedBox(
          // The height cap: ~9 visible rows, the rest scrolls (1500 cuts
          // = 150 rows — lazily built, never all at once).
          constraints: const BoxConstraints(maxHeight: 152),
          child: GridView.builder(
            key: const ValueKey<String>('export-cut-grid'),
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 10,
              mainAxisSpacing: 1.5,
              crossAxisSpacing: 1.5,
              childAspectRatio: 1.55,
            ),
            itemCount: widget.cuts.length,
            itemBuilder: (context, index) {
              final cut = widget.cuts[index];
              final selected = widget.isIncluded(cut.id);
              return _CutCell(
                key: ValueKey<String>('export-cut-cell-${cut.number}'),
                number: cut.number,
                selected: selected,
                enabled: widget.enabled,
                onTap: () => widget.onToggle(cut.id, !selected),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CutCell extends StatelessWidget {
  const _CutCell({
    super.key,
    required this.number,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final int number;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return ControlPressClaim(
      onPressed: enabled ? onTap : null,
      child: InkWell(
        onTap: silentPress(enabled ? onTap : null),
        child: CustomPaint(
          painter: selected
              ? null
              : _HatchPainter(color: theme.dividerColor.withValues(alpha: 0.7)),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.16) : null,
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.55)
                    : theme.dividerColor,
                width: 0.8,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 7.5,
                height: 1,
                color: selected ? accent : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The excluded-cell hatching (빗금) — selection stays COLOR (teal), the
/// hatch is the out-of-scope texture, per the v10 mock.
class _HatchPainter extends CustomPainter {
  _HatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.8;
    for (var x = -size.height; x < size.width; x += 4) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) => oldDelegate.color != color;
}
