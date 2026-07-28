import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_timeline_grid.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/xsheet_timeline_grid.dart';

import 'timeline_cell_probe.dart';

/// R5-⑤ geometry pin: the instruction endpoints (A/B) sit DEAD CENTER in
/// their cells — both axes — and the instruction name sits on the span's
/// true center, exactly like the printed sheet.
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

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      TimesheetStubState.uncovered;

  /// The cells are PAINTED now (R28 #4), so the target comes from the row
  /// painter's geometry rather than from a cell widget's box.
  void expectCentered(WidgetTester tester, Finder text, Offset cellCenter) {
    final textCenter = tester.getCenter(text);
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
            layers: [camLayer],
            activeLayerId: null,
            frameCursor: cursor,
            playbackFrameCount: 24,
            exposureStateForLayer: stateFor,
            instructionDefById: CameraInstructionSet.standard.defById,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
          ),
        ),
      ),
    );

    expectCentered(
      tester,
      find.text('ㄱ'),
      timelineCellCenter(tester, 'cam-1', 2),
    );
    expectCentered(
      tester,
      find.text('ㄴ'),
      timelineCellCenter(tester, 'cam-1', 6),
    );
    // Span covers cells 2..6 — its center is cell 4's center.
    expectCentered(
      tester,
      find.text('PAN'),
      timelineCellCenter(tester, 'cam-1', 4),
    );
  });

  testWidgets('X-sheet: the same dead-center rule (Axis policy)', (
    tester,
  ) async {
    final cursor = ValueNotifier<int>(0);
    addTearDown(cursor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XSheetTimelineGrid(
            layers: [camLayer],
            activeLayerId: null,
            frameCursor: cursor,
            frameCount: 24,
            exposureStateForLayer: stateFor,
            instructionDefById: CameraInstructionSet.standard.defById,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onAddLayer: () {},
            onToggleLayerVisibility: (_) {},
            onLayerOpacityChanged: (_, _) {},
            onToggleLayerTimesheet: (_) {},
            onLayerMarkSelected: (_, _) {},
          ),
        ),
      ),
    );

    expectCentered(
      tester,
      find.text('ㄱ'),
      timelineCellCenter(tester, 'cam-1', 2, prefix: 'xsheet'),
    );
    expectCentered(
      tester,
      find.text('ㄴ'),
      timelineCellCenter(tester, 'cam-1', 6, prefix: 'xsheet'),
    );
    // R6-①c: the name reads HORIZONTALLY on the X-sheet too (glyph stack
    // retired) — one Text, dead center on the span like the timeline.
    expectCentered(
      tester,
      find.text('PAN'),
      timelineCellCenter(tester, 'cam-1', 4, prefix: 'xsheet'),
    );
  });
}

/// Alias keeping the stub readable (instruction rows derive their own
/// exposure states internally — the passed resolver is never consulted).
typedef TimesheetStubState = TimelineCellExposureState;
