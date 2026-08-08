import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_mount.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_repeat.dart';

/// P3's model half: what a SYNCED mount has to agree on, and what a row
/// becomes when it stops riding a base.

Layer _row(
  String id, {
  LayerKind kind = LayerKind.animation,
  List<(int start, int length, String cel)> blocks = const [],
  Map<String, String> links = const {},
  String? attachedTo,
  AttachedMode mode = AttachedMode.synced,
  List<TimelineRunBehavior> runBehaviors = const [],
}) {
  final celIds = <String>{for (final block in blocks) block.$3, ...links.values};
  return Layer(
    id: LayerId(id),
    name: id,
    kind: kind,
    frames: [
      for (final cel in celIds)
        Frame(id: FrameId(cel), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final block in blocks)
        block.$1: TimelineExposure.drawing(
          FrameId(block.$3),
          length: block.$2,
        ),
    },
    attachedToLayerId: attachedTo == null ? null : LayerId(attachedTo),
    attachedMode: mode,
    baseFrameLinks: {
      for (final entry in links.entries)
        FrameId(entry.key): FrameId(entry.value),
    },
    runBehaviors: runBehaviors,
  );
}

List<(int, int, String)> _blocks(Layer layer) => [
  for (final entry in layer.timeline.entries)
    if (!entry.value.ghost)
      (entry.key, entry.value.length!, entry.value.frameId!.value),
];

