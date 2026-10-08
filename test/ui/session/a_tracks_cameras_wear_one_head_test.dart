import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️유저 2026-10-09: 「그럼 카메라행도 글로벌? 콘티행처럼 머리 같도록
/// 할까하는데」 → I-73-camera-row-Q1: 「좋은데 색라벨은 컷마다 있는게
/// 좋을거같은데」.
///
/// The cameras of a track's cuts are one row on the storyboard, so they go
/// by one NAME and one FX SWITCH: either, written on one, is written on
/// all of them — and a cut joining the track is born wearing both. The
/// colour LABEL stays each cut's own.
///
/// Track V holds cuts a and b; track W holds w.
void main() {
  Cut cutOf(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(id: LayerId('$id-cel'), name: 'A', frames: const []),
      Layer(
        id: LayerId('$id-cam'),
        name: 'Camera',
        kind: LayerKind.camera,
        frames: const [],
      ),
    ],
  );

  EditorSessionManager open() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('heads'),
        name: 'Heads',
        createdAt: DateTime.utc(2026, 10, 9),
        tracks: [
          Track(
            id: const TrackId('v'),
            name: 'V',
            cuts: [cutOf('a'), cutOf('b')],
          ),
          Track(id: const TrackId('w'), name: 'W', cuts: [cutOf('w')]),
        ],
      ),
    );
    addTearDown(session.dispose);
    session.selectCut(const CutId('a'));
    return session;
  }

  Layer layerOf(EditorSessionManager session, String id) {
    for (final track in session.repository.requireProject().tracks) {
      for (final cut in track.cuts) {
        if (cut.layers.byId(LayerId(id)) case final layer?) {
          return layer;
        }
      }
    }
    throw StateError('no $id');
  }

  test('🚨a name given one camera is the track\'s cameras\' — and undo takes '
      'it back from all of them', () {
    final session = open();

    session.layerVerbs.renameLayer(const LayerId('a-cam'), 'Crane');

    expect(layerOf(session, 'a-cam').name, 'Crane');
    expect(layerOf(session, 'b-cam').name, 'Crane');
    expect(layerOf(session, 'w-cam').name, 'Camera', reason: 'another track');
    expect(layerOf(session, 'b-cel').name, 'A', reason: 'not a camera');

    session.undo();
    expect(layerOf(session, 'a-cam').name, 'Camera');
    expect(layerOf(session, 'b-cam').name, 'Camera');
  });

  test('a row that is no camera keeps its name its own', () {
    final session = open();

    session.layerVerbs.renameLayer(const LayerId('a-cel'), 'B');

    expect(layerOf(session, 'b-cel').name, 'A');
  });

  test('🚨the fx switch is the track\'s cameras\' too', () {
    final session = open();

    session.effectsAndFx.toggleLayerFx(const LayerId('b-cam'));

    expect(layerOf(session, 'a-cam').transformEnabled, isFalse);
    expect(layerOf(session, 'b-cam').transformEnabled, isFalse);
    expect(layerOf(session, 'w-cam').transformEnabled, isTrue);
  });

  test('⛔the colour label stays each cut\'s own', () {
    final session = open();

    session.layerMarks.setLayerMark(
      const LayerId('a-cam'),
      const LayerMark(process: LayerProcess.key),
    );

    expect(
      layerOf(session, 'a-cam').mark,
      const LayerMark(process: LayerProcess.key),
    );
    expect(layerOf(session, 'b-cam').mark, LayerMark.none);
  });

  test('🚨a cut joining the track is born wearing the head — its label '
      'is still its own', () {
    final session = open();
    session.layerVerbs.renameLayer(const LayerId('a-cam'), 'Crane');
    session.effectsAndFx.toggleLayerFx(const LayerId('a-cam'));
    session.layerMarks.setLayerMark(
      const LayerId('a-cam'),
      const LayerMark(process: LayerProcess.key),
    );
    final before = {
      for (final cut in session.repository.requireProject().tracks.first.cuts)
        cut.id,
    };

    session.cutVerbs.createCut();

    final born = session.repository
        .requireProject()
        .tracks
        .first
        .cuts
        .singleWhere((cut) => !before.contains(cut.id));
    final camera = born.layers.cameraLayer!;
    expect(camera.name, 'Crane');
    expect(camera.transformEnabled, isFalse);
    expect(camera.mark, LayerMark.none);
  });
}
