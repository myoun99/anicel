import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

Layer baseLayer(Map<int, (String, int)> blocks, {bool ghostAt1 = false}) {
  final frameIds = <String>{for (final b in blocks.values) b.$1};
  return Layer(
    id: const LayerId('base'),
    name: 'base',
    frames: [
      for (final id in frameIds)
        Frame(id: FrameId(id), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final entry in blocks.entries)
        entry.key: TimelineExposure.drawing(
          FrameId(entry.value.$1),
          length: entry.value.$2,
        ),
      if (ghostAt1)
        1: TimelineExposure.drawing(
          FrameId(blocks.values.first.$1),
          length: 1,
          ghost: true,
          ghostOwnerId: 'x:end',
        ),
    },
  );
}

Layer syncedAttach({
  Map<FrameId, FrameId> links = const {},
  List<Frame> frames = const [],
}) {
  return Layer(
    id: const LayerId('mirror'),
    name: '+1',
    frames: frames,
    timeline: const {},
    attachedToLayerId: const LayerId('base'),
    attachedMode: AttachedMode.synced,
    baseFrameLinks: links,
  );
}

Cut cutOf(List<Layer> layers) => Cut(
  id: const CutId('cut'),
  name: 'cut',
  duration: 24,
  canvasSize: const CanvasSize(width: 100, height: 100),
  layers: layers,
);

void main() {
  test('adds one deterministic cel + link per unlinked base cel', () {
    final cut = cutOf([baseLayer({0: ('a', 1), 2: ('b', 2)}), syncedAttach()]);
    final next = cutWithReconciledAttachedMirrors(cut);
    final mirror = next.layers.last;
    expect(mirror.frames, hasLength(2));
    expect(mirror.baseFrameLinks, hasLength(2));
    expect(
      mirror.baseFrameLinks[const FrameId('a')],
      attachedMirrorCelId(const LayerId('mirror'), const FrameId('a')),
    );
    // Deterministic: reconciling an equal input mints the identical ids.
    final again = cutWithReconciledAttachedMirrors(cut);
    expect(again.layers.last.baseFrameLinks, mirror.baseFrameLinks);
    // The base row itself is untouched.
    expect(identical(next.layers.first, cut.layers.first), isTrue);
  });

  test('a complete cut passes through IDENTICALLY (no-op identity)', () {
    final once = cutWithReconciledAttachedMirrors(
      cutOf([baseLayer({0: ('a', 1)}), syncedAttach()]),
    );
    final twice = cutWithReconciledAttachedMirrors(once);
    expect(identical(twice, once), isTrue);
  });

  test('orphan links stay untouched; ghost entries never mint links', () {
    final orphanLink = {
      const FrameId('gone'): const FrameId('mirror-gone'),
    };
    final cut = cutOf([
      baseLayer({0: ('a', 1)}, ghostAt1: true),
      syncedAttach(links: orphanLink),
    ]);
    final next = cutWithReconciledAttachedMirrors(cut);
    final mirror = next.layers.last;
    // 'gone' orphan kept; 'a' added; the ghost minted nothing extra.
    expect(mirror.baseFrameLinks.keys.toSet(), {
      const FrameId('gone'),
      const FrameId('a'),
    });
    // No cel resurrected for the orphan (no base cel needs it).
    expect(
      mirror.frames.map((f) => f.id),
      isNot(contains(const FrameId('mirror-gone'))),
    );
  });

  test('re-materializes a MISSING cel under its existing link id', () {
    final cut = cutOf([
      baseLayer({0: ('a', 1)}),
      // Link exists but the Frame object is missing.
      syncedAttach(links: {const FrameId('a'): const FrameId('m-a')}),
    ]);
    final next = cutWithReconciledAttachedMirrors(cut);
    final mirror = next.layers.last;
    expect(mirror.frames.single.id, const FrameId('m-a'));
    expect(mirror.baseFrameLinks[const FrameId('a')], const FrameId('m-a'));
  });

  test('FREE attach rows and plain layers are never touched', () {
    final free = Layer(
      id: const LayerId('free'),
      name: 'f',
      frames: const [],
      attachedToLayerId: const LayerId('base'),
      attachedMode: AttachedMode.free,
    );
    final cut = cutOf([baseLayer({0: ('a', 1)}), free]);
    expect(identical(cutWithReconciledAttachedMirrors(cut), cut), isTrue);
  });
}
