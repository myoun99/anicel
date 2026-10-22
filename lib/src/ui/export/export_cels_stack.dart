import 'package:flutter/material.dart';

import '../../models/layer.dart';
import '../text/app_strings.dart';
import '../timeline/layer_label_controls.dart';
import '../timeline/layer_rail_columns.dart' show LayerTypeButton;
import '../widgets/app_scrollbar.dart';
import '../widgets/settings_rows.dart';
import 'export_cels_board.dart';

/// One line of the attach column: a row of the stack the list stands on,
/// and whether the files hold it.
typedef ExportCelsStackLine = ({Layer layer, bool on});

/// THE ATTACH COLUMN, between the rules and the rows: what the files of the
/// row the Cels list stands on HOLD — its stack as the timeline draws it,
/// the attach rows above, the base, the attach rows below
/// ([ExportCelsListing.stackOf]) — each with the app's switch: in, or not.
///
/// 🗣️export-four-tabs (유저 2026-10-08 · 09): Q1 「안 A — 규칙 칸과 행
/// 사이에 어태치 칸(184px)」 · Q3 「쌓이는 순서 그대로 — 위 어태치, 기준,
/// 아래 어태치」 · the consult — the base wears a switch too (「어태치만」 is
/// the base switched off here), and every line can be switched off: a stack
/// that holds nothing is a row with no file, dimmed in the list like any
/// row that is off (「보이더라도 다른거처럼 이름 흐리게 이런거 동일하게」).
/// An attach row a filter leaves out is not offered (「필터전부」).
///
/// A switch is a row exception ([ExportCelsCutDelta.layerOverrides]): the
/// label button reads 「커스텀」 while one answers by hand. A document's row
/// holds no rows — the column stands empty under its head.
class ExportCelsStack extends StatefulWidget {
  const ExportCelsStack({
    super.key,
    required this.row,
    required this.lines,
    required this.onSwitched,
  });

  /// The row the list stands on — the base its lines mark; null in a
  /// list with no row.
  final ExportCelsBoardRow? row;

  /// What its files can hold, top to bottom.
  final List<ExportCelsStackLine> lines;

  /// A line's switch, pressed: what the files should do with its row. Null
  /// while an export runs.
  final void Function(Layer layer, bool on)? onSwitched;

  /// The slot that leads every line and marks the base.
  static const double baseSlotWidth = 28;

  @override
  State<ExportCelsStack> createState() => _ExportCelsStackState();
}

class _ExportCelsStackState extends State<ExportCelsStack> {
  final ScrollController _down = ScrollController();

  @override
  void dispose() {
    _down.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: Theme.of(context).dividerColor);
    return Column(
      key: const ValueKey<String>('export-cels-stack'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: ExportCelsBoard.bandHeight,
          decoration: BoxDecoration(border: Border(bottom: line)),
          child: _head(context),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: AppScrollbarLane.wide,
                child: AppControllerScrollbar(
                  controller: _down,
                  axis: Axis.vertical,
                  laneKey: const ValueKey<String>(
                    'export-cels-stack-vertical-lane',
                  ),
                  thumbKey: const ValueKey<String>(
                    'export-cels-stack-vertical-thumb',
                  ),
                ),
              ),
              Expanded(
                child: ScrollConfiguration(
                  // The lane IS the bar: the app's own scroll behaviour
                  // would lay a second one over the lines.
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    controller: _down,
                    child: Column(
                      children: [
                        for (final each in widget.lines) _line(context, each),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// What the column is: the layers the files put out.
  ///
  /// 🗣️F-395 (유저 2026-10-18): 「상단에 BG라는 이름써있는곳? 선택된 레이어
  /// 써있는거 없애고, 해당영역 출력할 레이어 이렇게 텍스트 써두기」. ↩️It
  /// headed the column with the row stood on — its label and name.
  Widget _head(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        AppText.strings.exCelsLayersOut,
        key: const ValueKey<String>('export-cels-stack-head'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: layerRowNameStyle(
          context,
        ).copyWith(fontWeight: FontWeight.bold),
      ),
    ),
  );

  /// One row of the stack: the app's labelled boolean — the whole line
  /// presses, the ring on its right (`SettingsSwitchRow`, 유저 2026-09-24:
  /// 「설정 줄 하나로」) — led as the timeline leads the row: its colour
  /// label, its take and its kind; and before them a slot of its own that
  /// marks the base, the base on the wash of the row stood on.
  ///
  /// 🗣️F-395 (유저 2026-10-18): 「밑에 영역엔 기준 BG 이런식말고 타임라인이랑
  /// 똑같이 미술색라벨, 테이크, 아이콘, 이름 이렇게. 해당 영역 전부. 그리고 그
  /// 왼쪽에 공간만들어서 규칙에 의해 기준으로 정해진 레이어에 기준이라고
  /// 표시」. ↩️A line was led by the base's word or an attach row's arrow.
  Widget _line(BuildContext context, ExportCelsStackLine line) {
    final (:layer, :on) = line;
    final scheme = Theme.of(context).colorScheme;
    final row = widget.row;
    final isBase = row is ExportCelsLayerRow && layer.id == row.base;
    final onSwitched = widget.onSwitched;
    final idValue = layer.id.value;
    return Container(
      key: ValueKey<String>('export-cels-stack-line-$idValue'),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: isBase ? railSelectedRowColor(scheme) : null,
      child: SettingsSwitchRow(
        tileKey: ValueKey<String>('export-cels-stack-switch-$idValue'),
        label: layer.name,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The base's slot stands on every line, the word on the base's
            // alone.
            SizedBox(
              width: ExportCelsStack.baseSlotWidth,
              child: isBase
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppText.strings.exSelBase,
                        key: ValueKey<String>(
                          'export-cels-stack-base-$idValue',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : null,
            ),
            SizedBox(
              height: 24,
              child: LayerMarkPlates(mark: layer.mark),
            ),
            LayerTypeButton(
              keyPrefix: 'export-cels-stack',
              idValue: idValue,
              kind: layer.kind,
            ),
          ],
        ),
        value: on,
        onChanged: onSwitched == null
            ? null
            : (bool next) => onSwitched(layer, next),
      ),
    );
  }
}
