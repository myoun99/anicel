import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/timeline_row_address.dart';
import '../widgets/tick_layer.dart';
import 'timeline_cell_style.dart'
    show
        timelineRangeSelectionBandDecorationAt,
        timelineRowSelectionBandDecoration;
import 'axis_turn.dart';
import 'timeline_row_edges.dart';

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
///
/// A band ends where its last row does: the room an open graph stands past
/// its lanes is no row, so a band does not reach into it — but a selection
/// that carries on past it is still one, so a band crosses it (I-89 ③).
///
/// 🚨A SPAN GROWS PER POINTER MOVE, SO THE BANDS HEAR IT — ON A TICK
/// ([TickLayer]). 🔬11-06 (S5_BA 컷352, 디버그 · 프로파일): the timeline's
/// host heard the selection and built its whole panel at every step of a
/// rail sweep — the grid, both viewports, the header and the scrollbars
/// painted again, and the bottom dock drawn live instead of from its image
/// (`StillRaster`) on 238 of 248 frames, 8ms of raster a frame against the
/// cells' 1.5 (whose band is the cursor layer's, on a tick). One law for
/// both bands, and for every rail that draws these: the layer rail, the
/// x-sheet's header strip and the storyboard's rail.
class TimelineRowSelectionBands extends StatelessWidget {
  const TimelineRowSelectionBands({
    super.key,
    required this.selection,
    required this.rows,
    required this.edges,
    this.firstRow = 0,
    required this.crossExtent,
    this.axis = Axis.horizontal,
  });

  /// The row selection — heard here, so a span growing under the pointer
  /// lays and paints the bands alone.
  final ValueListenable<List<TimelineRowAddress>> selection;

  /// What each DRAWN row from [firstRow] is, in draw order: its address, or
  /// null for a row no selection holds. The rail knows what its rows are;
  /// this widget asks no more of a row than whether the selection holds it.
  final List<TimelineRowAddress?> rows;

  /// Where the rail's rows sit along it ([TimelineRowEdges]) — the grids'
  /// rows and the storyboard's alike (F-322: its rows are not all one
  /// height). ↩️It took one pitch, or a list of extents it summed itself.
  final TimelineRowEdges edges;

  /// The row [rows] begins at — a windowed rail's first built row.
  final int firstRow;

  /// The band's extent ACROSS the rail. The HOST states where the band
  /// region begins and how wide it is — since A2 (2026-08-17) the timeline
  /// passes the layer-controls area only, excluding the section zone.
  final double crossExtent;

  /// Which way the rail runs.
  final Axis axis;

  @override
  Widget build(BuildContext context) => TickLayer(
    child: ValueListenableBuilder<List<TimelineRowAddress>>(
      valueListenable: selection,
      builder: (context, selected, _) => _bands(selected.toSet()),
    ),
  );

  Widget _bands(Set<TimelineRowAddress> held) {
    final bands = <Widget>[];
    var runStart = -1;
    for (var index = 0; index <= rows.length; index += 1) {
      final selected = index < rows.length && held.contains(rows[index]);
      if (selected) {
        if (runStart < 0) {
          runStart = index;
        }
        continue;
      }
      if (runStart < 0) {
        continue;
      }
      final offset = edges.startOf(firstRow + runStart);
      bands.add(
        placedAlong(
          axis,
          along: 0,
          across: offset,
          alongExtent: crossExtent,
          acrossExtent: edges.endOf(firstRow + index - 1) - offset,
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
    key: ValueKey<String>(
      'timeline-row-selection-band-${firstRow + runStart}',
    ),
    // F-26: a row's corners are square, so its band's are.
    decoration: timelineRowSelectionBandDecoration,
  );
}
