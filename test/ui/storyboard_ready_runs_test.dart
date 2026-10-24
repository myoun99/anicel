import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
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

import '../helpers/draw_on_current_frame.dart';

/// I-22: the storyboard's green bar answers in stretches — each cut for
/// its own frames, shifted to where the track lays it, the gaps ready by
/// definition, and a frame two entries cover belonging to the FIRST, as
/// it did when the bar asked frame by frame.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  /// Four frames: a drawn cel at 0..1 (inked by [session], and made by
  /// none of these tests but the last), then a hole at 2..3 with nothing to
  /// make.
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

  /// The session, its drawn cel inked: a cel with nothing on it has no
  /// picture to wait for.
  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(id: const TrackId('track'), name: 'T', cuts: [drawn, empty]),
        ],
      ),
    );
    inkCel(
      s,
      s.brushFrameKeyForCut(
        drawn,
        const LayerId('layer'),
        const FrameId('frame-a'),
      ),
      canvasSize: canvasSize,
      at: CanvasPoint(x: 4, y: 4),
      size: 4,
    );
    return s;
  }

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
      (startIndex: 0, endIndexExclusive: 10, unreadable: false),
      (startIndex: 12, endIndexExclusive: 20, unreadable: false),
    ]);
  });

  testWidgets('a cut answers only up to its own end — the next cut answers '
      'for the frames after it', (tester) async {
    final s = session();
    addTearDown(s.dispose);

    expect(
      storyboardReadyRuns(s, 0, 12, layout: [at(empty, 0), at(drawn, 8)]),
      [
        (startIndex: 0, endIndexExclusive: 8, unreadable: false),
        (startIndex: 10, endIndexExclusive: 12, unreadable: false),
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
        (startIndex: 8, endIndexExclusive: 10, unreadable: false),
        (startIndex: 12, endIndexExclusive: 16, unreadable: false),
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
      (startIndex: 12, endIndexExclusive: 13, unreadable: false),
    ]);
  });

  // 유저 2026-10-16 (frame-picture-indicator-Q1 b): a cel the project's file
  // does not hold is red on the bar over the frames it shows.
  testWidgets('🚨a cel that cannot be read is red where the track lays its '
      'cut — a stretch of its own, not run into the ready frames around '
      'it', (tester) async {
    final s = session();
    addTearDown(s.dispose);
    // How the cache keeps a cel whose reading threw.
    s.renderCaches.layerFrameImageCache.unreadable.note(
      s.brushFrameKeyForCut(
        drawn,
        const LayerId('layer'),
        const FrameId('frame-a'),
      ),
    );

    expect(storyboardReadyRuns(s, 0, 20, layout: [at(drawn, 10)]), [
      (startIndex: 0, endIndexExclusive: 10, unreadable: false),
      (startIndex: 10, endIndexExclusive: 12, unreadable: true),
      (startIndex: 12, endIndexExclusive: 20, unreadable: false),
    ]);
  });

  testWidgets('🚨the storyboard\'s bar counts the FILM\'s pictures — the '
      'canvas\'s own, which a cut played alone shows too: what one made, '
      'both bars count', (tester) async {
    await tester.runAsync(() async {
      final s = session();
      addTearDown(s.dispose);
      final cut = s.activeCutOrNull!;
      await s.playbackRig.canvasPictures.make((
        cut: cut,
        frameIndex: 0,
        paintPaper: true,
      ), shouldAbort: () => false);
      expect(
        s.playbackRig.playbackCache.playbackReadyRuns(0, 4),
        [(startIndex: 0, endIndexExclusive: 4, unreadable: false)],
        reason: '⛔premise: the timeline\'s bar is green — its run plays on '
            'the canvas, from those very pictures',
      );

      expect(
        storyboardReadyRuns(s, 0, 4, layout: [at(cut, 0)]),
        [(startIndex: 0, endIndexExclusive: 4, unreadable: false)],
        reason: 'the film shows a frame from those very images. ↩️It played '
            'on composites, and its bar stayed grey over pictures it never '
            'showed (until 2026-10-10)',
      );
    });
  });
}
