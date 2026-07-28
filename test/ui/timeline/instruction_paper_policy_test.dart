import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_instruction_row_visual.dart';

Layer _layer(Map<int, InstructionEvent> instructions) {
  return Layer(
    id: const LayerId('cam-1'),
    name: 'CAM 1',
    kind: LayerKind.instruction,
    frames: const [],
    timeline: const {},
    instructions: instructions,
  );
}

void main() {
  test('instruction events adapt onto the paper-cell exposure states', () {
    final layer = _layer({
      2: const InstructionEvent(instructionId: 'pan', length: 3),
      8: const InstructionEvent(instructionId: 'fo', length: 1),
    });

    expect(
      [for (var f = 0; f < 10; f += 1) instructionCellExposureState(layer, f)],
      const [
        TimelineCellExposureState.uncovered,
        TimelineCellExposureState.uncovered,
        TimelineCellExposureState.drawingStart,
        TimelineCellExposureState.held,
        TimelineCellExposureState.held,
        TimelineCellExposureState.uncovered,
        TimelineCellExposureState.uncovered,
        TimelineCellExposureState.uncovered,
        TimelineCellExposureState.drawingStart,
        TimelineCellExposureState.uncovered,
      ],
    );
    expect(
      instructionCellExposureState(layer, -1),
      TimelineCellExposureState.uncovered,
    );
    expect(
      instructionCellExposureState(_layer(const {}), 0),
      TimelineCellExposureState.uncovered,
    );
  });
}
