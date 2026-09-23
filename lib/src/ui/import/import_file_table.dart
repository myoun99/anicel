import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../text/text_measure.dart';
import '../theme/app_theme.dart';
import '../widgets/anchored_popup.dart';
import '../widgets/app_scrollbar.dart';
import '../widgets/boolean_dot.dart';
import '../input/control_press_claim.dart';

/// The import window's file list: one row per file, one COLUMN per question.
///
/// The window used to hold one answer for the whole batch, which meant the
/// answer was wrong for at least one file most of the time. Here the cell
/// shows what THIS file will do, and pressing it offers only the answers
/// this file can give.
///
/// A column's header is a button too: it applies one answer to every row,
/// because setting twenty files one at a time is not a feature.

/// How a column's cells are drawn.
enum ImportColumnStyle {
  /// A chip that opens the column's answers.
  choice,

  /// An on/off boolean — the ring, dotted when on: the column's answers are
  /// `false` and `true`.
  toggle,
}

/// One question, asked of every row.
class ImportColumn<T> {
  const ImportColumn({
    required this.id,
    required this.label,
    required this.values,
    required this.labelOf,
    required this.valueOf,
    required this.appliesTo,
    required this.enabledFor,
    required this.onPick,
    this.style = ImportColumnStyle.choice,
  });

  /// What the keys are built from — the same in every language, which the
  /// [label] is not.
  final String id;
  final String label;
  final ImportColumnStyle style;

  /// Every answer, in the order the popup lists them.
  final List<T> values;
  final String Function(T value) labelOf;

  /// This row's current answer.
  final T Function(String path) valueOf;

  /// False when the question is meaningless for this file — the cell shows
  /// a dash rather than a value nobody chose.
  final bool Function(String path) appliesTo;

  /// False for an answer this file cannot give. Shown, and dim, in the
  /// popup: the row says what is impossible instead of hiding that it was
  /// ever asked. A row left with ONE answer shows it LOCKED — the context
  /// answered the question (a new cut's 1:1, an expanded PSD's bake), and
  /// the answer stays on screen, disabled (유저 2026-09-11: 「1:1로
  /// 고정시켜서 노출시키도록. 비활성화된상태로」).
  final bool Function(String path, T value) enabledFor;

  final void Function(Iterable<String> paths, T value) onPick;
}

class ImportFileRow {
  const ImportFileRow({
    required this.path,
    required this.name,
    required this.extension,
    required this.modified,
    required this.size,
  });

  final String path;

  /// The name WITHOUT its extension, which [extension] carries: the name is
  /// what gets cut short when room runs out, the extension never is.
  final String name;
  final String extension;

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

  /// Below this much room a name is no longer READ, and the name is the
  /// row's subject. The fixed columns used to take whatever they were given
  /// and leave the name 20px (유저 2026-09-11: 「이름은 표시도안되고」).
  static const double nameMinWidth = 120;

  /// What a name is given when nothing asks the table to be narrower.
  static const double namePreferredWidth = 200;

  /// The scrollbar's lane. It is reserved beside the HEADER too: it used to
  /// stand beside the rows only, so every fixed column of a row sat 16px
  /// left of the header naming it (유저 2026-09-11: 「열끼리 길이 어긋났거든?
  /// 크기랑 실제 크기 쪽이랑 규격이 달라」).
  static const double laneWidth = 16;

  static const double _sidePadding = 8;

  /// The narrowest this table may be laid out: every column at its measured
  /// width and the name still readable.
  static double minimumWidth(
    BuildContext context, {
    required List<ImportFileRow> rows,
    required List<ImportColumn<Object?>> columns,
  }) => _ImportTableMetrics.of(
    context,
    rows: rows,
    columns: columns,
  ).tableWidthFor(nameMinWidth);

  /// The width that gives the name [namePreferredWidth].
  static double preferredWidth(
    BuildContext context, {
    required List<ImportFileRow> rows,
    required List<ImportColumn<Object?>> columns,
  }) => _ImportTableMetrics.of(
    context,
    rows: rows,
    columns: columns,
  ).tableWidthFor(namePreferredWidth);

  @override
  State<ImportFileTable> createState() => _ImportFileTableState();
}

