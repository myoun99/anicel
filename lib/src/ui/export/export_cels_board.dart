import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/export_cel_kind.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_mark.dart';
import '../canvas/guide_overlay.dart' show guideColorOf;
import '../input/control_press_claim.dart';
import '../text/app_strings.dart';
import '../theme/app_theme.dart' show AppColors, AppCursors, AppShapes;
import '../timeline/layer_label_controls.dart';
import '../timeline/layer_rail_columns.dart';
import '../timeline/timeline_block_look.dart';
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

/// ONE ROW of the Cels tab's list — a series of FILES: what its switch says
/// and the files that stand on it, a block each — a stack of the cut the
/// list shows ([ExportCelsLayerRow]), or one of the cut's documents
/// ([ExportCelsDocumentRow]).
///
/// 🗣️export-four-tabs (유저 2026-10-09): 「결국 나가는건 파일 하나니까
/// 파일기준 행이니까 접기 펼치기 없이 한 행만 보이면되」. ↩️A row was a
/// layer: a folder's switched the rows under it, and a base's twirl folded
/// its attach rows away.
sealed class ExportCelsBoardRow {
  const ExportCelsBoardRow({required this.state});

  /// Its files on, off — or, where they disagree, mixed ([exportRowState]).
  final BooleanMix state;

  /// Names the row in the list: its widget keys, and where the list stands.
  String get idValue;

  String get name;

  /// The files that stand on this row, in the order the plan lists them.
  List<ExportListSheet> get sheets;

  /// The label its blocks are papered in.
  LayerMark get mark;
}

/// A STACK of the cut: a base and the attach rows riding it, which its
/// files hold as the attach column says ([ExportCelsStack]).
final class ExportCelsLayerRow extends ExportCelsBoardRow {
  const ExportCelsLayerRow({
    required this.layer,
    required this.base,
    required super.state,
    required this.sheets,
  });

  /// The row its files stand on — the stack's base, or the free attach row
  /// that is the stack's only picture, whose name and frames they take.
  final Layer layer;

  /// The stack's base: what the row IS — where the list stands, what the
  /// attach column opens — whichever row its files stand on.
  final LayerId base;

  /// The drawings of [layer] the plan files — none while the stack holds
  /// no picture.
  @override
  final List<ExportCelSheet> sheets;

  @override
  String get idValue => base.value;

  @override
  String get name => layer.name;

  @override
  LayerMark get mark => layer.mark;
}

/// One of the cut's DOCUMENTS the tab writes beside its cels — its
/// timesheet, its cut envelope — closing the list under the cut's rows
/// (drawn so in the F-289 mock).
final class ExportCelsDocumentRow extends ExportCelsBoardRow {
  const ExportCelsDocumentRow({
    required this.kind,
    required this.name,
    required super.state,
    required this.sheets,
  });

  final ExportCelKind kind;

  @override
  final String name;

  @override
  final List<ExportDocumentSheet> sheets;

  /// No row of a cut wears this: a layer's id is never spelled so.
  @override
  String get idValue => 'document-${kind.jsonValue}';

  /// A document wears no label: its blocks are plain paper.
  @override
  LayerMark get mark => LayerMark.none;
}

