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
import 'package:anicel/src/models/timeline_repeat.dart'
    show rederiveRunBehaviors;
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/media/media_asset_uses.dart'
    show FrameMediaUse;
import 'package:anicel/src/services/media/media_preset_sync.dart';
import 'package:anicel/src/services/project_lookup.dart'
    show requireLayerAnywhere;
import 'package:anicel/src/ui/editor_session_manager.dart';

const _clap = 'C:/media/clap.wav';

/// What the pool says the clap places: frames 2 to 7 of it, named 「Door」,
/// its words 「bang」.
const _preset = MediaPreset(
  inFrame: 2,
  outFrame: 7,
  seName: 'Door',
  dialogue: 'bang',
);

Frame _frame(String id, {String? seName, String? name}) => Frame(
  id: FrameId(id),
  duration: 1,
  strokes: const [],
  seName: seName,
  name: name,
);

/// Two places of the clap on one SE row: 「a」 shown by two blocks a frame
/// apart (a footstep reused), so the first one grown pushes the second;
/// its sound from the file's start; 「b」 already from
/// where the preset starts it, its block short — and the block after it
/// close enough to be pushed when it grows.
Project _project() => Project(
  id: const ProjectId('sync-a-sound'),
  name: 'Sync a sound',
  createdAt: DateTime.utc(2026, 11, 18),
  mediaAssets: [MediaAsset(path: _clap, name: 'clap', preset: _preset)],
  tracks: [
    Track(
      id: const TrackId('t1'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('c1'),
          name: 'c1',
          duration: 24,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: const [],
        ),
      ],
      seLayers: [
        rederiveRunBehaviors(
          Layer(
            id: const LayerId('s1'),
            name: 's1',
            kind: LayerKind.se,
            frames: [
              _frame('a', seName: 'SE', name: 'clap'),
              _frame('b', seName: 'Cat', name: 'meow'),
              _frame('other', seName: 'SE', name: 'step'),
            ],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('a'), length: 4),
              5: const TimelineExposure.drawing(FrameId('a'), length: 4),
              12: const TimelineExposure.drawing(FrameId('b'), length: 3),
              16: const TimelineExposure.drawing(FrameId('other'), length: 2),
            },
            audioClips: [
              AudioClip(filePath: _clap, frameId: const FrameId('a')),
              AudioClip(
                filePath: _clap,
                frameId: const FrameId('b'),
                offsetFrames: 2,
              ),
            ],
          ),
          drawnFrameCount: 24,
        ),
      ],
    ),
  ],
);

/// The clap's sound as its conform holds it: twenty frames.
const MediaSyncLengths _known = (sound: 20, pictures: null);

/// The places [project] plays the clap at, its length [lengths].
List<MediaSyncPlace> placesIn(
  Project project, {
  MediaSyncLengths lengths = _known,
}) => syncPlacesOf(project, project.mediaAssets.single, lengths: lengths);

