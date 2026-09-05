import 'dart:typed_data';

/// The two 4-neighbour morphological passes an 8-bit coverage mask goes
/// through, in place, [passes] generations each: the fill's expand and the
/// selection's grow are [dilateMask4]; the selection's shrink is
/// [erodeMask4]. The caller picks the operator from the SIGN of its value
/// — there is no mode inside these kernels.
///
/// ⚠️ THE C MIRROR: `qa_fill_finish_mask` mode 1 in
/// `packages/qa_native/src/qa_engine.c` is the fill expand's native copy
/// ('identical to the Dart grown-copy'), held to [dilateMask4] mask for
/// mask by `test/services/fill_gap_close_test.dart` ('C kernel == Dart
/// reference, mask for mask') and `test/services/
/// qa_native_engine_parity_test.dart`. Both SKIP without a built
/// `qa_engine.dll` — build it before touching this file.

/// Expand: grow the region by N pixels (covers anti-aliased ink edges).
/// 4-neighbor generations — generation-exact like the fill expand: a zero
/// pixel that touches a nonzero pixel on a side becomes 255, a nonzero
/// pixel keeps its byte, and the canvas edge is not a barrier.
void dilateMask4(
  Uint8List mask, {
  required int width,
  required int height,
  required int passes,
}) => _generations(
  mask,
  passes,
  (src, dst) => _dilateGeneration(src, dst, width, height),
);

/// Shrink: a nonzero pixel that touches a zero pixel on a side, or sits
/// on the canvas border, becomes 0; the rest keep their byte.
void erodeMask4(
  Uint8List mask, {
  required int width,
  required int height,
  required int passes,
}) => _generations(
  mask,
  passes,
  (src, dst) => _erodeGeneration(src, dst, width, height),
);

/// [passes] generations of [step] over [mask], in place. Each generation
/// reads the previous one whole and writes the next, so growth is
/// diamond-shaped (a diagonal neighbour is two generations away). ONE
/// scratch buffer serves every pass — the two are swapped, and the result
/// is copied back only when it landed in the scratch. [step] is called
/// once per PASS, never per pixel.
void _generations(
  Uint8List mask,
  int passes,
  void Function(Uint8List src, Uint8List dst) step,
) {
  var src = mask;
  var dst = Uint8List(mask.length);
  for (var pass = 0; pass < passes; pass += 1) {
    step(src, dst);
    final swap = src;
    src = dst;
    dst = swap;
  }
  if (!identical(src, mask)) {
    mask.setAll(0, src);
  }
}

void _dilateGeneration(Uint8List src, Uint8List dst, int width, int height) {
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final index = y * width + x;
      final center = src[index];
      if (center != 0) {
        dst[index] = center;
        continue;
      }
      final touches =
          (x > 0 && src[index - 1] != 0) ||
          (x < width - 1 && src[index + 1] != 0) ||
          (y > 0 && src[index - width] != 0) ||
          (y < height - 1 && src[index + width] != 0);
      dst[index] = touches ? 255 : 0;
    }
  }
}

void _erodeGeneration(Uint8List src, Uint8List dst, int width, int height) {
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final index = y * width + x;
      final center = src[index];
      if (center == 0) {
        dst[index] = 0;
        continue;
      }
      final touches =
          (x > 0 && src[index - 1] == 0) ||
          (x < width - 1 && src[index + 1] == 0) ||
          (y > 0 && src[index - width] == 0) ||
          (y < height - 1 && src[index + width] == 0) ||
          x == 0 ||
          x == width - 1 ||
          y == 0 ||
          y == height - 1;
      dst[index] = touches ? 0 : center;
    }
  }
}
