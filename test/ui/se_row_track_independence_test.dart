import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// UI-R5 — an S row belongs to its TRACK, not to whichever cut is open.
///
/// User, 2026-08-09: "S행은 V랑 관련없이 독립적으로 움직일 수 있어야 해.
/// 독립적으로 타임라인에 있는 기능 뭐든 작동하도록. 행간이동이든 뭐든."
///
/// 🚨The fixture needs TWO tracks and the active cut on the FIRST, because
/// with one track every wrong answer ("the selected track") is also the
/// right one.
void main() {
  const trackA = TrackId('track-a');
  const trackB = TrackId('track-b');

  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 6,
    canvasSize: const CanvasSize(width: 100, height: 100),
    layers: [
      Layer(
        id: LayerId('$id-cel'),
        name: 'A',
        frames: const [],
        timeline: const {},
      ),
    ],
  );

  Layer se(String id) => Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.se,
    frames: const [],
    timeline: const {},
  );

  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'p',
        createdAt: DateTime.utc(2026, 8, 9),
        tracks: [
          Track(
            id: trackA,
            name: 'V1',
            cuts: [cut('a-1')],
            seLayers: [se('a-s1')],
          ),
          Track(
            id: trackB,
            name: 'V2',
            cuts: [cut('b-1')],
            seLayers: [se('b-s1'), se('b-s2'), se('b-s3')],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  List<String> seOrderOf(EditorSessionManager manager, TrackId trackId) =>
      manager.repository
          .requireProject()
          .tracks
          .firstWhere((track) => track.id == trackId)
          .seLayers
          .map((layer) => layer.id.value)
          .toList();

  test('re-ordering an S row of the track WITHOUT the open cut moves that '
      'track\'s list, and leaves the open one alone', () {
    final manager = session();
    expect(manager.selectedTrackId, trackA, reason: 'the open cut is on A');
    expect(seOrderOf(manager, trackB), ['b-s1', 'b-s2', 'b-s3']);

    // Track B's rail draws its slots top-down = the model list reversed.
    final displayRows = [se('b-s3'), se('b-s2'), se('b-s1')];
    manager.beginLayerRowDrag(const LayerRowSubject(LayerId('b-s3')));
    manager.updateLayerRowDrag(displayRows, 3);
    manager.endLayerRowDrag();

    expect(seOrderOf(manager, trackB), [
      'b-s3',
      'b-s1',
      'b-s2',
    ], reason: 'the row moved inside its OWN track');
    expect(
      seOrderOf(manager, trackA),
      ['a-s1'],
      reason: 'the selected track was not the subject and did not move',
    );
  });

  test('the row-kind question does not ask which cut is open', () {
    final manager = session();
    expect(
      manager.isTrackSeLayerId(const LayerId('b-s1')),
      isTrue,
      reason:
          'a track fixture is one wherever the open cut is — every axis '
          'rule keyed off this answered NO for another track\'s S row',
    );
    expect(manager.isTrackSeLayerId(const LayerId('a-s1')), isTrue);
    expect(manager.isTrackSeLayerId(const LayerId('a-1-cel')), isFalse);
  });
}
