import 'package:flutter_test/flutter_test.dart';

import '../../tool/refactor/clone_scan.dart';

/// 🚨ONE ALGORITHM, ONE PLACE.
///
/// The audit's Round 1 (2026-09-03) worked the clone scan from the top of
/// its list and wrote each law once. This keeps the count from growing
/// back: a candidate is a run of 40+ normalised tokens (identifiers and
/// literals folded) that two bodies share, across `lib/` with `lib/dev/`
/// excluded. It is a CANDIDATE — connascence, the same algorithm whatever
/// the text, is the judgment, made by reading — so the test asks only
/// that the number does not rise. The ceiling is the count when the round
/// closed; a session that unifies more lowers it here, and a session that
/// pastes a body is stopped here with the pair named.
///
/// Round 6 (2026-09-04) refined the scan: a run with fewer than three
/// distinct control-flow or operator tokens — a named-argument list, a
/// field reset list — is a shape, not a law, and no longer counts. The
/// ceiling is the refined scan's count for this tree (the same scan gave
/// 673 at the round-2 commit that set 2157).
///
/// 🚨The ceiling is read from THIS test's own scan, never from a side
/// tool. A scratch counter set it to 660 on 2026-09-04 and the gate then
/// measured 661 on the same tree: two instruments, one number apart.
/// 87 → 88 (2026-09-09, the アンチエイリアス import). The new pair is named:
///
///     41 tokens
///       lib/src/services/sut/sut_decoder.dart  _antiAliasOf
///       lib/src/services/sut/sut_decoder.dart  _blendModeOf
///
/// They ARE one algorithm — "look a Clip Studio menu index up in a table;
/// when it is not there, warn and fall back to a default" — so this is a
/// candidate the reading confirms rather than dismisses.
///
/// ⛔It is not merged, because it is the SECOND. The rule of three holds:
/// merging two would have to reconcile differences that have not yet shown
/// which of them is essential — `_blendModeOf` names the unknown value out of
/// a menu table (`_clipStudioBlendName`) while `_antiAliasOf` has only a
/// number to give, and a shared helper would need a describe-hook invented
/// for a shape seen twice. 🔜**The third index-to-enum importer merges all
/// three and lowers this back**; it will most likely arrive from the .abr
/// side, which has its own menus to map.
/// 88 → 89 (2026-09-10, the preset name's ink). The new pair is named:
///
///     54 tokens
///       lib/src/ui/brush/brush_stroke_preview_cache.dart
///         brushStrokeNameGroundCoverage
///       lib/src/ui/timeline/timeline_grid_tile_store.dart
///         TimelineGridTileStore.boxFilterA8
///
/// The shared core is real: sum an A8 rectangle over a width-strided buffer
/// and divide by the count. So the reading CONFIRMS the candidate.
///
/// ⛔It is not merged, and this one is not the rule of three — it is the
/// SUBJECT. `boxFilterA8` resamples a bitmap: it walks that kernel once per
/// destination pixel and its whole argument (the decision comment above it)
/// is about averaging rather than point-sampling. The brush measures ONE
/// rectangle to answer "how dark is it where the name goes", which is a
/// legibility question, not a resampling one. A shared `meanA8Rect` would
/// have to live outside both subsystems and would leave each caller with a
/// helper that explains neither of them — the count rising with a reason is
/// what this ratchet is FOR, and the alternative is the number-chasing the
/// complexity section refuses.
/// 🔜**A third rectangle-mean makes it a law**, and then it is extracted and
/// this comes back down.
/// 89 → 88 (2026-09-10, the pixel pass's recipe builder). The pair that left:
///
///     lib/src/services/cel_pixel_overwrite.dart
///       _RestoreBuilder._openStructures
///       _RestoreBuilder._addToStructures
///
/// Both spelled the same "one raw add and one palette index per pixel" loop.
/// The C pass feeds the builder RUNS now and a run is filled in bulk, so
/// neither loop exists any more — the ceiling follows the count down.
/// 88 → 89 (2026-09-11, I-14 — the media viewer's cut). The new pair is
/// named:
///
///     76 tokens
///       lib/src/services/import/raster_cel_import.dart
///         rasterizeImageToSurface
///       lib/src/services/media/viewer_document.dart  cropImageRgba
///
/// They ARE one algorithm — draw an image into a recorded picture the
/// target's size, rasterize it and read it back as straight RGBA, giving
/// the picture and the raster back on every arm — so the reading confirms
/// the candidate.
///
/// ⛔It is not merged, because it is the SECOND. The import's is the middle
/// of a function that places, clips and slices into tiles; the cut's is the
/// whole of one that copies a box 1:1. A shared helper would take the
/// paint's filter and the canvas's translation as arguments for a shape
/// seen twice. ⛔Nor is the cut read another way to keep the count: reading
/// the WHOLE image back and slicing rows would hold the page twice at its
/// own size, which on the tablets this app is written for is the worse
/// trade.
/// 🔜**The third picture-to-straight-RGBA read merges all three**, and this
/// comes back down.
void main() {
  const ceiling = 89;

  test(
    'clone candidates across bodies do not grow past the round\'s count',
    () {
      final hits = cloneCandidates(cloneBodies('lib'), minTokens: 40);
      expect(
        hits.length,
        lessThanOrEqualTo(ceiling),
        reason:
            'a body was copied instead of shared — the longest candidates now '
            'candidates:\n'
            '${hits.take(12).map((h) => h.describe()).join('\n')}',
      );
      expect(
        ceiling - hits.length,
        lessThan(40),
        reason:
            'the ceiling is slack — lower it to ${hits.length} so the '
            'ratchet keeps its bite',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
