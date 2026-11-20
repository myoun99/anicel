import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/media_asset.dart';
import '../input/pen_friendly_scroll_controller.dart';
import '../input/scroller_press_hold.dart';
import '../layout/device_grid_scroll_controller.dart' show singleScrollPixelsOf;
import '../layout/render_shifted_child.dart';
import '../text/text_measure.dart';
import '../theme/app_theme.dart';
import '../timeline/timeline_grid_metrics.dart' show timelineLayerRowHeightIn;
import '../widgets/content_scrollbar.dart';
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
/// ONE SURFACE SCROLLED TWO WAYS, as `OverflowScrollers` is: the lines
/// scroll down under the head, and the columns sideways under a view that
/// stays — the names in it pinned, so what scrolls out from under them is
/// the columns alone.
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
    final columnsWidth = widths.fold(0.0, (sum, width) => sum + width);
    return LayoutBuilder(
      builder: (context, room) {
        // The lines stand left of their bar's lane ([_window]) — and so
        // does the sideways scroll's end: the last column, scrolled to,
        // ends where the lane begins. ↩️The lane came out of the lines and
        // not out of the scroll (H62, d631c9def), so the last column's last
        // lane-width stayed under it for good (검증 2026-11-20: 「크기 칸
        // 숫자가 레인 앞에서 잘려 보인다(「3」 · 「220」)」).
        final lane = ContentScrollbar.laneIn(context);
        final nameWidth = math.min(
          MediaPoolList.nameWidth,
          math.max(0.0, room.maxWidth - lane),
        );
        // 🚨THE COLUMNS SCROLL, THE VIEW DOES NOT: a window as wide as the
        // view rides the sideways scroll ([_RidesTheScroll]), and only the
        // columns in it move. So the lines' own scroll is as wide as the
        // view, and its bar stands at the view's edge, not at the columns'
        // end; and a line is pressed where it is drawn. ↩️The whole surface
        // scrolled sideways under a name translated back: the list's bar
        // went off-screen with the columns, and was hand-placed at the edge
        // to stay.
        return SingleChildScrollView(
          controller: _across,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(room.maxWidth, nameWidth + columnsWidth + lane),
            height: room.maxHeight,
            child: _RidesTheScroll(
              controller: _across,
              along: 1,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: room.maxWidth,
                  height: room.maxHeight,
                  child: _window(context, nameWidth, widths),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// What the view shows: the heads, and every file's line under them, its
  /// bar in a lane of its own beside the lines — always there, as every
  /// panel's content's is ([ContentScrollbar]); the heads stop where the
  /// lines do, so a head stands over the cells it names.
  ///
  /// 🗣️H62 (유저 2026-11-18): 「미디어풀 스크롤바같은게 안뜨는데 … 계속
  /// 떠있도록. 스크롤바가 필요한 상황인데도 안뜨고있음」. ↩️Its bar was the
  /// scroll behaviour's, which lays none down a vertical list on a tablet
  /// and only while it overflows on a desktop.
  Widget _window(BuildContext context, double nameWidth, List<double> widths) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: MediaPoolList.headHeight,
            child: Padding(
              padding: EdgeInsets.only(right: ContentScrollbar.laneIn(context)),
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
          ),
          const Divider(height: 1),
          Expanded(
            child: ContentScrollbar(
              controller: _down,
              builder: (context, controller) => ListView.builder(
                controller: controller,
                padding: EdgeInsets.zero,
                itemExtent: timelineLayerRowHeightIn(context),
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
      );

  /// One line — the head and every file's alike, so a head stands over
  /// exactly the cells it names: the name where it is, the columns right of
  /// it moved by the sideways scroll.
  Widget _line(
    double nameWidth,
    List<double> widths, {
    required Widget name,
    required List<Widget> cells,
  }) => Row(
    children: [
      SizedBox(
        width: nameWidth,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(right: BorderSide(color: AppColors.hairline)),
          ),
          child: name,
        ),
      ),
      Expanded(
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: _RidesTheScroll(
              controller: _across,
              along: -1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < cells.length; index += 1)
                    SizedBox(width: widths[index], child: cells[index]),
                ],
              ),
            ),
          ),
        ),
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

/// [child] moved along the list's sideways scroll as [controller] stands
/// when it is PAINTED and pressed — [along] 1 with the scroll, the view
/// that stays; −1 against it, the columns under that view.
///
/// 🚨READ AFTER THE PULL (card a-widened-pool-list-leaves-its-window-behind,
/// 저장 2026-11-20): a single-child viewport lays its content out first and
/// pulls its position into the new range after, telling no listener
/// (`ScrollWindowSettle` says the same of the dock's column). Read at the
/// build, the view stood where the position had been: scrolled to its end
/// at 190 px and widened to 260, the position came back from 957 to 905 and
/// the names, the lines and the bar's lane stood 52 px to the right — the
/// lane off the panel. Read where it is painted, it is read after the pull,
/// in the same frame.
///
/// A push is a PAINT offset, as a rail window's is (`LayerRailWindow`): a
/// scroll repaints what rides it and builds and lays out nothing. ↩️The
/// whole window was built again at every step of a sideways scroll.
class _RidesTheScroll extends SingleChildRenderObjectWidget {
  const _RidesTheScroll({
    required this.controller,
    required this.along,
    required Widget super.child,
  });

  final ScrollController controller;
  final double along;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRidesTheScroll(controller, along);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderRidesTheScroll).configure(controller, along);
}

class _RenderRidesTheScroll extends RenderProxyBox
    with RenderShiftedChildHitTest {
  _RenderRidesTheScroll(this._controller, this._along);

  ScrollController _controller;
  double _along;

  void configure(ScrollController controller, double along) {
    if (identical(controller, _controller) && along == _along) {
      return;
    }
    if (attached) {
      _controller.removeListener(_scrolled);
      controller.addListener(_scrolled);
    }
    _controller = controller;
    _along = along;
    _scrolled();
  }

  void _scrolled() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_scrolled);
  }

  @override
  void detach() {
    _controller.removeListener(_scrolled);
    super.detach();
  }

  @override
  Offset get childPaintOffset =>
      Offset(_along * (singleScrollPixelsOf(_controller) ?? 0), 0);

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) {
      context.paintChild(child, offset + childPaintOffset);
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = childPaintOffset;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }
}
