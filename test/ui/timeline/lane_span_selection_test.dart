import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/timeline/transform_lane_editing.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart';

/// R26 #3: the lane selection becomes the cells' grammar — multi-lane
/// spans (Excel rule on lane rows), the group header as the whole-group
/// anchor, and the rigid all-or-nothing multi-lane key move.
void main() {
  group('transformLaneSpan', () {
    test('spans display-ordered lanes between anchor and head', () {
      expect(transformLaneSpan('position', 'rotation'), [
        'position',
        'scale',
        'rotation',
      ]);
      // Direction never matters — the span is the ordered interval.
      expect(transformLaneSpan('rotation', 'position'), [
        'position',
        'scale',
        'rotation',
      ]);
      expect(transformLaneSpan('scale', 'scale'), ['scale']);
    });

    test('the group header as either endpoint selects the whole group', () {
      expect(
        transformLaneSpan(transformGroupHeaderLane.laneId, 'scale'),
        transformLaneDisplayOrder,
      );
      expect(
        transformLaneSpan('position', transformGroupHeaderLane.laneId),
        transformLaneDisplayOrder,
      );
    });

    test('unknown lane ids fall back to the anchor alone', () {
      expect(transformLaneSpan('se-audio', 'position'), ['se-audio']);
      expect(transformLaneSpan('position', 'folder-fx:f1:position'), [
        'position',
      ]);
    });
  });

  group('TimelineLaneSelection span', () {
    const selection = TimelineLaneSelection(
      layerId: LayerId('layer-a'),
      laneId: 'position',
      startIndex: 2,
      endIndexExclusive: 6,
      laneIds: ['position', 'scale', 'rotation'],
    );

    test('coversLane follows the span, not just the anchor', () {
      expect(selection.coversLane(const LayerId('layer-a'), 'scale'), isTrue);
      expect(
        selection.coversLane(const LayerId('layer-a'), 'rotation'),
        isTrue,
      );
      expect(
        selection.coversLane(const LayerId('layer-a'), 'opacity'),
        isFalse,
      );
      expect(selection.coversLane(const LayerId('layer-b'), 'scale'), isFalse);
    });

    test('anchor-only selections keep the single-lane contract', () {
      const single = TimelineLaneSelection(
        layerId: LayerId('layer-a'),
        laneId: 'position',
        startIndex: 0,
        endIndexExclusive: 1,
      );
      expect(single.spanLaneIds, ['position']);
      expect(single.coversLane(const LayerId('layer-a'), 'position'), isTrue);
      expect(single.coversLane(const LayerId('layer-a'), 'scale'), isFalse);
    });
  });

  group('laneSelectionCoversBandRow (the shared paint+gesture predicate)', () {
    const wholeGroup = TimelineLaneSelection(
      layerId: LayerId('layer-a'),
      laneId: 'transform-group',
      startIndex: 0,
      endIndexExclusive: 5,
      laneIds: ['anchor-point', 'position', 'scale', 'rotation', 'opacity'],
    );
    const partial = TimelineLaneSelection(
      layerId: LayerId('layer-a'),
      laneId: 'position',
      startIndex: 0,
      endIndexExclusive: 5,
      laneIds: ['position', 'scale'],
    );

    test('the header row counts as covered ONLY by a whole-group span '
        '(so a header drag inside it MOVES — 한번에 잡아 이동)', () {
      expect(
        laneSelectionCoversBandRow(
          wholeGroup,
          const LayerId('layer-a'),
          'transform-group',
        ),
        isTrue,
      );
      expect(
        laneSelectionCoversBandRow(
          partial,
          const LayerId('layer-a'),
          'transform-group',
        ),
        isFalse,
      );
      expect(
        laneSelectionCoversBandRow(
          wholeGroup,
          const LayerId('layer-b'),
          'transform-group',
        ),
        isFalse,
      );
      expect(
        laneSelectionCoversBandRow(null, const LayerId('layer-a'), 'position'),
        isFalse,
      );
    });

    test('member rows keep reading the span directly', () {
      expect(
        laneSelectionCoversBandRow(
          partial,
          const LayerId('layer-a'),
          'scale',
        ),
        isTrue,
      );
      expect(
        laneSelectionCoversBandRow(
          partial,
          const LayerId('layer-a'),
          'rotation',
        ),
        isFalse,
      );
    });
  });

  group('transformTrackWithLaneSpanKeysShifted', () {
    TransformTrack track() => TransformTrack.properties(
      anchorPoint: PropertyTrack.empty(),
      position: PropertyTrack(
        keys: {
          2: PropertyKey(CanvasPoint(x: 1, y: 1)),
          8: PropertyKey(CanvasPoint(x: 9, y: 9)),
        },
      ),
      scale: PropertyTrack(keys: {3: const PropertyKey(1.5)}),
      rotation: PropertyTrack.empty(),
      opacity: PropertyTrack(keys: {4: const PropertyKey(0.5)}),
    );

    test('shifts every spanned lane rigidly; empty lanes ride along', () {
      final shifted = transformTrackWithLaneSpanKeysShifted(
        track(),
        laneIds: const ['position', 'scale', 'rotation'],
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 5,
        frameDelta: 2,
      );
      expect(shifted, isNotNull);
      expect(shifted!.position.keys.keys.toSet(), {4, 8});
      expect(shifted.scale.keys.keys.toSet(), {5});
      // Out-of-span lanes are untouched.
      expect(shifted.opacity.keys.keys.toSet(), {4});
    });

    test('one blocked lane vetoes the whole move (all-or-nothing)', () {
      // position's ranged key at 2 would land on its unshifted key at 8.
      final blocked = transformTrackWithLaneSpanKeysShifted(
        track(),
        laneIds: const ['position', 'scale'],
        rangeStartIndex: 2,
        rangeEndIndexExclusive: 4,
        frameDelta: 6,
      );
      expect(blocked, isNull);
    });

    test('null when no spanned lane has a ranged key', () {
      final none = transformTrackWithLaneSpanKeysShifted(
        track(),
        laneIds: const ['rotation'],
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 10,
        frameDelta: 1,
      );
      expect(none, isNull);
    });

    test('matches the single-lane shifter on a one-lane span', () {
      final span = transformTrackWithLaneSpanKeysShifted(
        track(),
        laneIds: const ['scale'],
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 10,
        frameDelta: 3,
      );
      final single = transformTrackWithLaneKeysShifted(
        track(),
        laneId: 'scale',
        rangeStartIndex: 0,
        rangeEndIndexExclusive: 10,
        frameDelta: 3,
      );
      expect(span!.scale.keys.keys.toSet(), single!.scale.keys.keys.toSet());
    });
  });
}