void main() {
  group('the exposure shape', () {
    test('is where each block starts, how long it holds and which blocks '
        'share a cel', () {
      final row = _row(
        'row',
        blocks: [(0, 2, 'a'), (2, 3, 'b'), (5, 1, 'a')],
      );
      expect(attachExposureShape(row), [
        (start: 0, length: 2, celOrdinal: 0),
        (start: 2, length: 3, celOrdinal: 1),
        // The third block re-uses the FIRST block's cel, so it names it.
        (start: 5, length: 1, celOrdinal: 0),
      ]);
    });

    test('ignores GHOSTS — a repeat tail is not authored timing', () {
      final authored = _row('row', blocks: [(0, 1, 'a')]);
      final withTail = authored.copyWith(
        timeline: {
          0: TimelineExposure.drawing(const FrameId('a'), length: 1),
          1: TimelineExposure.drawing(
            const FrameId('a'),
            length: 1,
            ghost: true,
            ghostOwnerId: 'a:end',
          ),
        },
      );
      expect(attachExposureShape(withTail), attachExposureShape(authored));
    });
  });

  group('the links a SYNCED mount would store', () {
    test('pair every base cel with the row\'s block in the same place', () {
      final base = _row('base', blocks: [(0, 2, 'b1'), (2, 1, 'b2')]);
      final row = _row('row', blocks: [(0, 2, 'r1'), (2, 1, 'r2')]);
      expect(attachedLinksForMount(row: row, base: base), {
        const FrameId('b1'): const FrameId('r1'),
        const FrameId('b2'): const FrameId('r2'),
      });
    });

    test('COMPLETENESS: one link per base cel, so the always-mirror '
        'normalization has no gap to fill with an empty cel', () {
      final base = _row('base', blocks: [(0, 1, 'b1'), (1, 1, 'b2'), (2, 1, 'b1')]);
      final row = _row('row', blocks: [(0, 1, 'r1'), (1, 1, 'r2'), (2, 1, 'r1')]);
      final links = attachedLinksForMount(row: row, base: base)!;
      final baseCels = {for (final block in _blocks(base)) block.$3};
      expect(links.keys.map((id) => id.value).toSet(), baseCels);
    });

    test('refuse when a block starts elsewhere, holds differently, or there '
        'are more of them', () {
      final base = _row('base', blocks: [(0, 2, 'b1'), (2, 1, 'b2')]);
      expect(
        attachedLinksForMount(
          row: _row('row', blocks: [(1, 2, 'r1'), (3, 1, 'r2')]),
          base: base,
        ),
        isNull,
        reason: 'same lengths, shifted starts',
      );
      expect(
        attachedLinksForMount(
          row: _row('row', blocks: [(0, 1, 'r1'), (2, 1, 'r2')]),
          base: base,
        ),
        isNull,
        reason: 'same starts, different hold',
      );
      expect(
        attachedLinksForMount(
          row: _row('row', blocks: [(0, 2, 'r1')]),
          base: base,
        ),
        isNull,
        reason: 'fewer blocks',
      );
    });

    test('refuse when only the CEL-REUSE pattern differs — otherwise one of '
        'the row\'s two drawings would have no link to live in', () {
      final base = _row('base', blocks: [(0, 1, 'b1'), (1, 1, 'b1')]);
      final row = _row('row', blocks: [(0, 1, 'r1'), (1, 1, 'r2')]);
      expect(attachExposureShape(row).length, attachExposureShape(base).length);
      expect(attachedLinksForMount(row: row, base: base), isNull);
      // The row that mirrors the re-use is fine.
      expect(
        attachedLinksForMount(
          row: _row('row', blocks: [(0, 1, 'r1'), (1, 1, 'r1')]),
          base: base,
        ),
        {const FrameId('b1'): const FrameId('r1')},
      );
    });

    test('two EMPTY rows agree — nothing to lose, and the mirror fills in as '
        'the base gains cels', () {
      expect(
        attachedLinksForMount(row: _row('row'), base: _row('base')),
        isEmpty,
      );
      // An empty row against a base WITH work does not: that is where
      // "an empty row mounts FREE" comes from.
      expect(
        attachedLinksForMount(
          row: _row('row'),
          base: _row('base', blocks: [(0, 1, 'b1')]),
        ),
        isNull,
      );
    });
  });

  group('what can ride what', () {
    test('drawing rows only, no nesting, and no singleton kinds', () {
      final base = _row('base');
      expect(
        canMountLayerOnBase(row: _row('row'), base: base),
        isTrue,
      );
      expect(
        canMountLayerOnBase(row: _row('row', kind: LayerKind.text), base: base),
        isTrue,
      );
      expect(
        canMountLayerOnBase(row: _row('row', kind: LayerKind.se), base: base),
        isFalse,
      );
      expect(
        canMountLayerOnBase(
          row: _row('row', kind: LayerKind.folder),
          base: base,
        ),
        isFalse,
      );
      expect(
        canMountLayerOnBase(
          row: _row('row', kind: LayerKind.storyboard),
          base: base,
        ),
        isFalse,
        reason: 'a cut holds exactly one storyboard row',
      );
      expect(
        canMountLayerOnBase(
          row: _row('row'),
          base: _row('base2', attachedTo: 'base'),
        ),
        isFalse,
        reason: 'an attach row is never itself a base',
      );
      expect(canMountLayerOnBase(row: base, base: base), isFalse);
    });
  });

  group('detaching', () {
    Layer baseWith2Blocks() =>
        _row('base', blocks: [(0, 2, 'b1'), (2, 3, 'b2')]);

    test('a SYNCED row BAKES the derived timing into its own timeline and '
        'lets go of the links', () {
      final base = baseWith2Blocks();
      final attached = _row(
        'row',
        attachedTo: 'base',
        links: {'b1': 'r1', 'b2': 'r2'},
      );
      // Riding: it owns no timeline at all.
      expect(attached.timeline, isEmpty);

      final detached = detachedLayer(
        attached: attached,
        base: base,
        cutFrameCount: 6,
      );

      expect(detached.attachedToLayerId, isNull);
      expect(detached.baseFrameLinks, isEmpty);
      // The base's blocks, at the base's positions, showing the row's OWN
      // cels — which is exactly what the screen was showing.
      expect(_blocks(detached), [(0, 2, 'r1'), (2, 3, 'r2')]);
      expect(attachExposureShape(detached), attachExposureShape(base));
    });

    test('the base\'s run-edge behaviour comes along, restated through the '
        'links — the tail the user was looking at survives the next edit', () {
      final base = baseWith2Blocks().copyWith(
        runBehaviors: const [
          TimelineRunBehavior(
            anchorFrameId: FrameId('b1'),
            side: TimelineRunEdgeSide.end,
            mode: TimelineRunEdgeMode.hold,
          ),
        ],
      );
      final attached = _row(
        'row',
        attachedTo: 'base',
        links: {'b1': 'r1', 'b2': 'r2'},
      );

      final detached = detachedLayer(
        attached: attached,
        base: base,
        cutFrameCount: 8,
      );

      expect(detached.runBehaviors.single.anchorFrameId, const FrameId('r1'));
      // Rederived on the row's own blocks: the hold fills to the cut end
      // with the row's last cel, so the ghosts are the row's.
      final ghosts = detached.timeline.entries
          .where((entry) => entry.value.ghost)
          .toList();
      expect(ghosts, isNotEmpty);
      expect(ghosts.every((e) => e.value.frameId == const FrameId('r2')), isTrue);
      // An anchor with no link drops rather than pointing at a foreign cel.
      final unlinked = detachedLayer(
        attached: _row('row', attachedTo: 'base', links: {'b2': 'r2'}),
        base: base,
        cutFrameCount: 8,
      );
      expect(unlinked.runBehaviors, isEmpty);
    });

    test('a FREE row only loses the pointer — its timeline was always its '
        'own', () {
      final free = _row(
        'row',
        attachedTo: 'base',
        mode: AttachedMode.free,
        blocks: [(1, 4, 'r1')],
      );
      final detached = detachedLayer(
        attached: free,
        base: baseWith2Blocks(),
        cutFrameCount: 6,
      );
      expect(detached.attachedToLayerId, isNull);
      expect(_blocks(detached), [(1, 4, 'r1')]);
    });

    test('a DANGLING synced row (base deleted) detaches without inventing '
        'timing', () {
      final detached = detachedLayer(
        attached: _row('row', attachedTo: 'gone', links: {'b1': 'r1'}),
        base: null,
        cutFrameCount: 6,
      );
      expect(detached.attachedToLayerId, isNull);
      expect(detached.timeline, isEmpty);
      expect(detached.baseFrameLinks, isEmpty);
    });

    test('an ordinary row is returned untouched', () {
      final row = _row('row', blocks: [(0, 1, 'r1')]);
      expect(
        detachedLayer(attached: row, base: null, cutFrameCount: 3),
        same(row),
      );
    });
  });

  group('mounting', () {
    test('SYNCED clears the row\'s timeline and stores the links; the round '
        'trip through a detach gives the timing back', () {
      final base = _row('base', blocks: [(0, 2, 'b1'), (2, 1, 'b2')]);
      final row = _row('row', blocks: [(0, 2, 'r1'), (2, 1, 'r2')]);

      final mounted = attachmentForMount(
        standaloneRow: row,
        base: base,
        placement: AttachedPlacement.above,
        mode: AttachedMode.synced,
      ).applyTo(row);

      expect(mounted.attachedToLayerId, base.id);
      expect(mounted.attachedMode, AttachedMode.synced);
      expect(mounted.attachedPlacement, AttachedPlacement.above);
      expect(mounted.timeline, isEmpty);
      expect(mounted.baseFrameLinks, hasLength(2));
      // What the row shows while riding is what it had.
      expect(
        [
          for (final entry in attachedDisplayTimeline(
            attached: mounted,
            base: base,
          ).entries)
            (entry.key, entry.value.length!, entry.value.frameId!.value),
        ],
        _blocks(row),
      );
      final back = detachedLayer(
        attached: mounted,
        base: base,
        cutFrameCount: 3,
      );
      expect(_blocks(back), _blocks(row));
    });

    test('FREE keeps the row\'s timeline and behaviours and stores no links', () {
      final base = _row('base', blocks: [(0, 2, 'b1')]);
      final row = _row(
        'row',
        blocks: [(3, 1, 'r1')],
        runBehaviors: const [
          TimelineRunBehavior(
            anchorFrameId: FrameId('r1'),
            side: TimelineRunEdgeSide.end,
            mode: TimelineRunEdgeMode.hold,
          ),
        ],
      );

      final mounted = attachmentForMount(
        standaloneRow: row,
        base: base,
        placement: AttachedPlacement.below,
        mode: AttachedMode.free,
      ).applyTo(row);

      expect(mounted.attachedMode, AttachedMode.free);
      expect(mounted.attachedPlacement, AttachedPlacement.below);
      expect(_blocks(mounted), _blocks(row));
      expect(mounted.baseFrameLinks, isEmpty);
      expect(mounted.runBehaviors, row.runBehaviors);
    });

    test('a SYNCED request whose shapes disagree stands down to FREE rather '
        'than storing an incomplete link map', () {
      final base = _row('base', blocks: [(0, 2, 'b1'), (2, 1, 'b2')]);
      final row = _row('row', blocks: [(0, 1, 'r1')]);

      final mounted = attachmentForMount(
        standaloneRow: row,
        base: base,
        placement: AttachedPlacement.above,
        mode: AttachedMode.synced,
      ).applyTo(row);

      expect(mounted.attachedMode, AttachedMode.free);
      expect(mounted.baseFrameLinks, isEmpty);
      expect(_blocks(mounted), _blocks(row));
    });
  });

  test('LayerAttachment.of round-trips a row through applyTo', () {
    final row = _row(
      'row',
      attachedTo: 'base',
      links: {'b1': 'r1'},
      blocks: [(0, 1, 'r1')],
    );
    expect(LayerAttachment.of(row).applyTo(row), row);
  });
}
