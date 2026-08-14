import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
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

    test('requireTrackOfCut finds the holding track, else throws', () {
      final project = _project(cuts: [_cut('a')]);

      expect(
        requireTrackOfCut(project, const CutId('a')).id,
        const TrackId('t'),
      );
      expect(
        () => requireTrackOfCut(project, const CutId('missing')),
        throwsStateError,
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
  });

  group('projectAudioSourcePaths', () {
    // A conform reads the WHOLE source into memory before the decoder can
    // reject it, so handing the pool over blind cost a full read of every
    // movie and still on project open. One case per kind: the table is the
    // contract, and adding a kind without deciding this is a failing test
    // rather than a silent 3GB read.
    for (final (kind, warmed) in const [
      (MediaAssetKind.audio, true),
      (MediaAssetKind.video, false),
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
      });
    });
  });

  group('what the project carries', () {
    test('sounds, stills and PDFs are carried by default; video is not', () {
      // Blender's rule as the DEFAULT — it was a ceiling until 08-14, when
      // the user reversed it: a movie starts as a reference because three
      // gigabytes should not land in a project by accident, and it can
      // still be carried by someone who means it.
      expect(mediaKindCarriedByDefault(MediaAssetKind.audio), isTrue);
      expect(mediaKindCarriedByDefault(MediaAssetKind.image), isTrue);
      expect(mediaKindCarriedByDefault(MediaAssetKind.pdf), isTrue);
      expect(mediaKindCarriedByDefault(MediaAssetKind.video), isFalse);
    });

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
