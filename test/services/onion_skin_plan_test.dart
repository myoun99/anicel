import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/onion_skin_settings.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/onion_skin_plan.dart';

void main() {
  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  /// A: [0,3) held, B: [3,5), A again (linked): [5,7), C: [8,10) — with an
  /// empty cell at 7.
  final layer = Layer(
    id: const LayerId('layer'),
    name: 'L',
    frames: [frame('a'), frame('b'), frame('c')],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('a'), length: 3),
      3: const TimelineExposure.drawing(FrameId('b'), length: 2),
      5: const TimelineExposure.drawing(FrameId('a'), length: 2),
      8: const TimelineExposure.drawing(FrameId('c'), length: 2),
    },
  );

  // No master enable anymore (UI-R17 #5): application is per-layer at
  // the session; these settings only shape the ghosts.
  const settings = OnionSkinSettings(
    beforePegs: [OnionPeg(opacity: 0.4), OnionPeg(opacity: 0.2)],
    afterPegs: [OnionPeg(opacity: 0.3)],
  );

  test('pegs resolve UNIQUE drawings around the playhead, holds respected, '
      'linked repeats of the current cel skipped', () {
    // Playhead mid-B (frame 4): before = A (its block start, once — the
    // linked A at 5 is after); after = the linked A at 5? A is unique vs
    // current B, so after peg 1 = a.
    final plans = planOnionSkin(
      layer: layer,
      frameIndex: 4,
      settings: settings,
    );
    expect(plans.map((p) => p.frameId.value), ['a', 'a']);
    expect(plans.first.opacity, 0.4);
    expect(plans.first.tint, settings.tintBefore);
    expect(plans.last.opacity, 0.3);
    expect(plans.last.tint, settings.tintAfter);
  });

  test('a held playhead mid-block sees the PREVIOUS drawing, not its own '
      'block start; duplicates across the walk collapse', () {
    // Playhead at frame 6 (inside the linked-A block): current cel = a.
    // Before: b (frame 3); the a-block at 0 is SKIPPED (same cel as
    // current). After: the empty cell at 7 is the next step — F-175 — so
    // the one after peg is spent there and C is not reached.
    final plans = planOnionSkin(
      layer: layer,
      frameIndex: 6,
      settings: settings,
    );
    expect(plans.map((p) => p.frameId.value), ['b']);
  });

  test('a silent peg keeps its slot (peg 2 stays two units back) and '
      'Images mode drops the tints', () {
    final plans = planOnionSkin(
      layer: layer,
      frameIndex: 8,
      settings: settings.copyWith(
        mode: OnionSkinMode.images,
        beforePegs: const [OnionPeg(opacity: 0), OnionPeg(opacity: 0.2)],
        afterPegs: const [OnionPeg(opacity: 0.3)],
      ),
    );
    // At C: the unit before is the EMPTY cell at 7 (F-175), then a (5) —
    // peg 1 (the empty cell) is at 0 anyway, peg 2 = a shows; nothing
    // after C.
    expect(plans.map((p) => p.frameId.value), ['a']);
    expect(plans.single.opacity, 0.2);
    expect(plans.single.tint, isNull);
  });

  test('an empty timeline yields nothing', () {
    expect(
      planOnionSkin(
        layer: layer.copyWith(timeline: const {}, frames: const []),
        frameIndex: 4,
        settings: settings,
      ),
      isEmpty,
    );
  });

  test('an empty cell under the playhead still ghosts the neighbors', () {
    // Frame 7 is uncovered: before walks a(5) then b(3); after finds c.
    final plans = planOnionSkin(
      layer: layer,
      frameIndex: 7,
      settings: settings,
    );
    expect(plans.map((p) => p.frameId.value), ['b', 'a', 'c']);
    // Furthest-first paint order on the before side.
    expect(plans[0].opacity, 0.2);
    expect(plans[1].opacity, 0.4);
  });

  group('F-175: an empty stretch is ONE step', () {
    // 🗣️유저 2026-09-21: 「어니언스킨 블록 단위일때, 사이에 빈 공간 있는데도
    // 그 너머의 첫번째 블럭이 인식됨. 빈 공간 한칸은 블럭으로서 한칸으로
    // 쳐서 빈공간이면 다음 1번의 어니언스킨 안보이게.」

    /// D: [0,2) · EMPTY [2,5) — three cells, one step · E: [5,6) · F: [6,7)
    /// touching E with no gap.
    final gapped = Layer(
      id: const LayerId('gapped'),
      name: 'G',
      frames: [frame('d'), frame('e'), frame('f')],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('d'), length: 2),
        5: const TimelineExposure.drawing(FrameId('e'), length: 1),
        6: const TimelineExposure.drawing(FrameId('f'), length: 1),
      },
    );
    const twoEachWay = OnionSkinSettings(
      beforePegs: [OnionPeg(opacity: 0.4), OnionPeg(opacity: 0.2)],
      afterPegs: [OnionPeg(opacity: 0.3), OnionPeg(opacity: 0.1)],
    );

    List<(String, double)> ghosts(int frameIndex) => [
      for (final plan in planOnionSkin(
        layer: gapped,
        frameIndex: frameIndex,
        settings: twoEachWay,
      ))
        (plan.frameId.value, plan.opacity),
    ];

    test('🚨after: peg 1 lands on the stretch and shows NOTHING; peg 2 '
        'reaches the drawing beyond it', () {
      // At D (frame 0): after peg 1 = the empty [2,5) → nothing; after
      // peg 2 = E. The old walk jumped the stretch and made E peg 1.
      expect(ghosts(0), [('e', 0.1)]);
    });

    test('🚨before: the same stretch is the same one step, however long', () {
      // At E (frame 5): before peg 1 = the empty [2,5) → nothing; before
      // peg 2 = D. Three empty cells are ONE step, as the sheet's single
      // `x` says.
      expect(ghosts(5).where((g) => g.$1 == 'd'), [('d', 0.2)]);
      expect(
        ghosts(5).map((g) => g.$1),
        isNot(contains('e')),
        reason: '⛔전제: the current cel never ghosts itself',
      );
    });

    test('⛔the CONTROL: blocks that touch step straight onto each other',
        () {
      // At E (frame 5): after peg 1 = F, glued to E — no stretch between,
      // so nothing is spent. Without this a walk that treated every step
      // as empty would pass the two above.
      expect(ghosts(5).where((g) => g.$1 == 'f'), [('f', 0.3)]);
    });
  });

  group('frames step', () {
    const frameSteps = OnionSkinSettings(
      beforePegs: [OnionPeg(opacity: 0.4), OnionPeg(opacity: 0.2)],
      afterPegs: [OnionPeg(opacity: 0.3)],
      step: OnionSkinStep.frames,
    );

    test('a peg is that many FRAMES away, not that many drawings', () {
      // Playhead at 5 (the linked-A block's first frame): one frame back
      // is B at 4, two frames back is B at 3 — the same drawing twice,
      // which is what a raw frame walk means. One frame on is A at 6...
      // which is the drawing already on screen, so it ghosts nothing.
      final plans = planOnionSkin(
        layer: layer,
        frameIndex: 5,
        settings: frameSteps,
      );
      expect(plans.map((p) => p.frameId.value), ['b', 'b']);
      // Furthest first: peg 2 (0.2) paints under peg 1 (0.4).
      expect(plans.map((p) => p.opacity), [0.2, 0.4]);
    });

    test('a hold shows the drawing already on screen — it draws NOTHING '
        'rather than stacking the current cel under itself', () {
      // Playhead at 1, inside A [0,3): every neighbour frame is A.
      expect(
        planOnionSkin(layer: layer, frameIndex: 1, settings: frameSteps),
        isEmpty,
      );
    });

    test('an uncovered frame is simply skipped, and the peg keeps its '
        'distance', () {
      // Playhead at 8 (C): one back = frame 7, empty → nothing; two back
      // = frame 6, the linked A.
      final plans = planOnionSkin(
        layer: layer,
        frameIndex: 8,
        settings: frameSteps,
      );
      expect(plans.map((p) => p.frameId.value), ['a']);
      expect(plans.single.opacity, 0.2, reason: 'peg 2 kept its own value');
    });

    test('the walk stops at frame 0 and runs off the end harmlessly', () {
      expect(
        planOnionSkin(layer: layer, frameIndex: 0, settings: frameSteps),
        isEmpty,
        reason: 'nothing before frame 0, and frame 1 holds the current cel',
      );
      // Frame 9 is C's second frame: back is C itself then the empty 7,
      // forward is past the end.
      expect(
        planOnionSkin(layer: layer, frameIndex: 9, settings: frameSteps),
        isEmpty,
      );
    });
  });

  test('the shipped default ghosts exactly one drawing each way', () {
    const defaults = OnionSkinSettings();
    expect(defaults.beforePegs, hasLength(OnionSkinSettings.maxPegs));
    expect(defaults.afterPegs, hasLength(OnionSkinSettings.maxPegs));
    expect(
      defaults.beforePegs.where((peg) => peg.shows).length,
      1,
      reason: 'the artist turns the rest up when they want them',
    );
    final plans = planOnionSkin(
      layer: layer,
      frameIndex: 4,
      settings: defaults,
    );
    expect(plans.map((p) => p.frameId.value), ['a', 'a']);
    expect(plans.map((p) => p.opacity), [0.4, 0.3]);
  });
}
