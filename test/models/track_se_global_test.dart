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
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_se_window.dart';

/// W3: SE rows move from cut-owned to TRACK-owned (global frame axis,
/// cut-crossing sounds). Pins the legacy migration, the JSON shapes and
/// the display window.
void main() {
  Layer seLayer(
    String id, {
    Map<int, TimelineExposure> timeline = const {},
    List<Frame> frames = const [],
    List<AudioClip> audioClips = const [],
  }) {
    return Layer(
      id: LayerId(id),
      name: id,
      frames: frames,
      timeline: timeline,
      audioClips: audioClips,
      kind: LayerKind.se,
    );
  }

  Cut cut(String id, int duration, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    layers: layers,
    duration: duration,
    canvasSize: const CanvasSize(width: 100, height: 100),
  );

  Frame frame(String id) => Frame(id: FrameId(id), duration: 1, strokes: []);

  group('legacy migration (Track.fromJson without seLayers)', () {
    Track legacyTrack() {
      // Cut 1 (24f): slot0 has a block [4,10) that legacy-overhangs the
      // cut end via length 40 (clamped on migration). Cut 2 (12f): slot0
      // block [2,6).
      final cut1 = cut('cut-1', 24, [
        Layer(
          id: const LayerId('cel-1'),
          name: 'A',
          frames: const [],
          timeline: const {},
        ),
        seLayer(
          'cut-1-se-1',
          timeline: {
            4: const TimelineExposure.drawing(FrameId('f1'), length: 40),
          },
          frames: [frame('f1')],
          audioClips: const [
            AudioClip(filePath: 'C:/snd/a.wav', frameId: FrameId('f1')),
          ],
        ),
        seLayer('cut-1-se-2'),
      ]);
      final cut2 = cut('cut-2', 12, [
        Layer(
          id: const LayerId('cel-2'),
          name: 'A',
          frames: const [],
          timeline: const {},
        ),
        seLayer(
          'cut-2-se-1',
          timeline: {
            2: const TimelineExposure.drawing(FrameId('f2'), length: 4),
          },
          frames: [frame('f2')],
        ),
        seLayer('cut-2-se-2'),
      ]);
      final json = Track(
        id: const TrackId('track-1'),
        name: 'Track 1',
        cuts: [cut1, cut2],
      ).toJson();
      // Simulate the legacy shape: no seLayers key.
      json.remove('seLayers');
      return Track.fromJson(json);
    }

    test('lifts per-cut SE slots onto the track at global frames, clamped '
        'to each cut window', () {
      final track = legacyTrack();

      expect(track.seLayers, hasLength(2));
      expect(track.seLayers[0].name, 'S1');
      expect(track.seLayers[0].id.value, 'track-1-se-1');
      // Cut 1's block [4, 4+40) clamps to the cut end (legacy playback
      // never ran past it): global [4, 24). Cut 2's block lands at
      // 24 + 2 = 26, length 4.
      final timeline = track.seLayers[0].timeline;
      expect(timeline[4]!.length, 20);
      expect(timeline[26]!.length, 4);
      // Frames and sounds ride along.
      expect(
        track.seLayers[0].frames.map((frame) => frame.id.value),
        containsAll(['f1', 'f2']),
      );
      expect(track.seLayers[0].audioClips, hasLength(1));
      // The cuts lose their SE rows.
      for (final migratedCut in track.cuts) {
        expect(
          migratedCut.layers.where((layer) => layer.kind == LayerKind.se),
          isEmpty,
        );
      }
    });

    test('new-shape JSON round-trips without re-migrating', () {
      final track = legacyTrack();
      final reloaded = Track.fromJson(track.toJson());
      expect(reloaded, track);
    });
  });

  group('TrackSeWindow', () {
    final global = seLayer(
      'track-1-se-1',
      // Block A [10, 30) crosses the window start at 20; block B [30, 38)
      // starts inside the window [20, 32) and crosses its end.
      timeline: {
        10: const TimelineExposure.drawing(FrameId('fa'), length: 20),
        30: const TimelineExposure.drawing(FrameId('fb'), length: 8),
      },
      frames: [frame('fa'), frame('fb')],
    );
    const window = TrackSeWindow(cutStartFrame: 20, cutDurationFrames: 12);

    test('rebases in-window entries and synthesizes the spill-in block', () {
      final display = window.displayLayer(global);

      // Block A spills in: local 0 with the remaining length (10 frames).
      expect(display.timeline[0]!.frameId, const FrameId('fa'));
      expect(display.timeline[0]!.length, 10);
      // Block B keeps its TRUE length past the window end (cut-cross).
      expect(display.timeline[10]!.frameId, const FrameId('fb'));
      expect(display.timeline[10]!.length, 8);
    });

    test('conversion helpers: spill start maps to the earlier-cut block', () {
      expect(window.isSpillInStart(global, 0), isTrue);
      expect(window.globalBlockStartFor(global, 0), 10);
      expect(window.globalBlockStartFor(global, 10), 30);
      expect(window.toGlobalFrame(5), 25);
      expect(window.toLocalFrame(25), 5);
    });

    test('no spill synthesis when the window start is uncovered', () {
      const cleanWindow = TrackSeWindow(
        cutStartFrame: 0,
        cutDurationFrames: 10,
      );
      final display = cleanWindow.displayLayer(global);
      expect(display.timeline[0], isNull);
      expect(cleanWindow.isSpillInStart(global, 0), isFalse);
    });

    test('the window is OPEN-ENDED on the right (SE globalization): '
        'entries at or beyond the cut end ride too, rebased — the runway '
        'shows the neighbours\' sounds', () {
      // Window [20, 32): block B [30, 38) starts inside; a third block at
      // 40 sits entirely BEYOND the cut end — it used to be dropped.
      final withNeighbour = global.copyWith(
        timeline: {
          ...global.timeline,
          40: const TimelineExposure.drawing(FrameId('fc'), length: 5),
        },
      );
      final display = window.displayLayer(withNeighbour);

      expect(display.timeline[10]!.frameId, const FrameId('fb'));
      expect(
        display.timeline[20]!.frameId,
        const FrameId('fc'),
        reason: 'global 40 rebases to local 20, past the 12-frame cut',
      );
      expect(display.timeline[20]!.length, 5);
      // And the conversion round-trips: editing the runway block
      // addresses global 40.
      expect(window.globalBlockStartFor(withNeighbour, 20), 40);
    });

    test('the degenerate no-cut window (duration 0) shows nothing — '
        'without a cut there is no local axis to rebase onto', () {
      const parked = TrackSeWindow(cutStartFrame: 0, cutDurationFrames: 0);
      expect(parked.displayLayer(global).timeline, isEmpty);
    });
  });
}