/// The Cels tab's list, under its preview (F-289): the rules that pick the
/// rows on the left, the attach column beside them, and the cut's FILE rows
/// in the timeline's order — the rail's own leading cells, then one block a
/// drawing.
///
/// 🗣️유저 2026-10-06: 「그냥 세로말고 타임라인처럼 가로로 … 다만 물론
/// 타임라인처럼 코마수에따라 버튼 늘리거나 하지않고 지금처럼 하나의 정해진
/// 크기의 버튼으로서」, under the preview (「가로/아래가 좋고」), eight rows
/// tall with both scrollbars standing (「8줄? 고정으로 두고 스크롤바 가로
/// 세로 두고싶어」). ↩️It folded a base's attach rows behind the timeline's
/// twirl (「타임라인처럼 어태치레이어 펼치는 버튼 똑같이 통일해서」); a row is
/// a stack's files now, and what they hold is the attach column's
/// (export-four-tabs, 유저 2026-10-09).
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
    required this.stack,
    required this.band,
    required this.rows,
    required this.standing,
    required this.shown,
    required this.enabled,
    required this.onRowSwitched,
    required this.onStoodOn,
    required this.onSheetPressed,
    this.rulesNeed = 0,
  });

  /// The rules column — the window's, which knows what its words need
  /// ([rulesNeed]).
  final Widget rules;

  /// How wide [rules] needs to stand for every word of it to be whole, its
  /// padding included — the column stands [rulesWidthFor] that.
  final double rulesNeed;

  /// How wide the rules column stands for rules that need [need]: its
  /// least, or what they need and the hairline that closes the column.
  static double rulesWidthFor(double need) =>
      math.max(leastRulesWidth, need + const BorderSide().width);

  /// The attach column of the row stood on ([ExportCelsStack]).
  final Widget stack;

  /// The band over the rows ([ExportCelsBand]).
  final Widget band;

  final List<ExportCelsBoardRow> rows;

  /// The row stood on, and the file of it the preview shows
  /// ([ExportCelsBoardRow.idValue] · [ExportListSheet.idValue]).
  final String? standing;
  final String? shown;

  /// False while an export runs: nothing here takes a press.
  final bool enabled;

  /// A row's switch, pressed: what its files should become.
  final void Function(ExportCelsBoardRow row, bool on) onRowSwitched;
  final ValueChanged<ExportCelsBoardRow> onStoodOn;
  final ValueChanged<ExportListSheet> onSheetPressed;

  /// The rules column's least width — what it stands at in a language
  /// whose words fit it.
  ///
  /// ↩️It was the column's width in every language (F-486: 「絵コンテ」 got 22
  /// of its 43 px).
  static const double leastRulesWidth = 168;

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
      AppScrollbarLane.thin +
      2;

  /// The attach column's width (export-four-tabs-Q1, 유저 2026-10-08: 「안 A —
  /// 규칙 칸과 행 사이에 어태치 칸(184px)」) — grown by the cells its lines
  /// lead with since F-395, the base's slot and the timeline's label, take
  /// and kind, so a name keeps the room it had. ↩️184 while a line was led
  /// by the base's word or an attach row's arrow alone.
  static const double stackWidth = 248;

  /// The narrowest a board whose rules need [rulesNeed] lays out at: the
  /// rules, the attach column, the vertical bar's lane, the rail and five
  /// blocks.
  static double minimumWidthFor(double rulesNeed) =>
      rulesWidthFor(rulesNeed) +
      stackWidth +
      AppScrollbarLane.thin +
      railWidth +
      5 * blockWidth +
      2;

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
            key: const ValueKey<String>('export-cels-rules'),
            width: ExportCelsBoard.rulesWidthFor(widget.rulesNeed),
            decoration: BoxDecoration(border: Border(right: line)),
            child: widget.rules,
          ),
          Container(
            width: ExportCelsBoard.stackWidth,
            decoration: BoxDecoration(border: Border(right: line)),
            child: widget.stack,
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
          width: AppScrollbarLane.thin,
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
    height: AppScrollbarLane.thin + 1,
    decoration: BoxDecoration(border: Border(top: line)),
    padding: const EdgeInsets.only(
      left: AppScrollbarLane.thin + ExportCelsBoard.railWidth,
    ),
    child: AppControllerScrollbar(
      controller: _across,
      axis: Axis.horizontal,
      laneKey: const ValueKey<String>('export-cels-board-horizontal-lane'),
      thumbKey: const ValueKey<String>('export-cels-board-horizontal-thumb'),
    ),
  );

  /// A row's rail: the timeline rail's leading cells ([_leading]), then the
  /// name. ↩️The nesting guides and the fold twirl's seat stood after them
  /// while a row was a layer among folders.
  Widget _rail(BuildContext context, ExportCelsBoardRow row, double height) {
    final scheme = Theme.of(context).colorScheme;
    final on = row.state != BooleanMix.off;
    final ink = on
        ? AppColors.text
        : AppColors.text.withValues(alpha: AppColors.offAlpha);
    final line = BorderSide(color: scheme.outlineVariant);
    return Container(
      key: ValueKey<String>('export-cels-row-${row.idValue}'),
      height: height,
      // The rail row's own plate: its standing wash, its hairlines.
      decoration: BoxDecoration(
        color: row.idValue == widget.standing
            ? railSelectedRowColor(scheme)
            : scheme.surface,
        border: Border(bottom: line, right: line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._leading(row, ink: ink, lit: on),
          Expanded(child: _name(context, row, ink)),
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
    final idValue = row.idValue;
    Widget kindCell(LayerTypeButton button) =>
        IconTheme.merge(data: IconThemeData(color: ink), child: button);
    return switch (row) {
      ExportCelsLayerRow(:final layer) => layerRailLeadingCells(
        sectionBand: _switch(row),
        mark: LayerMarkPlates(mark: layer.mark, isVisible: lit),
        timesheet: isAttachedLayer(layer)
            ? LayerAttachArrowCell(
                keyPrefix: 'export-cels',
                idValue: idValue,
                placement: layer.attachedPlacement,
              )
            : null,
        typeButton: kindCell(
          LayerTypeButton(
            keyPrefix: 'export-cels',
            idValue: idValue,
            kind: layer.kind,
          ),
        ),
      ),
      // A document is no layer: its label plate and its sheet slot stand
      // empty, and its kind cell wears its own panel's icon.
      ExportCelsDocumentRow(:final kind) => layerRailLeadingCells(
        sectionBand: _switch(row),
        typeButton: kindCell(
          LayerTypeButton(
            keyPrefix: 'export-cels',
            idValue: idValue,
            icon: exportDocumentIcon(kind),
            semanticLabel: row.name,
          ),
        ),
      ),
    };
  }

  /// The row's name — the press that stands the list on it, whether or not
  /// it holds a file (its attach column is where a picture is put back).
  /// Dead while an export runs, as the rest of the board is: standing on a
  /// row turns the preview, and the preview shows what the run is writing.
  Widget _name(BuildContext context, ExportCelsBoardRow row, Color ink) {
    final idValue = row.idValue;
    final standOn = widget.enabled ? () => widget.onStoodOn(row) : null;
    return ControlPressClaim(
      onPressed: standOn,
      child: InkWell(
        mouseCursor: AppCursors.press,
        key: ValueKey<String>('export-cels-stand-$idValue'),
        onTap: silentPress(standOn),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            row.name,
            key: ValueKey<String>('export-cels-name-$idValue'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: layerRowNameStyle(context).copyWith(color: ink),
          ),
        ),
      ),
    );
  }

  /// The row's switch: the app's boolean over its files — the one that can
  /// say they disagree ([exportRowState]).
  Widget _switch(ExportCelsBoardRow row) => BooleanMixDotButton(
    keyValue: 'export-cels-switch-${row.idValue}',
    tooltip: AppText.strings.exExport,
    value: row.state,
    size: const AppIconButtonBox(
      width: layerSectionLabelSlotWidth,
      height: 24,
      iconSize: 14,
    ),
    onChanged: widget.enabled
        ? (bool on) => widget.onRowSwitched(row, on)
        : null,
  );

  /// The row's drawings, a block each.
  Widget _blocks(BuildContext context, ExportCelsBoardRow row, double height) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      // The wash the timeline lays under the cells of the row stood on.
      decoration: BoxDecoration(
        color: row.idValue == widget.standing
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
              rowId: row.idValue,
              mark: row.mark,
              // The hairline under the row is the row's, not the block's.
              height: height - 1,
              shown:
                  row.idValue == widget.standing &&
                  sheet.idValue == widget.shown,
              onPressed: widget.enabled
                  ? () => widget.onSheetPressed(sheet)
                  : null,
            ),
        ],
      ),
    );
  }
}

