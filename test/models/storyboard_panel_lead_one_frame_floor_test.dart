// A FRONT-EDGE DRAG STOPS ONE FRAME SHORT OF EMPTYING THE PANEL, AND THE
// QUERY AND THE RETIME AGREE ON WHERE THAT IS.
//
// `storyboardPanelLeadMaxShrink` reports the room and
// `storyboardTimelineWithPanelLeadRetimed` clamps to it; the two used to
// compute the floor separately, so these pins hold them to one number.
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/storyboard_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

SplayTreeMap<int, TimelineExposure> _row(Map<int, int> lengths) =>
    SplayTreeMap<int, TimelineExposure>.of({
      for (final entry in lengths.entries)
        entry.key: TimelineExposure.drawing(
          FrameId('f${entry.key}'),
          length: entry.value,
        ),
    });

void main() {
  test('the room is the cell minus its one kept frame', () {
    expect(
      storyboardPanelLeadMaxShrink(
        timeline: _row({0: 4, 4: 6}),
        cutDuration: 10,
        panelIndex: 1,
      ),
      5,
    );
  });

  test('a delta past the room retimes exactly as the room itself does', () {
    final atTheFloor = storyboardTimelineWithPanelLeadRetimed(
      timeline: _row({0: 4, 4: 6}),
      cutDuration: 10,
      panelIndex: 1,
      delta: 5,
    );
    final pastTheFloor = storyboardTimelineWithPanelLeadRetimed(
      timeline: _row({0: 4, 4: 6}),
      cutDuration: 10,
      panelIndex: 1,
      delta: 8,
    );

    expect(atTheFloor, isNotNull);
    expect(pastTheFloor, atTheFloor);
    expect(atTheFloor![4]!.length, 1, reason: 'the panel keeps one frame');
  });

  test('a one-frame panel has no room, and a drag on it retimes nothing', () {
    expect(
      storyboardPanelLeadMaxShrink(
        timeline: _row({0: 4, 4: 1, 5: 5}),
        cutDuration: 10,
        panelIndex: 1,
      ),
      0,
    );
    expect(
      storyboardTimelineWithPanelLeadRetimed(
        timeline: _row({0: 4, 4: 1, 5: 5}),
        cutDuration: 10,
        panelIndex: 1,
        delta: 3,
      ),
      isNull,
    );
  });
}
