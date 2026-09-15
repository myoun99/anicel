import 'package:flutter_test/flutter_test.dart';
import '../helpers/run_edge_fixtures.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart';

// Direct coverage for the shared Project -> Track -> Cut -> Layer lookups.
// Command tests used to each carry a private copy of these walks (the
// `_cutById`/`_layerById` reimplementations); those now call these functions,
// but nothing named them directly, so this pins their found / not-found and
// track-owned-SE behaviour.
Cut _cut(String id, {List<Layer> layers = const []}) => Cut(
  id: CutId(id),
  name: id,
  duration: 1,
  canvasSize: const CanvasSize(width: 8, height: 8),
  layers: layers,
);

Layer _layer(String id) => Layer(
  id: LayerId(id),
  name: id,
  frames: const [],
  kind: LayerKind.animation,
);

Project _project({
  List<Cut> cuts = const [],
  List<Layer> seLayers = const [],
  List<MediaAsset> mediaAssets = const [],
}) => Project(
  id: const ProjectId('p'),
  name: 'p',
  createdAt: DateTime.utc(2026, 6, 11),
  tracks: [
    Track(id: const TrackId('t'), name: 't', cuts: cuts, seLayers: seLayers),
  ],
  mediaAssets: mediaAssets,
);

Layer _seLayer(String id, List<String> clipPaths) => Layer(
  id: LayerId(id),
  name: id,
  frames: const [],
  kind: LayerKind.se,
  audioClips: [
    for (final path in clipPaths)
      AudioClip(filePath: path, frameId: FrameId('$id-frame')),
  ],
);

MediaAsset _asset(String path, MediaAssetKind kind, {bool carried = true}) =>
    MediaAsset(path: path, name: path, kind: kind, carried: carried);

