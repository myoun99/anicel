import 'dart:typed_data';

/// ONE boundary soft pass over an 8-bit coverage mask: every pixel whose
/// 4-neighbourhood is not uniform becomes `(center * 3 + neighbour sum) / 7`,
/// rounded.
///
/// 🚨★★★THE FORMULA IS SHARED. THE MEANING IS NOT — and that is what
/// [insideOutlineOnly] is for.
///
/// A FILL's anti-alias is allowed to reach one pixel past its own outline:
/// the fill is painting, and paint that stops dead on the outline reads as
/// a hard edge. A SELECTION's is not: since #1288 a pixel the mask touches
/// at all travels whole, so a ramp outside the outline is a ring of the
/// neighbour's artwork lifted along with the selection and erased from where
/// it was (유저 2026-08-27, after looking at TVPaint: 「애초 tvp 보니까
/// **선택의 aa가 선택 바깥에 걸리는게 아니라 선택 안쪽에 걸고있는거같거든**?」).
///
/// ⛔SO DO NOT COLLAPSE THE TWO INTO ONE ANSWER. The card that opened this
/// said it in one line: 「억지로 하나로 만들면 안 된다 — 뜻이 둘이다」. What
/// they share is the arithmetic; what they disagree about is a clamp, and a
/// clamp is an argument.
///
/// ⚠️THERE IS A THIRD COPY AND IT STAYS. `qa_fill_finish_mask` in
/// `packages/qa_native/src/qa_engine.c` is the C kernel for the FILL, and it
/// mirrors the `insideOutlineOnly: false` branch line for line — including
/// the double division and the round, for byte identity.
/// `fill_gap_close_test` compares them mask for mask on randomised walls, so
/// the C copy is the one kind of copy this repo keeps: one a test holds shut.
/// 🚨That test SKIPS when `qa_engine.dll` is not built. Build it before
/// touching this file — the command is in `qa_engine_abi.dart`'s header —
/// or the guard is not running and you will not be told.
void softenMaskBoundary(
  Uint8List mask, {
  required int width,
  required int height,
  required bool insideOutlineOnly,
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
      final softened = ((center * 3 + (sum - center)) / 7).round();
      // ⚠️`center` is this pixel BEFORE the pass, which is the hard outline's
      // own answer — 255 inside, 0 outside. Taking the smaller of the two
      // lets the ramp only ever darken what was already in, and never lights
      // up what was out.
      mask[index] = insideOutlineOnly && softened > center ? center : softened;
    }
  }
}