/// Every width and height the table is laid out with, MEASURED from the
/// words it shows in the language it shows them. The columns used to be
/// fixed pixel widths sized for English words; the header and the cells
/// asked those numbers separately, and the name got what was left.
class _ImportTableMetrics {
  _ImportTableMetrics._({
    required this.modifiedWidth,
    required this.sizeWidth,
    required this.columnWidths,
    required this.rowHeight,
  });

  factory _ImportTableMetrics.of(
    BuildContext context, {
    required List<ImportFileRow> rows,
    required List<ImportColumn<Object?>> columns,
  }) {
    final text = TextMeasure(
      context,
      Theme.of(context).textTheme.labelSmall ?? const TextStyle(fontSize: 11),
    );

    final chipHeight = text.size('Ag').height + 2 * chipPadV + 2 * chipBorder;
    return _ImportTableMetrics._(
      modifiedWidth:
          text.widest([
            AppText.strings.imModified,
            for (final row in rows) row.modified,
          ]) +
          gap,
      sizeWidth:
          text.widest([
            AppText.strings.imSize,
            for (final row in rows) row.size,
          ]) +
          gap,
      columnWidths: [
        for (final column in columns)
          math.max(
                text.size(column.label).width,
                column.style == ImportColumnStyle.toggle
                    ? dotSize +
                          dotGap +
                          text.widest(column.values.map(column.labelOf))
                    : text.widest(column.values.map(column.labelOf)) +
                          2 * chipPadH +
                          2 * chipBorder,
              ) +
              gap,
      ],
      // The row is the chip plus its own padding, so the chip is never
      // cut: the row used to be a fixed 22px and its bordered chips lost
      // their bottom edge.
      rowHeight: math.max(chipHeight, dotSize) + 2 * rowPadV,
    );
  }

  static const double chipPadH = 6;
  static const double chipPadV = 2;
  static const double chipBorder = 1;
  static const double rowPadV = 3;
  static const double gap = 10;
  /// The boolean ring a toggle cell draws, square — the height the switch
  /// it replaced had, so the row keeps its height.
  static const double dotSize = 20;
  static const double dotGap = 4;

  final double modifiedWidth;
  final double sizeWidth;
  final List<double> columnWidths;
  final double rowHeight;

  double get _fixedWidth =>
      modifiedWidth + sizeWidth + columnWidths.fold(0.0, (sum, w) => sum + w);

  double tableWidthFor(double nameWidth) =>
      2 * ImportFileTable._sidePadding +
      nameWidth +
      _fixedWidth +
      ImportFileTable.laneWidth;
}

