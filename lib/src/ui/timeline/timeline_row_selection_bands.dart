import 'package:flutter/material.dart';

import 'timeline_cell_style.dart'
    show
        timelineRangeSelectionBandDecorationAt,
        timelineRowSelectionBandDecoration;
import 'axis_turn.dart';

/// 🚨T1 — THE ROW SELECTION, as ONE band over the run it covers.
///
/// ★유저 08-12: 「레이어의 선택범위가 액티브레이어랑 생긴게 똑같아서 이상함.
/// 프레임셀처럼 외곽선으로 감싸자」 — the wash says where you are STANDING,
/// the band's edge says what is SELECTED, and the active row inside a
/// selection wears both.
///
/// 유저 2026-08-13: 「레이어 선택, 여러개 선택시 **외곽선이 레이어 하나마다
/// 들어오는데, 그게아니라 프레임셀 처럼 연결된 레이어들 선택하면 한 외곽선,
/// 바탕**이 되도록. 그리고 지금 **외곽선이 왼쪽 섹션부분의 선이 없음**」.
///
/// ⛔Each selected row used to wrap itself in a ring of its own, so
/// four selected rows drew four boxes with three seams down the middle of
/// what is one selection. And the box it drew was the row's INNER container —
/// `layerControlsWidth − sectionLabelGutterWidth` — which is why the left
/// edge had no line: the section band lives in that gutter, outside the box.
///
/// ★So this is the frame side's own arrangement, transposed: the cells do not
/// each outline themselves either — the cursor overlay lays one band across
/// the run ([timelineRangeSelectionBandDecorationAt], the same fill and the
/// same edge). A selection is one thing and gets one shape.
///
/// Contiguous runs are drawn separately: a selection can be broken by a row
/// that is not in it (a collapsed group, a filtered row), and two runs with a
/// gap between them are two shapes, not one tall one.
///
/// ⚠️A2 (유저 2026-08-17) reversed T1's full-width call: 「선택범위
/// 외곽선+바탕색이 왼쪽 섹션란까지 침범. 레이어 영역만 칠하도록」. The band
/// now covers the LAYER area only — the host mounts it inset past the
/// section zone ([layerSectionLabelSlotWidth]) and passes the reduced
/// [crossExtent]. T1's own complaint about the missing left line is
/// satisfied by the band's border sitting at the layer area's left edge,
/// not by invading the sections' plate.
class TimelineRowSelectionBands extends StatelessWidget {
  const TimelineRowSelectionBands({
    super.key,
    required this.selectedFlags,
    required this.rowExtent,
    required this.leadingSpacer,
    required this.crossExtent,
    this.axis = Axis.horizontal,
  });

  /// One flag per DRAWN row, in draw order — the rail already knows which of
  /// its rows are in the selection, and asking it here keeps this widget from
  /// needing to know what a row IS.
  final List<bool> selectedFlags;

  /// A row's extent along the rail (height in the timeline, width in the
  /// X-sheet).
  final double rowExtent;

  /// What sits before the first drawn row — the virtualization spacer.
  final double leadingSpacer;

  /// The band's extent ACROSS the rail. The HOST states where the band
  /// region begins and how wide it is — since A2 (2026-08-17) the timeline
  /// passes the layer-controls area only, excluding the section zone.
  final double crossExtent;

  /// Which way the rail runs.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final bands = <Widget>[];
    var runStart = -1;
    for (var index = 0; index <= selectedFlags.length; index += 1) {
      final selected = index < selectedFlags.length && selectedFlags[index];
      if (selected) {
        if (runStart < 0) {
          runStart = index;
        }
        continue;
      }
      if (runStart < 0) {
        continue;
      }
      final offset = leadingSpacer + runStart * rowExtent;
      final extent = (index - runStart) * rowExtent;
      bands.add(
        placedAlong(
          axis,
          along: 0,
          across: offset,
          alongExtent: crossExtent,
          acrossExtent: extent,
          child: _band(runStart),
        ),
      );
      runStart = -1;
    }
    if (bands.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(child: Stack(children: bands));
  }

  Widget _band(int runStart) => DecoratedBox(
    key: ValueKey<String>('timeline-row-selection-band-$runStart'),
    // F-26: a row's corners are square, so its band's are.
    decoration: timelineRowSelectionBandDecoration,
  );
}
