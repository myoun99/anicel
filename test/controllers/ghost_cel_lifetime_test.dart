import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/timeline_controller.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';

/// R8-b: a GHOST is not a reference, so it cannot keep a cel alive.
///
/// A ghost is DERIVED — a repeat run recomputes its instances from the
/// authored exposure that owns them. Counting one as a reference means
/// "keep this cel because something that only exists while the cel's own
/// block exists is pointing at it", which comes apart the moment the block
/// goes: the ghosts hold the cel through the delete, then re-derive
/// themselves out of existence and leave it orphaned.
void main() {
  const cutId = CutId('cut');
  const layerId = LayerId('layer');
  const celId = FrameId('cel');

  ProjectRepository repositoryWith(Layer layer) => ProjectRepository(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: cutId,
              name: 'Cut',
              duration: 24,
              canvasSize: const CanvasSize(width: 1920, height: 1080),
              layers: [layer],
            ),
          ],
        ),
      ],
    ),
  );

  /// One authored cel at 0, and an end-hold's ghosts standing at 1 and 2.
  ///
  /// ⚠️Ghosts are written into the fixture rather than derived, because the
  /// claim is about what the CONTROLLER does when it sees them — deriving
  /// them here would test the deriver instead.
  Layer heldRow() => Layer(
    id: layerId,
    name: 'A',
    frames: [Frame(id: celId, duration: 1, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(celId, length: 1),
      1: TimelineExposure.drawing(celId, length: 1, ghost: true),
      2: TimelineExposure.drawing(celId, length: 1, ghost: true),
    },
  );

  Layer layerIn(ProjectRepository repository) =>
      repository.requireProject().tracks.single.cuts.single.layers.single;

  test('★deleting the block takes its cel with it, ghosts and all', () {
    final repository = repositoryWith(heldRow());
    final controller = TimelineController(repository: repository, cutId: cutId);

    // Sanity: the fixture really is the shape the defect needs — an
    // authored block with derived instances standing after it.
    expect(layerIn(repository).timeline[1]!.ghost, isTrue);
    expect(layerIn(repository).frames, hasLength(1));

    controller.deleteBlocksForLayer(layerId: layerId, blockStartIndexes: [0]);

    final after = layerIn(repository);
    expect(
      after.frames,
      isEmpty,
      reason:
          'the cel left with its block — it used to survive as an orphan '
          'because the ghosts were counted as references, and then the '
          'ghosts re-derived away and left frames=1 / timeline={}',
    );
    expect(
      after.timeline.values.where((e) => e.isDrawing),
      isEmpty,
      reason: 'and nothing is left pointing at it',
    );
  });

  test('⛔an AUTHORED second exposure still keeps the cel', () {
    // The other half of the law, so the filter cannot be over-applied: a
    // cel a person exposed twice survives deleting one of those blocks.
    final repository = repositoryWith(
      Layer(
        id: layerId,
        name: 'A',
        frames: [Frame(id: celId, duration: 1, strokes: const [])],
        timeline: {
          0: TimelineExposure.drawing(celId, length: 1),
          4: TimelineExposure.drawing(celId, length: 1),
        },
      ),
    );
    final controller = TimelineController(repository: repository, cutId: cutId);

    controller.deleteBlocksForLayer(layerId: layerId, blockStartIndexes: [0]);

    expect(
      layerIn(repository).frames.map((f) => f.id),
      contains(celId),
      reason: 'the exposure at 4 is authored, so the cel is still spoken for',
    );
  });
}
