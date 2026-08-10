import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transition_geometry.dart';
import 'package:anicel/src/services/playback/playback_frame_mapping.dart';
import 'package:anicel/src/ui/storyboard_timeline_layout.dart';

void main() {
  Cut cut(String id, int duration) => Cut(
    id: CutId(id),
    name: id,
    layers: const [],
    duration: duration,
    canvasSize: const CanvasSize(width: 8, height: 8),
  );

  List<StoryboardTimelineLayoutEntry> playlist() {
    return buildStoryboardTimelineLayout(
      Project(
        id: const ProjectId('project'),
        name: 'Project',
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [cut('cut-a', 4), cut('cut-b', 6)],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
  }

  test('elapsedToGlobalFrame maps wall clock to frames at fps', () {
    const fps24 = ProjectFrameRate.integer(24);
    const fps12 = ProjectFrameRate.integer(12);
    expect(elapsedToGlobalFrame(Duration.zero, fps24), 0);
    expect(elapsedToGlobalFrame(const Duration(milliseconds: 41), fps24), 0);
    expect(elapsedToGlobalFrame(const Duration(milliseconds: 42), fps24), 1);
    expect(elapsedToGlobalFrame(const Duration(seconds: 1), fps24), 24);
    expect(elapsedToGlobalFrame(const Duration(seconds: 2), fps12), 24);
  });

  test('23.976 runs slower than 24 by exactly the NTSC 1000/1001', () {
    const ntsc = ProjectFrameRate.ntsc(24);
    // One second of wall clock shows frame 23, not 24 — the pulldown rate
    // genuinely is slower, and the clock must not round that away.
    expect(elapsedToGlobalFrame(const Duration(seconds: 1), ntsc), 23);
    // 1001/1000 seconds is exactly 24 frames.
    expect(elapsedToGlobalFrame(const Duration(milliseconds: 1001), ntsc), 24);
  });

  test('the clock does not drift over an hour of playback', () {
    // The failure this whole program exists to prevent: a rate held as a
    // double accumulates error, and after an hour the picture and the
    // sound are seconds apart. Frame N must land on frame N no matter how
    // far from zero it is, so we check the clock against the exact frame
    // boundary at the one-hour mark rather than integrating small steps.
    for (final rate in const [
      ProjectFrameRate.integer(24),
      ProjectFrameRate.ntsc(24),
      ProjectFrameRate.ntsc(30),
    ]) {
      final anHourOfFrames = rate.countingBase * 60 * 60;
      final boundary = rate.frameStart(anHourOfFrames);
      expect(
        elapsedToGlobalFrame(boundary, rate),
        anHourOfFrames,
        reason: '$rate lands exactly on its own frame boundary',
      );
      expect(
        elapsedToGlobalFrame(
          boundary - const Duration(microseconds: 1),
          rate,
        ),
        anHourOfFrames - 1,
        reason: '$rate is still on the previous frame a microsecond before',
      );
    }
  });

  test('resolvePlaybackPosition finds the cut and local frame', () {
    final entries = playlist();

    final inFirst = resolvePlaybackPosition(
      playlist: entries,
      globalFrameIndex: 3,
    )!;
    expect(inFirst.cutId, const CutId('cut-a'));
    expect(inFirst.localFrameIndex, 3);

    final inSecond = resolvePlaybackPosition(
      playlist: entries,
      globalFrameIndex: 4,
    )!;
    expect(inSecond.cutId, const CutId('cut-b'));
    expect(inSecond.localFrameIndex, 0);

    expect(
      resolvePlaybackPosition(playlist: entries, globalFrameIndex: 10),
      isNull,
    );
    expect(
      resolvePlaybackPosition(playlist: entries, globalFrameIndex: -1),
      isNull,
    );
  });

  test('playlistTotalFrames sums sequential cut durations', () {
    expect(playlistTotalFrames(playlist()), 10);
    expect(playlistTotalFrames(const []), 0);
  });

  test('gap frames resolve to null (black) but still count toward the '
      'total', () {
    final entries = buildStoryboardTimelineLayout(
      Project(
        id: const ProjectId('gap-project'),
        name: 'Gaps',
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              cut('cut-a', 4),
              Cut(
                id: const CutId('cut-b'),
                name: 'cut-b',
                layers: const [],
                duration: 6,
                leadingGapFrames: 3,
                canvasSize: const CanvasSize(width: 8, height: 8),
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );

    // Frames 4..6 sit in the gap: no cut plays there.
    expect(
      resolvePlaybackPosition(playlist: entries, globalFrameIndex: 3),
      isNotNull,
    );
    for (var frame = 4; frame < 7; frame += 1) {
      expect(
        resolvePlaybackPosition(playlist: entries, globalFrameIndex: frame),
        isNull,
        reason: 'frame $frame is in the gap',
      );
    }
    final afterGap = resolvePlaybackPosition(
      playlist: entries,
      globalFrameIndex: 7,
    )!;
    expect(afterGap.cutId, const CutId('cut-b'));
    expect(afterGap.localFrameIndex, 0);

    // The playback clock runs THROUGH the gap: total = last end.
    expect(playlistTotalFrames(entries), 13);
  });

  group('resolveTrackStackPositions (multitrack display path)', () {
    // track-1: cut-a [0,4) then cut-b [7,13) (3-frame gap between).
    // track-2: cut-c [2,12) (2-frame leading gap). Axes overlap on
    // purpose: every track starts at global 0 independently.
    List<StoryboardTimelineLayoutEntry> layout() {
      return buildStoryboardTimelineLayout(
        Project(
          id: const ProjectId('stack-project'),
          name: 'Stack',
          tracks: [
            Track(
              id: const TrackId('track-1'),
              name: 'One',
              cuts: [
                cut('cut-a', 4),
                Cut(
                  id: const CutId('cut-b'),
                  name: 'cut-b',
                  layers: const [],
                  duration: 6,
                  leadingGapFrames: 3,
                  canvasSize: const CanvasSize(width: 8, height: 8),
                ),
              ],
            ),
            Track(
              id: const TrackId('track-2'),
              name: 'Two',
              cuts: [
                Cut(
                  id: const CutId('cut-c'),
                  name: 'cut-c',
                  layers: const [],
                  duration: 10,
                  leadingGapFrames: 2,
                  canvasSize: const CanvasSize(width: 8, height: 8),
                ),
              ],
            ),
          ],
          createdAt: DateTime.utc(2026),
        ),
      );
    }

    test('a frame covered on both tracks answers once per track, in track '
        'order (paint order: later tracks on top)', () {
      final positions = resolveTrackStackPositions(
        layout: layout(),
        globalFrameIndex: 3,
      );
      expect(positions, hasLength(2));
      expect(positions[0].cutId, const CutId('cut-a'));
      expect(positions[0].localFrameIndex, 3);
      expect(positions[1].cutId, const CutId('cut-c'));
      expect(positions[1].localFrameIndex, 1);
    });

    test('a gap on one track drops just that track', () {
      // Frame 5 gaps on track-1 (between cut-a and cut-b).
      final positions = resolveTrackStackPositions(
        layout: layout(),
        globalFrameIndex: 5,
      );
      expect(positions, hasLength(1));
      expect(positions.single.cutId, const CutId('cut-c'));
      expect(positions.single.localFrameIndex, 3);
    });

    test('strict containment: past a short track\'s last cut is ABSENT — '
        'never the editing axis\'s owner-rule runway', () {
      // Frame 12: track-2's cut-c ended at 12 (exclusive); track-1's
      // cut-b still covers.
      final positions = resolveTrackStackPositions(
        layout: layout(),
        globalFrameIndex: 12,
      );
      expect(positions, hasLength(1));
      expect(positions.single.cutId, const CutId('cut-b'));
      expect(positions.single.localFrameIndex, 5);
    });

    test('leading gaps and frames past every track resolve empty', () {
      expect(
        resolveTrackStackPositions(layout: layout(), globalFrameIndex: 0),
        [isA<PlaybackPosition>()],
        reason: 'frame 0: only track-1 (track-2 still in its leading gap)',
      );
      expect(
        resolveTrackStackPositions(
          layout: layout(),
          globalFrameIndex: 0,
        ).single.cutId,
        const CutId('cut-a'),
      );
      expect(
        resolveTrackStackPositions(layout: layout(), globalFrameIndex: 13),
        isEmpty,
      );
      expect(
        resolveTrackStackPositions(layout: layout(), globalFrameIndex: -1),
        isEmpty,
      );
    });
  });

  group('resolveTransitionContributions', () {
    // cut-a is [0, 4), cut-b is [4, 10). A 4-frame O.L centred on the
    // boundary runs [2, 6): each side owes 2 frames of のりしろ.
    const ol = (start: 2, length: 4);

    List<TransitionContribution> at(int frame, {List<TransitionSpan> spans = const []}) =>
        resolveTransitionContributions(
          playlist: playlist(),
          spans: spans,
          globalFrameIndex: frame,
        );

    test('without transitions it answers exactly like the single resolver', () {
      for (var frame = 0; frame < 10; frame += 1) {
        final contributions = at(frame);
        final single = resolvePlaybackPosition(
          playlist: playlist(),
          globalFrameIndex: frame,
        );

        expect(contributions, hasLength(1), reason: 'frame $frame');
        expect(contributions.single.cut.id, single!.cutId);
        expect(contributions.single.localFrameIndex, single.localFrameIndex);
        expect(contributions.single.opacity, 1.0);
      }
    });

    test('outside every cut it answers nothing', () {
      expect(at(-1), isEmpty);
      expect(at(10), isEmpty);
    });

    test('inside the O.L both cuts arrive, outgoing first', () {
      final contributions = at(3, spans: const [ol]);

      expect(contributions, hasLength(2));
      expect(contributions[0].cut.id, const CutId('cut-a'));
      expect(contributions[1].cut.id, const CutId('cut-b'));
    });

    test('their opacities are the two halves of one ramp', () {
      for (final frame in [2, 3, 4, 5]) {
        final contributions = at(frame, spans: const [ol]);
        expect(contributions, hasLength(2), reason: 'frame $frame');
        expect(
          contributions[0].opacity + contributions[1].opacity,
          closeTo(1.0, 1e-9),
          reason: 'frame $frame',
        );
      }
      expect(at(2, spans: const [ol])[0].opacity, 1.0);
      expect(at(5, spans: const [ol])[1].opacity, 1.0);
    });

    test('the incoming cut supplies frames before its own block', () {
      // cut-b starts at global 4 but owes a 2-frame head handle, so its
      // frame 0 sits at global 2 — the block itself never moved.
      final early = at(2, spans: const [ol]);

      expect(early[1].cut.id, const CutId('cut-b'));
      expect(early[1].localFrameIndex, 0);
      expect(at(4, spans: const [ol])[1].localFrameIndex, 2);
    });

    test('the outgoing cut keeps supplying past its own block', () {
      final late = at(5, spans: const [ol]);

      expect(late[0].cut.id, const CutId('cut-a'));
      // 4 frames of conte plus the 2-frame tail handle: local 5 is the last.
      expect(late[0].localFrameIndex, 5);
      expect(at(6, spans: const [ol]).map((c) => c.cut.id), [
        const CutId('cut-b'),
      ]);
    });

    test('a span inside one cut leaves the frame alone', () {
      expect(at(1, spans: const [(start: 0, length: 3)]), hasLength(1));
      expect(at(1, spans: const [(start: 0, length: 3)]).single.opacity, 1.0);
    });
  });

  group('sourceOverWeights', () {
    /// What source-over ACTUALLY produces: paint bottom to top, each weight
    /// over what is already there. Returns (per-picture share, floor share) —
    /// the oracle the formula has to satisfy, computed independently of it.
    (List<double>, double) composited(List<double> weights) {
      final shares = List<double>.filled(weights.length, 0);
      var floor = 1.0;
      for (var i = 0; i < weights.length; i += 1) {
        final w = weights[i];
        for (var j = 0; j < i; j += 1) {
          shares[j] *= 1 - w;
        }
        floor *= 1 - w;
        shares[i] = w;
      }
      return (shares, floor);
    }

    test('one contribution paints at its own share, so a lone F.O really does '
        'fade to the floor', () {
      expect(sourceOverWeights([0.4]), [closeTo(0.4, 1e-9)]);
      final (shares, floor) = composited(sourceOverWeights([0.4]));
      expect(shares.single, closeTo(0.4, 1e-9));
      expect(floor, closeTo(0.6, 1e-9));
    });

    test('an O.L pair lays the leaving cut down OPAQUE — its own share would '
        'leave t(1-t) of the floor showing mid-dissolve', () {
      for (final t in [0.0, 0.25, 1 / 3, 0.5, 0.75, 1.0]) {
        final weights = sourceOverWeights([1 - t, t]);
        // The leaving cut goes down opaque for as long as it is there at all;
        // at t == 1 it is gone, and a weight of 1 would freeze it on screen.
        expect(weights[0], closeTo(t < 1 ? 1.0 : 0.0, 1e-9), reason: 't=$t');
        expect(weights[1], closeTo(t, 1e-9), reason: 't=$t');

        // The contract that actually matters, checked independently of the
        // formula: the mix is the ramp and the floor never shows.
        final (shares, floor) = composited(weights);
        expect(shares[0], closeTo(1 - t, 1e-9), reason: 't=$t');
        expect(shares[1], closeTo(t, 1e-9), reason: 't=$t');
        expect(floor, closeTo(0.0, 1e-9), reason: 'no dip to black at t=$t');
      }

      // The naive version, for contrast: at t=0.5 a quarter of the floor
      // shows through the middle of every dissolve.
      final (_, naiveFloor) = composited([0.5, 0.5]);
      expect(naiveFloor, closeTo(0.25, 1e-9));
    });

    test('a partially faded pair keeps BOTH its mix and its floor share — the '
        'O.L runs inside a track fade without either eating the other', () {
      final weights = sourceOverWeights([0.5 * 0.75, 0.5 * 0.25]);
      final (shares, floor) = composited(weights);

      expect(shares[0], closeTo(0.375, 1e-9));
      expect(shares[1], closeTo(0.125, 1e-9));
      expect(floor, closeTo(0.5, 1e-9), reason: 'the track fade, intact');
    });

    test('alphas summing past 1 are layering, not a mix, and pass through', () {
      expect(sourceOverWeights([1.0, 1.0]), [1.0, 1.0]);
      expect(sourceOverWeights([0.8, 0.8]), [0.8, 0.8]);
    });

    test('an empty stack has no weights, and zeros stay zero', () {
      expect(sourceOverWeights(const []), isEmpty);
      expect(sourceOverWeights([0.0]), [0.0]);
      expect(sourceOverWeights([0.0, 0.0]), [0.0, 0.0]);
    });
  });

  group('resolveTrackStackContributions', () {
    Project twoTracks() => Project(
      id: const ProjectId('project'),
      name: 'Project',
      tracks: [
        Track(
          id: const TrackId('track-1'),
          name: 'One',
          cuts: [cut('a1', 4), cut('a2', 6)],
        ),
        Track(id: const TrackId('track-2'), name: 'Two', cuts: [cut('b1', 8)]),
      ],
      createdAt: DateTime.utc(2026),
    );

    test('with no transition it agrees with resolveTrackStackPositions, frame '
        'for frame', () {
      final layout = buildStoryboardTimelineLayout(twoTracks());
      for (var frame = -1; frame < 12; frame += 1) {
        final positions = resolveTrackStackPositions(
          layout: layout,
          globalFrameIndex: frame,
        );
        final contributions = resolveTrackStackContributions(
          layout: layout,
          spansOf: (_) => const [],
          globalFrameIndex: frame,
        );
        expect(
          contributions.map((c) => (c.cut.id, c.localFrameIndex)),
          positions.map((p) => (p.cut.id, p.localFrameIndex)),
          reason: 'frame $frame',
        );
        expect(
          contributions.every((c) => c.opacity == 1.0),
          isTrue,
          reason: 'frame $frame',
        );
      }
    });

    test('the STAGE is the bottom covered TRACK, and every contribution of it '
        '— including the cut arriving over an O.L', () {
      final layout = buildStoryboardTimelineLayout(twoTracks());
      final stack = resolveTrackStackContributions(
        layout: layout,
        spansOf: (trackId) => trackId == const TrackId('track-1')
            ? const [(start: 2, length: 4)]
            : const [],
        globalFrameIndex: 3,
      );

      expect(stack.map((c) => c.cut.id), [
        const CutId('a1'),
        const CutId('a2'),
        const CutId('b1'),
      ]);
      expect(stack[0].isBottomTrack, isTrue);
      expect(stack[1].isBottomTrack, isTrue, reason: 'same track, same stage');
      expect(stack[2].isBottomTrack, isFalse);
    });

    test('a track that gaps here is simply absent, and the NEXT track becomes '
        'the stage', () {
      final project = Project(
        id: const ProjectId('project'),
        name: 'Project',
        tracks: [
          Track(id: const TrackId('track-1'), name: 'One', cuts: [cut('a', 2)]),
          Track(id: const TrackId('track-2'), name: 'Two', cuts: [cut('b', 8)]),
        ],
        createdAt: DateTime.utc(2026),
      );
      final stack = resolveTrackStackContributions(
        layout: buildStoryboardTimelineLayout(project),
        spansOf: (_) => const [],
        globalFrameIndex: 5,
      );

      expect(stack.map((c) => c.cut.id), [const CutId('b')]);
      expect(stack.single.isBottomTrack, isTrue);
    });
  });

  group('trackGroupSourceOverWeights', () {
    test('normalises WITHIN a track and leaves the tracks layering — two '
        'tracks each at half opacity stay two half-opacity layers', () {
      final project = Project(
        id: const ProjectId('project'),
        name: 'Project',
        tracks: [
          Track(id: const TrackId('t1'), name: 'One', cuts: [cut('a', 8)]),
          Track(id: const TrackId('t2'), name: 'Two', cuts: [cut('b', 8)]),
        ],
        createdAt: DateTime.utc(2026),
      );
      final stack = resolveTrackStackContributions(
        layout: buildStoryboardTimelineLayout(project),
        spansOf: (_) => const [],
        globalFrameIndex: 3,
      );

      expect(trackGroupSourceOverWeights(stack, [0.5, 0.5]), [0.5, 0.5]);
    });

    test('a bottom-track O.L is normalised while an upper track keeps its own '
        'share', () {
      final project = Project(
        id: const ProjectId('project'),
        name: 'Project',
        tracks: [
          Track(
            id: const TrackId('t1'),
            name: 'One',
            cuts: [cut('a1', 4), cut('a2', 6)],
          ),
          Track(id: const TrackId('t2'), name: 'Two', cuts: [cut('b', 8)]),
        ],
        createdAt: DateTime.utc(2026),
      );
      final stack = resolveTrackStackContributions(
        layout: buildStoryboardTimelineLayout(project),
        spansOf: (trackId) => trackId == const TrackId('t1')
            ? const [(start: 2, length: 4)]
            : const [],
        globalFrameIndex: 3,
      );
      expect(stack, hasLength(3));

      final weights = trackGroupSourceOverWeights(stack, [
        stack[0].opacity,
        stack[1].opacity,
        0.4,
      ]);
      expect(weights[0], closeTo(1.0, 1e-9), reason: 'the pair partitions');
      expect(weights[1], closeTo(stack[1].opacity, 1e-9));
      expect(weights[2], closeTo(0.4, 1e-9), reason: 'a track apart');
    });
  });
}
