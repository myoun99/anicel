import 'dart:typed_data';

/// ONE boundary soft pass over an 8-bit coverage mask: every pixel whose
/// 4-neighbourhood is not uniform becomes `(center * 3 + neighbour sum) / 7`,
/// rounded — an area's anti-alias, which reaches one pixel past its own
/// outline: the fill is painting, and paint that stops dead on the outline
/// reads as a hard edge.
///
/// ⚠️IT IS SPELLED ONCE MORE, OUTSIDE DART. The engine's mask kernel
/// (`packages/gpu_engine/rust/src/kernels/mask`, WGSL) carries this
/// arithmetic, and since 2026-11-12 the bucket's flood is finished by it —
/// while an area (`buildRegionFillDabs`) is still finished here. `test/
/// native/an_area_is_finished_as_the_bucket_is_test.dart` holds this to the
/// kernel's byte for byte — the one kind of copy this repo keeps is one a
/// test holds shut — so a change to this arithmetic is a change to the
/// kernel's (board `an-areas-finish-is-a-second-spelling-of-the-floods`).
/// ↩️The C kernel `qa_fill_finish_mask` was that copy till then, held by
/// `fill_gap_close_test`, which skipped without a built DLL.
///
/// ↩️A selection's anti-alias was this pass too, clamped inside its outline
/// by an argument — the formula shared, the meaning not (유저 2026-08-27 ·
/// 「억지로 하나로 만들면 안 된다 — 뜻이 둘이다」) — till 2026-11-14, when the
/// last of the CPU's selection masks went (board
/// `a-selection-mask-is-built-on-the-cpu-at-every-move`, L2d). The clamp
/// and why lives where a selection is finished now: the engine's
/// `mask_softened` (mask.wgsl). ↩️So did the 3-4 chamfer distance a
/// selection's feather measured (`chamferDistance34`), now `kernels/mask`'s.
void softenMaskBoundary(
  Uint8List mask, {
  required int width,
  required int height,
}) {
  final source = Uint8List.fromList(mask);
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final index = y * width + x;
      final center = source[index];
      final left = x > 0 ? source[index - 1] : 0;
      final right = x < width - 1 ? source[index + 1] : 0;
      final up = y > 0 ? source[index - width] : 0;
      final down = y < height - 1 ? source[index + width] : 0;
      final sum = center + left + right + up + down;
      if (sum == center * 5) {
        continue;
      }
      mask[index] = ((center * 3 + (sum - center)) / 7).round();
    }
  }
}
