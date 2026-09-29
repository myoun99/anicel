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
import 'package:anicel/src/ui/session/playback_cache_budget.dart';

/// 🗣️F-227 (유저 2026-09-29): 「재생도 타임라인패널의 재생이면 여백까지 재생」.
///
/// A cut plays every frame it is DRAWN for: the timeline panel's playback
/// runs through the のりしろ an O.L asks of it, and while ANY playback runs,
/// the frames an O.L composites — each cut's のりしろ — are protected like
/// the rest of what plays.
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

  PlaybackCacheBudget budgetOf(EditorSessionManager s) =>
      s.playbackRig.playbackCache;

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

  testWidgets('while the storyboard plays, each cut keeps every frame it is '
      'drawn for — the O.L composites both のりしろ', (tester) async {
    final s = session(overlapped: true);
    addTearDown(s.dispose);
    final ends = await whilePlaying(tester, s, PlaybackScope.allCuts, () => {
      for (final range in budgetOf(s).debugPlaybackProtectedRanges())
        range.cutId: range.endFrame,
    });
    expect(ends, {leaving: 29, arriving: 29});
  });

  testWidgets('the storyboard\'s playback WARMS every frame each cut is drawn '
      'for — the のりしろ an O.L composites included', (tester) async {
    final s = session(overlapped: true);
    addTearDown(s.dispose);
    final total = await whilePlaying(
      tester,
      s,
      PlaybackScope.allCuts,
      () => s.playbackRig.prerenderScheduler.progress.value.total,
    );
    expect(total, 60, reason: '(24 + 6) + (24 + 6)');
  });
}
