import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/storyboard_timeline_layout.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_playhead_mapping.dart';

/// I-22: the storyboard's green bar answers in stretches — each cut for
/// its own frames, shifted to where the track lays it, the gaps ready by
/// definition, and a frame two entries cover belonging to the FIRST, as
/// it did when the bar asked frame by frame.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  /// Four frames: a drawn cel at 0..1 (not baked in these tests), then a
  /// hole at 2..3 that composes to nothing.
  final drawn = Cut(
    id: const CutId('drawn'),
    name: '1',
    duration: 4,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: const LayerId('layer'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('frame-a'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('frame-a'), length: 2),
        },
      ),
    ],
  );

  /// Nothing to compose anywhere — ready at every frame.
  final empty = Cut(
    id: const CutId('empty'),
    name: '2',
    duration: 8,
    canvasSize: canvasSize,
    layers: const [],
  );

  EditorSessionManager session() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'P',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(id: const TrackId('track'), name: 'T', cuts: [drawn, empty]),
      ],
    ),
  );

  StoryboardTimelineLayoutEntry at(Cut cut, int startFrame) =>
      StoryboardTimelineLayoutEntry(
        trackId: const TrackId('track'),
        cutId: cut.id,
        trackIndex: 0,
        cutIndex: 0,
        startFrame: startFrame,
        endFrame: startFrame + cut.duration,
        duration: cut.duration,
        cut: cut,
      );

  testWidgets('a cut answers for its own frames where the track lays it, '
      'and the gaps around it are ready', (tester) async {
    final s = session();
    addTearDown(s.dispose);

    expect(storyboardReadyRuns(s, 0, 20, layout: [at(drawn, 10)]), [
      (startIndex: 0, endIndexExclusive: 10),
      (startIndex: 12, endIndexExclusive: 20),
    ]);
  });

  testWidgets('a cut answers only up to its own end — the next cut answers '
      'for the frames after it', (tester) async {
    final s = session();
    addTearDown(s.dispose);

    expect(
      storyboardReadyRuns(s, 0, 12, layout: [at(empty, 0), at(drawn, 8)]),
      [
        (startIndex: 0, endIndexExclusive: 8),
        (startIndex: 10, endIndexExclusive: 12),
      ],
      reason: '8..9 are the drawn cut\'s unbaked cel — the empty cut before '
          'it ends at 8 and has no say there',
    );
  });

  testWidgets('a frame two entries cover belongs to the first', (
    tester,
  ) async {
    final s = session();
    addTearDown(s.dispose);

    expect(
      storyboardReadyRuns(s, 8, 16, layout: [at(drawn, 10), at(empty, 8)]),
      [
        (startIndex: 8, endIndexExclusive: 10),
        (startIndex: 12, endIndexExclusive: 16),
      ],
      reason: '10..11 are the drawn cut\'s unbaked cel — the empty cut '
          'under it must not answer for them',
    );
  });

  testWidgets('a window inside one cut asks that cut for exactly itself', (
    tester,
  ) async {
    final s = session();
    addTearDown(s.dispose);

    expect(storyboardReadyRuns(s, 11, 13, layout: [at(drawn, 10)]), [
      (startIndex: 12, endIndexExclusive: 13),
    ]);
  });
}