/// The icon of one of the cut's documents: its own panel's, as the
/// workspace's tab wears it.
IconData exportDocumentIcon(ExportCelKind kind) => switch (kind) {
  ExportCelKind.envelope => Icons.mail_outline,
  _ => Icons.table_chart_outlined,
};

/// ONE FILE in the list — a drawing, a page of a document: the timeline's
/// frame block — its row's label colour for paper, the block's own corner,
/// its word in the block's print — at one cell's width whatever its length
/// on the timeline.
///
/// BRIGHT while its file is written, HOLLOW while it is not; the one the
/// preview shows wears the accent, and one a direction is laid over wears a
/// 「D」 (유저 2026-10-06: 「블록에 디렉션적용시 빨간점말고 D라는 텍스트가 더
/// 맞을듯」).
class ExportCelBlock extends StatelessWidget {
  const ExportCelBlock({
    super.key,
    required this.sheet,
    required this.rowId,
    required this.mark,
    required this.height,
    required this.shown,
    required this.onPressed,
  });

  final ExportListSheet sheet;

  /// The row it stands on ([ExportCelsBoardRow.idValue]), and the label
  /// that row papers its blocks in.
  final String rowId;
  final LayerMark mark;

  /// The block's height — its row's, which its corner is cut against.
  final double height;

