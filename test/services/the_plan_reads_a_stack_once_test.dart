import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/cut_frame_composite_plan.dart';

/// Card an-eye-toggle-holds-the-ui-thread: the plan asks of every row of
/// every frame where the row stands and which folders hold it — answers
/// that are the STACK's, not the frame's. Each was a scan of the list, n²
/// id compares a frame. The stack is read once, and an edit — a new list
/// — is read again.
void main() {
  Layer drawing(String id, {String? folder, bool clips = false}) => Layer(
    id: LayerId(id),
    name: id.toUpperCase(),
    frames: [Frame(id: FrameId('frame-$id'), duration: 1, strokes: const [])],
    timeline: {0: TimelineExposure.drawing(FrameId('frame-$id'), length: 24)},
    folderId: folder == null ? null : LayerId(folder),
    clipsToBelow: clips,
  );

  Cut cut() => Cut(
    id: const CutId('cut'),
    name: 'Cut',
    layers: [
      drawing('a', folder: 'f'),
      drawing('b', folder: 'f', clips: true),
      createFolderLayer(id: const LayerId('f'), name: 'F'),
      drawing('c'),
      drawing('d', clips: true),
    ],
    duration: 24,
    canvasSize: const CanvasSize(width: 4, height: 4),
  );

  test('every frame of a cut is laid from one reading of its stack', () {
    final held = cut();
    final before = debugPlanStacksRead;

    for (var frame = 0; frame < 24; frame += 1) {
      resolveCutFrameCompositeTree(cut: held, frameIndex: frame);
    }

    expect(
      debugPlanStacksRead - before,
      1,
      reason: 'one stack, read once however many frames are laid',
    );
  });

  test('an edited cut is a new stack and is read again', () {
    final held = cut();
    resolveCutFrameCompositeTree(cut: held, frameIndex: 0);
    final before = debugPlanStacksRead;
    final edited = held.copyWith(
      layers: [
        for (final layer in held.layers)
          if (layer.id == const LayerId('c'))
            layer.copyWith(isVisible: false)
          else
            layer,
      ],
    );

    resolveCutFrameCompositeTree(cut: edited, frameIndex: 0);
    resolveCutFrameCompositeTree(cut: edited, frameIndex: 1);

    expect(debugPlanStacksRead - before, 1);
  });
}
