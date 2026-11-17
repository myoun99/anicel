import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/media_asset.dart';
import '../input/pen_friendly_scroll_controller.dart';
import '../input/scroller_press_hold.dart';
import '../panels/panel_scrollbar.dart';
import '../text/text_measure.dart';
import '../theme/app_scroll_behavior.dart' show UnbarredScrollable;
import '../theme/app_theme.dart';
import '../timeline/timeline_grid_metrics.dart' show timelineLayerRowHeightIn;
import '../widgets/ellipsis_text.dart';

/// One column of the pool's list right of its names: what its head says and
/// what each file's line says under it.
final class MediaPoolColumn {
  const MediaPoolColumn({
    required this.id,
    required this.label,
    required this.wordOf,
    this.iconOf,
    this.keepsRoomFor = const [],
    this.numeric = false,
  });

  /// What the keys are built from — the same in every language, which the
  /// [label] is not.
  final String id;
  final String label;

  /// What a file's line says here — a dash where the question means nothing
  /// for that file, or its answer is not read yet.
  final String Function(MediaAsset asset) wordOf;

  /// The picture before the word, for a column that shows one (the kind of
  /// layer a preset makes).
  final IconData Function(MediaAsset asset)? iconOf;

  /// Words the column keeps room for although no line may say them yet —
  /// one of each shape an answer read later takes. ⛔Not the widest that has
  /// come in: a column that widened as its answers came would shove every
  /// column past it while the person reads (「없다가 생기는 UI 금지」 — the
  /// import table's resolution column keeps its room the same way).
  final List<String> keepsRoomFor;

  /// A count, a size or a length — set at the column's end, so its digits
  /// stand in line.
  final bool numeric;
}

/// The media pool as a list: a line a file, as a layer is a line on the rail
/// (🗣️asset-placement-presets Q4, 유저 2026-11-17: 「리스트뷰는 레이어처럼
/// 한줄로 컴팩트하게」 · 「이름칸은 고정되고 그 오른쪽 상세들은 가로스크롤되는
/// 프리미어방식」).
///
/// ONE SURFACE SCROLLED TWO WAYS, as `OverflowScrollers` is: the lines scroll
/// down under the head, and the whole sideways — with the names pinned at
/// the view's left edge ([_PinnedLeft]), so what scrolls out from under them
/// is the columns alone.
class MediaPoolList extends StatefulWidget {
  const MediaPoolList({
    super.key,
    required this.assets,
    required this.columns,
    required this.nameLabel,
    required this.nameOf,
    required this.lineOf,
  });

  final List<MediaAsset> assets;
  final List<MediaPoolColumn> columns;

  /// The head over the names.
  final String nameLabel;

  /// The pinned part of a file's line: what it is, what it is called, and
  /// what can be done to it.
  final Widget Function(BuildContext context, MediaAsset asset) nameOf;

  /// [line] as the pool hands it out — the drag that places the file.
  final Widget Function(MediaAsset asset, Widget line) lineOf;

  /// How wide the names stand — all of the view where it is narrower.
  static const double nameWidth = 200;

  /// The head's height, over the names and the columns alike.
  static const double headHeight = 24;

  @override
  State<MediaPoolList> createState() => _MediaPoolListState();
}

class _MediaPoolListState extends State<MediaPoolList> {
  final ScrollController _across = PenFriendlyScrollController();
  final ScrollController _down = PenFriendlyScrollController();

  @override
  void initState() {
    super.initState();
    // One surface scrolled two ways, not a scroller inside a scroller.
    scrollTogether(_across, _down);
  }

  @override
  void dispose() {
    _across.dispose();
    _down.dispose();
    super.dispose();
  }

