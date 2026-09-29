import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/exposure_instruction.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cells_row.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// 🗣️F-228 (유저 2026-09-29): 「디렉션레이어나 트랜지션레이어만 코마텍스트가
/// 없는데, 블록이라면 전부 코마텍스트가 존재해야함. 통일해서 적용」.
void main() {
  TimelineCellExposureState stateFor(Layer layer, int frameIndex) =>
      TimelineCellExposureState.uncovered;

  Future<TimelineRowRunLabelsPainter?> mount(
    WidgetTester tester,
    Layer layer,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Material(
            child: TimelineFrameCellsRow(
              layer: layer,
              playbackFrameCount: 12,
              geometry: testFrameGeometry(
                frameCellExtent: 48,
                frameEndIndexExclusive: 12,
              ),
              crossAxisExtent: 52,
              exposureStateForLayer: stateFor,
              onSelectLayer: (_) {},
              onSelectFrame: (_) {},
            ),
          ),
        ),
      ),
    );
    return tester
            .widget<CustomPaint>(
              find.byKey(ValueKey<String>('timeline-row-cells-${layer.id}')),
            )
            .foregroundPainter
        as TimelineRowRunLabelsPainter?;
  }

  List<(int, String)> labelsOf(TimelineRowRunLabelsPainter? painter) => [
    for (final label in painter!.runLabels()) (label.startIndex, label.text),
  ];

  testWidgets('🚨a DIRECTION block prints its length', (tester) async {
    final painter = await mount(
      tester,
      Layer(
        id: const LayerId('d-1'),
        name: 'D',
        kind: LayerKind.instruction,
        frames: const [],
        timeline: {
          0: const TimelineExposure.drawing(
            FrameId('d-f1'),
            length: 3,
            instruction: ExposureInstruction(instructionId: 'pan'),
          ),
          5: const TimelineExposure.drawing(FrameId('d-f2'), length: 4),
        },
      ),
    );

    expect(labelsOf(painter), [(0, '3'), (5, '4')]);
  });

  testWidgets('🚨a TRANSITION span prints its length', (tester) async {
    final painter = await mount(
      tester,
      Layer(
        id: const LayerId('t-1'),
        name: 'T',
        kind: LayerKind.transition,
        frames: const [],
        instructions: {
          2: const InstructionEvent(instructionId: 'ol', length: 4),
        },
      ),
    );

    expect(labelsOf(painter), [(2, '4')]);
  });

  testWidgets('the camera row keeps keys, not blocks — no lengths', (
    tester,
  ) async {
    final painter = await mount(
      tester,
      Layer(
        id: const LayerId('c-1'),
        name: 'C',
        kind: LayerKind.camera,
        frames: const [],
      ),
    );

    expect(painter, isNull);
  });

  test('every kind whose content is blocks has them — and only those', () {
    for (final kind in LayerKind.values) {
      expect(
        kind.hasBlocks,
        kind.holdsDrawings || kind.carriesInstructions,
        reason: kind.name,
      );
    }
    expect(LayerKind.instruction.hasBlocks, isTrue);
    expect(LayerKind.transition.hasBlocks, isTrue);
    expect(LayerKind.camera.hasBlocks, isFalse);
  });
}
