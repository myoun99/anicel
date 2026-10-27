import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/direction_spans_normalize.dart';
import 'package:anicel/src/models/exposure_instruction.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

/// 🗣️I-72-direction-link — the write-time half: a direction row's drawing
/// is named by what its block says, whatever verb wrote the row, and a name
/// written so means nothing on any other row.
void main() {
  const said = ExposureInstruction(
    instructionId: 'pan',
    valueA: 'A',
    valueB: 'B',
  );
  const pan = CameraInstructionDef(id: 'pan', name: 'PAN', iconKey: 'pan');
  final written = linkNameOfWriting(said, pan)!;

  Cut cutOf(LayerKind kind, {String? name}) => Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 8,
    canvasSize: const CanvasSize(width: 64, height: 36),
    layers: [
      Layer(
        id: const LayerId('row'),
        name: 'row',
        kind: kind,
        frames: [
          Frame(
            id: const FrameId('d'),
            duration: 1,
            strokes: const [],
            name: name,
          ),
        ],
        timeline: {
          2: const TimelineExposure.drawing(
            FrameId('d'),
            length: 2,
            instruction: said,
          ),
        },
      ),
    ],
  );

  Frame drawingOf(Cut cut) => cut.layers.single.frames.single;

  test('a direction row names its drawing by what the block says', () {
    final cut = cutWithSpansOnTheirBlocks(
      cutOf(LayerKind.instruction),
      defById: (id) => id == 'pan' ? pan : null,
    );
    expect(drawingOf(cut).name, written);
  });

  test('…and the name it held before is not the one it keeps', () {
    final cut = cutWithSpansOnTheirBlocks(
      cutOf(LayerKind.instruction, name: 'A1'),
      defById: (id) => id == 'pan' ? pan : null,
    );
    expect(drawingOf(cut).name, written);
  });

  test('a drawing row puts down the span, and the name it wrote', () {
    final cut = cutWithSpansOnTheirBlocks(
      cutOf(LayerKind.animation, name: written),
      defById: (_) => pan,
    );
    expect(cut.layers.single.timeline[2]!.instruction, isNull);
    expect(drawingOf(cut).name, isNull);
  });

  test('…and keeps a name a hand gave', () {
    final cut = cutWithSpansOnTheirBlocks(
      cutOf(LayerKind.animation, name: 'A1'),
      defById: (_) => pan,
    );
    expect(drawingOf(cut).name, 'A1');
  });
}
