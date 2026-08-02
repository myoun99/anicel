import 'dart:typed_data';

import 'package:anicel/src/services/resample/resample_kernel.dart';

/// The DEFINITION of Pick, computed the slow honest way, so the fast
/// kernel has something to be wrong against.
///
/// Pick's contract says the colour covering the most of a destination
/// pixel's preimage wins. That is a statement about area, and area is
/// exactly what a separable weight cannot measure once the preimage stops
/// being axis-aligned: a rotation turns it into a parallelogram, and any
/// product of two one-dimensional weights integrates over a RECTANGLE.
///
/// This integrates over the real thing. It subdivides the destination
/// pixel into [samples]² points, maps each through the same inverse
/// transform the kernel uses, and counts which source pixel each landed
/// in. The winner is the colour with the most samples. That is the area
/// argmax by construction — no footprint, no radius, no separability —
/// and it converges to the true answer as [samples] grows.
///
/// It is far too slow to ship (a 200×200 output at 24² samples is 23
/// million inverse maps) and that is fine: its job is to be right, in a
/// test, so a measurement can say how far the shipping kernel is from
/// right rather than how far it is from its previous self. Two rounds of
/// this feature were fixed against the kernel's own previous behaviour
/// and both times the remaining error was invisible for exactly that
/// reason.
///
/// The shipping kernel is now this same computation — the separable box it
/// was written to indict is gone. It differs only in what it can afford:
/// a rate chosen per axis from the source-space length of that axis's
/// step, one doubling when the vote comes back tied, and a sixteen-slot
/// vote table where this one has an unbounded map. Those are the three
/// places a disagreement can come from, and the sweep in
/// `resample_kernel_test.dart` measures how large it gets (1.06% of
/// pixels, worst case, all of them near-ties).
Uint8List coverageTruth({
  required Uint8List src,
  required int srcWidth,
  required int srcHeight,
  required int dstWidth,
  required int dstHeight,
  required ResampleTransform transform,
  int samples = 16,
}) {
  final dst = Uint8List(dstWidth * dstHeight * 4);
  final srcWords = Uint32List.view(
    src.buffer,
    src.offsetInBytes,
    srcWidth * srcHeight,
  );
  final dstWords = Uint32List.view(dst.buffer, 0, dstWidth * dstHeight);
  final t = transform;
  final counts = <int, int>{};

  for (var y = 0; y < dstHeight; y += 1) {
    for (var x = 0; x < dstWidth; x += 1) {
      counts.clear();
      for (var sy = 0; sy < samples; sy += 1) {
        // Sample centres, so the subdivision is symmetric about the pixel
        // and an odd count does not bias towards one corner.
        final py = y + (sy + 0.5) / samples;
        for (var sx = 0; sx < samples; sx += 1) {
          final px = x + (sx + 0.5) / samples;
          double u, v;
          if (t.isAffine) {
            u = t.a * px + t.b * py + t.c - 0.5;
            v = t.d * px + t.e * py + t.f - 0.5;
          } else {
            final w = t.g * px + t.h * py + t.i;
            if (w == 0) {
              continue;
            }
            u = (t.a * px + t.b * py + t.c) / w - 0.5;
            v = (t.d * px + t.e * py + t.f) / w - 0.5;
          }
          if (!u.isFinite || !v.isFinite) {
            continue;
          }
          final ix = u.round();
          final iy = v.round();
          final token = (ix < 0 || ix >= srcWidth || iy < 0 || iy >= srcHeight)
              ? kResampleOutsideToken
              : srcWords[iy * srcWidth + ix];
          counts[token] = (counts[token] ?? 0) + 1;
        }
      }
      var best = kResampleOutsideToken;
      var bestCount = 0;
      counts.forEach((token, count) {
        if (count > bestCount) {
          bestCount = count;
          best = token;
        }
      });
      dstWords[y * dstWidth + x] = best;
    }
  }
  return dst;
}
