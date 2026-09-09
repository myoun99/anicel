import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/export_spec.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/export/export_cel_group_plan.dart';

void main() {
  test('the cel plan carries the chosen extension, de-dup included (EX4)',
      () {
    // Cels carry their number as the frame name — an unnamed frame is the
    // in-between mark and exports nothing, so the fixture names every cel.
    Frame frame(String id, String number) =>
        Frame(id: FrameId(id), duration: 1, strokes: const [], name: number);
    final project = Project(
      id: const ProjectId('project'),
      name: 'Project',
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: const CutId('cut'),
              name: 'Cut',
              duration: 2,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                Layer(
                  id: const LayerId('a'),
                  name: 'A',
                  frames: [frame('f1', '1'), frame('f2', '2')],
                ),
                Layer(
                  id: const LayerId('b'),
                  name: 'A',
                  frames: [frame('f3', '1')],
                ),
                createCameraLayer(cutId: const CutId('cut')),
              ],
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    );

    final plan = buildExportCelGroupPlan(
      project: project,
      activeCutId: const CutId('cut'),
      spec: const CelsExportSpec(),
      fileExtension: 'jpg',
    );
    expect(plan.cels.map((task) => task.fileName), [
      'A1.jpg',
      'A2.jpg',
      // The second layer 'A' collides on cel 1 — the bump keeps the ext.
      'A1_2.jpg',
    ]);
  });
}
