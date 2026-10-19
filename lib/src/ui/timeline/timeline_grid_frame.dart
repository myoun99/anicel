import 'package:flutter/widgets.dart';

import 'layer_rail_window.dart'
    show LayerRailSplitter, TimelineSecondsToggleCorner;

// THE GRID'S FRAME, said once for the panels that lay a grid in it — the
// timeline's and the conte panel's:
//
//   [legend      | splitter | ruler          | corner        ]
//   [rail        | splitter | frames         | layer-axis bar]
//   [rail's bar  | splitter | frame-axis bar |               ]
//
// and the grip floating over the splitter's column.
//
// 🚨F-409 (유저 2026-10-19): 「우선 세로 스크롤바를 프레임 영역. 즉 제일
// 오른쪽으로 이동. 초+코마 버튼 위치도 그에맞춰서 이동. 타임라인/콘티패널
// 동일함. 법 통일」. ↩️Each panel wrote the three rows out by hand, with
// the layer-axis bar on the LEFT edge — where the splitter, taking the gap
// between the rail and the cells, had pushed it — and the corner over it.
// The export board's cels list draws this frame a third time
// (`export_cels_board.dart`), in the export lane's hands.

/// The frame's top row: the legend in the rail's window, the splitter's
/// column, the ruler, and the corner over the layer-axis bar — the
/// frames↔seconds toggle.
class TimelineGridHeaderRow extends StatelessWidget {
  const TimelineGridHeaderRow({
    super.key,
    required this.legend,
    required this.ruler,
    required this.barWidth,
    required this.height,
    required this.showSeconds,
    required this.onShowSecondsChanged,
    this.cornerKey = const ValueKey<String>(
      'timeline-time-display-toggle-button',
    ),
  });

  final Widget legend;
  final Widget ruler;
  final double barWidth;
  final double height;
  final bool showSeconds;
  final ValueChanged<bool>? onShowSecondsChanged;
  final Key cornerKey;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      legend,
      const SizedBox(width: LayerRailSplitter.thickness),
      Expanded(child: ruler),
      TimelineSecondsToggleCorner(
        key: cornerKey,
        width: barWidth,
        height: height,
        showSeconds: showSeconds,
        onChanged: onShowSecondsChanged,
      ),
    ],
  );
}

/// The frame's middle row: the scroll body (the rail, the splitter's
/// column and the frames, in one vertical scroll), and the layer-axis bar
/// at the far right.
class TimelineGridBodyRow extends StatelessWidget {
  const TimelineGridBodyRow({
    super.key,
    required this.body,
    required this.bar,
    required this.barWidth,
  });

  final Widget body;
  final Widget bar;
  final double barWidth;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: body),
      SizedBox(width: barWidth, child: bar),
    ],
  );
}

/// The frame's bottom row: the rail's own bar, the splitter's column, the
/// frame-axis bar, and the room under the layer-axis bar.
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
      Expanded(child: frameBar),
      SizedBox(
        key: ValueKey<String>('$keyPrefix-vertical-scrollbar-bottom-spacer'),
        width: barWidth,
        height: height,
      ),
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
