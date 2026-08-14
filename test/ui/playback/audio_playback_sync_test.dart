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
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/playback/audio_playback_sync.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';

class _FakeClipPlayer implements AudioClipPlayer {
  _FakeClipPlayer(this.log, {this.volumeLog});

  final List<String> log;

  /// Volume ramps log separately — the lifecycle assertions stay
  /// volume-agnostic (every start is preceded by a setVolume).
  final List<String>? volumeLog;
  String? _path;

  @override
  Future<void> prepare(String filePath) async {
    _path = filePath;
    log.add('prepare $filePath');
  }

  @override
  Future<void> startAt(Duration position) async =>
      log.add('start $_path @${position.inMilliseconds}ms');

  @override
  Future<void> setVolume(double volume) async =>
      volumeLog?.add('$_path ${volume.toStringAsFixed(2)}');

  @override
  Future<void> pause() async => log.add('pause $_path');

  @override
  Future<void> resume() async => log.add('resume $_path');

  @override
  Future<void> stop() async => log.add('stop $_path');

  @override
  Future<void> dispose() async => log.add('dispose $_path');
}

/// One SE layer with one sound linked to a single block (frame-linked
/// model: the block is the sound's window).
Layer _seLayer(
  String id, {
  required String file,
  required int start,
  required int length,
}) => Layer(
  id: LayerId(id),
  name: 'S1',
  kind: LayerKind.se,
  frames: [Frame(id: FrameId('$id-frame'), duration: 1, strokes: const [])],
  timeline: {
    start: TimelineExposure.drawing(FrameId('$id-frame'), length: length),
  },
  audioClips: [AudioClip(filePath: file, frameId: FrameId('$id-frame'))],
);

// SE lives on the TRACK's global frame axis; a cut only shows a window
// onto it. (Cut-owned SE is a legacy file shape that `Track.fromJson`
// lifts on load, so no loaded project can carry one — a fixture that built
// it was pinning a shape production cannot produce.)
//
// fps 10, cut-a = global 0..10 and cut-b = global 10..30:
//   a.wav  global 0..10  (1.0 s = exactly its window)
//   b.wav  global 6..10  (unknown length → the block is the window)
//   c.wav  global 13..30 (0.5 s → audible 13..18, then it simply ends)
final Project _project = Project(
  id: const ProjectId('sync-project'),
  name: 'Sync',
  createdAt: DateTime.utc(2026, 7, 8),
  tracks: [
    Track(
      id: const TrackId('track'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('cut-a'),
          name: 'A',
          duration: 10,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: const [],
        ),
        Cut(
          id: const CutId('cut-b'),
          name: 'B',
          duration: 20,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: const [],
        ),
      ],
      seLayers: [
        _seLayer('se-a1', file: 'a.wav', start: 0, length: 10),
        _seLayer('se-a2', file: 'b.wav', start: 6, length: 4),
        _seLayer('se-b', file: 'c.wav', start: 13, length: 17),
      ],
    ),
  ],
);

const _durations = {'a.wav': 1.0, 'c.wav': 0.5};

