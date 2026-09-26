import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_double_tap.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// R26 #37: the cell editor opens on two taps of the SAME cell only —
/// tapping two different frames of one block is two seeks (the double-tap
/// recognizer's 100px slop used to fuse them into a rename).
void main() {
  const layerId = LayerId('layer');
  const cellExtent = 24.0;
  final layer = Layer(
    id: layerId,
    name: 'A',
    frames: [
      Frame(id: const FrameId('cel'), duration: 6, strokes: const []),
    ],
    timeline: {0: const TimelineExposure.drawing(FrameId('cel'), length: 6)},
  );

  setUp(TimelineCellDoubleTapGate.reset);

  Future<void> pumpRow(
    WidgetTester tester, {
    required List<int> activations,
    required List<int> selections,
    Layer? onLayer,
    double cell = cellExtent,
    int frames = 6,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (context) => timelineRowCellsPaintArea(
                context: context,
                keyPrefix: 'timeline',
                layer: onLayer ?? layer,
                geometry: testFrameGeometry(
                  frameCellExtent: cell,
                  frameEndIndexExclusive: frames,
                ),
                crossAxisExtent: 24,
                axis: Axis.horizontal,
                exposureStateForLayer: (_, _) =>
                    TimelineCellExposureState.held,
                onSelectLayer: (_) {},
                onSelectFrame: selections.add,
                onActivateCell: (_, frameIndex) => activations.add(frameIndex),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset centerOf(int frameIndex) =>
      Offset(frameIndex * cellExtent + cellExtent / 2, 12);

  testWidgets('two taps on DIFFERENT frames of one block never activate the '
      'cell editor', (tester) async {
    final activations = <int>[];
    final selections = <int>[];
    await pumpRow(tester, activations: activations, selections: selections);

    await tester.tapAt(centerOf(0));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(centerOf(1));
    await tester.pump(const Duration(milliseconds: 700));

    expect(activations, isEmpty, reason: 'a seek, not a rename');
    expect(selections, containsAllInOrder(<int>[0, 1]));
  });

  testWidgets('two taps on the SAME frame still activate the cell editor', (
    tester,
  ) async {
    final activations = <int>[];
    final selections = <int>[];
    await pumpRow(tester, activations: activations, selections: selections);

    await tester.tapAt(centerOf(2));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(centerOf(2));
    await tester.pump(const Duration(milliseconds: 700));

    expect(activations, <int>[2]);
  });

  // 🗣️유저 2026-09-26 (zoom-floor-fixed-marks-Q2, 「1px 보다 좁은 칸은 같은
  // 픽셀이면 같은 칸」): at the ten-minute floor a pixel is eight frames, and
  // a hand that moved within one pixel landed on another cell.
  group('narrower than a pixel, a cell is the pixel it falls in', () {
    const eighth = 1 / 8;
    final film = Layer(
      id: layerId,
      name: 'A',
      frames: [
        Frame(id: const FrameId('cel'), duration: 2000, strokes: const []),
      ],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('cel'), length: 2000),
      },
    );

    Future<List<int>> doubleTapAt(
      WidgetTester tester,
      double first,
      double second,
    ) async {
      final activations = <int>[];
      await pumpRow(
        tester,
        activations: activations,
        selections: [],
        onLayer: film,
        cell: eighth,
        frames: 2000,
      );
      await tester.tapAt(Offset(first, 12));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(Offset(second, 12));
      await tester.pump(const Duration(milliseconds: 700));
      return activations;
    }

    testWidgets('two taps in one pixel open the cell that pixel is', (
      tester,
    ) async {
      // 100.1 and 100.8 are frames 800 and 806; the pixel's middle is 804.
      expect(await doubleTapAt(tester, 100.1, 100.8), <int>[804]);
    });

    testWidgets('two taps a pixel apart are two cells', (tester) async {
      expect(await doubleTapAt(tester, 100.8, 101.2), isEmpty);
    });

    test('a pixel a cell and up, the aim is the tap itself', () {
      for (final axis in Axis.values) {
        const tap = Offset(100.3, 40.7);
        expect(
          timelineDoubleTapAim(tap, (
            frameAt: (_) => null,
            axis: axis,
            cellExtent: () => 1.0,
          )),
          tap,
        );
        expect(
          timelineDoubleTapAim(tap, (
            frameAt: (_) => null,
            axis: axis,
            cellExtent: () => eighth,
          )),
          axis == Axis.horizontal
              ? const Offset(100.5, 40.7)
              : const Offset(100.3, 40.5),
          reason: 'only along the frame axis',
        );
      }
    });
  });

  // 🗣️유저 2026-09-11: 「트랜스폼행에서 더블클릭으로 편집창 안열리는것등
  // 이런거 싹 법 하나로 통일」 — a lane band rides this same gate, so a lane is
  // part of WHICH cell a tap hit.
  test("a layer's cell and its lane's cell at one frame are TWO cells", () {
    const layerId = LayerId('a');
    TimelineCellDoubleTapGate.recordTapDown(layerId, 3);
    expect(
      TimelineCellDoubleTapGate.acceptsActivation(
        layerId,
        3,
        laneId: 'position',
      ),
      isFalse,
      reason: 'the cells row, then its lane: two seeks',
    );
    TimelineCellDoubleTapGate.recordTapDown(layerId, 3, laneId: 'position');
    expect(
      TimelineCellDoubleTapGate.acceptsActivation(layerId, 3, laneId: 'scale'),
      isFalse,
      reason: 'two lanes of one layer: two cells',
    );
    TimelineCellDoubleTapGate.recordTapDown(layerId, 3, laneId: 'position');
    expect(
      TimelineCellDoubleTapGate.acceptsActivation(
        layerId,
        3,
        laneId: 'position',
      ),
      isTrue,
    );
  });
}
