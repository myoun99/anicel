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
/// 89 → 90 (2026-09-11, I-16 — the playhead's pair on the ruler). The new
/// pair is named:
///
///     47 tokens
///       lib/src/ui/timeline/timeline_frame_ruler_painter.dart
///         TimelineFrameRulerPainter.glyphsAt
///       lib/src/ui/timeline/xsheet_timeline_grid.dart
///         XSheetFrameRailPainter.glyphsAt
///
/// The reading split it. WHAT the two strips write — their own writing or
/// the playhead's pair, and in whose ink — was one algorithm spelled twice,
/// and it moved onto the scale they share ([TimelineRulerScale.writingAt],
/// `inkOf`, `secondsInk`). What the scan still finds is WHERE each lays a
/// glyph out: the ruler's two lines, the rail's centred number (R10 R6) —
/// the shape that is left once the law is shared.
/// ⛔It is not merged: two layouts, deliberately different, and a layout
/// spec for two would take the number's style, place and order as
/// arguments for a shape seen twice. 🔜A third strip merges them.
///
/// 90 → 89 (2026-09-11, F-17's key window). The window's TYPE made a THIRD
/// walk of the lane-key verbs' accumulate-and-flag loop — Create, Delete,
/// and the name/type write — so the rule of three merged them into one
/// fold (`_foldedEdits` in `lane_verbs.dart`), and the older Create/Delete
/// pair (63 tokens) went with it.
///
/// 89 → 90 (2026-09-16, storyboard-drop — a sound let go on an SE row's
/// empty cell on the storyboard). The new pair is named:
///
///     44 tokens
///       lib/src/ui/storyboard_panel.dart
///         _StoryboardSeRow._cellDropLayer
///       lib/src/ui/timeline/timeline_frame_cells_row.dart
///         TimelineFrameCellsRow._seCellDropTargets
///
/// The reading CONFIRMS it: a drop place over each empty gap of an SE row,
/// laid on the row's span layer — the timeline's law (「SE 행의 빈 칸 → 새
/// 블록」) asked on the storyboard's axis. The gaps are already one answer
/// ([emptyGapsBetween]); what is spelled twice is laying a place over each.
/// ⛔It is not merged: it is the SECOND. Each walks the range it owns — the
/// timeline its visible window, the storyboard up to its row's last block
/// with one gap after it — and each lays its own place (the timeline's
/// hover-and-caret target, the storyboard's press-then-drop), so a shared
/// layer would take both as arguments for a shape seen twice.
/// 🔜**The third surface that lays a place over each empty gap merges all
/// three**, and this comes back down.
///
/// 90 → 91 (2026-09-16, the 3.44.2 → 3.47.4 upgrade). ⛔**NOTHING WAS
/// COPIED. A PAIR THAT WAS ALWAYS THERE CROSSED THE FLOOR.** The new pair
/// is named:
///
///     41 tokens
///       lib/src/ui/brush/brush_preset_library.dart
///         BrushPresetLibrary.rename
///       lib/src/ui/brush/brush_preset_library.dart
///         BrushPresetLibrary.setGroupCollapsed
///
/// 🧪MEASURED, not reasoned: the same scan on master that day returns 90
/// and does NOT name this pair, and the pair comes in at 41 — one token
/// over. 3.47's analyzer started flagging
/// `prefer_if_elements_to_conditional_expressions` (a rule this repo turned
/// on in Round 2, clean until the analyzer got better at it) at 41 sites,
/// and `cond ? a : b` → `if (cond) a else b` adds two tokens. Both bodies
/// grew by two, and 39 became 41. The duplication is the SAME AGE as the
/// two methods.
/// ⛔It is not merged HERE, and the reason is not the rule of three — the
/// third is already in the file (`editGroup`), and a fourth is in
/// `brush_tip_library.dart` (`rename`). It is that the merge has a
/// DECISION in it that an SDK upgrade must not make on the way past:
/// `services/project_tree_editor.dart` already owns `_replacingOne`, whose
/// stated reason to exist is fusing the replacement with a found-flag so
/// the two cannot come apart. The brush libraries want the replacement and
/// NOT the flag, so folding them in means either a no-op callback at every
/// call site or a second general helper — and choosing between those is a
/// round, not a side effect.
/// 🔜**That round takes this back down by at least one**, and probably more:
/// the family is four.
///
/// 91 → 90 (2026-09-16, the round above, run immediately). The pair is gone
/// because both bodies now call a walk that was ALREADY IN THE TREE:
/// `core/mapped_or_same.dart`'s [mappedOrSame], written for four write-time
/// normalizations that had each spelled it out by hand. The brush family's
/// four — `BrushPresetLibrary.rename`, `.editGroup`, `.setGroupCollapsed`
/// and `BrushTipLibrary.rename`, plus the tip library's mask-load write —
/// go through it, and each one's own decision (which item, what it becomes)
/// is what is left at the call site.
/// ⛔**No new helper was authored**, which was the whole worry: the choice
/// was never "no-op callback vs. second general helper", because the third
/// option — the one the rule about investigating what exists is for — was
/// sitting in `core/` already. `mappedOrSame` also does strictly more than
/// the loops it replaced: it hands the SAME list back when nothing changed.
/// ⛔`_replacingOne` in `services/project_tree_editor.dart` is untouched and
/// is not the same thing: it fuses the found-flag into the step, which is
/// its stated reason to exist and which none of these five wants.
/// ⛔`delete` and `deleteGroup` are untouched too — they FILTER, a different
/// verb, and folding a remover into a replacer is how one flag ends up
/// answering two questions.
/// Only one candidate left with it: the others in the family were already
/// under the 40-token floor and never counted.
///
/// 90 → 91 (2026-09-25, the app tooltip). The new pair is
/// `_HoldingRawTooltipState._handleTap` and `._handleLongPress` in
/// `ui/widgets/app_tooltip.dart` — Flutter's two trigger handlers, carried
/// with the rest of `RawTooltip` line for line, because the fork's one rule
/// is that only the pointer route differs from Flutter's tooltip.
/// ⛔Not merged: a shared helper would make the fork a rewrite, and there
/// are two of them — the third is what earns a merge.
///
/// 90 → 91 again (2026-09-25, the conte cover), under the ceiling the
/// tooltip set — a pair had left since without the ceiling following it
/// down. The new pair is `_cover` and `_content` in
/// `models/conte/conte_page_marks.dart`: each prints a media image where
/// the source names one — the cover's picture, the body's company logo.
/// ⛔Not merged: two of them, and the third is what earns a merge.
void main() {
  const ceiling = 91;

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
