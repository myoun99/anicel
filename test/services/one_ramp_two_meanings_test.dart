import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/mask_soft_edge.dart';

/// 🚨★★★ONE RAMP, TWO MEANINGS.
///
/// The same five-tap average — `(center * 3 + neighbour sum) / 7` — was
/// written out in three places: the fill's Dart reference, the fill's C
/// kernel, and the selection's mask pass. ①↔③ were watched byte for byte by
/// `fill_gap_close_test`; ② was watched by nothing, and it duly diverged the
/// day the selection's ramp was clamped inside its outline (#1300).
///
/// ⛔THE FIX IS NOT ONE ANSWER. The card that opened this said so: 「억지로
/// 하나로 만들면 안 된다 — 뜻이 둘이다」. A fill's ramp is allowed past its
/// outline; a selection's is not, because a mask pixel travels whole. So the
/// arithmetic is shared and the clamp is an argument — and these tests exist
/// to prove the argument still changes something.
void main() {
  /// A hard 4x4 block inside an 8x8 field: 255 in, 0 out, nothing between.
  Uint8List hardBlock() {
    final mask = Uint8List(64);
    for (var y = 2; y < 6; y += 1) {
      for (var x = 2; x < 6; x += 1) {
        mask[y * 8 + x] = 255;
      }
    }
    return mask;
  }

  int at(Uint8List mask, int x, int y) => mask[y * 8 + x];

  test('unclamped, the ramp reaches one pixel PAST the outline', () {
    final mask = hardBlock();
    expect(at(mask, 1, 3), 0, reason: 'fixture: x=1 is outside the block');
    softenMaskBoundary(mask, width: 8, height: 8, insideOutlineOnly: false);
    expect(
      at(mask, 1, 3),
      greaterThan(0),
      reason: 'a fill paints past its own outline — that is the soft edge',
    );
  });

  test('clamped, it never lights a pixel the outline did not', () {
    final mask = hardBlock();
    softenMaskBoundary(mask, width: 8, height: 8, insideOutlineOnly: true);
    expect(
      at(mask, 1, 3),
      0,
      reason: 'a selection that reaches one pixel past itself erases artwork '
          'nobody selected — the skirt IS the bug (#1300)',
    );
    // ⛔And it still SOFTENS, or the clamp would just be "turn the pass off".
    expect(
      at(mask, 2, 2),
      lessThan(255),
      reason: 'the corner of the block still ramps INWARD',
    );
  });

  test('the clamp only ever darkens — every pixel is <= the unclamped one', () {
    final loose = hardBlock();
    final tight = hardBlock();
    softenMaskBoundary(loose, width: 8, height: 8, insideOutlineOnly: false);
    softenMaskBoundary(tight, width: 8, height: 8, insideOutlineOnly: true);
    expect(loose, isNot(tight), reason: 'fixture: the two disagree somewhere');
    for (var i = 0; i < loose.length; i += 1) {
      expect(
        tight[i],
        lessThanOrEqualTo(loose[i]),
        reason: 'clamping must not brighten anything (index $i)',
      );
    }
  });

  test('an interior pixel is untouched either way', () {
    for (final inside in const [true, false]) {
      final mask = hardBlock();
      softenMaskBoundary(mask, width: 8, height: 8, insideOutlineOnly: inside);
      expect(
        at(mask, 3, 3),
        255,
        reason: 'a uniform neighbourhood is skipped (insideOutlineOnly: '
            '$inside)',
      );
    }
  });

  test('nothing in lib/ writes the five-tap average by hand', () {
    // ⛔A SOURCE SCAN, because behaviour cannot see this. Two copies that
    // agree today pass every pixel comparison; what breaks is the third
    // written next year — which is exactly what happened here. The C kernel
    // is not Dart and stays: `fill_gap_close_test` holds it byte for byte.
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      if (path.endsWith('lib/src/services/mask_soft_edge.dart')) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (line.contains('center * 3') || line.contains('center*3')) {
          offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'the five-tap average lives in `softenMaskBoundary`; a '
          'hand-written one is the copy that diverged last time',
    );
  });

  test('the C kernel is still the one copy a test holds shut', () {
    // ⛔A REMINDER WITH TEETH. `fill_gap_close_test` SKIPS when the DLL is
    // not built, so "green" there can mean "did not run". If the kernel ever
    // stops mirroring the unclamped branch, this points at where to look.
    final kernel = File(
      'packages/qa_native/src/qa_engine.c',
    ).readAsStringSync();
    expect(
      kernel.contains('center * 3 + (sum - center)'),
      isTrue,
      reason: 'qa_fill_finish_mask must still mirror the unclamped branch of '
          'softenMaskBoundary — fill_gap_close_test compares them, and it '
          'skips silently without build/native_standalone',
    );
  });
}
