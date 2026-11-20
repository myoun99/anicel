import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart'
    show rederiveRunBehaviors;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/media/media_asset_uses.dart';
import 'package:anicel/src/services/media/media_preset_sync.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart'
    show debugVideoDecodeBackend;
import 'package:anicel/src/services/project_lookup.dart'
    show requireLayer, requireLayerAnywhere;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_sync_flow.dart' show syncLengthsOf;

import '../../helpers/fake_video_backend.dart';
import '../../helpers/stand_in_movie.dart';
import '../../helpers/project_scratch_folder.dart';

const _take = 'C:/media/take.mp4';
const _cloud = 'C:/media/cloud.png';
const _cutId = CutId('c1');
const _movieRow = LayerId('m1');
const _stillRow = LayerId('p1');
const _soundRow = LayerId('s1');

/// What the pool says the take places: frames 2 to 7 of it.
const _preset = MediaPreset(inFrame: 2, outFrame: 7);

MediaReference _reference(String path) => MediaReference(
  assetPath: path,
  pose: TransformPose(center: CanvasPoint(x: 320, y: 180)),
  pictureSize: const CanvasSize(width: 640, height: 360),
);

/// The take placed whole and then cut in two on its row — ten frames from
/// its start and four more — its sound beside it on an SE row, ten frames
/// long; and a still on a row of its own — its fit and its kind a sync
/// sets, its start and its length none.
Project _project() => Project(
  id: const ProjectId('sync-a-movie'),
  name: 'Sync a movie',
  createdAt: DateTime.utc(2026, 11, 18),
  mediaAssets: [
    MediaAsset(
      path: _take,
      name: 'take',
      kind: MediaAssetKind.video,
      preset: _preset,
    ),
    MediaAsset(path: _cloud, name: 'cloud', kind: MediaAssetKind.image),
  ],
  tracks: [
    Track(
      id: const TrackId('t1'),
      name: 'Video',
      cuts: [
        Cut(
          id: _cutId,
          name: 'c1',
          duration: 24,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            Layer(
              id: _movieRow,
              name: 'take',
              frames: [
                Frame(id: const FrameId('mv'), duration: 1, strokes: const []),
              ],
              timeline: {
                0: const TimelineExposure.drawing(FrameId('mv'), length: 10),
                12: const TimelineExposure.drawing(FrameId('mv'), length: 4),
              },
              mediaReference: _reference(_take),
            ),
            Layer(
              id: _stillRow,
              name: 'cloud',
              kind: LayerKind.image,
              frames: [
                Frame(id: const FrameId('pc'), duration: 1, strokes: const []),
              ],
              timeline: {
                0: const TimelineExposure.drawing(FrameId('pc'), length: 24),
              },
              mediaReference: _reference(_cloud),
            ),
          ],
        ),
      ],
      seLayers: [
        rederiveRunBehaviors(
          Layer(
            id: _soundRow,
            name: 's1',
            kind: LayerKind.se,
            frames: [
              Frame(
                id: const FrameId('snd'),
                duration: 1,
                strokes: const [],
                seName: 'SE',
                name: 'take',
              ),
            ],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('snd'), length: 10),
            },
            audioClips: [
              AudioClip(filePath: _take, frameId: const FrameId('snd')),
            ],
          ),
          drawnFrameCount: 24,
        ),
      ],
    ),
  ],
);

/// The take's sound covers twenty frames, its pictures twenty-four — the
/// preset keeps frames 2 to 7 of either.
const MediaSyncLengths _known = (sound: 20, pictures: 24);

List<MediaSyncPlace> _placesIn(
  Project project, {
  String path = _take,
  MediaSyncLengths lengths = _known,
}) => syncPlacesOf(
  project,
  project.mediaAssets.singleWhere((entry) => entry.path == path),
  lengths: lengths,
);

