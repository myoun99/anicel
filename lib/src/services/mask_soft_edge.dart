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
/// Two-pass 3-4 chamfer distance transform: [target] receives the
/// distance (orthogonal step 3, diagonal 4, saturated at [infinity])
/// from every pixel to the nearest SOURCE pixel, where source means
/// `from[i] == zeroWhen`. Integer math only — the C kernel mirrors it
/// exactly.
///
/// [borderDistance] is the chamfer distance the canvas border is treated
/// as lying at. The FILL passes [infinity]: off-canvas neighbors are
/// ignored (the canvas edge is NOT a barrier). The SELECTION feather
/// passes 3: a border pixel ramps as if the pixel beyond the edge were
/// outside. It is applied to the four border lines ONCE, before the two
/// relaxation passes, which is the same value at the same read points as
/// forcing it inside the forward pass — a border pixel seeded to 3 can be
/// lowered by no neighbour (nothing is below 0 + 3), and every neighbour
/// a pass reads has already been visited by that pass.
void chamferDistance34(
  Uint16List target, {
  required Uint8List from,
  required int zeroWhen,
  required int width,
  required int height,
  required int infinity,
  required int borderDistance,
}) {
  for (var index = 0; index < target.length; index += 1) {
    target[index] = from[index] == zeroWhen ? 0 : infinity;
  }
  if (borderDistance < infinity) {
    for (var x = 0; x < width; x += 1) {
      final top = x;
      final bottom = (height - 1) * width + x;
      if (target[top] > borderDistance) target[top] = borderDistance;
      if (target[bottom] > borderDistance) target[bottom] = borderDistance;
    }
    for (var y = 0; y < height; y += 1) {
      final left = y * width;
      final right = left + width - 1;
      if (target[left] > borderDistance) target[left] = borderDistance;
      if (target[right] > borderDistance) target[right] = borderDistance;
    }
  }
  // Forward pass (top-left → bottom-right).
  for (var y = 0; y < height; y += 1) {
    final row = y * width;
    for (var x = 0; x < width; x += 1) {
      final index = row + x;
      var best = target[index];
      if (best == 0) {
        continue;
      }
      if (x > 0 && target[index - 1] + 3 < best) {
        best = target[index - 1] + 3;
      }
      if (y > 0) {
        final up = index - width;
        if (target[up] + 3 < best) {
          best = target[up] + 3;
        }
        if (x > 0 && target[up - 1] + 4 < best) {
          best = target[up - 1] + 4;
        }
        if (x < width - 1 && target[up + 1] + 4 < best) {
          best = target[up + 1] + 4;
        }
      }
      target[index] = best > infinity ? infinity : best;
    }
  }
  // Backward pass (bottom-right → top-left).
  for (var y = height - 1; y >= 0; y -= 1) {
    final row = y * width;
    for (var x = width - 1; x >= 0; x -= 1) {
      final index = row + x;
      var best = target[index];
      if (best == 0) {
        continue;
      }
      if (x < width - 1 && target[index + 1] + 3 < best) {
        best = target[index + 1] + 3;
      }
      if (y < height - 1) {
        final down = index + width;
        if (target[down] + 3 < best) {
          best = target[down] + 3;
        }
        if (x < width - 1 && target[down + 1] + 4 < best) {
          best = target[down + 1] + 4;
        }
        if (x > 0 && target[down - 1] + 4 < best) {
          best = target[down - 1] + 4;
        }
      }
      target[index] = best > infinity ? infinity : best;
    }
  }
}

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
