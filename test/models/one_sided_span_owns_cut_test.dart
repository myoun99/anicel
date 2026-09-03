// A ZERO-LENGTH TRANSITION SPAN OWNS NO CUT; A ONE-SIDED SPAN OWNS THE CUT
// ITS ANCHOR FRAME SITS IN.
//
// A survivor of the mutation campaign (2026-09-03): the empty-span guard's
// `length <= 0` became `length < 0`, so a zero-length fade-out anchored at
// its start frame claimed the cut around it. Nothing noticed; this pins
// the guard beside the rule it guards.
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/transition_geometry.dart';

void main() {
  test('a zero-length span owns nothing', () {
    expect(
      oneSidedSpanOwnsCut(
        span: (start: 5, length: 0, mark: CameraInstructionMarkType.fo),
        cutStart: 0,
        cutEnd: 10,
      ),
      isFalse,
    );
  });

  test('a fade-out owns the cut its first frame is in', () {
    const span = (start: 5, length: 3, mark: CameraInstructionMarkType.fo);
    expect(oneSidedSpanOwnsCut(span: span, cutStart: 0, cutEnd: 6), isTrue);
    expect(oneSidedSpanOwnsCut(span: span, cutStart: 6, cutEnd: 12), isFalse);
  });

  test('a fade-in owns the cut its last frame is in', () {
    const span = (start: 5, length: 3, mark: CameraInstructionMarkType.fi);
    expect(oneSidedSpanOwnsCut(span: span, cutStart: 0, cutEnd: 6), isFalse);
    expect(oneSidedSpanOwnsCut(span: span, cutStart: 6, cutEnd: 12), isTrue);
  });

  test('a two-sided span answers no cut', () {
    const span = (start: 5, length: 3, mark: CameraInstructionMarkType.ol);
    expect(oneSidedSpanOwnsCut(span: span, cutStart: 0, cutEnd: 12), isFalse);
  });
}