/// 🗣️유저 2026-11-17 (card 「파일마다 배치 기본값」-Q5 · Q6 「시안대로」 ·
/// Q7 kind-too-off): a movie is synced as a sound is — its row's start in
/// the file and its blocks' length, by the same window, in one undo step.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a movie\'s places are its row — its offset into the file and its '
      'blocks — and its sound\'s frame, each with what the preset places '
      'there; a still\'s row holds no start and no length', () {
    final places = _placesIn(_project());
    final row = places.singleWhere((place) => place.use is RowMediaUse);
    final sound = places.singleWhere((place) => place.use is FrameMediaUse);
    expect(places, hasLength(2));
    expect(row.starts, [0]);
    expect(row.lengths, [10, 4]);
    expect(row.fields, {
      MediaSyncField.start,
      MediaSyncField.length,
      MediaSyncField.fit,
    }, reason: 'a movie of no known count is not one picture: no kind');
    expect((row.placed.start, row.placed.length), (2, 6));
    expect(row.partsFrom(MediaSyncField.values.toSet()), {
      MediaSyncField.start,
      MediaSyncField.length,
    });
    expect(sound.partsFrom(MediaSyncField.asked), {
      MediaSyncField.start,
      MediaSyncField.length,
    });
    expect(_placesIn(_project(), path: _cloud).single.fields, {
      MediaSyncField.fit,
      MediaSyncField.kind,
    });
    expect(
      _placesIn(_project(), lengths: (sound: 20, pictures: null))
          .singleWhere((place) => place.use is RowMediaUse)
          .partsFrom(MediaSyncField.asked),
      isEmpty,
      reason: 'a movie whose rate is not read yet parts from nothing',
    );
  });

  test('syncing the start and the length sets the row\'s offset into its '
      'file and every block\'s length through the comma edge, and its '
      'sound\'s alike — ONE undo takes all of it back', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    Layer movie() => requireLayer(
      session.repository.requireProject(),
      cutId: _cutId,
      layerId: _movieRow,
    );
    Layer sound() => requireLayerAnywhere(
      session.repository.requireProject(),
      _soundRow,
    );
    final before = (movie(), sound());
    session.mediaPool.syncPlaces(
      _take,
      fields: MediaSyncField.asked,
      places: _placesIn(session.repository.requireProject()),
    );
    expect(movie().mediaReference?.frameOffset, 2);
    expect(
      {
        for (final MapEntry(:key, :value) in movie().timeline.entries)
          key: value.length,
      },
      {0: 6, 12: 6},
    );
    expect([for (final clip in sound().audioClips) clip.offsetFrames], [2]);
    expect(sound().timeline[0]?.length, 6);
    final synced = session.repository.requireProject();
    expect(
      [
        for (final place in syncPlacesOf(
          synced,
          synced.mediaAssets.first,
          lengths: _known,
        ))
          place.partsFrom(MediaSyncField.asked),
      ],
      everyElement(isEmpty),
    );
    session.historyManager.undo();
    expect((movie(), sound()), before);
  });

  test('🐛the sync counts a movie\'s pictures as a placement keeps them — '
      'in the project\'s frames once the pool has read its rate, none '
      'before', () async {
    final dir = Directory.systemTemp.createTempSync('anicel-sync-movie');
    deleteAfterSessionEnds(dir);
    final take = normalizedMediaPath(
      (File('${dir.path}${Platform.pathSeparator}take.mp4')
            ..writeAsBytesSync(standInMovieBytes))
          .path,
    );
    // Fifteen frames of 30 fps are twelve of the project's 24.
    debugVideoDecodeBackend = FakeVideoBackend(
      width: 64,
      height: 36,
      frameCount: 15,
      fpsNumerator: 30,
      fpsDenominator: 1,
    );
    addTearDown(() => debugVideoDecodeBackend = null);
    final asset = MediaAsset(
      path: take,
      name: 'take',
      kind: MediaAssetKind.video,
      frameCount: 15,
      preset: _preset,
    );
    final session = EditorSessionManager(
      initialProject: _project().copyWith(mediaAssets: [asset]),
    );
    addTearDown(session.dispose);
    final read = Completer<void>();
    session.mediaPool.mediaFactsRead.addListener(() {
      if (!read.isCompleted) {
        read.complete();
      }
    });
    // The pool's line asks for the file's facts as it shows the file.
    session.mediaPool.mediaFactsOf(take);
    expect(
      syncLengthsOf(session, asset).pictures,
      isNull,
      reason: 'its rate not read yet: a length the preset cannot count',
    );
    await read.future;
    expect(syncLengthsOf(session, asset).pictures, 12);
  });
}