void main() {
  late CanvasPlaybackController controller;
  late List<String> log;

  setUp(() {
    log = [];
    controller = CanvasPlaybackController(
      resolveProject: () => _project,
      resolveActiveCutId: () => const CutId('cut-a'),
      resolveActiveTrackId: () => const TrackId('track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    );
    final sync = AudioPlaybackSync(
      controller: controller,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      durationSecondsFor: (path) => _durations[path],
      playerFactory: () => _FakeClipPlayer(log),
      // The schedule reads TRACK-owned SE, so it needs the project.
      resolveProject: () => _project,
    )..attach();
    addTearDown(sync.dispose);
    addTearDown(controller.dispose);
  });

  test('play prepares every scheduled clip once and starts the overlapping '
      'ones', () {
    controller.play(scope: PlaybackScope.activeCut);
    expect(log, ['prepare a.wav', 'prepare b.wav', 'start a.wav @0ms']);

    log.clear();
    controller.seekToGlobalFrame(3); // small forward step = dropped frames
    expect(log, isEmpty);

    controller.seekToGlobalFrame(6); // crosses b.wav's start
    expect(log, ['start b.wav @0ms']);
  });

  test('play mid-timeline starts clips at the matching position', () {
    controller.play(scope: PlaybackScope.activeCut, startGlobalFrame: 5);
    expect(log, ['prepare a.wav', 'prepare b.wav', 'start a.wav @500ms']);
  });

  test('a forward jump past the threshold restarts at the new position', () {
    controller.play(scope: PlaybackScope.activeCut);
    log.clear();

    controller.seekToGlobalFrame(8); // 8 frames > fps/2 → resync
    expect(log, ['stop a.wav', 'start a.wav @800ms', 'start b.wav @200ms']);
  });

  test('a backward jump (loop wrap) stops everything and re-evaluates', () {
    controller.play(scope: PlaybackScope.activeCut);
    controller.seekToGlobalFrame(6);
    log.clear();

    controller.seekToGlobalFrame(0);
    expect(log, ['stop a.wav', 'stop b.wav', 'start a.wav @0ms']);
  });

  /// ⛔T28 — this was 'pause/resume forward to playing clips; a paused seek
  /// restarts'. Both halves described the paused state, which no longer
  /// exists. A seek while ROLLING is the case that survived, and it never
  /// went through pause: it stops what is stale and starts what now
  /// overlaps, in one step.
  test('a seek while rolling swaps the clips under it', () {
    controller.play(scope: PlaybackScope.activeCut);
    log.clear();

    controller.seekToGlobalFrame(6);

    expect(log, ['stop a.wav', 'start a.wav @600ms', 'start b.wav @0ms']);
  });

  test('stopping playback stops and disposes every player', () {
    controller.play(scope: PlaybackScope.activeCut);
    controller.seekToGlobalFrame(6);
    log.clear();

    controller.stop();
    expect(log, ['stop a.wav', 'stop b.wav', 'dispose a.wav', 'dispose b.wav']);
  });

  test('all-cuts playback lays clips globally and clamps at cut ends', () {
    // Frame 12 = cut-b local 2: everything is prepared, nothing plays yet.
    controller.play(scope: PlaybackScope.allCuts, startGlobalFrame: 12);
    expect(log, ['prepare a.wav', 'prepare b.wav', 'prepare c.wav']);

    log.clear();
    controller.seekToGlobalFrame(13); // c.wav's global start
    expect(log, ['start c.wav @0ms']);

    log.clear();
    controller.seekToGlobalFrame(18); // c.wav ends (0.5 s = 5 frames)
    expect(log, ['stop c.wav']);
  });

  test('an unknown-length clip stops at its cut boundary', () {
    // b.wav has no extracted peaks → its end clamps to cut-a's end (10).
    controller.play(scope: PlaybackScope.allCuts, startGlobalFrame: 7);
    expect(log, [
      'prepare a.wav',
      'prepare b.wav',
      'prepare c.wav',
      'start a.wav @700ms',
      'start b.wav @100ms',
    ]);

    log.clear();
    controller.seekToGlobalFrame(10); // cut-a → cut-b boundary
    expect(log, ['stop a.wav', 'stop b.wav']);
  });

  test('a cut boundary tick never opens or tears down a media pipeline', () {
    // Playback must never stall at a cut boundary: crossing one only
    // seeks/starts/stops PREPARED players — no prepare, no dispose.
    controller.play(scope: PlaybackScope.allCuts, startGlobalFrame: 9);
    log.clear();

    controller.seekToGlobalFrame(13); // crosses the boundary, starts c.wav
    expect(log, ['stop a.wav', 'stop b.wav', 'start c.wav @0ms']);
    expect(log.where((line) => line.startsWith('prepare')), isEmpty);
    expect(log.where((line) => line.startsWith('dispose')), isEmpty);
  });

  test('a loop wrap restarts clips on the same prepared players', () {
    controller.play(scope: PlaybackScope.activeCut);
    controller.seekToGlobalFrame(6);
    log.clear();

    controller.seekToGlobalFrame(0); // loop wrap
    expect(log, ['stop a.wav', 'stop b.wav', 'start a.wav @0ms']);
    expect(log.where((line) => line.startsWith('prepare')), isEmpty);
  });

  test('an offset trim seeks into the file and shortens the audible '
      'window', () {
    // One 10-frame cut: a 1.0 s file (10 frames at fps 10) trimmed by 4 —
    // playback starts 0.4 s into the file and only 6 frames remain audible.
    final trimmedLog = <String>[];
    final project = Project(
      id: const ProjectId('trim-project'),
      name: 'Trim',
      createdAt: DateTime.utc(2026, 7, 9),
      tracks: [
        Track(
          id: const TrackId('trim-track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('trim-cut'),
              name: 'T',
              duration: 10,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: const [],
            ),
          ],
          seLayers: [
            _seLayer('se-trim', file: 'a.wav', start: 0, length: 10).copyWith(
              audioClips: const [
                AudioClip(
                  filePath: 'a.wav',
                  frameId: FrameId('se-trim-frame'),
                  offsetFrames: 4,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final trimmedController = CanvasPlaybackController(
      resolveProject: () => project,
      resolveActiveCutId: () => const CutId('trim-cut'),
      resolveActiveTrackId: () => const TrackId('trim-track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    );
    final sync = AudioPlaybackSync(
      controller: trimmedController,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      durationSecondsFor: (path) => _durations[path],
      playerFactory: () => _FakeClipPlayer(trimmedLog),
      resolveProject: () => project,
    )..attach();
    addTearDown(sync.dispose);
    addTearDown(trimmedController.dispose);

    trimmedController.play(scope: PlaybackScope.activeCut);
    expect(trimmedLog, ['prepare a.wav', 'start a.wav @400ms']);

    // The remaining file is 6 frames (10 - 4): a resync PAST the shortened
    // end stops the clip and starts nothing.
    trimmedLog.clear();
    trimmedController.seekToGlobalFrame(8); // > fps/2 → resync
    expect(trimmedLog, ['stop a.wav']);

    // A resync inside the window compounds elapsed time with the trim.
    trimmedLog.clear();
    trimmedController.seekToGlobalFrame(2);
    expect(trimmedLog, ['start a.wav @600ms']);

    // Ticking across the shortened end (frame 6) stops the clip.
    trimmedLog.clear();
    trimmedController.seekToGlobalFrame(5); // dropped-frames step: silent
    trimmedController.seekToGlobalFrame(6); // shortened end crossed
    expect(trimmedLog, ['stop a.wav']);
  });

  test('muted SE layers are skipped by the schedule entirely', () {
    final mutedLog = <String>[];
    final project = Project(
      id: const ProjectId('mute-project'),
      name: 'Mute',
      createdAt: DateTime.utc(2026, 7, 10),
      tracks: [
        Track(
          id: const TrackId('mute-track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('mute-cut'),
              name: 'M',
              duration: 10,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: const [],
            ),
          ],
          seLayers: [
            _seLayer(
              'se-muted',
              file: 'a.wav',
              start: 0,
              length: 10,
            ).copyWith(muted: true),
            _seLayer('se-live', file: 'c.wav', start: 0, length: 10),
          ],
        ),
      ],
    );
    final mutedController = CanvasPlaybackController(
      resolveProject: () => project,
      resolveActiveCutId: () => const CutId('mute-cut'),
      resolveActiveTrackId: () => const TrackId('mute-track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    );
    final sync = AudioPlaybackSync(
      controller: mutedController,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      durationSecondsFor: (path) => _durations[path],
      playerFactory: () => _FakeClipPlayer(mutedLog),
      resolveProject: () => project,
    )..attach();
    addTearDown(sync.dispose);
    addTearDown(mutedController.dispose);

    mutedController.play(scope: PlaybackScope.activeCut);
    // The muted layer's a.wav never even prepares; the live layer plays.
    expect(mutedLog, ['prepare c.wav', 'start c.wav @0ms']);
  });

  test('track-owned SE sounds keep playing through played cut gaps; a '
      'gap-starting sound fires on its exact frame (W3c)', () {
    // Track: cut A [0,10), gap [10,15), cut B [15,25). Track SE rows on
    // the global axis: g.wav spans [8,18) ACROSS the gap; h.wav starts
    // INSIDE it at 12 (length 5 → [12,17)).
    final gapLog = <String>[];
    final project = Project(
      id: const ProjectId('gap-project'),
      name: 'Gap',
      createdAt: DateTime.utc(2026, 7, 11),
      tracks: [
        Track(
          id: const TrackId('gap-track'),
          name: 'Video',
          seLayers: [
            _seLayer('se-g', file: 'g.wav', start: 8, length: 10),
            _seLayer('se-h', file: 'h.wav', start: 12, length: 5),
          ],
          cuts: [
            Cut(
              id: const CutId('gap-a'),
              name: 'A',
              duration: 10,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: const [],
            ),
            Cut(
              id: const CutId('gap-b'),
              name: 'B',
              duration: 10,
              leadingGapFrames: 5,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: const [],
            ),
          ],
        ),
      ],
    );
    final gapController = CanvasPlaybackController(
      resolveProject: () => project,
      resolveActiveCutId: () => const CutId('gap-a'),
      resolveActiveTrackId: () => const TrackId('gap-track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    );
    final sync = AudioPlaybackSync(
      controller: gapController,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      durationSecondsFor: (path) => const {'g.wav': 1.0, 'h.wav': 0.5}[path],
      playerFactory: () => _FakeClipPlayer(gapLog),
      resolveProject: () => project,
    )..attach();
    addTearDown(sync.dispose);
    addTearDown(gapController.dispose);

    gapController.play(scope: PlaybackScope.allCuts, startGlobalFrame: 8);
    expect(gapLog, ['prepare g.wav', 'prepare h.wav', 'start g.wav @0ms']);

    // Ticking into the gap does NOT stop g — audio lives on the global
    // axis and the clock plays through the gap. (The regression: the run
    // used to break at the gap, clipping g at frame 10.)
    gapLog.clear();
    gapController.seekToGlobalFrame(11);
    expect(gapLog, isEmpty);

    // The gap-starting sound fires exactly on its frame, mid-gap.
    gapController.seekToGlobalFrame(12);
    expect(gapLog, ['start h.wav @0ms']);

    // Both true ends hold — the cut boundary at 15 stops nothing.
    gapLog.clear();
    gapController.seekToGlobalFrame(16);
    expect(gapLog, isEmpty);
    gapController.seekToGlobalFrame(17);
    expect(gapLog, ['stop h.wav']);
    gapLog.clear();
    gapController.seekToGlobalFrame(18);
    expect(gapLog, ['stop g.wav']);
  });

  test('gain and fades ramp the volume per tick, clamped into 0..1', () {
    // One 10-frame cut: gain 2.0 (platform-clamped to 1), fade-in over 4
    // frames, fade-out over 5 anchored at the audible end (10).
    final rampLog = <String>[];
    final volumeLog = <String>[];
    final project = Project(
      id: const ProjectId('ramp-project'),
      name: 'Ramp',
      createdAt: DateTime.utc(2026, 7, 10),
      tracks: [
        Track(
          id: const TrackId('ramp-track'),
          name: 'Video',
          cuts: [
            Cut(
              id: const CutId('ramp-cut'),
              name: 'R',
              duration: 10,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: const [],
            ),
          ],
          seLayers: [
            _seLayer('se-ramp', file: 'a.wav', start: 0, length: 10).copyWith(
              audioClips: const [
                AudioClip(
                  filePath: 'a.wav',
                  frameId: FrameId('se-ramp-frame'),
                  gain: 2.0,
                  fadeInFrames: 4,
                  fadeOutFrames: 5,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final rampController = CanvasPlaybackController(
      resolveProject: () => project,
      resolveActiveCutId: () => const CutId('ramp-cut'),
      resolveActiveTrackId: () => const TrackId('ramp-track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    );
    final sync = AudioPlaybackSync(
      controller: rampController,
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
      durationSecondsFor: (path) => _durations[path],
      playerFactory: () => _FakeClipPlayer(rampLog, volumeLog: volumeLog),
      resolveProject: () => project,
    )..attach();
    addTearDown(sync.dispose);
    addTearDown(rampController.dispose);

    // Frame 0: fade-in floor — volume lands BEFORE the first samples.
    rampController.play(scope: PlaybackScope.activeCut);
    expect(volumeLog, ['a.wav 0.00']);
    expect(rampLog.last, 'start a.wav @0ms');

    // Mid-fade-in (frame 2 of 4): gain 2 × 0.5 = 1.0 after the clamp;
    // frame 3 stays clamped at 1.00 → no redundant platform call.
    volumeLog.clear();
    rampController.seekToGlobalFrame(2);
    rampController.seekToGlobalFrame(3);
    expect(volumeLog, ['a.wav 1.00']);

    // Fade-out: remaining 3 of 5 → 2 × 3/5 = 1.2 → clamped 1.00 (silent
    // ramp until the clamp releases), then remaining 2 → 0.80.
    volumeLog.clear();
    rampController.seekToGlobalFrame(7);
    expect(volumeLog, isEmpty);
    rampController.seekToGlobalFrame(8);
    expect(volumeLog, ['a.wav 0.80']);
  });
}
