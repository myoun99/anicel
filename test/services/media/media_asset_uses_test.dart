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
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/media/media_asset_uses.dart';

/// 🚨★★★WHERE A POOL FILE IS USED IS ONE ANSWER (F-118).
///
/// 유저 2026-09-12: 「미디어풀의 타임라인에서 쓰는중 버튼, 정확히 어디서
/// 쓰는건지 모르겠음 … 어디서 쓰는지 리스트로 표시하도록」 — and a remove
/// that asks and then takes the uses away. The mark, the list and the
/// removal all read [mediaAssetUsesOf].
void main() {
  const movie = r'C:\media\walk.mp4';
  const clap = r'C:\media\clap.wav';

  Frame frame(String id, {String? name}) =>
      Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

  Layer picture(String id, String name, {String? reference}) => Layer(
    id: LayerId(id),
    name: name,
    frames: [frame('$id-cel')],
    timeline: {0: TimelineExposure.drawing(FrameId('$id-cel'), length: 4)},
    mediaReference: reference == null
        ? null
        : MediaReference(assetPath: reference),
  );

  Cut cut(String id, String name, List<Layer> layers) => Cut(
    id: CutId(id),
    name: name,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: layers,
  );

  final project = Project(
    id: const ProjectId('uses'),
    name: 'Uses',
    createdAt: DateTime.utc(2026, 9, 15),
    tracks: [
      Track(
        id: const TrackId('video'),
        name: 'Video',
        cuts: [
          cut('c1', 'C1', [
            picture('plain', 'A'),
            picture('walk-1', 'walk', reference: movie),
          ]),
          cut('c2', 'C2', [
            picture('walk-2', 'walk again', reference: movie),
          ]),
        ],
        seLayers: [
          Layer(
            id: const LayerId('s1'),
            name: 'S1',
            kind: LayerKind.se,
            frames: [
              frame('step', name: 'walk.mp4'),
              frame('blank', name: ' '),
              frame('hit', name: 'clap'),
            ],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('step'), length: 4),
              4: const TimelineExposure.drawing(FrameId('blank'), length: 2),
              6: const TimelineExposure.drawing(FrameId('hit'), length: 2),
            },
            audioClips: [
              AudioClip(filePath: movie, frameId: const FrameId('step')),
              // The same frame linking the file twice is ONE use.
              AudioClip(
                filePath: movie,
                frameId: const FrameId('step'),
                offsetFrames: 2,
              ),
              AudioClip(filePath: movie, frameId: const FrameId('blank')),
              AudioClip(filePath: clap, frameId: const FrameId('hit')),
              // REC1-A: a link to a frame the row no longer holds.
              AudioClip(filePath: movie, frameId: const FrameId('gone')),
            ],
          ),
        ],
      ),
    ],
  );

  String described(MediaAssetUse use) => switch (use) {
    RowMediaUse(
      :final cutId,
      :final layerId,
      :final ownerName,
      :final layerName,
    ) =>
      'row ${cutId.value}/${layerId.value} = $ownerName · $layerName',
    FrameMediaUse(
      :final trackId,
      :final cutId,
      :final layerId,
      :final frameId,
      :final place,
    ) =>
      'frame ${trackId.value}/${cutId?.value}/${layerId.value}/'
          '${frameId.value} = ${place.ownerName} · ${place.layerName} · '
          '${place.celName}',
  };

  List<String> usesOf(String path) => [
    for (final use in mediaAssetUsesOf(project, path)) described(use),
  ];

  test('🚨every use of the file, in the order the project holds its rows — '
      'the frames that carry it as a sound, once each and only while the row '
      'holds them, then the rows placed from it', () {
    expect(usesOf(movie), [
      'frame video/null/s1/step = Video · S1 · walk.mp4',
      // A frame named nothing is found by the mark the timeline prints.
      'frame video/null/s1/blank = Video · S1 · $unnamedDrawingMark',
      'row c1/walk-1 = C1 · walk',
      'row c2/walk-2 = C2 · walk again',
    ]);
  });

  test('a file used somewhere else has only its own uses, and a file '
      'nothing uses has none', () {
    expect(usesOf(clap), ['frame video/null/s1/hit = Video · S1 · clap']);
    expect(mediaAssetUsesOf(project, r'C:\media\unused.png'), isEmpty);
  });
}
