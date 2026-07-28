import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';
import 'package:anicel/src/ui/export/export_instruction_render.dart';

void main() {
  ExportInstructionTask task() => ExportInstructionTask(
    cut: Cut(
      id: const CutId('cut'),
      name: 'CUT1',
      duration: 12,
      canvasSize: const CanvasSize(width: 64, height: 48),
      layers: [
        Layer(
          id: const LayerId('inst'),
          name: 'Camera',
          frames: const [],
          kind: LayerKind.instruction,
        ),
      ],
    ),
    layer: Layer(
      id: const LayerId('inst'),
      name: 'Camera',
      frames: const [],
      kind: LayerKind.instruction,
    ),
    startFrame: 0,
    length: 12,
    label: 'PAN',
    fileName: 'Camera1.png',
  );

  testWidgets('renders the writing at the asked size, honest alpha',
      (tester) async {
    await tester.runAsync(() async {
      final transparent = await renderInstructionCelImage(
        task: task(),
        size: const CanvasSize(width: 64, height: 48),
      );
      expect(transparent.width, 64);
      expect(transparent.height, 48);
      final clearData = await transparent.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(clearData!.buffer.asUint8List()[3], 0,
          reason: 'no background = transparent corner');
      transparent.dispose();

      final backed = await renderInstructionCelImage(
        task: task(),
        size: const CanvasSize(width: 64, height: 48),
        background: const ui.Color(0xFFFFFFFF),
      );
      final backedData = await backed.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final bytes = backedData!.buffer.asUint8List();
      expect(bytes[3], 255);
      // The ink is red-ish; SOMETHING non-white must have painted.
      var inked = false;
      for (var i = 0; i < bytes.length; i += 4) {
        if (bytes[i] > 100 && bytes[i + 1] < 120 && bytes[i + 2] < 120) {
          inked = true;
          break;
        }
      }
      expect(inked, isTrue, reason: 'the label/arrow paints in ink');
      backed.dispose();
    });
  });
}
