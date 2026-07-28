import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/cut_duplicate_helpers.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

void main() {
  Frame frame(String id) =>
      Frame(id: FrameId(id), duration: 1, strokes: const []);

  /// Base with two blocks: b1 at [0,3) (reused at [5,7)), b2 at [3,5).
  final base = Layer(
    id: const LayerId('base'),
    name: 'A',
    frames: [frame('b1'), frame('b2')],
    timeline: {
      0: const TimelineExposure.drawing(FrameId('b1'), length: 3),
      3: const TimelineExposure.drawing(FrameId('b2'), length: 2),
      5: const TimelineExposure.drawing(FrameId('b1'), length: 2),
    },
  );

  /// Attach layer linking only b1 → a1 (b2 unlinked).
  final attached = Layer(
    id: const LayerId('attach'),
    name: 'A +1',
    frames: [frame('a1')],
    timeline: const {},
    attachedToLayerId: const LayerId('base'),
    attachedPlacement: AttachedPlacement.above,
    baseFrameLinks: {const FrameId('b1'): const FrameId('a1')},
  );

  test('the attach cel resolves through the base exposure and the cell '
      'link — linked-cel reuse on the base reuses the attach cel', () {
    Frame? at(int f) =>
        resolveAttachedFrameAt(attached: attached, base: base, frameIndex: f);

    expect(at(0)!.id, const FrameId('a1'));
    expect(at(2)!.id, const FrameId('a1'));
    expect(at(3), isNull, reason: 'b2 has no link');
    expect(at(5)!.id, const FrameId('a1'), reason: 'b1 reused → a1 reused');
    expect(at(7), isNull, reason: 'past the base coverage');
  });

  test('the display timeline mirrors the base blocks through the links as '
      'GHOST exposures (same starts and lengths; unlinked and orphan '
      'blocks stay empty)', () {
    final timeline = attachedDisplayTimeline(attached: attached, base: base);

    expect(timeline.keys, [0, 5]);
    // Ghost entries (UI-R20 #8): the attach row reads as a text-only
    // mirror of the base — no block chrome, timing affordances stand
    // down; drawing and playback still resolve the cels through them.
    expect(
      timeline[0],
      const TimelineExposure.drawing(FrameId('a1'), length: 3, ghost: true),
    );
    expect(
      timeline[5],
      const TimelineExposure.drawing(FrameId('a1'), length: 2, ghost: true),
    );

    // An orphan link (cel deleted off the attach layer) shows nothing.
    final orphaned = attached.copyWith(frames: const []);
    expect(attachedDisplayTimeline(attached: orphaned, base: base), isEmpty);
  });

  test('attach linkage survives a JSON round-trip; plain layers stay '
      'link-free', () {
    final restored = Layer.fromJson(attached.toJson());
    expect(restored, attached);
    expect(restored.attachedToLayerId, const LayerId('base'));
    expect(restored.baseFrameLinks, {const FrameId('b1'): const FrameId('a1')});

    final plainJson = base.toJson();
    expect(plainJson.containsKey('attachedTo'), isFalse);
    expect(Layer.fromJson(plainJson).attachedToLayerId, isNull);
  });

  test('the attach MODE round-trips (UI-R21 #3): synced omits the key '
      '(pre-mode files read back unchanged), free persists it', () {
    expect(attached.attachedMode, AttachedMode.synced);
    expect(isSyncedAttachedLayer(attached), isTrue);
    expect(attached.toJson().containsKey('attachedMode'), isFalse);

    final free = attached.copyWith(attachedMode: AttachedMode.free);
    expect(isAttachedLayer(free), isTrue);
    expect(isSyncedAttachedLayer(free), isFalse);
    final json = free.toJson();
    expect(json['attachedMode'], 'free');
    final restored = Layer.fromJson(json);
    expect(restored.attachedMode, AttachedMode.free);
    expect(restored, free);
  });

  test('v1 base eligibility: drawing kinds only, and never an attach layer '
      'itself (no nesting)', () {
    expect(canCarryAttachedLayers(base), isTrue);
    expect(canCarryAttachedLayers(attached), isFalse);
    expect(canCarryAttachedLayers(base.copyWith(kind: LayerKind.se)), isFalse);
    expect(
      canCarryAttachedLayers(base.copyWith(kind: LayerKind.camera)),
      isFalse,
    );
  });

  test('duplicating a cut remaps the attach linkage onto the copies (both '
      'the base pointer and the per-cel links)', () {
    final cut = Cut(
      id: const CutId('cut'),
      name: 'Cut',
      layers: [base, attached],
      duration: 8,
      canvasSize: const CanvasSize(width: 8, height: 8),
    );
    final layerIdMap = {
      const LayerId('base'): const LayerId('base-copy'),
      const LayerId('attach'): const LayerId('attach-copy'),
    };
    final frameIdMap = {
      const FrameId('b1'): const FrameId('b1-copy'),
      const FrameId('b2'): const FrameId('b2-copy'),
      const FrameId('a1'): const FrameId('a1-copy'),
    };

    final copy = duplicateCutAsIndependentCopy(
      source: cut,
      newCutId: const CutId('cut-copy'),
      newName: 'Cut Copy',
      layerIdMap: layerIdMap,
      frameIdMap: frameIdMap,
    );

    final attachedCopy = copy.layers[1];
    expect(attachedCopy.attachedToLayerId, const LayerId('base-copy'));
    expect(attachedCopy.attachedPlacement, AttachedPlacement.above);
    expect(attachedCopy.baseFrameLinks, {
      const FrameId('b1-copy'): const FrameId('a1-copy'),
    });

    // The copied pair resolves independently of the original.
    final resolved = resolveAttachedFrameAt(
      attached: attachedCopy,
      base: copy.layers[0],
      frameIndex: 0,
    );
    expect(resolved!.id, const FrameId('a1-copy'));
  });

  test('group helpers: attach rows adjacent to the base, insertion past the '
      'group, numbered names', () {
    final below = attached.copyWith(
      id: const LayerId('attach-below'),
      attachedPlacement: AttachedPlacement.below,
    );
    final layers = [below, base, attached];

    expect(attachedBaseOf(attached, layers)!.id, const LayerId('base'));
    expect(attachedLayersOf(const LayerId('base'), layers).map((l) => l.id), [
      const LayerId('attach-below'),
      const LayerId('attach'),
    ]);
    expect(attachedGroupEndIndex(const LayerId('base'), layers), 3);
    // Signed, per-side numbering (UI-R20 #11) on the BASE's name
    // (R26 #29): one above and one below exist, so the next of each side
    // is A+2 / A-2.
    expect(nextAttachedLayerName(base, layers, AttachedPlacement.above), 'A+2');
    expect(nextAttachedLayerName(base, layers, AttachedPlacement.below), 'A-2');
    expect(
      nextAttachedLayerName(base, [base], AttachedPlacement.below),
      'A-1',
      reason: 'each side numbers its own count',
    );
  });
}