  /// Whether the preview shows this drawing.
  final bool shown;

  /// Null while an export runs.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final written = sheet.written;
    final idValue = '$rowId-${sheet.idValue}';
    final file = sheet.fileName;
    return AppTooltip(
      message: file.isEmpty ? sheet.fullName : file,
      child: ControlPressClaim(
        onPressed: onPressed,
        child: InkWell(
          mouseCursor: AppCursors.press,
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
                if (sheet.cameraLaid ||
                    sheet.directionLaid ||
                    sheet.guidesLaid)
                  _laidMarks(idValue, written, guideColorOf(context)),
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
  BoxDecoration _paper(bool written) {
    final look = _look(written);
    final line = look.line;
    return BoxDecoration(
      color: look.paper,
      borderRadius: BorderRadius.all(
        timelineBlockCornerRadiusAt(
          cellExtent: ExportCelsBoard.blockWidth,
          crossExtent: height,
        ),
      ),
      border: line == null
          ? null
          : Border.all(
              color: shown ? AppColors.accent : line,
              width: timelineBlockLineWidth,
            ),
    );
  }

  /// The block as the timeline draws a frame block ([timelineBlockLook]):
  /// a written one shown, one not written HOLLOW — the empty block's look,
  /// which the timeline's empty blocks took from this one (I-129).
  TimelineBlockLook _look(bool written) => timelineBlockLook(
    written ? TimelineBlockState.shown : TimelineBlockState.empty,
    paper: layerMarkColor(mark),
    ink: timelineInBlockInk(),
  );

  /// What the block reads ([ExportCelSheet.word]) in the frame block's own
  /// print: one type whatever its length, narrowed into the block where it
  /// runs long — a hollow one's in its outline's grey (I-129: 「텍스트는 …
  /// 외곽선이랑 동일한 회색으로」).
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
      ink: _look(written).ink,
      fontSize: 12,
      bold: written,
    ),
  );

  /// What is laid over this drawing, in its corner: 「C」 for the camera's
  /// work, 「D」 for a direction, 「G」 for the guides — side by side where
  /// more than one is.
  ///
  /// 🗣️I-89-Q21 (유저 2026-10-12): 「「C」를 붙인다」 — beside the 「D」
  /// 유저 asked for on 10-06 (「블록에 디렉션적용시 빨간점말고 D라는 텍스트가
  /// 더 맞을듯」), by the same law: each letter in the colour of the band's
  /// button that laid it. 「G」 by that law too (I-105) — in [guideInk], the
  /// colour the canvas draws the guides in.
  Widget _laidMarks(String idValue, bool written, Color guideInk) => Positioned(
    top: 1,
    right: 1.5,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 1.5,
      children: [
        if (sheet.cameraLaid)
          _laidMark(
            'C',
            'export-cels-block-c-$idValue',
            exportLaidCameraInk,
            written,
          ),
        if (sheet.directionLaid)
          _laidMark(
            'D',
            'export-cels-block-d-$idValue',
            exportLaidDirectionInk,
            written,
          ),
        if (sheet.guidesLaid)
          _laidMark('G', 'export-cels-block-g-$idValue', guideInk, written),
      ],
    ),
  );

