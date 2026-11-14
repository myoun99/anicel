import 'dart:typed_data';

/// The 4-neighbour growth an 8-bit coverage mask goes through, in place,
/// [passes] generations: an area's expand ([dilateMask4]).
///
/// ⚠️IT IS SPELLED ONCE MORE, OUTSIDE DART: the engine's mask kernel
/// (`packages/gpu_engine/rust/src/kernels/mask`, WGSL) grows and shrinks
/// the same way, and since 2026-11-12 the bucket's expand is its growth —
/// while an area's expand (`buildRegionFillDabs`) is still this one.
/// `test/native/an_area_is_finished_as_the_bucket_is_test.dart` holds
/// [dilateMask4] to the kernel's byte for byte (board
/// `an-areas-finish-is-a-second-spelling-of-the-floods`). ↩️The C kernel
/// `qa_fill_finish_mask` mode 1 was that copy till then. ↩️A selection's
/// grow was this one and its shrink `erodeMask4` here till 2026-11-14,
/// when the last of the CPU's selection masks went (board
/// `a-selection-mask-is-built-on-the-cpu-at-every-move`, L2d).

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