  static const double _cellPadding = 8;
  static const double _iconSize = 14;
  static const double _iconGap = 4;
  static const TextStyle _cellLine = TextStyle(
    fontSize: 11,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const TextStyle _headLine = TextStyle(fontSize: 10.5);

  /// Each column's width: the widest of its head, the words it keeps room
  /// for and what its lines say, measured in the language shown.
  List<double> _widths(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final cells = TextMeasure(context, style.merge(_cellLine));
    final heads = TextMeasure(context, style.merge(_headLine));
    return [
      for (final column in widget.columns)
        math.max(
              heads.widest([column.label]),
              cells.widest([
                    ...column.keepsRoomFor,
                    for (final asset in widget.assets) column.wordOf(asset),
                  ]) +
                  (column.iconOf == null ? 0 : _iconSize + _iconGap),
            ).ceilToDouble() +
            2 * _cellPadding,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final widths = _widths(context);
    final lineHeight = timelineLayerRowHeightIn(context);
    final columnsWidth = widths.fold(0.0, (sum, width) => sum + width);
    return LayoutBuilder(
      builder: (context, room) {
        final nameWidth = math.min(MediaPoolList.nameWidth, room.maxWidth);
        return PanelScrollbar(
          controller: _down,
          axis: Axis.vertical,
          child: SingleChildScrollView(
            controller: _across,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(room.maxWidth, nameWidth + columnsWidth),
              height: room.maxHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: MediaPoolList.headHeight,
                    child: _line(
                      nameWidth,
                      widths,
                      name: _head(widget.nameLabel),
                      cells: [
                        for (final column in widget.columns)
                          _head(column.label, end: column.numeric),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    // This scroll's bar stands at the view's edge (above),
                    // not at the columns' end, which is off-screen as often
                    // as not.
                    child: UnbarredScrollable(
                      child: ListView.builder(
                        controller: _down,
                        padding: EdgeInsets.zero,
                        itemExtent: lineHeight,
                        itemCount: widget.assets.length,
                        itemBuilder: (context, index) {
                          final asset = widget.assets[index];
                          return widget.lineOf(
                            asset,
                            _line(
                              nameWidth,
                              widths,
                              name: widget.nameOf(context, asset),
                              cells: [
                                for (final column in widget.columns)
                                  _cell(column, asset),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// One line — the head and every file's alike, so a head stands over
  /// exactly the cells it names. The name goes last, so it is drawn over the
  /// columns scrolled under it.
  Widget _line(
    double nameWidth,
    List<double> widths, {
    required Widget name,
    required List<Widget> cells,
  }) => Stack(
    children: [
      Positioned(
        left: nameWidth,
        top: 0,
        bottom: 0,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < cells.length; index += 1)
              SizedBox(width: widths[index], child: cells[index]),
          ],
        ),
      ),
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: nameWidth,
        child: _PinnedLeft(across: _across, child: name),
      ),
    ],
  );

  Widget _head(String label, {bool end = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
    child: Align(
      alignment: end ? Alignment.centerRight : Alignment.centerLeft,
      child: EllipsisText(
        label,
        maxLines: 1,
        style: _headLine.copyWith(color: AppColors.textDim),
      ),
    ),
  );

  Widget _cell(MediaPoolColumn column, MediaAsset asset) {
    final word = EllipsisText(
      column.wordOf(asset),
      key: ValueKey<String>('media-pool-cell-${column.id}-${asset.path}'),
      maxLines: 1,
      style: _cellLine.copyWith(color: AppColors.textDim),
    );
    final icon = column.iconOf?.call(asset);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _cellPadding),
      child: Align(
        alignment: column.numeric
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: icon == null
            ? word
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: _iconSize, color: AppColors.textDim),
                  const SizedBox(width: _iconGap),
                  Flexible(child: word),
                ],
              ),
      ),
    );
  }
}

/// [child] held at the view's left edge while the line under it scrolls
/// sideways — drawn over what scrolls under it, and pressed where it is
/// drawn.
class _PinnedLeft extends StatelessWidget {
  const _PinnedLeft({required this.across, required this.child});

  final ScrollController across;
  final Widget child;

  double get _offset =>
      across.hasClients && across.positions.length == 1 ? across.offset : 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: across,
      builder: (context, pinned) =>
          Transform.translate(offset: Offset(_offset, 0), child: pinned),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(right: BorderSide(color: AppColors.hairline)),
        ),
        child: child,
      ),
    );
  }
}
