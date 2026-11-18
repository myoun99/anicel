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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/services/project_tree_editor.dart';

void main() {
  late Project project;

  setUp(() {
    project = createDefaultProject();
  });

  test('🚨updateLayerAnywhere reaches EVERY layer the one walk yields — the '
      'editor and the walk cannot disagree about where layers live (F-131)',
      () {
    // Finding a layer by id and collecting the ids in use read
    // `projectLayersAnywhere`; the editor rebuilds the tree and cannot. So
    // the editor's reach is pinned against the walk here: the collector
    // once walked cut layers only, and a mint then handed out an SE row's
    // id.
    final layers = projectLayersAnywhere(project).toList();
    expect(
      layers.map((layer) => layer.id).toSet(),
      hasLength(layers.length),
      reason: 'premise: the default project holds no duplicate ids',
    );
    expect(
      project.tracks.first.seLayers,
      isNotEmpty,
      reason: 'premise: the fixture has track SE rows to reach',
    );
    for (final layer in layers) {
      expect(
        updateLayerAnywhere(
          project,
          layer.id,
          (found) => found.copyWith(name: 'Reached'),
        ),
        isNotNull,
        reason: '${layer.id} is in the walk but the editor cannot find it',
      );
    }
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

  test('🚨THE WALK IS THE WHOLE PROJECT — updateCutAnywhere finds a cut in '
      'the SECOND track without the caller knowing which track it is in', () {
    final first = project.tracks.first;
    final second = Track(
      id: const TrackId('t2'),
      name: 'B',
      cuts: [first.cuts.first.copyWith(id: const CutId('c2'))],
    );
    final twoTracks = project.copyWith(tracks: [first, second]);

    final next = updateCutAnywhere(
      twoTracks,
      const CutId('c2'),
      (c) => c.copyWith(layers: const []),
    );

    expect(next!.tracks.last.cuts.single.layers, isEmpty);
    expect(
      next.tracks.first.cuts.first.layers,
      first.cuts.first.layers,
      reason: 'the other cut is untouched',
    );
    expect(
      [for (final track in next.tracks) track.id],
      [first.id, second.id],
      reason: 'each track comes back as ITSELF — the walk must not hand one '
          'track another\'s name',
    );
  });

  group('🚨A WALK HANDS BACK, AS THEY WERE, EVERY TRACK AND CUT IT DID NOT '
      'CHANGE — card conte-one-eye-repaints-every-track (11-08)', () {
    // One S row's eye made every track and every cut anew, and the conte's
    // rows — kept while their cuts are the same objects — all built again.
    // Two tracks, two cuts on the first: each edit below lands in one place.
    late Project two;
    late Track first;
    late Track second;

    setUp(() {
      final track = project.tracks.first;
      final cut = track.cuts.first;
      first = track.copyWith(
        cuts: [
          cut,
          cut.copyWith(id: const CutId('c1b'), layers: const []),
        ],
        seLayers: [
          Layer(
            id: const LayerId('se-a'),
            name: 'SE',
            frames: const [],
            kind: LayerKind.se,
          ),
        ],
      );
      second = Track(
        id: const TrackId('t2'),
        name: 'B',
        cuts: [
          cut.copyWith(
            id: const CutId('c2'),
            layers: [
              Layer(
                id: const LayerId('b-row'),
                name: 'B row',
                frames: [
                  Frame(
                    id: const FrameId('b-frame'),
                    duration: 1,
                    strokes: const [],
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      two = project.copyWith(tracks: [first, second]);
    });

    Layer rename(Layer layer) => layer.copyWith(name: 'Renamed');

    /// A track built again round an edit of its own rows wraps its lists
    /// anew ([Track]'s constructor): it is its cuts that stand as they were.
    void expectTheSameCuts(Track track) {
      expect(track.cuts, hasLength(first.cuts.length));
      for (final (index, cut) in track.cuts.indexed) {
        expect(cut, same(first.cuts[index]), reason: 'cut $index');
      }
    }

    test('a cut row\'s edit keeps the other cut, the track\'s own rows and '
        'the other track', () {
      final next = updateLayerAnywhere(
        two,
        first.cuts.first.layers.first.id,
        rename,
      )!;
      expect(next.tracks.first.cuts.first.layers.first.name, 'Renamed');
      expect(next.tracks.first.cuts.last, same(first.cuts.last));
      expect(next.tracks.first.seLayers.single, same(first.seLayers.single));
      expect(
        next.tracks.first.transitionLayer,
        same(first.transitionLayer),
      );
      expect(next.tracks.last, same(second));
    });

    test('an S row\'s edit keeps every cut, and the other track', () {
      final next = updateLayerAnywhere(two, const LayerId('se-a'), rename)!;
      expect(next.tracks.first.seLayers.single.name, 'Renamed');
      expectTheSameCuts(next.tracks.first);
      expect(next.tracks.last, same(second));
    });

    test('a transition row\'s edit keeps every cut, and the other track', () {
      final next = updateLayerAnywhere(
        two,
        first.transitionLayer.id,
        rename,
      )!;
      expect(next.tracks.first.transitionLayer.name, 'Renamed');
      expectTheSameCuts(next.tracks.first);
      expect(next.tracks.last, same(second));
    });

    test('a frame\'s edit keeps the other track', () {
      final next = updateFrameAnywhere(
        two,
        const FrameId('b-frame'),
        (frame) => frame.copyWith(name: 'Renamed'),
      )!;
      expect(
        next.tracks.last.cuts.single.layers.single.frames.single.name,
        'Renamed',
      );
      expect(next.tracks.first, same(first));
    });

    test('a cut\'s edit keeps the other track, and the other cut', () {
      final next = updateCutAnywhere(
        two,
        const CutId('c1b'),
        (cut) => cut.copyWith(name: 'Renamed'),
      )!;
      expect(next.tracks.first.cuts.last.name, 'Renamed');
      expect(next.tracks.first.cuts.first, same(first.cuts.first));
      expect(next.tracks.last, same(second));
    });

    test('a cut\'s removal keeps the other track', () {
      final removed = removeCutAnywhere(two, const CutId('c2'));
      expect(removed.project.tracks.first, same(first));
      expect(
        removeCutAnywhere(two, const CutId('nowhere')).project,
        same(two),
        reason: 'nothing removed, nothing made anew',
      );
    });

    test('an edit that changes nothing hands back the very project, or cut',
        () {
      expect(
        updateLayerAnywhere(two, const LayerId('b-row'), (layer) => layer),
        same(two),
      );
      expect(
        updateFrameAnywhere(two, const FrameId('b-frame'), (frame) => frame),
        same(two),
      );
      expect(
        updateCutAnywhere(two, const CutId('c2'), (cut) => cut),
        same(two),
      );
      expect(
        updateTrackById(two, const TrackId('t2'), (track) => track),
        same(two),
      );
      final cut = second.cuts.single;
      expect(
        updateLayerInCut(cut, const LayerId('b-row'), (layer) => layer),
        same(cut),
      );
    });
  });

  test('removeCutAnywhere takes the cut out of whichever track holds it '
      'and hands it back; an unknown id removes nothing', () {
    final first = project.tracks.first;
    final second = Track(
      id: const TrackId('t2'),
      name: 'B',
      cuts: [first.cuts.first.copyWith(id: const CutId('c2'))],
    );
    final twoTracks = project.copyWith(tracks: [first, second]);

    final removed = removeCutAnywhere(twoTracks, const CutId('c2'));
    expect(removed.removed?.id, const CutId('c2'));
    expect(removed.project.tracks.last.cuts, isEmpty);
    expect(removed.project.tracks.first.cuts, first.cuts);

    final untouched = removeCutAnywhere(twoTracks, const CutId('nowhere'));
    expect(untouched.removed, isNull);
    expect(untouched.project.tracks.last.cuts, second.cuts);
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

  test('updateFrameAnywhere reaches the transition row, as the layer write '
      'does', () {
    final row = project.tracks.first.transitionLayer;
    final frame = Frame(id: const FrameId('t'), duration: 1, strokes: const []);
    project = updateLayerAnywhere(
      project,
      row.id,
      (l) => l.copyWith(frames: [frame]),
    )!;

    final edited = updateFrameAnywhere(
      project,
      frame.id,
      (f) => f.copyWith(name: 'Renamed'),
    );

    expect(
      edited!.tracks.first.transitionLayer.frames.single.name,
      'Renamed',
    );
  });
}