  Widget _laidMark(String letter, String keyValue, Color ink, bool written) =>
      Text(
        letter,
        key: ValueKey<String>(keyValue),
        style: TextStyle(
          fontSize: 7.5,
          height: 1,
          fontWeight: FontWeight.bold,
          color: ink.withValues(alpha: written ? 1 : 0.6),
        ),
      );
}

/// The colour a laid direction is said in: the 「D」 on the drawing it is
/// laid over, and the band's pill that laid it — one colour, so the eye
/// ties the pill to the mark it put there (drawn so in the F-289 mock).
Color get exportLaidDirectionInk => AppColors.danger;

/// The colour the camera's work laid is said in: the 「C」 on the drawing it
/// is laid over, and the CAM pill that laid it — as for
/// [exportLaidDirectionInk] (I-89-Q21). Read live: the accent is the
/// user's to set ([AppColors.accentSettings]).
Color get exportLaidCameraInk => AppColors.accent;

/// One direction drawing the band offers to lay over the drawing shown.
typedef ExportCelsDirection = ({
  String keyValue,
  String name,
  String fullName,
  bool laid,
  VoidCallback? onPressed,
});

/// What the band offers to lay over the drawing shown with one pill — the
/// camera's work, the guides: lit while it is laid, null to press while
/// there is nothing to lay it on.
typedef ExportCelsLaying = ({bool laid, VoidCallback? onPressed});

/// The band over the rows: the cut the list shows, how many files the
/// export writes, the two steps that turn through the standing row's
/// drawings, and what is laid over the drawing shown.
///
/// 🗣️유저 2026-10-06: 「미리보기창 위에 이 그림에 디렉션 적용이라는 텍스트
/// 옆에 디렉션 레이어의 그림 버튼이 있는거지 … 버튼엔 지시이름만 넣자. T.U
/// 이렇게하고 툴팁으로 T.U_A-B 이렇게」 — and it stands whether or not the
/// direction KIND is written (「디렉션 on이든 off든 관계없이 떠있도록」).
///
/// CAM lays the camera's work over it, as the canvas draws it (I-89-Q18).
/// ↩️It was the door alone until the canvas's was settled: 「나중에
/// 캔버스에서 그 카메라 궤도같은거 어떻게 보여주게할지를 정할거고, 그
/// 정한거를 가져오도록 입구만 만들어 주면되」.
///
/// 「가이드」 beside it lays the cut's guides over it, as the canvas draws
/// them at rest — 🗣️I-105 (유저 2026-10-16): 「셀 출력시 CAM 적용 하는거랑
/// 똑같이 거기에 가이드 버튼 만들어서 해당 컷 가이드 그림에 넣기」.
class ExportCelsBand extends StatelessWidget {
  const ExportCelsBand({
    super.key,
    required this.cutPicker,
    required this.count,
    required this.onStep,
    required this.canStepBack,
    required this.canStepOn,
    required this.directions,
    this.camera = const (laid: false, onPressed: null),
    this.guides = const (laid: false, onPressed: null),
    this.laysOver = true,
  });

