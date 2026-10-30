import 'package:flutter/widgets.dart';

import 'frame_ruler_view.dart';
import 'layer_rail_window.dart'
    show LayerRailSplitter, TimelineRulerViewCorner;

// THE GRID'S FRAME, said once for the panels that lay a grid in it — the
// timeline's and the conte panel's:
//
//   [legend      | splitter | corner        | ruler         ]
//   [rail        | splitter | layer-axis bar| frames        ]
//   [rail's bar  | splitter |               | frame-axis bar]
//
// and the grip floating over the splitter's column.
//
// 🚨F-459 (유저 2026-10-23): 「타임라인/콘티패널의 세로 스크롤바, 예전처럼
// 역시 레이어영역이랑 프레임 사이에 두고싶음. 초+코마버튼도 동일. 위치는
// 현재 레이어영역 스플리터의 오른쪽」. ↩️F-409 (유저 2026-10-19) had stood
// the bar and its corner at the frame area's far right 「우선」(c39db2400);
// before that the bar was the grid's LEFT edge, where the splitter, taking
// the gap between the rail and the cells, had pushed it. Each panel wrote
// the three rows out by hand until F-409 said them here once. The export
// board's cels list draws this frame a third time
// (`export_cels_board.dart`), in the export lane's hands.

/// The frame's top row: the legend in the rail's window, the splitter's
/// column, the corner over the layer-axis bar — the ruler's count
/// (I-81) — and the ruler.
class TimelineGridHeaderRow extends StatelessWidget {
  const TimelineGridHeaderRow({
    super.key,
    required this.legend,
    required this.ruler,
    required this.barWidth,
    required this.height,
    required this.rulerView,
    required this.onRulerViewChanged,
    this.cornerKey = const ValueKey<String>(
      'timeline-time-display-toggle-button',
    ),
  });

  final Widget legend;
  final Widget ruler;
  final double barWidth;
  final double height;
  final FrameRulerView rulerView;
  final ValueChanged<FrameRulerView>? onRulerViewChanged;
  final Key cornerKey;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      legend,
      const SizedBox(width: LayerRailSplitter.thickness),
      TimelineRulerViewCorner(
        key: cornerKey,
        width: barWidth,
        height: height,
        rulerView: rulerView,
        onChanged: onRulerViewChanged,
      ),
      Expanded(child: ruler),
    ],
  );
}

/// The frame's middle row: the scroll body (the rail, the gap after it
/// and the frames, in one vertical scroll — [TimelineGridRailGap] is the
/// body's own), and the layer-axis bar standing still over the gap's
/// second column while the body scrolls under it.
class TimelineGridBodyRow extends StatelessWidget {
  const TimelineGridBodyRow({
    super.key,
    required this.body,
    required this.bar,
    required this.barWidth,
    required this.railWindowExtent,
  });

  final Widget body;
  final Widget bar;
  final double barWidth;

  /// How wide the rail's window is laid — the gap starts at its edge.
  final double railWindowExtent;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: body),
      Positioned(
        left: railWindowExtent + LayerRailSplitter.thickness,
        top: 0,
        bottom: 0,
        width: barWidth,
        child: bar,
      ),
    ],
  );
}

/// The body's gap between the rail and the frames: the splitter's column,
/// then the layer-axis bar's ([TimelineGridBodyRow] stands the bar in it).
class TimelineGridRailGap extends StatelessWidget {
  const TimelineGridRailGap({super.key, required this.barWidth});

  final double barWidth;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: LayerRailSplitter.thickness + barWidth);
}

/// The frame's bottom row: the rail's own bar, the splitter's column, the
/// room under the layer-axis bar, and the frame-axis bar.
class TimelineGridBottomRow extends StatelessWidget {
  const TimelineGridBottomRow({
    super.key,
    required this.keyPrefix,
    required this.railBar,
    required this.frameBar,
    required this.barWidth,
    required this.height,
  });

  final String keyPrefix;
  final Widget railBar;
  final Widget frameBar;
  final double barWidth;
  final double height;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      railBar,
      SizedBox(
        key: ValueKey<String>('$keyPrefix-bottom-scrollbar-splitter-spacer'),
        width: LayerRailSplitter.thickness,
        height: height,
      ),
      SizedBox(
        key: ValueKey<String>('$keyPrefix-vertical-scrollbar-bottom-spacer'),
        width: barWidth,
        height: height,
      ),
      Expanded(child: frameBar),
    ],
  );
}

/// The grip over the splitter's column, which the three rows each reserve
/// right after the rail's window — so one grab spans the legend, the rows
/// and the bar line.
Positioned timelineGridGrip({
  required double railWindowExtent,
  required LayerRailSplitter splitter,
}) => Positioned(
  left: railWindowExtent,
  top: 0,
  bottom: 0,
  width: LayerRailSplitter.thickness,
  child: splitter,
);
