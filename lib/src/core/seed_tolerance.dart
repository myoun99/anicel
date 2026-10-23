import 'dart:typed_data';

/// The pixel at [base] in [rgba] as one seed — the four bytes a fill
/// raster holds a pixel in (premultiplied colour, then coverage), red in
/// the low byte: the form every flood takes its seed in, the native ones
/// too.
int seedAt(Uint8List rgba, int base) =>
    rgba[base] |
    rgba[base + 1] << 8 |
    rgba[base + 2] << 16 |
    rgba[base + 3] << 24;

/// THE seed test every flood shares: whether the pixel at [base] in [rgba]
/// is within [tolerance] of [seed] ([seedAt]) on EVERY lane — inclusive,
/// so a pixel exactly `tolerance` away fills. The plain flood, the
/// close-gap flood and the native wave driver's candidate re-test each
/// wrote this out; the C kernels mirror it and the parity suites hold them
/// to it.
///
/// 🚨THE COVERAGE IS A LANE LIKE THE COLOURS (board F-416 — 유저
/// 2026-10-20: 「레이어에 그린것도 흰색일때 … 배경이랑 그림이랑 같은 흰색이라고
/// 생각해서 캔버스 전체를 칠해버리는거같음. 그림부분만 칠해야하는데」). A pixel
/// drawn white and the empty canvas are as far apart as their coverage,
/// whatever the paper shows under them. ↩️Compared on the colour over the
/// paper alone, ink of the paper's colour was the paper — white ink on a
/// white paper, and black ink on an absent one, which the fill read as
/// black — and a fill on it flooded the whole canvas.
///
/// Per pixel and inlined: a static leaf, not a closure, so the hot loops
/// that call it gain no call at all.
@pragma('vm:prefer-inline')
bool pixelWithinTolerance(
  Uint8List rgba,
  int base,
  int seed,
  int tolerance,
) =>
    (rgba[base] - (seed & 0xFF)).abs() <= tolerance &&
    (rgba[base + 1] - (seed >> 8 & 0xFF)).abs() <= tolerance &&
    (rgba[base + 2] - (seed >> 16 & 0xFF)).abs() <= tolerance &&
    (rgba[base + 3] - (seed >> 24 & 0xFF)).abs() <= tolerance;
