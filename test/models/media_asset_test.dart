import 'package:flutter_test/flutter_test.dart';
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

Layer _seLayer({List<AudioClip> audioClips = const []}) {
  return Layer(
    id: const LayerId('se-1'),
    name: 'S1',
    kind: LayerKind.se,
    frames: [Frame(id: const FrameId('f1'), duration: 1, strokes: const [])],
    timeline: {0: const TimelineExposure.drawing(FrameId('f1'), length: 4)},
    audioClips: audioClips,
  );
}

Project _project({
  List<MediaAsset> mediaAssets = const [],
  List<AudioClip> audioClips = const [],
}) {
  return Project(
    id: const ProjectId('p1'),
    name: 'P',
    createdAt: DateTime.utc(2026, 7, 9),
    mediaAssets: mediaAssets,
    tracks: [
      Track(
        id: const TrackId('t1'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('c1'),
            name: 'Cut 1',
            duration: 24,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [_seLayer(audioClips: audioClips)],
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('MediaAsset', () {
    test('round-trips through json; unknown kind decodes to audio', () {
      const asset = MediaAsset(path: r'C:\snd\foot.wav', name: 'foot.wav');
      expect(MediaAsset.fromJson(asset.toJson()), asset);
      expect(asset.toJson()['kind'], 'audio');

      final unknownKind = MediaAsset.fromJson({
        'path': '/a/b.wav',
        'name': 'b',
        'kind': 'hologram',
      });
      expect(unknownKind.kind, MediaAssetKind.audio);
    });

    test('default name is the file name for either separator style', () {
      expect(mediaAssetDefaultName(r'C:\proj\snd\foot.wav'), 'foot.wav');
      expect(mediaAssetDefaultName('/home/a/clap.ogg'), 'clap.ogg');
      expect(mediaAssetDefaultName('bare.wav'), 'bare.wav');
    });

    test('copyWith moves the path and keeps the name', () {
      const asset = MediaAsset(path: '/old.wav', name: '발소리');
      final moved = asset.copyWith(path: '/new.wav');
      expect(moved.path, '/new.wav');
      expect(moved.name, '발소리');
    });

    test('duplicate pool paths are rejected', () {
      expect(
        () => Project(
          id: const ProjectId('p'),
          name: 'P',
          tracks: const [],
          createdAt: DateTime.utc(2026, 7, 9),
          mediaAssets: const [
            MediaAsset(path: '/a.wav', name: 'a'),
            MediaAsset(path: '/a.wav', name: 'a again'),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('Project.mediaAssets', () {
    test('serializes and round-trips', () {
      final project = _project(
        mediaAssets: const [MediaAsset(path: '/snd/foot.wav', name: '발소리')],
        audioClips: const [
          AudioClip(filePath: '/snd/foot.wav', frameId: FrameId('f1')),
        ],
      );

      final restored = Project.fromJson(project.toJson());
      // Pool equality only: Cut.fromJson tops up fixture layers, so whole-
      // project equality is not a round-trip invariant here.
      expect(restored.mediaAssets, project.mediaAssets);
    });

    test('loading reconciles clip references the stored pool misses '
        '(legacy projects predate the pool)', () {
      final legacy = _project(
        audioClips: const [
          AudioClip(filePath: r'C:\snd\foot.wav', frameId: FrameId('f1')),
        ],
      );
      final json = legacy.toJson()..remove('mediaAssets');

      final restored = Project.fromJson(json);
      expect(restored.mediaAssets, const [
        MediaAsset(path: r'C:\snd\foot.wav', name: 'foot.wav'),
      ]);
    });

    test('reconciliation keeps stored entries (names) and appends only the '
        'unknown paths once', () {
      final stored = [const MediaAsset(path: '/a.wav', name: '이름 있음')];
      final tracks = _project(
        audioClips: const [
          AudioClip(filePath: '/a.wav', frameId: FrameId('f1')),
          AudioClip(filePath: '/b.wav', frameId: FrameId('f1')),
          AudioClip(filePath: '/b.wav', frameId: FrameId('f1')),
        ],
      ).tracks;

      final reconciled = reconciledMediaAssets(stored, tracks);
      expect(reconciled, [
        const MediaAsset(path: '/a.wav', name: '이름 있음'),
        const MediaAsset(path: '/b.wav', name: 'b.wav'),
      ]);
    });

    test('mediaAssetByPath finds pool entries', () {
      final project = _project(
        mediaAssets: const [MediaAsset(path: '/a.wav', name: 'a')],
      );
      expect(project.mediaAssetByPath('/a.wav')?.name, 'a');
      expect(project.mediaAssetByPath('/missing.wav'), isNull);
    });
  });
}
