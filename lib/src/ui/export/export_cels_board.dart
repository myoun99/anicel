import 'package:flutter/material.dart';

import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../input/control_press_claim.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart' show AppColors, AppShapes;
import '../timeline/layer_label_controls.dart';
import '../timeline/layer_rail_columns.dart';
import '../timeline/timeline_block_word.dart';
import '../timeline/timeline_cell_style.dart';
import '../timeline/timeline_grid_metrics.dart'
    show timelineLayerRowHeightIn;
import '../widgets/app_icon_button.dart';
import '../widgets/app_scrollbar.dart';
import '../widgets/app_tooltip.dart';
import '../widgets/boolean_dot.dart';
import '../widgets/pill_strip.dart';
import 'export_cel_group_plan.dart';
import 'export_nav_bar.dart' show ExportStepButton;

/// ONE ROW of the Cels tab's list: a row of the cut the list shows, what
/// its switch says, whether it folds what is under it, and the drawings
/// that stand on it.
class ExportCelsBoardRow {
  const ExportCelsBoardRow({
    required this.layer,
    required this.state,
    required this.sheets,
    this.open,
  });

  final Layer layer;

  /// On or off — and, for a folder, what the rows under it say together.
  final BooleanMix state;

  /// The drawings that stand on this row, in the order the plan lists them:
  /// none on a folder, and none on a synced attach row (its drawings follow
  /// its base's).
  final List<ExportCelSheet> sheets;

  /// Whether what this row holds under it — a folder's rows, a base's
  /// attach rows — is shown; null on a row that holds nothing.
  final bool? open;

  bool get isFolder => layer.kind.groupsLayers;
}

/// The Cels tab's list, under its preview (F-289): the rules that pick the
/// rows on the left, and beside them the cut's rows AS THE TIMELINE DRAWS
/// THEM — the rail's own leading cells, then one block a drawing.
///
/// 🗣️유저 2026-10-06: 「타임라인처럼 어태치레이어 펼치는 버튼 똑같이
/// 통일해서 넣어서 … 그냥 세로말고 타임라인처럼 가로로 … 다만 물론
/// 타임라인처럼 코마수에따라 버튼 늘리거나 하지않고 지금처럼 하나의 정해진
/// 크기의 버튼으로서」, under the preview (「가로/아래가 좋고」), eight rows
/// tall with both scrollbars standing (「8줄? 고정으로 두고 스크롤바 가로
/// 세로 두고싶어」).
///
/// A block is BRIGHT while its file is written and HOLLOW while it is not
/// (「흐린블록은 상태적으로 필요없다고생각해」): pressed, a drawing the export
/// would write is turned off or back on, and one it would not says why.
///
/// Stateless but for its two scroll positions: the window owns everything
/// it shows.
class ExportCelsBoard extends StatefulWidget {
  const ExportCelsBoard({
    super.key,
    required this.rules,
    required this.band,
    required this.rows,
    required this.layers,
    required this.standing,
    required this.shown,
    required this.enabled,
    required this.onRowSwitched,
    required this.onFolded,
    required this.onStoodOn,
    required this.onSheetPressed,
  });

  /// The rules column ([ExportCelsRules]).
  final Widget rules;

  /// The band over the rows ([ExportCelsBand]).
  final Widget band;

  final List<ExportCelsBoardRow> rows;

  /// The cut's stack — a row's nesting depth is read from it.
  final List<Layer> layers;

  /// The row stood on, and the drawing of it the preview shows.
  final LayerId? standing;
  final FrameId? shown;

  /// False while an export runs: nothing here takes a press.
  final bool enabled;

  /// A row's switch, pressed: what the row — or every row under a folder —
  /// should become.
  final void Function(ExportCelsBoardRow row, bool on) onRowSwitched;
  final ValueChanged<ExportCelsBoardRow> onFolded;
  final ValueChanged<ExportCelsBoardRow> onStoodOn;
  final ValueChanged<ExportCelSheet> onSheetPressed;

  /// The rules column's width.
  static const double rulesWidth = 168;

  /// The rail's width: the timeline rail's leading cells and a name.
  static const double railWidth = 192;

  /// One block — a drawing, whatever its length on the timeline.
  static const double blockWidth = 24;

  /// The band's height.
  static const double bandHeight = 28;

  /// How many rows the list shows at once.
  static const int rowsShown = 8;

