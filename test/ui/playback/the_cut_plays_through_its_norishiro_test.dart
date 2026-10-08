import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

/// 🗣️F-227 (유저 2026-09-29): 「재생도 타임라인패널의 재생이면 여백까지 재생」.
///
/// A cut plays every frame it is DRAWN for: the timeline panel's playback
/// runs through the のりしろ an O.L asks of it, and while ANY playback runs,
/// the frames an O.L composites — each cut's のりしろ — are WANTED like the
/// rest of what plays: the warmer makes them, and the budget keeps them by
/// when the run shows them.
void main() {
  const leaving = CutId('a');
  const arriving = CutId('b');

  Cut cut(CutId id) => Cut(
    id: id,
    name: id.value,
    duration: 24,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: [
      Layer(
        id: LayerId('row-${id.value}'),
        name: 'A',
        frames: [
          Frame(id: FrameId('cel-${id.value}'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('cel-${id.value}'), length: 24),
        },
      ),
    ],
  );

  /// Two 24-frame cuts, standing in the first; an O.L over frames 18..29
  /// when [overlapped] — six frames of のりしろ on each side of the cut.
  EditorSessionManager session({required bool overlapped}) {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'T',
            cuts: [cut(leaving), cut(arriving)],
          ),
        ],
      ),
    );
    if (overlapped) {
      s.transitions.updateTransitionInstructions({
        18: const InstructionEvent(instructionId: 'ol', length: 12),
      });
    }
    return s;
  }

  /// Starts [scope]'s playback, reads what it asked for, and stands the run
  /// down INSIDE the test — the warm's zero-length yield timer otherwise
  /// trips the binding's timer invariant before the teardown dispose. Stop
  /// FIRST: stopping lands the playhead, which asks for a warm of its own.
  Future<T> whilePlaying<T>(
    WidgetTester tester,
    EditorSessionManager s,
    PlaybackScope scope,
    T Function() read,
  ) async {
    s.playbackRig.playback.play(scope: scope);
    final result = read();
    s.playbackRig.playback.stop();
    s.playbackRig.prerenderScheduler.cancel();
    await tester.pump();
    return result;
  }

  testWidgets('the timeline panel plays the cut through its のりしろ', (
    tester,
  ) async {
    final s = session(overlapped: true);
    addTearDown(s.dispose);
    final playlist = s.playbackRig.playback.playlistForScope(
      PlaybackScope.activeCut,
    );
    expect(playlist.single.cutId, leaving);
    expect(playlist.single.endFrame, 30, reason: '24 + 6 of のりしろ');
  });

  testWidgets('CONTROL: with nothing crossing it plays to the red line', (
    tester,
  ) async {
    final s = session(overlapped: false);
    addTearDown(s.dispose);
    final playlist = s.playbackRig.playback.playlistForScope(
      PlaybackScope.activeCut,
    );
    expect(playlist.single.endFrame, 24);
  });

  testWidgets('while the storyboard plays, each cut is wanted through every '
      'frame it is drawn for — the O.L composites both のりしろ', (
    tester,
  ) async {
    final s = session(overlapped: true);
    addTearDown(s.dispose);
    final read = await whilePlaying(tester, s, PlaybackScope.allCuts, () {
      final demand = s.playbackRig.demand!;
      final wanted = <CutId, Set<int>>{};
      for (var step = 0; step < demand.length; step += 1) {
        for (final picture in demand.picturesAt(step)!) {
          (wanted[picture.cut.id] ??= {}).add(picture.frameIndex);
        }
      }
      return (
        wanted: wanted,
        length: demand.length,
        lastOfLeaving: demand.stepOf(leaving, 29),
        firstOfArriving: demand.stepOf(arriving, 0),
        pastTheLeaving: demand.stepOf(leaving, 30),
      );
    });
    final thirty = {for (var frame = 0; frame < 30; frame += 1) frame};
    expect(read.wanted, {leaving: thirty, arriving: thirty});
    expect(read.length, 48, reason: 'the film is two cuts of 24');
    expect(read.lastOfLeaving, 29, reason: 'its tail のりしろ ends there');
    expect(
      read.firstOfArriving,
      18,
      reason: 'its material starts six frames ahead of its conte start',
    );
    expect(
      read.pastTheLeaving,
      isNull,
      reason: 'a frame the film does not show of the cut is wanted by no '
          'step — the budget lets it go first',
    );
  });

  testWidgets('a cut playing alone wants its own frames and no other '
      'cut\'s — and, played once, only what is left of it', (tester) async {
    final s = session(overlapped: true);
    addTearDown(s.dispose);
    s.playbackRig.playback.loopMode = PlaybackLoopMode.once;
    final read = await whilePlaying(tester, s, PlaybackScope.activeCut, () {
      s.playbackRig.playback.seekToGlobalFrame(10);
      final demand = s.playbackRig.demand!;
      return (
        length: demand.length,
        last: demand.stepOf(leaving, 29),
        behind: demand.stepOf(leaving, 5),
        other: demand.stepOf(arriving, 15),
      );
    });
    expect(read.length, 20, reason: 'thirty frames drawn, ten behind');
    expect(read.last, 19);
    expect(read.behind, isNull, reason: 'played once, it is not shown again');
    expect(read.other, isNull, reason: 'the run does not show the next cut');
  });

  testWidgets('the warmer follows the run it plays: the film\'s frames, '
      'one walk', (tester) async {
    final s = session(overlapped: true);
    addTearDown(s.dispose);
    final total = await whilePlaying(
      tester,
      s,
      PlaybackScope.allCuts,
      () => s.playbackRig.prerenderScheduler.progress.value.total,
    );
    expect(total, 48, reason: 'a walk is counted in the run\'s frames');
  });
}
