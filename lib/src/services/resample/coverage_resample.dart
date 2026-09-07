import 'dart:typed_data';

import 'resample_kernel.dart';

/// Reads an 8-bit COVERAGE map to another size through the app's ONE
/// resampler.
///
/// 🚨AVERAGED, not sampled. A tip mask is coverage, and a resize that
/// reads one source pixel per destination pixel drops the thin parts of a
/// stroke entirely — the failure `resample_kernel.dart` describes for
/// point sampling under reduction ("a destination pixel is not a point").
/// Averaging every source pixel the destination covers keeps the ink that
/// was drawn, at the weight it was drawn.
///
/// The two-value argument that keeps the stamp path on Pick does not
/// apply here: a tip mask is coverage, and a partly covered tip pixel is
/// a real thing rather than an invented mid-alpha edge. So [ResampleMode.blend].
///
/// ★THE ANSWER TO ARCH-audit-Q7 (board card, answered 2026-09-07, option
/// 2). The question was whether the image-tip's fixed 4-tap bilinear
/// should become an area average; the answer came back one better — the
/// SHARED resampler, because minification has to filter in proportion to
/// the reduction and this kernel already does: its tent radius is the
/// preimage's bounding box (`radiusX = math.max(floor, extentX)`), so
/// shrinking 4× reads 4 source pixels while a fixed 4-tap bilinear reads
/// 4 whatever the reduction and aliases. The user's criterion was "do it
/// the way professional tools do it; the tip's appearance changing is
/// fine". Every tip mask in the app minifies through here now, and there
/// is no second minification filter left to drift from it.
///
/// ★WHY A CONVERSION AND NOT A GRAY ENTRY POINT IN THE KERNEL — the
/// honest cost, decided 2026-09-07. The kernel is RGBA8 and this is
/// 8-bit gray, so this costs 4× the memory and the arithmetic of a gray
/// path. The alternative was a second accumulator inside
/// `resampleRgbaReferenceInto`, and that was rejected on two counts the
/// kernel states about itself: its agreement with the C engine is
/// EXPRESSION IDENTITY, not value identity ("the C kernel's parity with
/// this reference is expression identity"), so an 8-bit accumulator would
/// have to be mirrored in C and re-pinned by `qa_resample_rgba` parity or
/// the two languages would quietly diverge; and selecting between two
/// accumulators per tap is a branch in the innermost loop the whole file
/// is built to keep flat. This conversion runs ONCE, on a deliberate
/// "register this tip" action, on an image the library caps at 256px
/// on the way out — not in any hot loop. The kernel
/// is untouched, so the native/Dart byte parity still holds unchanged.
///
/// ★COVERAGE RIDES IN ALPHA, OVER BLACK. That is already the app's RGBA
/// spelling of a tip mask — `encodeBrushTipImage` writes a tip that way
/// and says why ("premultiplying black is black, so no rounding can creep
/// into the round trip") — and it is the spelling Blend answers exactly:
/// Blend's colour channels are averaged weighted by alpha, so black
/// contributes nothing, while its alpha is `Σw·coverage / Σw`, which IS
/// the proportional mean this function is for.
///
/// ⚠️OUTSIDE THE SOURCE IS EMPTY, which is the kernel's own boundary rule
/// ([kResampleOutsideToken]: "Fully transparent — what a destination
/// pixel gets when its preimage falls outside the source") and NOT a
/// choice made here. It is also the truthful one for coverage: outside
/// the registered image there is no ink, so a destination pixel straddling
/// the border is partly covered. The two filters this replaced both
/// clamped the border instead, so a tip whose drawing runs to the very
/// edge of its file now fades over the reduction's own radius rather than
/// ending in a cliff. Padding the source to avoid that would be this
/// caller inventing a second boundary rule for itself, which is the thing
/// that is forbidden.
///
/// ⛔NOT downscale-only. The predecessor (`areaAveragedGray`) refused to
/// enlarge — "Enlarging through here would nearest-neighbour, and the
/// shared resampler (`resampleRgbaReferenceInto`) is the answer for that"
/// — and this IS that resampler, so the thumbnail of a tip smaller than
/// its preview cell comes out reconstructed instead of blocky.
Uint8List resampleCoverage(
  Uint8List source, {
  required int width,
  required int height,
  required int newWidth,
  required int newHeight,
}) {
  final rgba = Uint8List(width * height * 4);
  for (var index = 0; index < source.length; index += 1) {
    rgba[index * 4 + 3] = source[index];
  }

  // Destination-to-source, so the scale is the REDUCTION: one destination
  // step covers `width / newWidth` source pixels, which is exactly the
  // extent the kernel turns into its tent radius.
  final resampled = resampleRgbaReference(
    src: rgba,
    srcWidth: width,
    srcHeight: height,
    dstWidth: newWidth,
    dstHeight: newHeight,
    transform: ResampleTransform(
      a: width / newWidth,
      b: 0,
      c: 0,
      d: 0,
      e: height / newHeight,
      f: 0,
    ),
    mode: ResampleMode.blend,
  );

  final coverage = Uint8List(newWidth * newHeight);
  for (var index = 0; index < coverage.length; index += 1) {
    coverage[index] = resampled[index * 4 + 3];
  }
  return coverage;
}