  final Widget cutPicker;

  /// How many files the export writes, said with its noun.
  final String count;

  /// Null while an export runs.
  final ValueChanged<int>? onStep;
  final bool canStepBack;
  final bool canStepOn;

  final List<ExportCelsDirection> directions;
  final ExportCelsLaying camera;
  final ExportCelsLaying guides;

  /// Whether the tab lays anything over its cels — the AE Script tab lays
  /// none: a direction goes over the shot as a guide of its own there
  /// (ae-script-export-Q3 「AE 가이드 레이어로 따로」).
  final bool laysOver;

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
          Expanded(
            child: laysOver
                ? _laying(guideColorOf(context))
                : const SizedBox.shrink(),
          ),
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
  /// caption, a pill a direction drawing, then CAM and 「가이드」 — that one
  /// in [guideInk], the colour the canvas draws the guides in.
  ///
  /// Where the band has not the room for all of it, the caption gives width
  /// up first — its whole, then its word — and the pills only after it, as
  /// strips side by side do ([PillStrips]). ⚖️공통 2026-10-17 (I-105, the
  /// user's to overturn): a pill is what is pressed, and cut short, 「T.U」
  /// and 「PAN」 read alike; the caption says once what they are for.
  /// ⚠️Not room the band can make: at the window's least width the end is
  /// 112–153 px in the app's faces (en · ja · ko · fr), and the caption's
  /// word and every pill whole take 180–230.
  Widget _laying(Color guideInk) => LayoutBuilder(
    builder: (context, room) => Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Flexible(child: _LayDirectionCaption()),
        const SizedBox(width: 8),
        ConstrainedBox(
          // All the room but the gap before it.
          constraints: BoxConstraints(
            maxWidth: room.maxWidth > 8 ? room.maxWidth - 8 : 0,
          ),
          child: PillStrips(
            strips: [
              // A cut with no direction drawing has nothing to offer here:
              // the caption keeps the band's shape.
              if (directions.isNotEmpty)
                PillStrip(
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
              PillStrip(
                items: [
                  PillItem(
                    keyValue: 'export-cels-cam',
                    label: 'CAM',
                    tooltip: AppText.strings.tlKindCamera,
                    selected: camera.laid,
                    tone: exportLaidCameraInk,
                    onTap: camera.onPressed,
                  ),
                  PillItem(
                    keyValue: 'export-cels-guides',
                    label: AppText.strings.exLayGuides,
                    selected: guides.laid,
                    tone: guideInk,
                    onTap: guides.onPressed,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
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

/// One step along the drawings a row turns through — ◀ or ▶ in a hairline
/// box, the band's pair (F-289, 유저 2026-10-06: 「좌우 버튼 만들어서 넣자.
/// 컴팩트하게」).
///
/// ↩️It was the nav bar's pair first: the bar that scrubbed every tab's
/// preview stood under the picture, and the preview's own panel turns it
/// now (`ExportPreviewPanel`).
class ExportStepButton extends StatelessWidget {
  const ExportStepButton({
    super.key,
    required this.keyValue,
    required this.glyph,
    required this.onPressed,
  });

  final String keyValue;
  final String glyph;

  /// Null = nowhere to step: the button keeps its place and takes no press.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ControlPressClaim(
      onPressed: onPressed,
      child: InkWell(
        mouseCursor: AppCursors.press,
        key: ValueKey<String>(keyValue),
        onTap: silentPress(onPressed),
        customBorder: AppShapes.container(AppShapes.wellRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: ShapeDecoration(
            shape: AppShapes.container(
              AppShapes.wellRadius,
              side: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Text(glyph, style: theme.textTheme.labelSmall),
        ),
      ),
    );
  }
}
