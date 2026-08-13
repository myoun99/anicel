import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/anchored_popup.dart';
import '../widgets/app_scrollbar.dart';

/// The import window's file list: one row per file, one COLUMN per question.
///
/// The window used to hold one answer for the whole batch, which meant the
/// answer was wrong for at least one file most of the time. Here the cell
/// shows what THIS file will do, and pressing it offers only the answers
/// this file can give.
///
/// A column's header is a button too: it applies one answer to every row,
/// because setting twenty files one at a time is not a feature.

/// One question, asked of every row.
class ImportColumn<T> {
  const ImportColumn({
    required this.label,
    required this.width,
    required this.values,
    required this.labelOf,
    required this.valueOf,
    required this.appliesTo,
    required this.enabledFor,
    required this.onPick,
  });

  final String label;
  final double width;

  /// Every answer, in the order the popup lists them.
  final List<T> values;
  final String Function(T value) labelOf;

  /// This row's current answer.
  final T Function(String path) valueOf;

  /// False when the question is meaningless for this file — the cell shows
  /// a dash rather than a value nobody chose.
  final bool Function(String path) appliesTo;

  /// False for an answer this file cannot give. Shown, and dim: the row
  /// says what is impossible instead of hiding that it was ever asked.
  final bool Function(String path, T value) enabledFor;

  final void Function(Iterable<String> paths, T value) onPick;
}

class ImportFileRow {
  const ImportFileRow({
    required this.path,
    required this.name,
    required this.modified,
    required this.size,
  });

  final String path;
  final String name;

  /// Already formatted — the table does not know about dates or bytes.
  final String modified;
  final String size;
}

class ImportFileTable extends StatefulWidget {
  const ImportFileTable({
    super.key,
    required this.rows,
    required this.columns,
    required this.selected,
    required this.onRowTap,
    this.enabled = true,
  });

  final List<ImportFileRow> rows;
  final List<ImportColumn<Object?>> columns;
  final Set<String> selected;
  final ValueChanged<String> onRowTap;
  final bool enabled;

  @override
  State<ImportFileTable> createState() => _ImportFileTableState();
}

