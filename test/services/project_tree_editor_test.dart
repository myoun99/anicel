// THE TREE EDITORS REACH EVERY HOME A NODE CAN HAVE, AND ANSWER NULL FOR
// AN ID THAT LIVES NOWHERE.
//
// No test named this file (audit 2026-09-03): the repository reaches it on
// every edit, but nothing pinned its own contract — that an unknown id is
// a null (not an unchanged project), and that `updateLayerAnywhere` finds
// a layer in a cut, in the track's SE rows, and in the transition row.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_tree_editor.dart';

void main() {
  late Project project;

  setUp(() {
    project = createDefaultProject();
  });

  test('updateTrackById edits the one track and refuses an unknown id', () {
    final track = project.tracks.first;
    final edited = updateTrackById(
      project,
      track.id,
      (t) => t.copyWith(name: 'Renamed'),
    );
    expect(edited!.tracks.first.name, 'Renamed');
    expect(
      updateTrackById(project, const TrackId('nowhere'), (t) => t),
      isNull,
    );
  });

  test('updateCutAnywhere edits the one cut and refuses an unknown id', () {
    final cut = project.tracks.first.cuts.first;
    final edited = updateCutAnywhere(
      project,
      cut.id,
      (c) => c.copyWith(name: 'Renamed'),
    );
    expect(edited!.tracks.first.cuts.first.name, 'Renamed');
    expect(
      updateCutAnywhere(project, const CutId('nowhere'), (c) => c),
      isNull,
    );
  });

  test('updateLayerInCut edits the one layer and refuses an unknown id', () {
    final cut = project.tracks.first.cuts.first;
    final layer = cut.layers.first;
    final edited = updateLayerInCut(
      cut,
      layer.id,
      (l) => l.copyWith(name: 'Renamed'),
    );
    expect(edited!.layers.first.name, 'Renamed');
    expect(updateLayerInCut(cut, const LayerId('nowhere'), (l) => l), isNull);
  });

  test('updateLayerAnywhere reaches a cut layer', () {
    final layer = project.tracks.first.cuts.first.layers.first;
    final edited = updateLayerAnywhere(
      project,
      layer.id,
      (l) => l.copyWith(name: 'Renamed'),
    );
    expect(edited!.tracks.first.cuts.first.layers.first.name, 'Renamed');
  });

  test('updateLayerAnywhere reaches a track SE row', () {
    final track = project.tracks.first;
    final se = Layer(
      id: const LayerId('se-row'),
      name: 'SE',
      frames: const [],
      kind: LayerKind.se,
    );
    final withSe = project.copyWith(
      tracks: [
        track.copyWith(seLayers: [...track.seLayers, se]),
      ],
    );
    final edited = updateLayerAnywhere(
      withSe,
      se.id,
      (l) => l.copyWith(name: 'Renamed'),
    );
    expect(edited!.tracks.first.seLayers.last.name, 'Renamed');
  });

  test('updateLayerAnywhere reaches the transition row', () {
    final transition = project.tracks.first.transitionLayer;
    final edited = updateLayerAnywhere(
      project,
      transition.id,
      (l) => l.copyWith(name: 'Renamed'),
    );
    expect(edited!.tracks.first.transitionLayer.name, 'Renamed');
  });

  test('updateLayerAnywhere refuses an unknown id', () {
    expect(
      updateLayerAnywhere(project, const LayerId('nowhere'), (l) => l),
      isNull,
    );
  });

  test('updateFrameAnywhere edits the one frame and refuses an unknown id', () {
    // The default project's layer starts without cels: give it one.
    final layer = project.tracks.first.cuts.first.layers.first;
    final frame = Frame(id: const FrameId('f'), duration: 1, strokes: const []);
    project = updateLayerAnywhere(
      project,
      layer.id,
      (l) => l.copyWith(frames: [frame]),
    )!;
    final edited = updateFrameAnywhere(
      project,
      frame.id,
      (f) => f.copyWith(name: 'Renamed'),
    );
    expect(
      edited!.tracks.first.cuts.first.layers.first.frames.first.name,
      'Renamed',
    );
    expect(
      updateFrameAnywhere(project, const FrameId('nowhere'), (f) => f),
      isNull,
    );
  });
}
