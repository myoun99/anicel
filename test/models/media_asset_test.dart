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
      final asset = MediaAsset(path: r'C:\snd\foot.wav', name: '발소리');
      expect(MediaAsset.fromJson(asset.toJson()), asset);
      expect(asset.toJson()['kind'], 'audio');

      final unknownKind = MediaAsset.fromJson({
        'path': '/a/b.wav',
        'name': 'b',
        'kind': 'hologram',
      });
      expect(unknownKind.kind, MediaAssetKind.audio);
    });

    test('🚨the default name is the file name WITHOUT its extension — the '
        'name a placement gives its rows (유저 2026-09-12)', () {
      expect(mediaAssetDefaultName(r'C:\proj\snd\foot.wav'), 'foot');
      expect(mediaAssetDefaultName('/home/a/clap.ogg'), 'clap');
      expect(mediaAssetDefaultName('bare.wav'), 'bare');
      expect(mediaAssetDefaultName('/a/take.2.wav'), 'take.2');
      expect(mediaAssetDefaultName('/a/.env'), '.env');
    });

    test('a FILE name keeps its extension, and splits at its last dot — the '
        'import table\'s rule, now the pool\'s too', () {
      expect(mediaFileName(r'C:\proj\snd\foot.wav'), 'foot.wav');
      expect(mediaFileName('/home/a/clap.ogg'), 'clap.ogg');
      expect(
        mediaFileNameParts('/a/take.2.wav'),
        (name: 'take.2', extension: '.wav'),
      );
      expect(mediaFileNameParts('/a/README'), (name: 'README', extension: ''));
      expect(mediaFileNameParts('/a/.env'), (name: '.env', extension: ''));
    });

    test('a name an older build wrote by DEFAULT — the file name with its '
        'extension — reads as today\'s default; a typed name stays', () {
      MediaAsset read(String name) =>
          MediaAsset.fromJson({'path': '/a/foot.wav', 'name': name});
      expect(read('foot.wav').name, 'foot');
      expect(read('발소리').name, '발소리');
      expect(read('foot').name, 'foot');
    });

    test('🚨a placement takes the POOL entry\'s name, which a rename '
        'changed — and the default for a file the pool has not seen', () {
      final entry = MediaAsset(path: '/pool/bg_street.png', name: '거리');
      expect(mediaAssetNameFor(entry, entry.path), '거리');
      expect(mediaAssetNameFor(null, '/pool/bg_street.png'), 'bg_street');
    });

    test('copyWith moves the path and keeps the name', () {
      final asset = MediaAsset(path: '/old.wav', name: '발소리');
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
          mediaAssets: [
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
        mediaAssets: [MediaAsset(path: '/snd/foot.wav', name: '발소리')],
        audioClips: [
          AudioClip(filePath: '/snd/foot.wav', frameId: const FrameId('f1')),
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
        audioClips: [
          AudioClip(filePath: r'C:\snd\foot.wav', frameId: const FrameId('f1')),
        ],
      );
      final json = legacy.toJson()..remove('mediaAssets');

      final restored = Project.fromJson(json);
      expect(restored.mediaAssets, [
        MediaAsset(path: r'C:\snd\foot.wav', name: 'foot'),
      ]);
    });

    test('reconciliation keeps stored entries (names) and appends only the '
        'unknown paths once', () {
      final stored = [MediaAsset(path: '/a.wav', name: '이름 있음')];
      final tracks = _project(
        audioClips: [
          AudioClip(filePath: '/a.wav', frameId: const FrameId('f1')),
          AudioClip(filePath: '/b.wav', frameId: const FrameId('f1')),
          AudioClip(filePath: '/b.wav', frameId: const FrameId('f1')),
        ],
      ).tracks;

      final reconciled = reconciledMediaAssets(stored, tracks);
      expect(reconciled, [
        MediaAsset(path: '/a.wav', name: '이름 있음'),
        MediaAsset(path: '/b.wav', name: 'b'),
      ]);
    });

    test('mediaAssetByPath finds pool entries', () {
      final project = _project(
        mediaAssets: [MediaAsset(path: '/a.wav', name: 'a')],
      );
      expect(project.mediaAssetByPath('/a.wav')?.name, 'a');
      expect(project.mediaAssetByPath('/missing.wav'), isNull);
    });
  });

  /// What a carry's bytes are called — in the staging room, and behind
  /// `media/` in the project file.
  group('a carry\'s name', () {
    const path = r'C:\media\take 1.wav';

    test('🚨is minted with the carry, so a relink does not change it '
        '(audit 09-25)', () {
      final asset = MediaAsset(
        path: path,
        name: 'take 1',
        carriedAs: mintMediaCarry(path),
      );
      final relinked = asset.copyWith(path: 'D:/moved/other.wav');

      expect(
        mediaCarryName(relinked.carry!),
        mediaCarryName(asset.carry!),
        reason:
            '🪦derived from the path, the name moved with a relink — and an '
            'undo of it looked for the old one and found nothing',
      );
      expect(
        MediaAsset.fromJson(relinked.toJson()).carry,
        relinked.carry,
        reason: 'and it is what the project file records',
      );
    });

    test('keeps the file\'s name behind its path\'s hash, for a person '
        'looking in the folder', () {
      final minted = mintMediaCarry(path);
      final (:hash, :safe) = mediaNameParts(path);

      expect(minted, startsWith('$hash-'));
      expect(minted, endsWith('-take_1.wav'));
      expect(safe, 'take_1.wav');
      expect(mediaCarryName((poolPath: path, token: minted)), minted);
    });

    test('two carries of one path are two names', () {
      expect(mintMediaCarry(path), isNot(mintMediaCarry(path)));
    });

    test('both spellings of one path make one name', () {
      expect(
        mediaNameParts('C:/media/take 1.wav'),
        mediaNameParts(path),
      );
      expect(
        mediaCarryName((poolPath: 'C:/media/take 1.wav', token: '')),
        mediaCarryName((poolPath: path, token: '')),
      );
    });

    test('a carry from before names were minted is named from the path it '
        'is at — what those projects hold', () {
      final (:hash, :safe) = mediaNameParts(path);

      expect(mediaCarryName((poolPath: path, token: '')), '$hash-$safe');
      expect(
        mediaCarryName((poolPath: path, token: 'c0ffee01')),
        '$hash-c0ffee01-$safe',
      );
    });
  });
}
