import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// #16 — 유저: 「스토리보드패널에서 S행의 프레임생성이 안됨.」
///
/// The S-row drag writes the TRACK selection, and its claim clears the
/// cut-local selection the create verb used to read — so creation fell
/// through to the stale active layer, the wrong row entirely. The ladder
/// rung was missing; delete and edit already had theirs.
void main() {
  const trackId = TrackId('track');
  final seLayerId = seLayerIdForTrack(trackId, 1);

  Cut cut(String id, {int leadingGap = 0}) => Cut(
    id: CutId(id),
    name: id,
    duration: 4,
    leadingGapFrames: leadingGap,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      Layer(
        id: LayerId('$id-layer'),
        name: 'A',
        frames: [
          Frame(id: FrameId('$id-frame'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('$id-frame'), length: 2),
        },
      ),
    ],
  );

  EditorSessionManager session({Layer? seedSe}) => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'P',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: trackId,
          name: 'T',
          // ⚠️The active cut starts at GLOBAL 5, on purpose: the fills
          // funnel re-applies the track-SE display lens (+cut start), so
          // a rung that forgot to pre-subtract lands every entry five
          // frames late — and a cut at 0 would hide exactly that.
          cuts: [cut('a', leadingGap: 5)],
          seLayers: [seedSe ?? createTrackSeLayer(trackId: trackId, slot: 1)],
        ),
      ],
    ),
  );

  Layer seLayerOf(EditorSessionManager s) =>
      s.repository.requireProject().tracks.single.seLayers.single;

  TrackFrameRangeSelection range({
    TimelineRowAddress? anchor,
    int start = 10,
    int end = 14,
  }) => TrackFrameRangeSelection(
    trackId: trackId,
    anchorRow: anchor ?? LayerRowAddress(seLayerId),
    startFrame: start,
    endFrameExclusive: end,
  );

  test('an S-row range creates one blank entry over the range, at the '
      'GLOBAL frames the storyboard named', () {
    final s = session();
    addTearDown(s.dispose);
    s.trackFrameRangeSelection.value = range();

    expect(s.createInstancesForSelection(), isTrue);

    final timeline = seLayerOf(s).timeline;
    expect(
      timeline[10],
      isNotNull,
      reason: 'the entry starts where the drag started — a rung that '
          'forgot the display lens would land this at 15',
    );
    expect(timeline[10]!.length, 4);
    final frame = seLayerOf(s).frames.single;
    expect(
      frame.name,
      isNull,
      reason: 'a blank dialogue — the fills funnel normalizes empty to '
          'null, the model\'s own convention for "not written yet"',
    );
  });

  test('covered frames split the fill — existing entries are never '
      'touched, and one undo removes everything the verb made', () {
    final seeded = createTrackSeLayer(trackId: trackId, slot: 1).copyWith(
      frames: [
        Frame(id: const FrameId('kept'), duration: 1, strokes: const []),
      ],
      timeline: {
        11: const TimelineExposure.drawing(FrameId('kept'), length: 2),
      },
    );
    final s = session(seedSe: seeded);
    addTearDown(s.dispose);
    s.trackFrameRangeSelection.value = range();

    expect(s.createInstancesForSelection(), isTrue);

    final timeline = seLayerOf(s).timeline;
    expect(timeline[10]!.length, 1, reason: 'the run before the block');
    expect(timeline[11]!.frameId, const FrameId('kept'));
    expect(timeline[13]!.length, 1, reason: 'the run after the block');

    s.undo();
    final restored = seLayerOf(s).timeline;
    expect(restored.length, 1, reason: 'one undo step for the whole verb');
    expect(restored[11]!.frameId, const FrameId('kept'));
  });

  test('a range that names no S row falls down the ladder untouched', () {
    final s = session();
    addTearDown(s.dispose);
    s.trackFrameRangeSelection.value = range(
      anchor: const TrackRowAddress(TrackId('track')),
    );

    expect(
      s.createInstancesForSelection(),
      isFalse,
      reason: 'a cut-row range is the cut pill\'s business (#18)',
    );
    expect(seLayerOf(s).timeline, isEmpty);
  });
}
