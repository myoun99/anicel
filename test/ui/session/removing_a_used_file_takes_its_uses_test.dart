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
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart'
    show rederiveRunBehaviors;
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/media/media_asset_uses.dart';
import 'package:anicel/src/services/project_lookup.dart'
    show layerAnywhereOrNull;
import 'package:anicel/src/ui/editor_session_manager.dart';

const _movie = r'C:\media\walk.mp4';
const _clap = r'C:\media\clap.wav';

Frame _frame(String id, {String? name}) =>
    Frame(id: FrameId(id), duration: 1, strokes: const [], name: name);

Layer _picture(String id, {String? reference, String? ridesOn}) => Layer(
  id: LayerId(id),
  name: id,
  frames: [_frame('$id-cel')],
  timeline: {0: TimelineExposure.drawing(FrameId('$id-cel'), length: 4)},
  mediaReference: reference == null
      ? null
      : MediaReference(assetPath: reference),
  attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
);

Cut _cut(String id, List<Layer> layers) => Cut(
  id: CutId(id),
  name: id,
  duration: 12,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: layers,
);

/// An SE row as an edit leaves it: the rederive has put a hold's ghost in.
Layer _seRow(
  String id, {
  required List<Frame> frames,
  Map<int, TimelineExposure> timeline = const {},
  List<AudioClip> clips = const [],
}) => rederiveRunBehaviors(
  Layer(
    id: LayerId(id),
    name: id,
    kind: LayerKind.se,
    frames: frames,
    timeline: timeline,
    audioClips: clips,
  ),
  cutFrameCount: 12,
);

Project _project() => Project(
  id: const ProjectId('remove-a-used-file'),
  name: 'Remove a used file',
  createdAt: DateTime.utc(2026, 9, 15),
  mediaAssets: const [
    MediaAsset(path: _movie, name: 'walk.mp4'),
    MediaAsset(path: _clap, name: 'clap.wav'),
  ],
  tracks: [
    Track(
      id: const TrackId('t1'),
      name: 'Video',
      cuts: [
        _cut('c1', [
          _picture('plain'),
          _picture('walk', reference: _movie),
          // Rides ABOVE its base, where an attach row goes: the base comes
          // first in the stack's order and takes it along.
          _picture('walk-over', reference: _movie, ridesOn: 'walk'),
        ]),
        _cut('c2', [_picture('walk-again', reference: _movie)]),
      ],
      seLayers: [
        _seRow(
          's1',
          frames: [_frame('step', name: 'walk.mp4'), _frame('hit')],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('step'), length: 4),
            6: const TimelineExposure.drawing(
              FrameId('hit'),
              length: 2,
              endEdge: TimelineRunEdgeMark(mode: TimelineRunEdgeMode.hold),
            ),
          },
          clips: const [
            AudioClip(filePath: _movie, frameId: FrameId('step')),
            AudioClip(filePath: _clap, frameId: FrameId('hit')),
          ],
        ),
        // A frame no block shows: there is no block to delete, only a link.
        _seRow(
          's2',
          frames: [_frame('lonely')],
          clips: const [
            AudioClip(filePath: _movie, frameId: FrameId('lonely')),
          ],
        ),
      ],
    ),
    Track(
      id: const TrackId('t2'),
      name: 'Video 2',
      cuts: [
        _cut('c3', [_picture('other')]),
      ],
      seLayers: [
        _seRow(
          't2-s1',
          frames: [_frame('beat')],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('beat'), length: 3),
          },
          clips: const [
            AudioClip(filePath: _movie, frameId: FrameId('beat')),
          ],
        ),
        _seRow('t2-s2', frames: const []),
      ],
    ),
  ],
);

/// 🚨★★★A POOL FILE SOMETHING USES CAN BE REMOVED, AND ITS USES GO WITH IT
/// (F-118).
///
/// 유저 2026-09-12: 「풀에서 그냥 제거버튼 누르면 사용중인데 제거하겠습니까?
/// 배치한 레이어/프레임이 삭제됩니다. 라고 표시해서 강제삭제할수있게」. The
/// question is the panel's; this is what a yes does — through the verbs a
/// person uses on each kind of use, as one undo step.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('🚨removing a file takes every use with it — the rows placed '
      'from it in any cut, the blocks that carry it on any track, the link '
      'on a frame no block shows — leaves everything else as it was, and '
      'ONE undo brings all of it back', () {
    final session = EditorSessionManager(initialProject: _project());
    addTearDown(session.dispose);
    expect(
      session.activeCutId,
      const CutId('c1'),
      reason: 'fixture premise: the first cut is the one in hand',
    );

    List<(LayerId, FrameId?)> uses() => [
      for (final use in session.mediaPool.mediaAssetUses(_movie))
        switch (use) {
          RowMediaUse(:final layerId) => (layerId, null),
          FrameMediaUse(:final layerId, :final frameId) => (layerId, frameId),
        },
    ];
    expect(uses(), [
      (const LayerId('s1'), const FrameId('step')),
      (const LayerId('s2'), const FrameId('lonely')),
      (const LayerId('walk'), null),
      (const LayerId('walk-over'), null),
      (const LayerId('walk-again'), null),
      (const LayerId('t2-s1'), const FrameId('beat')),
    ], reason: 'fixture premise: every kind of use is there');

    Layer? layer(String id) => layerAnywhereOrNull(
      session.repository.requireProject(),
      LayerId(id),
    );
    final heldRow = layer('s1')!;
    expect(
      heldRow.timeline.values.where((entry) => entry.ghost),
      isNotEmpty,
      reason: 'fixture premise: the clap block holds to the end of the cut',
    );
    session.selectLayer(const LayerId('walk'));
    final before = session.repository.requireProject().toJson();

    expect(session.mediaPool.removeMediaAsset(_movie), isTrue);

    expect(uses(), isEmpty);
    expect(
      [for (final asset in session.mediaPool.mediaAssets) asset.path],
      [_clap],
    );
    for (final placed in ['walk', 'walk-over', 'walk-again']) {
      expect(layer(placed), isNull, reason: '$placed was placed from it');
    }
    expect(layer('plain'), isNotNull);
    expect(layer('other'), isNotNull);

    // The sound's block went, and its frame and its link with it. The clap
    // beside it keeps its block, its link and the hold its block carries —
    // re-derived over the same cut the row is edited through by hand.
    expect(layer('s1')!.timeline, {
      for (final entry in heldRow.timeline.entries)
        if (entry.key != 0) entry.key: entry.value,
    });
    expect([for (final frame in layer('s1')!.frames) frame.id], [
      const FrameId('hit'),
    ]);
    expect(layer('s1')!.audioClips, const [
      AudioClip(filePath: _clap, frameId: FrameId('hit')),
    ]);
    // No block shows this frame, so the frame stays and the link goes.
    expect([for (final frame in layer('s2')!.frames) frame.id], [
      const FrameId('lonely'),
    ]);
    expect(layer('s2')!.audioClips, isEmpty);
    // A row of the track that is not in hand.
    expect(layer('t2-s1')!.timeline, isEmpty);
    expect(layer('t2-s1')!.frames, isEmpty);
    expect(layer('t2-s1')!.audioClips, isEmpty);

    // The rows in hand follow the stack: the deleted row is not held.
    expect(
      [for (final row in session.layers) row.id],
      isNot(contains(const LayerId('walk'))),
    );
    expect(session.activeLayerId, isNot(const LayerId('walk')));

    session.undo();
    expect(session.repository.requireProject().toJson(), before);
  });
}
