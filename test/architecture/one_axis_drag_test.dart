import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨★★AN AXIS DRAG NAMES ITS RECOGNISER FAMILY IN ONE PLACE.
///
/// A drag that runs along one axis mounts that axis's recogniser family and
/// NOT the other's — the rail swipe wrote the law down (「ONE recogniser
/// family, chosen by the axis … two recognisers in the arena where the host
/// only has one gesture」), and four more widgets spelled the same choice by
/// hand, `horizontal ? handler : null` eight times each. `AxisGestureDetector`
/// is the one spelling (rule of three: five sites).
///
/// The scan: a file that names BOTH `onHorizontalDragStart:` and
/// `onVerticalDragStart:` is choosing the family itself. Only the home may.
void main() {
  const home = 'lib/src/ui/widgets/axis_gesture_detector.dart';

  bool choosesTheFamily(String text) =>
      text.contains('onHorizontalDragStart:') &&
      text.contains('onVerticalDragStart:');

  test('premise: the home chooses the family', () {
    expect(choosesTheFamily(File(home).readAsStringSync()), isTrue);
  });

  test('no other file mounts both drag families', () {
    final offenders = <String>[
      for (final file in dartFilesUnder('lib'))
        if (libPath(file) != home && choosesTheFamily(file.readAsStringSync()))
          libPath(file),
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'mount AxisGestureDetector(axis: …) and hand it the handlers',
    );
  });
}