  /// What the board stands as tall as: the band, [rowsShown] rows, and the
  /// horizontal bar's lane under its hairline, inside its outline.
  static double heightIn(BuildContext context) =>
      bandHeight +
      rowsShown * timelineLayerRowHeightIn(context) +
      1 +
      AppScrollbarLane.wide +
      2;

  /// The narrowest the board lays out at: the rules, the vertical bar's
  /// lane, the rail and five blocks.
  static const double minimumWidth =
      rulesWidth + AppScrollbarLane.wide + railWidth + 5 * blockWidth + 2;

  @override
  State<ExportCelsBoard> createState() => _ExportCelsBoardState();
}

class _ExportCelsBoardState extends State<ExportCelsBoard> {
  final ScrollController _down = ScrollController();
  final ScrollController _across = ScrollController();

  @override
  void dispose() {
    _down.dispose();
    _across.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: Theme.of(context).dividerColor);
    return Container(
      key: const ValueKey<String>('export-cels-board'),
      height: ExportCelsBoard.heightIn(context),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        shape: AppShapes.container(AppShapes.wellRadius, side: line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: ExportCelsBoard.rulesWidth,
            decoration: BoxDecoration(border: Border(right: line)),
            child: widget.rules,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: ExportCelsBoard.bandHeight,
                  decoration: BoxDecoration(border: Border(bottom: line)),
                  child: widget.band,
                ),
                Expanded(child: _rows(context)),
                _acrossLane(line),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The rows under the band: the vertical bar's lane at their far left,
  /// then the rail that stays and the blocks that scroll across.
  Widget _rows(BuildContext context) {
    final rowHeight = timelineLayerRowHeightIn(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: AppScrollbarLane.wide,
          child: AppControllerScrollbar(
            controller: _down,
            axis: Axis.vertical,
            laneKey: const ValueKey<String>(
              'export-cels-board-vertical-lane',
            ),
            thumbKey: const ValueKey<String>(
              'export-cels-board-vertical-thumb',
            ),
          ),
        ),
        Expanded(
          child: ScrollConfiguration(
            // The lanes ARE the bars: the app's own scroll behaviour would
            // lay a second pair over the rows.
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: SingleChildScrollView(
              key: const ValueKey<String>('export-cels-board-rows'),
              controller: _down,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: ExportCelsBoard.railWidth,
                    child: Column(
                      children: [
                        for (final row in widget.rows)
                          _rail(context, row, rowHeight),
                      ],
                    ),
                  ),
                  Expanded(child: _blockRows(context, rowHeight)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The drawings, a row of blocks a row — as wide as the longest row, and
  /// scrolled across by the lane under them.
  Widget _blockRows(BuildContext context, double rowHeight) {
    final longest = widget.rows.fold<int>(
      0,
      (most, row) => row.sheets.length > most ? row.sheets.length : most,
    );
    return SingleChildScrollView(
      key: const ValueKey<String>('export-cels-board-blocks'),
      controller: _across,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: ExportCelsBoard.blockWidth * longest + 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in widget.rows) _blocks(context, row, rowHeight),
          ],
        ),
      ),
    );
  }

  /// The horizontal bar's lane, under its hairline: the bar runs under the
  /// blocks it scrolls, not under the rail that stays.
  Widget _acrossLane(BorderSide line) => Container(
    height: AppScrollbarLane.wide + 1,
    decoration: BoxDecoration(border: Border(top: line)),
    padding: const EdgeInsets.only(
      left: AppScrollbarLane.wide + ExportCelsBoard.railWidth,
    ),
    child: AppControllerScrollbar(
      controller: _across,
      axis: Axis.horizontal,
      laneKey: const ValueKey<String>('export-cels-board-horizontal-lane'),
      thumbKey: const ValueKey<String>('export-cels-board-horizontal-thumb'),
    ),
  );

  /// A row's rail: the timeline rail's leading cells ([_leading]), then the
  /// nesting guides, the name and the fold twirl's seat.
  Widget _rail(BuildContext context, ExportCelsBoardRow row, double height) {
    final scheme = Theme.of(context).colorScheme;
    final layer = row.layer;
    final on = row.state != BooleanMix.off;
    final ink = on
        ? AppColors.text
        : AppColors.text.withValues(alpha: AppColors.offAlpha);
    final line = BorderSide(color: scheme.outlineVariant);
    return Container(
      key: ValueKey<String>('export-cels-row-${layer.id.value}'),
      height: height,
      // The rail row's own plate: its standing wash, its hairlines.
      decoration: BoxDecoration(
        color: layer.id == widget.standing
            ? railSelectedRowColor(scheme)
            : scheme.surface,
        border: Border(bottom: line, right: line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._leading(row, ink: ink, lit: on),
          ?layerRailDepthGuides(
            Axis.horizontal,
            widget.layers.ancestryOf(layer.folderId).length,
            colorScheme: scheme,
          ),
          Expanded(child: _name(context, row, ink)),
          _twirlSeat(row),
        ],
      ),
    );
  }

  /// THE TIMELINE RAIL'S LEADING CELLS ([layerRailLeadingCells] — the one
  /// declaration of their order and widths), with this list's switch where
  /// the rail keeps its section band.
  List<Widget> _leading(
    ExportCelsBoardRow row, {
    required Color ink,
    required bool lit,
  }) {
    final layer = row.layer;
    final idValue = layer.id.value;
    return layerRailLeadingCells(
      sectionBand: _switch(row),
      mark: LayerMarkPlates(mark: layer.mark, isVisible: lit),
      timesheet: isAttachedLayer(layer)
          ? LayerAttachArrowCell(
              keyPrefix: 'export-cels',
              idValue: idValue,
              placement: layer.attachedPlacement,
            )
          : null,
      typeButton: IconTheme.merge(
        data: IconThemeData(color: ink),
        child: LayerTypeButton(
          keyPrefix: 'export-cels',
          idValue: idValue,
          kind: layer.kind,
          folderCollapsed: row.open == false,
        ),
      ),
    );
  }

  /// The row's name — and, on a row that holds drawings, the press that
  /// stands the list on it.
  Widget _name(BuildContext context, ExportCelsBoardRow row, Color ink) {
    final idValue = row.layer.id.value;
    final name = Align(
      alignment: Alignment.centerLeft,
      child: Text(
        row.layer.name,
        key: ValueKey<String>('export-cels-name-$idValue'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: layerRowNameStyle(context).copyWith(color: ink),
      ),
    );
    if (row.sheets.isEmpty) {
      return name;
    }
    return ControlPressClaim(
      onPressed: () => widget.onStoodOn(row),
      child: InkWell(
        key: ValueKey<String>('export-cels-stand-$idValue'),
        onTap: silentPress(() => widget.onStoodOn(row)),
        child: name,
      ),
    );
  }

  /// The fold twirl's seat: every row's, at the name's far edge as the rail
  /// has it (F-29), whether or not the row folds anything.
  Widget _twirlSeat(ExportCelsBoardRow row) {
    final open = row.open;
    final idValue = row.layer.id.value;
    return SizedBox(
      key: ValueKey<String>('export-cels-twirl-seat-$idValue'),
      width: layerLaneToggleSlotWidth,
      child: open == null
          ? null
          : LayerFoldTwirl(
              keyValue: 'export-cels-twirl-$idValue',
              expanded: open,
              onToggle: () => widget.onFolded(row),
            ),
    );
  }

  /// The row's switch: the app's boolean, and over a folder's rows the one
  /// that can say they disagree.
  Widget _switch(ExportCelsBoardRow row) {
    final idValue = row.layer.id.value;
    final pressed = widget.enabled
        ? (bool on) => widget.onRowSwitched(row, on)
        : null;
    const box = AppIconButtonBox(
      width: layerSectionLabelSlotWidth,
      height: 24,
      iconSize: 14,
    );
    return row.isFolder
        ? BooleanMixDotButton(
            keyValue: 'export-cels-switch-$idValue',
            tooltip: AppText.strings.exExport,
            value: row.state,
            size: box,
            onChanged: pressed,
          )
        : BooleanDotButton(
            keyValue: 'export-cels-switch-$idValue',
            tooltip: AppText.strings.exExport,
            value: row.state == BooleanMix.on,
            size: box,
            onChanged: pressed,
          );
  }

  /// The row's drawings, a block each.
  Widget _blocks(BuildContext context, ExportCelsBoardRow row, double height) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      // The wash the timeline lays under the cells of the row stood on.
      decoration: BoxDecoration(
        color: row.layer.id == widget.standing
            ? timelineActiveRowWashColor(colorScheme)
            : null,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final sheet in row.sheets)
            ExportCelBlock(
              sheet: sheet,
              // The hairline under the row is the row's, not the block's.
              height: height - 1,
              shown:
                  row.layer.id == widget.standing &&
                  sheet.frame.id == widget.shown,
              onPressed: widget.enabled
                  ? () => widget.onSheetPressed(sheet)
                  : null,
            ),
        ],
      ),
    );
  }
}

