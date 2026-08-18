import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/covering_image_normalize.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_repository.dart';

/// The image-row invariant (D22, 유저 08-17: 「블록은 1칸 + 성질 hold
/// 고정」): an IMAGE layer's stored timeline is always ONE real 1-frame
/// block at index 0 plus a fixed end-side HOLD whose ghosts fill to the
/// cut boundary — kept by the repository's write normalization (the
/// always-mirror precedent), so every duration path is covered at once.
void main() {
  Layer imageLayer({
    Map<int, TimelineExposure>? timeline,
    List<Frame>? frames,
  }) => Layer(
    id: const LayerId('img'),
    name: '_BG',
    kind: LayerKind.image,
    frames:
        frames ??
        [Frame(id: const FrameId('bg-cel'), duration: 1, strokes: const [])],
    timeline: timeline ?? const {},
  );

  Cut cutWith(Layer layer, {int duration = 24}) => Cut(
    id: const CutId('cut-1'),
    name: '1',
    duration: duration,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [layer],
  );

  test('any stored shape normalizes to 1 real cell + hold ghosts to the '
      'cut end; an already-shaped row passes IDENTICALLY', () {
    final short = cutWith(
      imageLayer(
        timeline: const {
          0: TimelineExposure.drawing(FrameId('bg-cel'), length: 5),
        },
      ),
    );
    final shaped = cutWithCoveringImageRows(short);
    final layer = shaped.layers.single;
    expect(layer.timeline[0]!.frameId, const FrameId('bg-cel'));
    expect(layer.timeline[0]!.length, 1, reason: '「블록은 1칸」');
    expect(layer.timeline[0]!.ghost, isFalse);
    final ghosts = [
      for (final entry in layer.timeline.entries)
        if (entry.value.ghost) entry,
    ];
    expect(ghosts, isNotEmpty, reason: 'the fixed hold fills to the end');
    var ghostFrames = 0;
    for (final entry in ghosts) {
      expect(entry.value.frameId, const FrameId('bg-cel'));
      ghostFrames += entry.value.length!;
    }
    expect(
      ghostFrames,
      23,
      reason: '1 real + 23 held = the 24-frame cut, no holes',
    );
    expect(layer.runBehaviors, hasLength(1));
    expect(layer.runBehaviors.single.mode, TimelineRunEdgeMode.hold);
    expect(layer.runBehaviors.single.side, TimelineRunEdgeSide.end);

    final noTimeline = cutWithCoveringImageRows(cutWith(imageLayer()));
    expect(noTimeline.layers.single.timeline[0]!.length, 1);

    expect(
      identical(shaped, cutWithCoveringImageRows(shaped)),
      isTrue,
      reason: 'no-op writes stay no-ops for dirty tracking',
    );
  });

  test('a cel-less image row stays empty; non-image rows are untouched', () {
    final empty = cutWith(imageLayer(frames: const []));
    expect(identical(cutWithCoveringImageRows(empty), empty), isTrue);

    final animation = cutWith(
      Layer(
        id: const LayerId('a'),
        name: 'A',
        frames: [
          Frame(id: const FrameId('a1'), duration: 1, strokes: const []),
        ],
        timeline: const {
          3: TimelineExposure.drawing(FrameId('a1'), length: 2),
        },
      ),
    );
    expect(identical(cutWithCoveringImageRows(animation), animation), isTrue);
  });

  test('the REPOSITORY keeps the invariant through duration changes — any '
      'write path, not just the ones that know about image rows', () {
    final repository = ProjectRepository(
      initialProject: Project(
        id: const ProjectId('p'),
        name: 'P',
        createdAt: DateTime.utc(2026, 7, 30),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V',
            cuts: [
              cutWith(
                imageLayer(
                  timeline: const {
                    0: TimelineExposure.drawing(FrameId('bg-cel'), length: 3),
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );

    Layer stored() =>
        repository.requireProject().tracks.single.cuts.single.layers.single;
    int coveredFrames() {
      var total = 0;
      for (final entry in stored().timeline.values) {
        total += entry.length!;
      }
      return total;
    }

    expect(
      stored().timeline[0]!.length,
      1,
      reason: 'load normalizes a stale stored shape to the 1-cell form',
    );
    expect(coveredFrames(), 24, reason: 'real + ghosts tile the cut');

    repository.updateProject(
      (project) => project.copyWith(
        tracks: [
          project.tracks.single.copyWith(
            cuts: [project.tracks.single.cuts.single.copyWith(duration: 48)],
          ),
        ],
      ),
    );
    expect(coveredFrames(), 48, reason: 'the hold ghosts grow with the cut');

    repository.updateProject(
      (project) => project.copyWith(
        tracks: [
          project.tracks.single.copyWith(
            cuts: [project.tracks.single.cuts.single.copyWith(duration: 12)],
          ),
        ],
      ),
    );
    expect(coveredFrames(), 12, reason: 'and shrink with it');
    expect(stored().timeline[0]!.length, 1, reason: 'the real cell stays 1');
  });

  test('MediaReference round-trips on the Layer JSON, and clearing it is '
      'expressible through copyWith (the rasterize edit)', () {
    final referenced = imageLayer().copyWith(
      mediaReference: const MediaReference(
        assetPath: 'C:/media/bg.png',
        frameOffset: 7,
      ),
    );
    final restored = Layer.fromJson(referenced.toJson());
    expect(restored, referenced);
    expect(restored.mediaReference!.assetPath, 'C:/media/bg.png');
    expect(restored.mediaReference!.frameOffset, 7);

    final rasterized = restored.copyWith(mediaReference: null);
    expect(rasterized.mediaReference, isNull);
    expect(rasterized.kind, LayerKind.image, reason: 'kind never changes');
    expect(
      Layer.fromJson(rasterized.toJson()).mediaReference,
      isNull,
      reason: 'the cleared field stays cleared through JSON',
    );

    final untouched = referenced.copyWith(name: 'renamed');
    expect(
      untouched.mediaReference,
      referenced.mediaReference,
      reason: 'the sentinel keeps the reference when not addressed',
    );
  });
}
