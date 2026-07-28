import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/ui/brush/brush_canvas_defaults.dart';

void main() {
  test('Project defaults to the Brush T2 camera size', () {
    final project = Project(
      id: const ProjectId('project'),
      name: 'Project',
      tracks: const [],
      createdAt: DateTime.utc(2026),
    );

    expect(project.cameraSize, defaultProjectCameraSize);
  });

  test(
    'default Cut and production brush canvas use the Brush T2 canvas size',
    () {
      final cut = createDefaultCut(
        cutId: const CutId('cut'),
        name: 'Cut',
        layerId: const LayerId('layer'),
      );

      expect(cut.canvasSize, defaultCutCanvasSize);
      expect(BrushCanvasDefaults.canvasSize, defaultCutCanvasSize);
    },
  );
}