class _ImportFileTableState extends State<ImportFileTable> {
  static const double _rowHeight = 22;

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // The lane is always visible ([[scrollbars-always-visible]]), so it has
    // to follow the list rather than appear when the list moves.
    _scroll.addListener(_onScrolled);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScrolled)
      ..dispose();
    super.dispose();
  }

  void _onScrolled() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Which rows a press on [path]'s cell speaks for: the selection when
  /// this row is part of it, otherwise this row alone.
  Iterable<String> _targets(String path) =>
      widget.selected.contains(path) ? widget.selected : [path];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = widget.rows;
    final columns = widget.columns;
    final enabled = widget.enabled;
    final selected = widget.selected;
    final onRowTap = widget.onRowTap;
    final dim = theme.textTheme.labelSmall?.copyWith(color: AppColors.textDim);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
          child: Row(
            children: [
              Expanded(child: Text('Name', style: dim)),
              SizedBox(width: 58, child: Text('Modified', style: dim)),
              SizedBox(
                width: 52,
                child: Text('Size', style: dim, textAlign: TextAlign.right),
              ),
              for (final column in columns)
                SizedBox(
                  width: column.width,
                  child: _HeaderButton(
                    column: column,
                    enabled: enabled && rows.isNotEmpty,
                    paths: [for (final row in rows) row.path],
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.zero,
                    itemCount: rows.length,
                    itemExtent: _rowHeight,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final isSelected = selected.contains(row.path);
                      return InkWell(
                        key: ValueKey<String>('import-row-${row.name}'),
                        onTap: enabled ? () => onRowTap(row.path) : null,
                        child: Container(
                          color: isSelected
                              ? AppColors.accent.withValues(alpha: 0.14)
                              : null,
                          padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isSelected ? AppColors.accent : null,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 58,
                                child: Text(row.modified, style: dim),
                              ),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  row.size,
                                  style: dim,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              for (final column in columns)
                                SizedBox(
                                  width: column.width,
                                  child: _OptionCell(
                                    column: column,
                                    path: row.path,
                                    enabled: enabled,
                                    targets: _targets(row.path),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 16,
                  child: AppScrollbar(
                    axis: Axis.vertical,
                    offset: _scroll.hasClients ? _scroll.offset : 0,
                    viewportExtent: constraints.maxHeight,
                    contentExtent: rows.length * _rowHeight,
                    onOffsetChanged: (offset) {
                      if (_scroll.hasClients) {
                        _scroll.jumpTo(offset);
                      }
                    },
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

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.column,
    required this.enabled,
    required this.paths,
  });

  final ImportColumn<Object?> column;
  final bool enabled;
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey<String>('import-column-${column.label}'),
      onTap: enabled
          ? () => _openColumnPopup(
              context,
              column: column,
              targets: paths,
              // A header speaks for every row, so an answer only some of
              // them can give is still offered — the ones that cannot will
              // resolve it away, and the cells will say so.
              enabledFor: (value) => true,
              current: null,
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Text(
          column.label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: enabled ? AppColors.textDim : theme.disabledColor,
          ),
        ),
      ),
    );
  }
}

class _OptionCell extends StatelessWidget {
  const _OptionCell({
    required this.column,
    required this.path,
    required this.enabled,
    required this.targets,
  });

  final ImportColumn<Object?> column;
  final String path;
  final bool enabled;
  final Iterable<String> targets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!column.appliesTo(path)) {
      // Keyed like any other cell: "this question does not apply here" is a
      // state of the cell, not the absence of one.
      return Text(
        '—',
        key: ValueKey<String>('import-cell-${column.label}-$path'),
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(color: theme.disabledColor),
      );
    }
    final value = column.valueOf(path);
    // A value the file was FORCED to (an expanded PSD is baked, a movie is
    // never carried) is shown, and shown quiet: it is the answer, and it is
    // not one the user can change here.
    final locked =
        column.values
            .where((option) => column.enabledFor(path, option))
            .length <=
        1;
    return Center(
      child: InkWell(
        key: ValueKey<String>('import-cell-${column.label}-$path'),
        // The app's own corner, not a circular one: a cell is a well cut
        // into the row, and every well in this app wears the same shape.
        customBorder: AppShapes.container(AppShapes.wellRadius),
        onTap: enabled && !locked
            ? () => _openColumnPopup(
                context,
                column: column,
                targets: targets,
                enabledFor: (option) => column.enabledFor(path, option),
                current: value,
              )
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: ShapeDecoration(
            shape: AppShapes.container(
              AppShapes.wellRadius,
              side: BorderSide(
                color: locked ? theme.dividerColor : AppColors.hairlineStrong,
              ),
            ),
          ),
          child: Text(
            column.labelOf(value),
            style: theme.textTheme.labelSmall?.copyWith(
              color: locked ? theme.disabledColor : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// One column's answers, anchored under whatever was pressed.
void _openColumnPopup(
  BuildContext context, {
  required ImportColumn<Object?> column,
  required Iterable<String> targets,
  required bool Function(Object? value) enabledFor,
  required Object? current,
}) {
  final rows = column.values;
  showAnchoredPopup<void>(
    context,
    label: column.label,
    width: 132,
    height: 8.0 + rows.length * 24,
    builder: (context, close) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final value in rows)
          _PopupRow(
            label: column.labelOf(value),
            selected: value == current,
            enabled: enabledFor(value),
            onTap: () {
              column.onPick(targets, value);
              close();
            },
          ),
      ],
    ),
  );
}

class _PopupRow extends StatelessWidget {
  const _PopupRow({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey<String>('import-option-$label'),
      onTap: enabled ? onTap : null,
      child: Container(
        height: 24,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        color: selected ? AppColors.accent.withValues(alpha: 0.18) : null,
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: !enabled
                ? theme.disabledColor
                : selected
                ? AppColors.accent
                : null,
          ),
        ),
      ),
    );
  }
}
