// A FRONT-EDGE DRAG ON A PANEL THAT DOES NOT EXIST HAS NO ROOM TO SHRINK —
// NULL, NOT A CRASH.
//
// A survivor of the mutation campaign (2026-09-03): one `||` in the
// out-of-range guard became `&&`, and an index past the last panel read
// straight into the key list. Nothing noticed; these pins ask for panels
// that are not there.
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/storyboard_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';

void main() {
  test('a panel index past the end has no lead bounds', () {
    expect(
      storyboardPanelLeadMaxShrink(
        timeline: SplayTreeMap<int, TimelineExposure>(),
        cutDuration: 10,
        panelIndex: 3,
      ),
      isNull,
    );
  });

  test('a negative panel index has no lead bounds', () {
    expect(
      storyboardPanelLeadMaxShrink(
        timeline: SplayTreeMap<int, TimelineExposure>(),
        cutDuration: 10,
        panelIndex: -1,
      ),
      isNull,
    );
  });
}
