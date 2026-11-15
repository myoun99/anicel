import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

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
/// arithmetic is shared and the clamp is an argument.
///
/// Both meanings are the engine's now, one spelling with the clamp its
/// argument (mask.wgsl's `mask_softened`), and each is pinned where it is
/// spelled: the selection's by `the_soften_keeps_inside_its_outline`
/// (`kernels/mask/tests.rs`), the fill's by
/// `the_fill_s_ramp_spreads_a_pixel_past_its_outline`
/// (`kernels/flood/tests.rs`) — and an area's through its own door by
/// `a_fill_ramp_spreads_on_every_side_test.dart`.
///
/// ↩️Both were spelled here in Dart, the clamp an argument of
/// `softenMaskBoundary`, till 2026-11-14, when the selection's went with
/// the last of the CPU's selection masks (board
/// `a-selection-mask-is-built-on-the-cpu-at-every-move`, L2d). The fill's
/// stayed a day more as an area's finish, a second spelling beside the
/// kernel's that `an_area_is_finished_as_the_bucket_is_test.dart` held
/// shut, and went 2026-11-15 when an area's finish moved to the engine
/// (board `an-areas-finish-is-a-second-spelling-of-the-floods`). ↩️The C
/// kernel `qa_fill_finish_mask` was a copy before that, and went with the
/// fill's C calls.
void main() {
  test('nothing in lib/ writes the five-tap average by hand', () {
    // ⛔A SOURCE SCAN, because behaviour cannot see this. Two copies that
    // agree today pass every pixel comparison; what breaks is the third
    // written next year — which is exactly what happened here. The engine's
    // kernel is not Dart, and holds the one spelling.
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = file.path.replaceAll(r'\', '/');
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
      reason: 'the five-tap average lives in the engine\'s mask kernel; a '
          'hand-written one is the copy that diverged last time',
    );
  });
}