/// ONE DRAWING in the list: the timeline's frame block — its row's label
/// colour for paper, the block's own corner, its word in the block's print
/// — at one cell's width whatever its length on the timeline.
///
/// BRIGHT while its file is written, HOLLOW while it is not; the one the
/// preview shows wears the accent, and one a direction is laid over wears a
/// 「D」 (유저 2026-10-06: 「블록에 디렉션적용시 빨간점말고 D라는 텍스트가 더
/// 맞을듯」).
class ExportCelBlock extends StatelessWidget {
  const ExportCelBlock({
    super.key,
    required this.sheet,
    required this.height,
    required this.shown,
    required this.onPressed,
  });

  final ExportCelSheet sheet;

  /// The block's height — its row's, which its corner is cut against.
  final double height;

  /// Whether the preview shows this drawing.
  final bool shown;

  /// Null while an export runs.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final written = sheet.written;
    final idValue = '${sheet.row.id.value}-${sheet.frame.id.value}';
    final file = sheet.look.fileName;
    return AppTooltip(
      message: file.isEmpty ? sheet.fullName : file,
      child: ControlPressClaim(
        onPressed: onPressed,
        child: InkWell(
          key: ValueKey<String>('export-cels-block-$idValue'),
          onTap: silentPress(onPressed),
          child: Container(
            width: ExportCelsBoard.blockWidth,
            clipBehavior: Clip.antiAlias,
            decoration: _paper(written),
            // The drawing the preview shows wears the accent over its paper.
            foregroundDecoration: shown && written
                ? BoxDecoration(color: AppColors.accent.withValues(alpha: 0.26))
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _word(context, written),
                if (sheet.look.overlays.isNotEmpty) _laidMark(idValue, written),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The block's paper: its row's label colour while its file is written —
  /// and none while it is not, the block's outline alone (the accent's on
  /// the one the preview shows).
  ///
  /// The timeline's own block corner, in the timeline's own form — a box
  /// rounded by the block law ([timelineBlockCornerRadiusAt]), as its
  /// selection band and its standing wash are.
  BoxDecoration _paper(bool written) => BoxDecoration(
    color: written ? layerMarkColor(sheet.row.mark) : null,
    borderRadius: BorderRadius.all(
      timelineBlockCornerRadiusAt(
        cellExtent: ExportCelsBoard.blockWidth,
        crossExtent: height,
      ),
    ),
    border: written
        ? null
        : Border.all(
            color: shown
                ? AppColors.accent
                : timelineDrawingHeldColor.withValues(alpha: 0.28),
          ),
  );

  /// What the block reads ([ExportCelSheet.word]) in the frame block's own
  /// print: one type whatever its length, narrowed into the block where it
  /// runs long.
  Widget _word(BuildContext context, bool written) => TimelineBlockText(
    text: sheet.word,
    place: (
      axis: Axis.horizontal,
      cells: 1,
      cellIndex: 0,
      growth: TimelineBlockWordGrowth.towardBlockEnd,
      acrossAlignment: 0,
    ),
    style: timelineBlockWordStyle(
      DefaultTextStyle.of(context).style,
      ink: written
          ? timelineInBlockInk()
          : Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 12,
      bold: written,
    ),
  );

  /// 「D」: a direction is laid over this drawing.
  Widget _laidMark(String idValue, bool written) => Positioned(
    top: 1,
    right: 1.5,
    child: Text(
      'D',
      key: ValueKey<String>('export-cels-block-d-$idValue'),
      style: TextStyle(
        fontSize: 7.5,
        height: 1,
        fontWeight: FontWeight.bold,
        color: exportLaidDirectionInk.withValues(alpha: written ? 1 : 0.6),
      ),
    ),
  );
}

/// The colour a laid direction is said in: the 「D」 on the drawing it is
/// laid over, and the band's pill that laid it — one colour, so the eye
/// ties the pill to the mark it put there (drawn so in the F-289 mock).
const Color exportLaidDirectionInk = AppColors.danger;

/// One direction drawing the band offers to lay over the drawing shown.
typedef ExportCelsDirection = ({
  String keyValue,
  String name,
  String fullName,
  bool laid,
  VoidCallback? onPressed,
});

/// The band over the rows: the cut the list shows, how many files the
/// export writes, the two steps that turn through the standing row's
/// drawings, and what is laid over the drawing shown.
///
/// 🗣️유저 2026-10-06: 「미리보기창 위에 이 그림에 디렉션 적용이라는 텍스트
/// 옆에 디렉션 레이어의 그림 버튼이 있는거지 … 버튼엔 지시이름만 넣자. T.U
/// 이렇게하고 툴팁으로 T.U_A-B 이렇게」 — and it stands whether or not the
/// direction KIND is written (「디렉션 on이든 off든 관계없이 떠있도록」).
///
/// CAM is the door alone: 「나중에 캔버스에서 그 카메라 궤도같은거 어떻게
/// 보여주게할지를 정할거고, 그 정한거를 가져오도록 입구만 만들어 주면되」.
class ExportCelsBand extends StatelessWidget {
  const ExportCelsBand({
    super.key,
    required this.cutPicker,
    required this.count,
    required this.onStep,
    required this.canStepBack,
    required this.canStepOn,
    required this.directions,
  });

  final Widget cutPicker;

  /// How many files the export writes, said with its noun.
  final String count;

  /// Null while an export runs.
  final ValueChanged<int>? onStep;
  final bool canStepBack;
  final bool canStepOn;

  final List<ExportCelsDirection> directions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 8),
      child: Row(
        children: [
          cutPicker,
          const SizedBox(width: 8),
          Text(
            count,
            key: const ValueKey<String>('export-cels-count'),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              letterSpacing: 0.6,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          ..._steps(),
          const SizedBox(width: 8),
          Expanded(child: _laying()),
        ],
      ),
    );
  }

  /// ◀ ▶: a drawing back and a drawing on, along the row stood on.
  List<Widget> _steps() {
    final step = onStep;
    return [
      ExportStepButton(
        keyValue: 'export-cels-prev',
        glyph: '◀',
        onPressed: step != null && canStepBack ? () => step(-1) : null,
      ),
      const SizedBox(width: 4),
      ExportStepButton(
        keyValue: 'export-cels-next',
        glyph: '▶',
        onPressed: step != null && canStepOn ? () => step(1) : null,
      ),
    ];
  }

  /// What is laid over the drawing shown, at the band's far end: the
  /// caption, a pill a direction drawing, and CAM. The caption and the
  /// pills give width up before the band runs over.
  Widget _laying() => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      const Flexible(child: _LayDirectionCaption()),
      const SizedBox(width: 8),
      // A cut with no direction drawing has nothing to offer here: the
      // caption keeps the band's shape.
      if (directions.isNotEmpty)
        Flexible(
          child: PillStrip(
            items: [
              for (final direction in directions)
                PillItem(
                  keyValue: direction.keyValue,
                  label: direction.name,
                  tooltip: direction.fullName,
                  selected: direction.laid,
                  tone: exportLaidDirectionInk,
                  onTap: direction.onPressed,
                ),
            ],
          ),
        ),
      const SizedBox(width: 8),
      PillStrip(
        items: [
          PillItem(
            keyValue: 'export-cels-cam',
            label: 'CAM',
            tooltip: AppText.strings.tlKindCamera,
            selected: false,
          ),
        ],
      ),
    ],
  );
}

/// 「이 그림에 디렉션 적용」 over the direction pills: the whole of it where
/// the band has the room, the row kind's own word (「디렉션」) where it has
/// not — and the whole of it on hover either way (drawn so in the F-289
/// mock, whose narrow band read 「디렉션」).
class _LayDirectionCaption extends StatelessWidget {
  const _LayDirectionCaption();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppText.strings;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AppTooltip(
      message: strings.exLayDirection,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final whole = TextPainter(
            text: TextSpan(text: strings.exLayDirection, style: style),
            maxLines: 1,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final fits = whole.width <= constraints.maxWidth;
          whole.dispose();
          return Text(
            fits ? strings.exLayDirection : strings.tlKindInstruction,
            key: const ValueKey<String>('export-cels-lay-caption'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        },
      ),
    );
  }
}
