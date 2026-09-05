import 'dart:typed_data';

/// THE seed test every flood shares: whether the RGB at [base] in [rgb]
/// (three bytes, whatever the stride) is within [tolerance] of the seed
/// on EVERY channel — inclusive, so a pixel exactly `tolerance` away
/// fills. The plain flood, the close-gap flood and the native wave
/// driver's candidate re-test each wrote this out; the C kernels mirror
/// it and the parity suites hold them to it.
///
/// Per pixel and inlined: a static leaf, not a closure, so the hot loops
/// that call it gain no call at all.
@pragma('vm:prefer-inline')
bool rgbWithinTolerance(
  Uint8List rgb,
  int base,
  int seedR,
  int seedG,
  int seedB,
  int tolerance,
) =>
    (rgb[base] - seedR).abs() <= tolerance &&
    (rgb[base + 1] - seedG).abs() <= tolerance &&
    (rgb[base + 2] - seedB).abs() <= tolerance;
