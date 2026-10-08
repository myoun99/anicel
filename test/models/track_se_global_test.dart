import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/se_name_tag.dart';
import 'package:anicel/src/models/track_se_window.dart';
import 'package:anicel/src/models/transform_track.dart';

/// W3: SE rows move from cut-owned to TRACK-owned (global frame axis,
/// cut-crossing sounds). Pins the JSON shape and the display window.
///
/// ↩️It pinned the lift of a file's cut-owned SE rows onto the track too;
/// those files are of formats refused by their number now (the save law,
/// 유저 2026-10-06).
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

  Frame frame(String id) => Frame(id: FrameId(id), duration: 1, strokes: []);

  test('a track\'s SE rows come back from its JSON — their blocks, cels '
      'and sounds with them', () {
    final row = seLayer(
      'track-1-se-1',
      timeline: {
        4: const TimelineExposure.drawing(FrameId('f1'), length: 20),
      },
      frames: [frame('f1')],
      audioClips: [
        AudioClip(filePath: 'C:/snd/a.wav', frameId: const FrameId('f1')),
      ],
    );
    final track = Track(
      id: const TrackId('track-1'),
      name: 'Track 1',
      cuts: const [],
      seLayers: [row],
    );

    final back = Track.fromJson(track.toJson())
        .seLayers
        .firstWhere((layer) => layer.id == row.id);

    expect(back.timeline, row.timeline);
    expect(back.frames.map((frame) => frame.id), [const FrameId('f1')]);
    expect(back.audioClips, row.audioClips);
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

  // R5 #8: the row showed transform lanes and refused every key, because
  // the display clone dropped the track outright. It rebases now; an edit
  // no longer comes back through it (F-102).
  group('the display clone rebases the transform track onto the cut', () {
    const window = TrackSeWindow(cutStartFrame: 12, cutDurationFrames: 24);

    Layer withRotation(Map<int, double> keys) => Layer(
      id: const LayerId('se-1'),
      name: 'S1',
      kind: LayerKind.se,
      frames: const [],
      timeline: const {},
      transformTrack: TransformTrack.empty().copyWith(
        rotation: keys.entries.fold<PropertyTrack<double>>(
          PropertyTrack<double>(),
          (track, entry) => track.withKey(entry.key, entry.value),
        ),
      ),
    );

    test('global keys arrive on the cut-local axis', () {
      final local = window
          .displayLayer(withRotation({12: 10, 20: 20, 40: 30}))
          .transformTrack
          .rotation;
      expect(local.keys.keys.toList(), [0, 8, 28]);
      expect(local.keyAt(0)!.value, 10);
      expect(
        local.keyAt(28)!.value,
        30,
        reason: 'the runway is open-ended: keys past the cut end ride too',
      );
    });

    // The clone is what the RAIL shows. The value an earlier cut's key holds
    // into this cut is read off the track's row instead (F-102) — pinned in
    // test/ui/session/se_row_keys_live_on_the_track_in_every_cut_test.dart.
    test('a key from an EARLIER cut is dropped, not folded onto frame 0', () {
      final local = window
          .displayLayer(withRotation({4: 99, 12: 10}))
          .transformTrack
          .rotation;
      expect(local.keys.keys.toList(), [0]);
      expect(
        local.keyAt(0)!.value,
        10,
        reason: 'the negative one has no row here; it must not overwrite',
      );
    });

    // ⛔The round trip is GONE (F-102): an edit no longer comes back through
    // this window — it reads the row the project holds. That law is pinned
    // where it lives, in
    // test/ui/session/se_row_keys_live_on_the_track_in_every_cut_test.dart.

    test('a window at the track start is the identity — no needless copy',
        () {
      const first = TrackSeWindow(cutStartFrame: 0, cutDurationFrames: 24);
      final layer = withRotation({0: 10, 6: 20});
      expect(
        identical(
          first.displayLayer(layer).transformTrack,
          layer.transformTrack,
        ),
        isTrue,
      );
    });
  });

  // The effect chain's parameter lanes key on the same axis as the
  // transform lanes and take the same trip — but nothing measured it, so
  // the effect rebase could have shifted the wrong way (or not at all)
  // with every test above still green.
  group('the display clone rebases EFFECT parameter lanes onto the cut', () {
    const window = TrackSeWindow(cutStartFrame: 20, cutDurationFrames: 12);

    LayerEffect blurWith(Map<int, double> keys) => LayerEffect(
      id: const EffectId('fx-1'),
      kind: EffectKind.blur,
      parameters: {
        'blurX': EffectParameter(
          track: keys.entries.fold<PropertyTrack<double>>(
            PropertyTrack<double>(),
            (track, entry) => track.withKey(entry.key, entry.value),
          ),
        ),
      },
    );

    Layer withEffect(LayerEffect effect) => Layer(
      id: const LayerId('se-1'),
      name: 'S1',
      kind: LayerKind.se,
      frames: const [],
      timeline: const {},
      effects: [effect],
    );

    PropertyTrack<double> blurXOf(List<LayerEffect> effects) =>
        effects.single.parameters['blurX']!.track;

    test('global keys arrive on the cut-local axis', () {
      final local = blurXOf(
        window.displayLayer(withEffect(blurWith({40: 7}))).effects,
      );
      expect(local.keys.keys.toList(), [20]);
      expect(local.keyAt(20)!.value, 7);
    });

    test('a key from an EARLIER cut is dropped, not folded onto frame 0', () {
      final local = blurXOf(
        window.displayLayer(withEffect(blurWith({8: 99, 20: 3}))).effects,
      );
      expect(local.keys.keys.toList(), [0]);
      expect(
        local.keyAt(0)!.value,
        3,
        reason: 'the negative one has no row here; it must not overwrite',
      );
    });

    test('a window at the track start is the identity', () {
      const first = TrackSeWindow(cutStartFrame: 0, cutDurationFrames: 24);
      final layer = withEffect(blurWith({0: 1, 6: 2}));
      expect(
        blurXOf(first.displayLayer(layer).effects).keys.keys.toList(),
        [0, 6],
      );
    });
  });

  // R5 #7: the name tag's members key on the same axis and are read off the
  // same clone.
  group('the display clone rebases NAME TAG members onto the cut', () {
    const window = TrackSeWindow(cutStartFrame: 12, cutDurationFrames: 24);

    Layer withTagSizes(Map<int, double> sizes) => Layer(
      id: const LayerId('se-1'),
      name: 'S1',
      kind: LayerKind.se,
      frames: const [],
      timeline: const {},
      seNameTag: SeNameTag(
        track: SeNameTagTrack(
          fontSize: PropertyTrack(
            keys: {
              for (final entry in sizes.entries)
                entry.key: PropertyKey(entry.value),
            },
          ),
        ),
      ),
    );

    test('member keys arrive on the cut-local axis, and an EARLIER cut\'s is '
        'dropped like every other lane\'s', () {
      final sizes = window
          .displayLayer(withTagSizes({4: 30, 20: 40}))
          .seNameTag!
          .track!
          .fontSize;
      expect(sizes.keys.keys.toList(), [8]);
      expect(sizes.keyAt(8)!.value, 40);
    });
  });
}