/// 🗣️유저 2026-11-17 (card 「파일마다 배치 기본값」-Q5 · Q6 「시안대로」): a
/// placement copies its file's preset once; a preset changed later is
/// SYNCED by hand — the window picks the fields and the places.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final preset = syncPresetOf(
    _project().mediaAssets.single,
    length: 20,
  );

  test('the preset places what a placement of it lands with — its span\'s '
      'first frame and count, its name tag and words — and nothing it '
      'cannot count before the sound\'s length is known', () {
    expect(preset, (
      start: 2,
      length: 6,
      fit: MediaFitMode.none,
      kind: LayerKind.se,
      nameTag: 'Door',
      words: 'bang',
    ));
    expect(
      syncPresetOf(
        MediaAsset(path: _clap, name: 'clap'),
        length: 20,
      ),
      (
        start: 0,
        length: 20,
        fit: MediaFitMode.none,
        kind: LayerKind.se,
        nameTag: 'SE',
        words: 'clap',
      ),
      reason: 'an untouched preset places the whole file as every sound',
    );
    expect(
      syncPresetOf(_project().mediaAssets.single, length: null),
      (
        start: null,
        length: null,
        fit: MediaFitMode.none,
        kind: LayerKind.se,
        nameTag: 'Door',
        words: 'bang',
      ),
    );
  });

  test('each place says where it parts from the preset, among the fields '
      'asked — a block shared by two counts both', () {
    final places = placesIn(_project());
    expect(
      [for (final place in places) (place.use as FrameMediaUse).frameId],
      const [FrameId('a'), FrameId('b')],
    );
    expect(places.first.lengths, [4, 4]);
    expect(
      [for (final place in places) place.partsFrom(MediaSyncField.asked)],
      [
        {MediaSyncField.start, MediaSyncField.length},
        {MediaSyncField.length},
      ],
    );
    expect(
      places.last.partsFrom(MediaSyncField.values.toSet()),
      {MediaSyncField.length, MediaSyncField.nameTag, MediaSyncField.words},
    );
    expect(
      placesIn(_project(), lengths: (sound: null, pictures: null))
          .first
          .partsFrom(MediaSyncField.asked),
      isEmpty,
      reason: 'a start and a length the preset cannot count part from '
          'nothing',
    );
  });

  test('syncing the start and the length sets every place\'s, the blocks '
      'through the comma edge — the one after pushed as a drag pushes it — '
      'and ONE undo takes all of it back', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    Layer row() => requireLayerAnywhere(
      session.repository.requireProject(),
      const LayerId('s1'),
    );
    final before = row();
    session.mediaPool.syncPlaces(
      _clap,
      fields: MediaSyncField.asked,
      places: placesIn(session.repository.requireProject()),
    );
    final after = row();
    expect(
      {
        for (final MapEntry(:key, :value) in after.timeline.entries)
          if (!value.ghost) key: (value.frameId, value.length),
      },
      {
        0: (const FrameId('a'), 6),
        6: (const FrameId('a'), 6),
        12: (const FrameId('b'), 6),
        18: (const FrameId('other'), 2),
      },
    );
    expect(
      [for (final clip in after.audioClips) clip.offsetFrames],
      [2, 2],
    );
    expect(
      [for (final frame in after.frames) (frame.seName, frame.name)],
      [for (final frame in before.frames) (frame.seName, frame.name)],
      reason: 'the name tag and the words were not asked for',
    );
    expect(
      placesIn(session.repository.requireProject()).map(
        (place) => place.partsFrom(MediaSyncField.values.toSet()),
      ),
      [
        {MediaSyncField.nameTag, MediaSyncField.words},
        {MediaSyncField.nameTag, MediaSyncField.words},
      ],
    );
    session.historyManager.undo();
    expect(row(), before);
  });

  test('syncing one place writes that block alone — its name tag, its '
      'words, where its sound starts — the other place and its sound kept', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    final places = placesIn(session.repository.requireProject());
    session.mediaPool.syncPlaces(
      _clap,
      fields: const {
        MediaSyncField.start,
        MediaSyncField.nameTag,
        MediaSyncField.words,
      },
      places: [places.last],
    );
    final row = requireLayerAnywhere(
      session.repository.requireProject(),
      const LayerId('s1'),
    );
    expect([for (final frame in row.frames) (frame.seName, frame.name)], [
      ('SE', 'clap'),
      ('Door', 'bang'),
      ('SE', 'step'),
    ]);
    expect(row.timeline[12]?.length, 3);
    expect([for (final clip in row.audioClips) clip.offsetFrames], [0, 2]);
  });

  test('the pool\'s mark turns into the sync where a place parts at its '
      'start or its length — not before the sound\'s length is known, not '
      'once every place is synced', () {
    final project = _project();
    final clap = project.mediaAssets.single;
    expect(partsFromItsPreset(project, clap, lengths: _known), isTrue);
    expect(
      partsFromItsPreset(
        project,
        clap,
        lengths: (sound: null, pictures: null),
      ),
      isFalse,
      reason: 'a start and a length the preset cannot count part from '
          'nothing',
    );
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    session.mediaPool.syncPlaces(
      _clap,
      fields: MediaSyncField.asked,
      places: placesIn(session.repository.requireProject()),
    );
    expect(
      partsFromItsPreset(
        session.repository.requireProject(),
        clap,
        lengths: _known,
      ),
      isFalse,
      reason: 'the name tag and the words still part, but the mark counts '
          'only what the window starts with on',
    );
  });
}
