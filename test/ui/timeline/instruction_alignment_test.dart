import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/timeline_block_word.dart'
    show TimelineBlockColumn;
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_instruction_row_visual.dart'
    show instructionLabelInset;
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import 'package:anicel/src/ui/timeline/timeline_grid_hooks.dart';

import '../../helpers/block_word_finder.dart';
import 'timeline_cell_probe.dart';

/// R5-⑤ geometry pin, revised 2026-08-08: the instruction endpoints (A/B)
/// still sit DEAD CENTER in their cells — both axes, and nothing is drawn
/// under them — but the NAME no longer does.
///
/// The mark keeps the cross-axis centre (every bar, wedge and bowtie is
/// drawn about it) and the name steps OFF it: UP on the timeline, RIGHT on
/// the sheet. Centred, the two were printed through each other.
void main() {
  final camLayer = Layer(
    id: const LayerId('cam-1'),
    name: 'CAM 1',
    kind: LayerKind.instruction,
    frames: const [],
    timeline: const {},
    instructions: {
      2: const InstructionEvent(
        instructionId: 'pan',
        length: 5,
        valueA: 'ㄱ',
        valueB: 'ㄴ',
      ),
    },
  );

  final neighbourLayer = Layer(
    id: const LayerId('neighbour'),
    name: 'A',
    frames: const [],
  );

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      TimesheetStubState.uncovered;

  /// The cells are PAINTED now (R28 #4), so the target comes from the row
  /// painter's geometry rather than from a cell widget's box.
  void expectCentered(Offset textCenter, Offset cellCenter) {
    expect(textCenter.dx, closeTo(cellCenter.dx, 1.0));
    expect(textCenter.dy, closeTo(cellCenter.dy, 1.0));
  }

  testWidgets('timeline: A/B center in the endpoint cells, the name on the '
      'span center', (tester) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayerTimelineGrid(
            hooks: TimelineGridHooks(
              activeLayerId: null,
              frameCursor: cursor,
              playbackFrameCount: 24,
              exposureStateForLayer: stateFor,
              instructionDefById: CameraInstructionSet.standard.defById,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
            ),
            layers: [camLayer],
          ),
        ),
      ),
    );

    expectCentered(
      blockWordRect(tester, findBlockText('ㄱ')).center,
      timelineCellCenter(tester, 'cam-1', 2),
    );
    expectCentered(
      blockWordRect(tester, findBlockText('ㄴ')).center,
      timelineCellCenter(tester, 'cam-1', 6),
    );

    // The NAME: on the span's centre along the FRAME axis, and off the
    // mark across it. Span covers cells 2..6, so its centre is cell 4's.
    final span = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-instruction-cam-1-2')),
    );
    final name = blockWordRect(tester, findBlockText('PAN'));
    expect(name.center.dx, closeTo(span.center.dx, 1.0));
    expect(
      name.top,
      closeTo(span.top + instructionLabelInset, 1.0),
      reason: 'the name hangs from the top of the row',
    );
    expect(
      name.center.dy,
      lessThan(span.center.dy),
      reason: 'the duration bar owns the cross-axis centre, not the name',
    );
  });

  testWidgets('X-sheet: the same rule, transposed (Axis policy)', (
    tester,
  ) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XSheetTimelineGrid(
            hooks: TimelineGridHooks(
              activeLayerId: null,
              frameCursor: cursor,
              playbackFrameCount: 24,
              exposureStateForLayer: stateFor,
              instructionDefById: CameraInstructionSet.standard.defById,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
            ),
            layers: [camLayer],
          ),
        ),
      ),
    );

    // On the sheet the writing reads DOWN its column ([findBlockColumn]).
    expectCentered(
      blockWordRect(tester, findBlockColumn('ㄱ')).center,
      timelineCellCenter(tester, 'cam-1', 2, prefix: 'xsheet'),
    );
    expectCentered(
      blockWordRect(tester, findBlockColumn('ㄴ')).center,
      timelineCellCenter(tester, 'cam-1', 6, prefix: 'xsheet'),
    );

    // Transposed: the frame axis runs DOWN, so the name centres on the
    // span vertically and hangs off the column's RIGHT wall.
    final span = tester.getRect(
      find.byKey(const ValueKey<String>('xsheet-instruction-cam-1-2')),
    );
    final name = blockWordRect(tester, findBlockColumn('PAN'));
    expect(name.center.dy, closeTo(span.center.dy, 1.0));
    expect(
      name.right,
      closeTo(span.right - instructionLabelInset, 1.0),
      reason: 'the name hangs off the right wall of the column',
    );
    expect(
      name.left,
      greaterThan(span.center.dx),
      reason: 'it never crosses back over the bar, which owns the centre',
    );
  });

  testWidgets('X-sheet: a long instruction name stays inside its own '
      'column', (tester) async {
    // The 42px bleed: `FOLLOW PAN` drew 112px wide in a 28px column,
    // straight over the neighbouring layer's cells, because three clip
    // opt-outs stacked up over horizontal writing. Written down its own
    // column it cannot reach the neighbour at all.
    final longNamed = Layer(
      id: const LayerId('cam-1'),
      name: 'CAM 1',
      kind: LayerKind.instruction,
      frames: const [],
      timeline: const {},
      instructions: {
        2: const InstructionEvent(instructionId: 'follow-pan', length: 5),
      },
    );
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XSheetTimelineGrid(
            hooks: TimelineGridHooks(
              activeLayerId: null,
              frameCursor: cursor,
              playbackFrameCount: 24,
              exposureStateForLayer: stateFor,
              instructionDefById: CameraInstructionSet.standard.defById,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
              onToggleLayerVisibility: (_) {},
              onLayerOpacityChanged: (_, _) {},
              onToggleLayerTimesheet: (_) {},
              onLayerMarkSelected: (_, _) {},
            ),
            layers: [longNamed, neighbourLayer],
          ),
        ),
      ),
    );

    final name = find.byWidgetPredicate((w) => w is TimelineBlockColumn);
    expect(name, findsWidgets);
    final columnWidth = XSheetTimelineGrid.defaultMetrics.layerRowHeight;
    for (final rect
        in tester
            .widgetList(name)
            .map((w) => blockWordRect(tester, find.byWidget(w)))) {
      expect(
        rect.width,
        lessThanOrEqualTo(columnWidth + 0.01),
        reason: 'instruction writing must stay inside its own column',
      );
    }
  });
}

/// Alias keeping the stub readable (instruction rows derive their own
/// exposure states internally — the passed resolver is never consulted).
typedef TimesheetStubState = TimelineCellExposureState;
