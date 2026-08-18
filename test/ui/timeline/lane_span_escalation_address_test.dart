import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/timeline/timeline_row_span_resolver.dart';

/// C② — the escalation law in the ADDRESS vocabulary: the one form the
/// storyboard rail can feed (a TRACK row has no Layer to wrap, the audio
/// strip has no address at all).
void main() {
  const se = LayerId('se-1');
  const trackId = TrackId('t');

  /// The storyboard rail's shape, top to bottom: transition row, SE row,
  /// audio strip (address-less), the lane group, then the V row.
  final rows = <TimelineRowAddress?>[
    const LayerRowAddress(LayerId('t-transitions')),
    const LayerRowAddress(se),
    null, // the audio strip — space, but never a head
    const LaneRowAddress(se, 'transform-group'),
    const LaneRowAddress(se, 'position'),
    const LaneRowAddress(se, 'scale'),
    const TrackRowAddress(trackId),
  ];

  test('in-group stays with the lane law (null), and the in-group head '
      'resolves off the same rows', () {
    expect(
      resolveLaneSpanEscalationOverAddresses(
        rows: rows,
        layerId: se,
        laneId: 'position',
        rowDelta: 1,
      ),
      isNull,
    );
    expect(
      resolveInGroupHeadLane(
        rows: rows,
        layerId: se,
        laneId: 'position',
        rowDelta: 1,
      ),
      'scale',
    );
    expect(
      resolveInGroupHeadLane(
        rows: rows,
        layerId: se,
        laneId: 'position',
        rowDelta: 0,
      ),
      isNull,
    );
  });

  test('UP across the address-less strip: the null row is counted for '
      'space, skipped as a head, and dropped from the span', () {
    final escalation = resolveLaneSpanEscalationOverAddresses(
      rows: rows,
      layerId: se,
      laneId: 'position',
      rowDelta: -3,
    )!;

    expect(escalation.head, const LayerRowAddress(se));
    expect(escalation.spanRows, const [
      LayerRowAddress(se),
      LaneRowAddress(se, 'transform-group'),
      LaneRowAddress(se, 'position'),
    ]);
  });

  test('a head that LANDS on the address-less strip walks back toward the '
      'anchor', () {
    // rowDelta -2 from 'position' is the null audio slot — the head steps
    // back to the group header, which is IN-GROUP, so the lane law keeps
    // the drag.
    expect(
      resolveLaneSpanEscalationOverAddresses(
        rows: rows,
        layerId: se,
        laneId: 'position',
        rowDelta: -2,
      ),
      isNull,
    );
  });

  test('DOWN onto the TRACK row — the head the TimelineDisplayRow form '
      'could never represent', () {
    final escalation = resolveLaneSpanEscalationOverAddresses(
      rows: rows,
      layerId: se,
      laneId: 'position',
      rowDelta: 2,
    )!;

    expect(escalation.head, const TrackRowAddress(trackId));
    expect(escalation.spanRows, const [
      LaneRowAddress(se, 'position'),
      LaneRowAddress(se, 'scale'),
      TrackRowAddress(trackId),
    ]);
  });

  test('clamps at the ends and answers null off-screen', () {
    expect(
      resolveLaneSpanEscalationOverAddresses(
        rows: rows,
        layerId: se,
        laneId: 'position',
        rowDelta: 99,
      )!.head,
      const TrackRowAddress(trackId),
    );
    expect(
      resolveLaneSpanEscalationOverAddresses(
        rows: rows,
        layerId: const LayerId('not-here'),
        laneId: 'position',
        rowDelta: 1,
      ),
      isNull,
    );
  });
}
