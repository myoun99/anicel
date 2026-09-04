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
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/commands/relink_media_asset_command.dart';
import 'package:anicel/src/services/project_repository.dart';

/// 🚨A RELINK REACHES EVERY REFERENCE, OR IT LEAVES SOME OFFLINE.
///
/// The pool entry and every clip and media reference across every track
/// move together in ONE undo step (the Resolve offline-media flow). A walk
/// that missed one leaves a layer pointing at a file that is not there —
/// and the user has no second relink to reach it with, because the pool
/// entry now says the media is found.
///
/// ⚠️Untouched tracks, cuts and layers keep their IDENTITY on purpose:
/// downstream caches key off it, and rebuilding what did not change is how
/// a relink of one clip re-decodes a film.
void main() {
  Layer audioLayer(String id, String path) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: LayerKind.se,
    audioClips: [AudioClip(filePath: path, frameId: FrameId('f-$id'))],
  );

  Layer imageLayer(String id, String path) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: LayerKind.image,
    mediaReference: MediaReference(assetPath: path),
  );

  Project projectWith({
    required List<Layer> cutLayers,
    List<Layer> seLayers = const [],
    List<MediaAsset> assets = const [],
  }) => Project(
    id: const ProjectId('p'),
    name: 'P',
    createdAt: DateTime.utc(2026, 9, 5),
    mediaAssets: assets,
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'V',
        seLayers: seLayers,
        cuts: [
          Cut(
            id: const CutId('c'),
            name: 'c',
            layers: cutLayers,
            duration: 12,
            canvasSize: const CanvasSize(width: 100, height: 100),
          ),
        ],
      ),
    ],
  );

  RelinkMediaAssetCommand relink(
    ProjectRepository repository, {
    bool recordSource = false,
    String? sourceStamp,
  }) => RelinkMediaAssetCommand(
    repository: repository,
    oldPath: '/old/clip.wav',
    newPath: '/new/clip.wav',
    recordSource: recordSource,
    sourceStamp: sourceStamp,
  );

  test('the pool entry, an SE clip and a media reference all move', () {
    final repository = ProjectRepository(
      initialProject: projectWith(
        cutLayers: [imageLayer('img', '/old/clip.wav')],
        seLayers: [audioLayer('se', '/old/clip.wav')],
        assets: const [MediaAsset(path: '/old/clip.wav', name: 'clip')],
      ),
    );

    relink(repository).execute();

    final project = repository.requireProject();
    expect(project.mediaAssets.single.path, '/new/clip.wav');
    expect(
      project.mediaAssets.single.name,
      'clip',
      reason: 'the display name survives the move',
    );
    expect(
      project.tracks.single.seLayers.single.audioClips.single.filePath,
      '/new/clip.wav',
    );
    expect(
      project.tracks.single.cuts.single.layers.single.mediaReference!.assetPath,
      '/new/clip.wav',
      reason: 'the media REFERENCE rides the same walk as the audio clip',
    );
  });

  test('a clip pointing somewhere else is left alone', () {
    final repository = ProjectRepository(
      initialProject: projectWith(
        cutLayers: [audioLayer('other', '/somewhere/else.wav')],
        assets: const [MediaAsset(path: '/old/clip.wav', name: 'clip')],
      ),
    );

    relink(repository).execute();

    expect(
      repository
          .requireProject()
          .tracks
          .single
          .cuts
          .single
          .layers
          .single
          .audioClips
          .single
          .filePath,
      '/somewhere/else.wav',
    );
  });

  test('a track with nothing to relink keeps its IDENTITY', () {
    final before = projectWith(
      cutLayers: [audioLayer('other', '/somewhere/else.wav')],
      assets: const [MediaAsset(path: '/old/clip.wav', name: 'clip')],
    );
    final repository = ProjectRepository(initialProject: before);

    relink(repository).execute();

    expect(
      identical(
        repository.requireProject().tracks.single,
        before.tracks.single,
      ),
      isTrue,
      reason:
          'downstream caches key off identity — rebuilding what did not '
          'change is how a relink of one clip re-decodes a film',
    );
  });

  test('undo puts the whole previous project back', () {
    final before = projectWith(
      cutLayers: [imageLayer('img', '/old/clip.wav')],
      assets: const [MediaAsset(path: '/old/clip.wav', name: 'clip')],
    );
    final repository = ProjectRepository(initialProject: before);
    final command = relink(repository);

    command.execute();
    command.undo();

    final project = repository.requireProject();
    expect(project.mediaAssets.single.path, '/old/clip.wav');
    expect(
      project.tracks.single.cuts.single.layers.single.mediaReference!.assetPath,
      '/old/clip.wav',
    );
  });

  test('undo before execute is refused', () {
    final repository = ProjectRepository(
      initialProject: projectWith(cutLayers: const []),
    );
    expect(relink(repository).undo, throwsStateError);
  });

  group('source tracking', () {
    test('a plain relink records NO source — a moved file has only ever had '
        'one path', () {
      final repository = ProjectRepository(
        initialProject: projectWith(
          cutLayers: const [],
          assets: const [MediaAsset(path: '/old/clip.wav', name: 'clip')],
        ),
      );

      relink(repository).execute();

      expect(repository.requireProject().mediaAssets.single.sourcePath, isNull);
    });

    test('a COPY records where it came from, so the changed badge has two '
        'paths to compare', () {
      final repository = ProjectRepository(
        initialProject: projectWith(
          cutLayers: const [],
          assets: const [MediaAsset(path: '/old/clip.wav', name: 'clip')],
        ),
      );

      relink(repository, recordSource: true, sourceStamp: 'stamp').execute();

      final asset = repository.requireProject().mediaAssets.single;
      expect(asset.sourcePath, '/old/clip.wav');
      expect(asset.sourceStamp, 'stamp');
    });
  });
}