class _ImportFileTableState extends State<ImportFileTable> {
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
    final metrics = _ImportTableMetrics.of(
      context,
      rows: widget.rows,
      columns: widget.columns,
    );
    final minimum = metrics.tableWidthFor(ImportFileTable.nameMinWidth);
    return LayoutBuilder(
      builder: (context, constraints) {
        final table = _table(theme, metrics);
        // Below the width that keeps every column and a readable name, the
        // table scrolls sideways at that width instead of overflowing — the
        // media pool's rule for its own rows (R10-①), in the same shape. A
        // long translation or a large text scale is what brings it here.
        if (!constraints.hasBoundedWidth || constraints.maxWidth >= minimum) {
          return table;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minimum,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: table,
          ),
        );
      },
    );
  }

  Widget _table(ThemeData theme, _ImportTableMetrics metrics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The header stands in the SAME box as the rows — beside the lane —
        // so its cells are laid out over exactly the width theirs are.
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  ImportFileTable._sidePadding,
                  6,
                  ImportFileTable._sidePadding,
                  5,
                ),
                child: _headerCells(theme, metrics),
              ),
            ),
            const SizedBox(width: ImportFileTable.laneWidth),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _rowList(theme, metrics)),
                SizedBox(
                  width: ImportFileTable.laneWidth,
                  child: _scrollbar(constraints, metrics),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// One line of the table — the header and every row alike.
  ///
  /// 🚨THE ALIGNMENT LAW LIVES HERE, and in the box it is laid out in. The
  /// header and the row each used to spell the same cells with the same
  /// widths; two copies of a column layout are two chances for the header to
  /// stop sitting over the values it names. One line was not enough on its
  /// own: the header's line was laid out 16px wider than the rows', because
  /// only the rows stood beside the scrollbar lane.
  Widget _tableLine(
    _ImportTableMetrics metrics, {
    required Widget name,
    required Widget modified,
    required Widget size,
    required Widget Function(ImportColumn<Object?> column) cell,
  }) => Row(
    children: [
      Expanded(child: name),
      SizedBox(
        width: metrics.modifiedWidth,
        child: Padding(
          padding: const EdgeInsets.only(left: _ImportTableMetrics.gap),
          child: modified,
        ),
      ),
      SizedBox(width: metrics.sizeWidth, child: size),
      for (var index = 0; index < widget.columns.length; index += 1)
        SizedBox(
          width: metrics.columnWidths[index],
          child: cell(widget.columns[index]),
        ),
    ],
  );

  TextStyle? _dimStyle(ThemeData theme) =>
      theme.textTheme.labelSmall?.copyWith(color: AppColors.textDim);

  Widget _headerCells(ThemeData theme, _ImportTableMetrics metrics) {
    final dim = _dimStyle(theme);
    return _tableLine(
      metrics,
      name: Text(
        AppText.strings.commonNameField,
        style: dim,
        overflow: TextOverflow.ellipsis,
      ),
      modified: Text(AppText.strings.imModified, style: dim, maxLines: 1),
      size: Text(
        AppText.strings.imSize,
        style: dim,
        maxLines: 1,
        textAlign: TextAlign.right,
      ),
      cell: (column) => _HeaderButton(
        column: column,
        enabled: widget.enabled && widget.rows.isNotEmpty,
        paths: [for (final row in widget.rows) row.path],
      ),
    );
  }

  Widget _rowList(ThemeData theme, _ImportTableMetrics metrics) =>
      ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.zero,
        itemCount: widget.rows.length,
        itemExtent: metrics.rowHeight,
        itemBuilder: (context, index) =>
            _fileRow(theme, metrics, widget.rows[index]),
      );

  Widget _fileRow(
    ThemeData theme,
    _ImportTableMetrics metrics,
    ImportFileRow row,
  ) {
    final dim = _dimStyle(theme);
    final isSelected = widget.selected.contains(row.path);
    final tap = widget.enabled ? () => widget.onRowTap(row.path) : null;
    return ControlPressClaim(
      onPressed: tap,
      child: InkWell(
        key: ValueKey<String>('import-row-${row.name}${row.extension}'),
        onTap: silentPress(tap),
        child: Container(
          color: isSelected ? AppColors.accent.withValues(alpha: 0.14) : null,
          padding: const EdgeInsets.fromLTRB(
            ImportFileTable._sidePadding,
            _ImportTableMetrics.rowPadV,
            ImportFileTable._sidePadding,
            _ImportTableMetrics.rowPadV,
          ),
          child: _tableLine(
            metrics,
            name: Row(
              children: [
                Flexible(
                  child: Text(
                    row.name,
                    key: ValueKey<String>('import-name-${row.path}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSelected ? AppColors.accent : null,
                    ),
                  ),
                ),
                Text(row.extension, maxLines: 1, style: dim),
              ],
            ),
            modified: Text(row.modified, style: dim, maxLines: 1),
            size: Text(
              row.size,
              style: dim,
              maxLines: 1,
              textAlign: TextAlign.right,
            ),
            cell: (column) => _OptionCell(
              column: column,
              path: row.path,
              enabled: widget.enabled,
              targets: _targets(row.path),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scrollbar(BoxConstraints constraints, _ImportTableMetrics metrics) =>
      AppScrollbar(
        axis: Axis.vertical,
        offset: _scroll.hasClients ? _scroll.offset : 0,
        viewportExtent: constraints.maxHeight,
        contentExtent: widget.rows.length * metrics.rowHeight,
        onOffsetChanged: (offset) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(offset);
          }
        },
      );
}

/// The key a column's answer goes by: the enum's name, or the value itself.
String _optionKey(Object? value) => value is Enum ? value.name : '$value';

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
    // A header speaks for every row, so an answer only some of them can give
    // is still offered — the ones that cannot will resolve it away, and the
    // cells will say so.
    final open = enabled
        ? () => _openColumnPopup(
            context,
            column: column,
            targets: paths,
            enabledFor: (value) => true,
            current: null,
          )
        : null;
    return ControlPressClaim(
      onPressed: open,
      child: InkWell(
        key: ValueKey<String>('import-column-${column.id}'),
        onTap: silentPress(open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(
            column.label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: enabled ? AppColors.textDim : theme.disabledColor,
            ),
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
    final key = ValueKey<String>('import-cell-${column.id}-$path');
    if (!column.appliesTo(path)) {
      // Keyed like any other cell: "this question does not apply here" is a
      // state of the cell, not the absence of one.
      return Text(
        '—',
        key: key,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(color: theme.disabledColor),
      );
    }
    final value = column.valueOf(path);
    // A value the file was FORCED to (an expanded PSD is baked, a new cut is
    // 1:1) is shown, and shown quiet: it is the answer, and it is not one
    // the user can change here.
    //
    // 🪦The example used to be「a movie is never carried」. That ceiling
    // died 2026-08-14 — a movie's carry chip is a CHOICE now, starting on
    // Reference, so it is not one of the locked ones.
    final locked =
        column.values
            .where((option) => column.enabledFor(path, option))
            .length <=
        1;
    final press = !enabled || locked
        ? null
        : column.style == ImportColumnStyle.toggle
        ? () => column.onPick(targets, value != true)
        : () => _openColumnPopup(
            context,
            column: column,
            targets: targets,
            enabledFor: (option) => column.enabledFor(path, option),
            current: value,
          );
    final wordStyle = theme.textTheme.labelSmall?.copyWith(
      color: locked ? theme.disabledColor : null,
    );
    return Center(
      child: ControlPressClaim(
        onPressed: press,
        child: InkWell(
          key: key,
          // The app's own corner, not a circular one: a cell is a well cut
          // into the row, and every well in this app wears the same shape.
          customBorder: AppShapes.container(AppShapes.wellRadius),
          onTap: silentPress(press),
          child: column.style == ImportColumnStyle.toggle
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The claim above fires the toggle; the ring is only
                    // its look (enabled, or dead when locked) — the app's
                    // one boolean, guide-sym ⑥⑦.
                    BooleanDot(
                      value: value == true,
                      enabled: !locked && enabled,
                      size: _ImportTableMetrics.dotSize,
                    ),
                    const SizedBox(width: _ImportTableMetrics.dotGap),
                    Text(column.labelOf(value), style: wordStyle),
                  ],
                )
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _ImportTableMetrics.chipPadH,
                    vertical: _ImportTableMetrics.chipPadV,
                  ),
                  decoration: ShapeDecoration(
                    shape: AppShapes.container(
                      AppShapes.wellRadius,
                      side: BorderSide(
                        color: locked
                            ? theme.dividerColor
                            : AppColors.hairlineStrong,
                      ),
                    ),
                  ),
                  child: Text(
                    column.labelOf(value),
                    maxLines: 1,
                    style: wordStyle,
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
  final text = TextMeasure(context, Theme.of(context).textTheme.labelSmall);
  // A popup row is its word plus its own padding, as a table row is: at a
  // fixed 24px a larger text scale cut every answer in half.
  final rowHeight = text.size('Ag').height + 2 * _PopupRow.padV;
  unawaited(
    showAnchoredPopup<void>(
      context,
      label: column.label,
      width: math.max(
        132,
        text.widest(rows.map(column.labelOf)) + 2 * _PopupRow.padH + 8,
      ),
      height: 8.0 + rows.length * rowHeight,
      builder: (context, close) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final value in rows)
            _PopupRow(
              keyValue: 'import-option-${column.id}-${_optionKey(value)}',
              label: column.labelOf(value),
              height: rowHeight,
              selected: value == current,
              enabled: enabledFor(value),
              onTap: () {
                column.onPick(targets, value);
                close();
              },
            ),
        ],
      ),
    ),
  );
}

class _PopupRow extends StatelessWidget {
  const _PopupRow({
    required this.keyValue,
    required this.label,
    required this.height,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  static const double padH = 8;
  static const double padV = 4;

  final String keyValue;
  final String label;
  final double height;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tap = enabled ? onTap : null;
    return ControlPressClaim(
      onPressed: tap,
      child: InkWell(
        key: ValueKey<String>(keyValue),
        onTap: silentPress(tap),
        child: Container(
          height: height,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: padH),
          color: selected ? AppColors.accent.withValues(alpha: 0.18) : null,
          child: Text(
            label,
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: !enabled
                  ? theme.disabledColor
                  : selected
                  ? AppColors.accent
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