void main() {
  group('project_lookup', () {
    test('requireCut returns the matching cut and throws when absent', () {
      final project = _project(cuts: [_cut('a'), _cut('b')]);

      expect(requireCut(project, const CutId('b')).id, const CutId('b'));
      expect(
        () => requireCut(project, const CutId('missing')),
        throwsStateError,
      );
    });

    test('requireCutPosition is ONE walk — the holding track, the cut and '
        'its index are its projections, and an absent id throws', () {
      final project = _project(cuts: [_cut('a'), _cut('b')]);

      final position = requireCutPosition(project, const CutId('b'));
      expect(position.track.id, const TrackId('t'));
      expect(position.trackId, const TrackId('t'));
      expect(position.cut.id, const CutId('b'));
      expect(position.cutId, const CutId('b'));
      expect(position.cutIndex, 1);
      expect(position.cutCount, 2);
      expect(
        () => requireCutPosition(project, const CutId('missing')),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Cut not found: missing',
          ),
        ),
      );
    });

    test('cutPositionOf answers null for an id that lives nowhere', () {
      final project = _project(cuts: [_cut('a')]);

      expect(cutPositionOf(project, const CutId('missing')), isNull);
      expect(
        cutPositionOf(project, const CutId('a'))?.cut.id,
        const CutId('a'),
      );
    });

    test('requireLayer is cut-scoped: found, wrong cut, missing layer', () {
      final project = _project(
        cuts: [
          _cut('a', layers: [_layer('la')]),
          _cut('b', layers: [_layer('lb')]),
        ],
      );

      expect(
        requireLayer(
          project,
          cutId: const CutId('a'),
          layerId: const LayerId('la'),
        ).id,
        const LayerId('la'),
      );
      // Layer lb lives in cut b, so it is not found scoped to cut a.
      expect(
        () => requireLayer(
          project,
          cutId: const CutId('a'),
          layerId: const LayerId('lb'),
        ),
        throwsStateError,
      );
      expect(
        () => requireLayer(
          project,
          cutId: const CutId('missing'),
          layerId: const LayerId('la'),
        ),
        throwsStateError,
      );
    });

    test('cutIdOfLayer returns the owning cut, or null for track SE rows', () {
      final project = _project(
        cuts: [
          _cut('a', layers: [_layer('la')]),
        ],
        seLayers: [_layer('se')],
      );

      expect(cutIdOfLayer(project, const LayerId('la')), const CutId('a'));
      // Track-owned SE rows have no owning cut.
      expect(cutIdOfLayer(project, const LayerId('se')), isNull);
      expect(cutIdOfLayer(project, const LayerId('missing')), isNull);
    });

    test('requireLayerAnywhere reaches cut layers AND track-owned SE rows', () {
      final project = _project(
        cuts: [
          _cut('a', layers: [_layer('la')]),
        ],
        seLayers: [_layer('se')],
      );

      expect(
        requireLayerAnywhere(project, const LayerId('la')).id,
        const LayerId('la'),
      );
      expect(
        requireLayerAnywhere(project, const LayerId('se')).id,
        const LayerId('se'),
      );
      expect(
        () => requireLayerAnywhere(project, const LayerId('missing')),
        throwsStateError,
      );
    });

    group('requireMemoBlockAt — the block a memo is addressed to', () {
      const cel = FrameId('cel');
      final layer = Layer(
        id: const LayerId('row'),
        name: 'row',
        kind: LayerKind.animation,
        frames: [Frame(id: cel, duration: 1, strokes: const [])],
        timeline: const {
          0: TimelineExposure.drawing(cel, length: 1),
          1: TimelineExposure.drawing(
            cel,
            length: 1,
            ghostOf: endHoldGhost,
          ),
        },
      );

      test('a real block start answers the entry itself', () {
        expect(
          identical(requireMemoBlockAt(layer, 0), layer.timeline[0]),
          isTrue,
        );
      });

      test('an index that starts no block is refused by name', () {
        expect(
          () => requireMemoBlockAt(layer, 5),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'No exposure block starts at 5 on row.',
            ),
          ),
        );
      });

      test('a GHOST cell is refused — it is rederived, so a memo on it '
          'would be lost on the next run pass', () {
        expect(
          () => requireMemoBlockAt(layer, 1),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'A ghost exposure is rederived, so it cannot hold a memo '
                  '(row at 1).',
            ),
          ),
        );
      });
    });
  });

  group('projectAudioSourcePaths', () {
    // 🪦This table used to say audio-only, and half its reason was real: a
    // conform read the WHOLE source into memory before any decoder could
    // reject it, so warming the pool blind cost a full read of every movie
    // on project open. The decoder takes a path and a span now, so that
    // half is gone — and a MOVIE HAS A SOUNDTRACK, which the old answer
    // had made unreachable.
    //
    // ⛔A still and a PDF are still left alone, and not to save a read:
    // they have nowhere to PUT an audio track. Warming one could only ever
    // learn what its format already says, and it would learn it again on
    // every open, because a source with no conform can never match one.
    //
    // The table is the contract: adding a kind without deciding this is a
    // failing test rather than a silent cost.
    for (final (kind, warmed) in const [
      (MediaAssetKind.audio, true),
      (MediaAssetKind.video, true),
      (MediaAssetKind.image, false),
      (MediaAssetKind.pdf, false),
    ]) {
      test('a ${kind.jsonValue} pool entry is '
          '${warmed ? 'warmed' : 'left alone'}', () {
        final project = _project(mediaAssets: [_asset('pool/file', kind)]);

        expect(
          projectAudioSourcePaths(project),
          warmed ? {'pool/file'} : isEmpty,
        );
      });
    }

    test('every kind has an answer — a new one cannot inherit somebody '
        'else\'s', () {
      // 🚨The predicate is exhaustive by switch, so this passes today by
      // construction. It is here for the day the enum grows in a branch
      // that did not touch this file: the table above would still be four
      // rows, and this is what notices.
      expect(
        MediaAssetKind.values.map(mediaKindCanCarrySound).length,
        MediaAssetKind.values.length,
      );
    });

    test('SE clips are warmed whatever the pool holds, and a path in both '
        'appears once', () {
      final project = _project(
        seLayers: [
          _seLayer('se1', ['voice.wav', 'shared.wav']),
          _seLayer('se2', ['footstep.wav']),
        ],
        mediaAssets: [
          _asset('shared.wav', MediaAssetKind.audio),
          _asset('bgm.wav', MediaAssetKind.audio),
          _asset('reference.mp4', MediaAssetKind.video),
        ],
      );

      expect(projectAudioSourcePaths(project), {
        'voice.wav',
        'shared.wav',
        'footstep.wav',
        'bgm.wav',
        // 🚨The movie is IN here, and that is the point of the round: its
        // soundtrack is a sound the project references, and a filter that
        // kept it out was the reason 「the importer cannot see video audio」
        // stood as a bug for months.
        'reference.mp4',
      });
    });
  });

  group('what the project carries', () {
    test('the pool decides, and CARRIED is the whole answer', () {
      final project = _project(
        mediaAssets: [
          _asset('bgm.wav', MediaAssetKind.audio),
          _asset('board.png', MediaAssetKind.image),
          _asset('conte.pdf', MediaAssetKind.pdf),
          _asset('reference.mp4', MediaAssetKind.video),
        ],
      );

      expect(projectArchivedMediaPaths(project), {
        'bgm.wav',
        'board.png',
        'conte.pdf',
        // The movie too, because this fixture says it is carried. The
        // kind used to veto that here, which meant a flag the user had
        // set said yes while the save said no.
        'reference.mp4',
      });
    });

    test('an SE clip is not a registration', () {
      // A clip references audio by path and gets warmed for playback, but
      // what the project CARRIES is what the pool holds. A clip pointing
      // at an unregistered file stays a reference like any other, and
      // packing it would put bytes in the archive that nothing in the pool
      // could ever name again.
      final project = _project(
        seLayers: [
          _seLayer('se1', ['unregistered.wav']),
        ],
        mediaAssets: [_asset('bgm.wav', MediaAssetKind.audio)],
      );

      expect(projectArchivedMediaPaths(project), {'bgm.wav'});
      expect(
        projectAudioSourcePaths(project),
        contains('unregistered.wav'),
        reason: 'still warmed for playback — the two questions differ',
      );
    });

    test('an empty pool carries nothing', () {
      expect(projectArchivedMediaPaths(_project()), isEmpty);
    });

    test('the toggle decides, whatever the kind starts at', () {
      // A sound the user deliberately left linked — the original is shared
      // with another tool — stays linked, and a movie the user asked the
      // project to hold is held. The kind is where each of them STARTED,
      // and this list is about where they ended up.
      final project = _project(
        mediaAssets: [
          _asset('kept.wav', MediaAssetKind.audio),
          _asset('linked.wav', MediaAssetKind.audio, carried: false),
          _asset('movie.mp4', MediaAssetKind.video),
          _asset('take.mp4', MediaAssetKind.video, carried: false),
        ],
      );

      expect(projectArchivedMediaPaths(project), {'kept.wav', 'movie.mp4'});
    });
  });
}
