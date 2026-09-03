// A CAMERA MARK TYPE ROUND-TRIPS THROUGH ITS JSON NAME, AND ANYTHING ELSE
// DECODES TO THE BAR SO OLD FILES STAY OPEN-ABLE.
//
// The mutation campaign (2026-09-03) turned the decoder's `==` into `!=` —
// every name then decoded to the first type that was NOT it — and nothing
// noticed. These pins do.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/camera_instruction.dart';

void main() {
  test('every type decodes from its own json name', () {
    for (final type in CameraInstructionMarkType.values) {
      expect(
        CameraInstructionMarkType.fromJson(type.jsonValue),
        type,
        reason: type.jsonValue,
      );
    }
  });

  test('an unknown or absent name decodes to the bar', () {
    expect(
      CameraInstructionMarkType.fromJson('no-such-mark'),
      CameraInstructionMarkType.bar,
    );
    expect(
      CameraInstructionMarkType.fromJson(null),
      CameraInstructionMarkType.bar,
    );
  });
}
