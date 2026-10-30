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
///     59 tokens
///       lib/src/services/import/raster_cel_import.dart  _laidBlock
///       lib/src/services/media/viewer_document.dart  cropImageRgba
///
/// (76 tokens and `rasterizeImageToSurface` until 2026-10-18, when a lay
/// went a block of tiles at a time — F-374-Q8 ⑦ — and the raster moved
/// into the block's own function. Still the pair, still the reading.)
///
/// They ARE one algorithm — draw an image into a recorded picture the
/// target's size, rasterize it and read it back as straight RGBA, giving
/// the picture and the raster back on every arm — so the reading confirms
/// the candidate.
///
/// ⛔It is not merged, because it is the SECOND. The import's is the middle
/// of a function that places and slices a block into tiles; the cut's is the
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
///
/// 91 → 90 (2026-09-26, I-22's ten-minute floor): the pair
/// `TimelineFrameRulerPainter.paint` and `XSheetFrameRailPainter.paint`
/// left — both strips lay their window through ONE call now
/// (`TimelineRulerScale.paintWindow`), and the widest-digits measure the
/// seconds cadence had copied from the numbers' is one method
/// (`_widestDigits`). 🔬`clones.dart` on master and on the lane: that pair
/// gone, nothing added.
///
/// 87 → 88 (2026-10-08, the narrowed word's average), under the ceiling —
/// three pairs had left since without it following them down.
/// 🔬`clones.dart` on master and on the lane: this pair added, none gone.
///
///     40 tokens
///       lib/src/services/resample/resample_kernel.dart
///         resampleRgbaReferenceInto
///       lib/src/ui/text/word_bake.dart
///         boxFilterA8
///
/// What they share is real, and it is the SHAPE of any weighted mean over a
/// rectangle of taps: two loops, a weight an axis, a sum and a divide.
/// ⛔It is not merged, and not by the rule of three — the reading DISMISSES
/// it. The kernel's Blend weighs under a tent as wide as the reduction; the
/// bake's average is the destination pixel's own box, by area. Those are
/// two filters, and the difference is what the bake is for. 🧪Measured the
/// same day, one raster through each: what a baked word loses through
/// Blend is in the comment over `boxFilterA8`.
///
/// 90 → 89 (2026-10-09, the .clip reader's chains): the pairs
/// `_DocumentReader._picturesById` · `_track` and `_timelines` · `_track`
/// left. Every chain the file keeps — the timelines, a timeline's tracks, a
/// track's labels, a layer's children and its objects, a mipmap's scales —
/// is walked by ONE `_chain` now; the sound objects' walk had been the
/// third copy. The pair that came, `_layer` · `_timelines` (44 tokens), is
/// two calls of it, the walk's arguments and nothing else.
/// 🔬Measured on the lane against its base (`2e56d2a0c`, at 90): those two
/// gone, that one added.
///
/// 89 → 88 (2026-10-10, F-322 — the conte panel's rail selects): the pair
/// `_StoryboardRailRows._railRowAtCrossOffset` · `resolveTrackSeDrop` (44
/// tokens) left. The rail's select drag reads the row under the pointer by
/// the walk the strips' sweep made, so the walk is ONE `_addressedRowAt`
/// both ask now, and the sweep's body no longer holds the index arithmetic
/// the pair had in common.
///
/// 87 → 88 (2026-10-13, I-57 — a kept cells row reads its row at the
/// press), under the ceiling a pair had left. The new pair is the two
/// range layers' `_startDrag` (43 tokens): each begins a select the same
/// way — its mode, its anchor, the grip taken, the first select told — on
/// callbacks of their own. The cells' layer reads its row once at the
/// press now, and the `widget.row` the tail spelled became one name like
/// the lane's `_rowAddress`. ⛔Not merged: two of them, and the third is
/// what earns a merge. The same lane put the cell under a press in ONE
/// place (`frameAtVisibleX`): the cells, the range drag over them and a
/// lane's had read it three ways, and the pair its first spelling made
/// with the lane's `_frameAt` is gone with them.
/// 🔬Measured on the lane against master (`16812efd7`, at 87): that one
/// added, none gone.
/// 🔬Measured on the lane against its base (`71ec1f1f0`, at 89): that one
/// gone, none added.
///
/// 88 → 89 (2026-10-14, F-317 — a text's box takes a height by its top
/// and its bottom), over a ceiling one above the count. Two pairs came,
/// and they are one law twice, on the box's other axis:
///
///     82 tokens
///       lib/src/services/cel_text_box_edits.dart  celTextBoxWidened
///       lib/src/services/cel_text_box_edits.dart  celTextBoxDeepened
///     48 tokens
///       lib/src/ui/canvas/text/cel_text_press.dart  _WidthPress._move
///       lib/src/ui/canvas/text/cel_text_press.dart  _DepthPress._move
///
/// The reading CONFIRMS both: an edge sizes the box — the far edge changes
/// the size alone, the edge the anchor is on carries the anchor by what the
/// size lost — along the letters' way for the width and the way the lines
/// stack for the height, and the press reads the hand's travel along that
/// way. ⛔Not merged: the SECOND, and the rule of three holds. A shared
/// body would take the axis as hooks — the way, the field it writes
/// (`wrapWidth` · `minHeight`) and the floor (the least room · the
/// letters' depth) — invented for a shape seen twice. 🔜The third edge
/// that sizes a box by carrying its anchor merges all three and lowers
/// this back.
/// 🔬Measured on the lane against master (`a33780650`, at 87): these two
/// added, none gone.
///
/// 89 → 88 (2026-10-14, F-351 — a sheet's two axes dragged as one). Its
/// first send came back at 90: born on the same two-way controllers, the
/// timeline grid's `initState` made a THIRD of the follow a kept layer
/// axis gets — 「if the host keeps one, follow it」 — beside the x-sheet's
/// and the conte panel's (42 and 41 tokens). Three copies of one guard is
/// the rule of three met: `followKeptAxis` asks it, once, for a null axis
/// too. The pair the conte panel and the x-sheet had made before the lane
/// went with it.
/// 🔬Measured on the lane against master (`279933153`, at 89): that one
/// gone, none added.
///
/// 88 → 86 (2026-10-14, F-360 — a row's folds and twirls are the row's):
/// the pairs `RailView.followLinks` · `followHeads` (52 tokens) and
/// `LayerController.setLayerBlendMode` · `setLayerOpacity` (40) left. The
/// rail no longer walks a link group or a head to make the twirls agree —
/// a command writes them on every row of the head, as it wrote a folder's
/// fold — so the two walks that did are gone. And a row's verb addressed
/// in its own cut is ONE `_executeInItsCut`: the lane twirl and a lane
/// group's twirl came as the third and fourth copies of the blend's and
/// the opacity's guard-and-execute (the scan named them before they were
/// merged), and the group fold had the same body.
/// 🔬Measured on the lane against F-351's lane (`afcd0ea95`, at 88): those two
/// gone, none added.
///
/// 86 → 87 (2026-10-15, F-343 — a track's conte is one structure every
/// cut's conte wears). The new pair is named:
///
///     41 tokens
///       lib/src/models/track_conte_laying.dart  cutWithoutConteFills
///       lib/src/ui/brush/brush_preset_library.dart
///         BrushPresetLibrary._importBrushFile
///
/// The reading DISMISSES the run: it is the filter both spell — the
/// entries a set names, as a map, and nothing to do when there are none —
/// over a cut's rows (the fills a write gave, each with the folder it is
/// filed in) and over a brush file's hand settings (those whose brush
/// landed). One indexes a list and the other narrows a map; a shared
/// helper would only name the comprehension.
/// What the fills' half does past the run IS a law met before, 폴더 해산's
/// (`DissolveFolderCommand`): a row filed in a folder that goes is filed
/// where that folder was. ⛔Not merged: the SECOND, and the rule of three
/// holds — the command walks one folder through the repository for its
/// undo, the fills a set of them in one pure pass. 🔜A third place that
/// takes folders out and keeps what they held merges the walk.
/// 🔬Measured on the lane against F-360's lane (`9760c59bc`, at 86): this
/// one added, none gone.
///
/// 87 → 88 (2026-10-15, F-363-Q2 — the legend's Show all · Hide all pass
/// the camera). The new pair is named:
///
///     51 tokens
///       lib/src/ui/session/layer_switch_verbs.dart
///         LayerSwitchVerbs.setAllLayersVisibility
///       lib/src/ui/session/opacity_verbs.dart
///         OpacityVerbs.setAllLayersOpacity
///
/// The reading DISMISSES the run: it is the comprehension every legend bulk
/// press spells — the active cut's rows its column reaches, less those
/// already there, handed to the controller as one batch — and the eye's
/// filter took the opacity's shape when it learned to pass the camera. The
/// law in it is WHICH rows a press reaches, and that is one place already:
/// the kind table's columns (`hasPictureEye` · `hasPictureOpacity` — two
/// questions on purpose, the transition answers them apart). The SE mute
/// and the bar's commit spell the same comprehension over their own rows.
/// ⛔A shared helper would take the column and the field as hooks and only
/// name the comprehension, reading worse with no law moved.
/// 🔬Measured on the lane against master (`8929cc433`, at 87): this one
/// added, none gone.
///
/// 88 → 89 (2026-10-16, storyboard-thumbnails-let-go-by-the-one-order — the
/// storyboard's pictures let go by the one order). The new pair is named:
///
///     63 tokens
///       lib/src/ui/sheet/sheet_image_cache.dart
///         SheetImageCache._letGoBeyondBudget
///       lib/src/ui/storyboard_cut_thumbnail_store.dart
///         StoryboardCutThumbnailStore._letGoBeyondBudget
///
/// The reading CONFIRMS it: both hold a map of pictures on one viewer's
/// share of the device and let go by the one order a budget lets go by
/// (`letGoLeastRecentlyUsed` — the thumbnails had written it out as a while
/// loop of their own, which this lane took away). What they share past the
/// call is the bookkeeping: the map in the order it was asked, the count of
/// what it holds, a picture's cost. ⛔Not merged: the SECOND, and the rule
/// of three holds — the sheet's cache gives a picture back at once and the
/// thumbnails after the next frame, forgetting its signature with it, so a
/// shared body would take both as hooks invented for a shape seen twice.
/// 🔜The third map of pictures on a viewer's share merges the bookkeeping
/// (the map, the count, the stand-in at another width, the memory warning)
/// and lowers this back.
/// 🔬Measured on the lane against master (`8d4b7c1fa`, at 88): this one
/// added, none gone.
///
/// 89 → 88 (2026-10-16, every-bounded-cache-is-one-lru — every bounded
/// cache lets go by one LRU). The pair named above is gone: both caches
/// keep an `Lru` (core), and the bookkeeping they shared past the call —
/// the map in the order it was asked, the count of what it holds, a
/// picture's cost — is the `Lru`'s now, as it is the tip masks', the live
/// stroke's results' and the rail's glyphs'. What stays theirs is what
/// differs: the stand-in at another width and the memory warning.
/// 🔬Measured on the lane against master (`8d4b7c1fa`, at 88): the same 88
/// pairs, none added, none gone.
///
/// 88 → 89 (2026-10-17, the-masks-are-baked-and-locks-said — CLIP STUDIO's
/// layer masks come in baked). The new pair is named:
///
///     75 tokens
///       lib/src/services/import/clip_offscreen.dart
///         clipColourRgba
///       lib/src/services/import/clip_offscreen.dart
///         clipMaskPlane
///
/// The reading CONFIRMS it: both lay a picture CLIP STUDIO keeps in
/// 256-pixel blocks onto one plane by the same walk — a block's place by
/// its number on the grid, its pixels cut at the picture's right and bottom
/// edges. What differs is a block's inside and the plane where none is: a
/// colour block is an alpha plane and then B · G · R · unused, turned to
/// straight RGBA over transparency; a mask's block is the plane itself,
/// over the mask's outside value. ⛔Not merged: the SECOND, and the rule of
/// three holds — a shared walk would take the pixel's writing and the empty
/// plane as hooks invented for a shape seen twice. 🔜The third picture read
/// out of these blocks merges the walk and lowers this back.
/// 🔬Measured on the lane against master (`4c997b9cc`, at 88): this one
/// added, none gone.
///
/// 89 → 88 (2026-10-20, a-picture-past-the-texture-limit-is-decoded
/// -squashed — a picture past the engine's side is read by the app). Its
/// reader would have added three, and adds none: a PNG is unfiltered by the
/// Paeth predictor the writer filters by (`pngPaeth`), a picture's straight
/// RGBA is read back one way (`straightRgbaOf`, whose third writer this
/// was), and a palette entry is copied as the four bytes it is. The read
/// back made one took a standing pair with it:
///
///     lib/src/services/import/raster_cel_import.dart  _laidBlock
///     lib/src/services/media/viewer_document.dart     cropImageRgba
///
/// 🔬Measured on the lane against master (`9705c2b3a`, at 89): none added,
/// that one gone.
///
/// 88 → 87 (2026-10-20, a-name-tag-value-is-a-key — F-407: a typed member
/// keys as an fx's parameter does). Keying always left the name tag's
/// typed number one walk with the transform's opacity: parse the number
/// with its `%`, key it at the frame. It was not two — twelve value
/// columns each read their typed number back by their own
/// `double.tryParse(…replaceAll('%', '')…)`, each with its own units. One
/// reader now stands beside the one writer (`columnValueOf` by
/// `columnValueText`), and its two-number form (`columnPairOf`) took a
/// standing pair with it:
///
///     lib/src/ui/timeline/scale_lane_form.dart      TwoScales.scrubbed
///     lib/src/ui/timeline/transform_lane_policy.dart scrubTransformLaneValue
///
/// 🔬Measured on the lane against master (`942ad5e5c`, at 88): none added,
/// that one gone.
///
/// 87 → 88 (2026-10-17, frame-picture-indicator — the storyboard's bar
/// joins its runs, red or not, in a function of its own; 88 → 89 where the
/// lane was cut, and 89 → 90 over the masks' pair once it stood on master,
/// before master took two pairs away). The new pair is named:
///
///     40 tokens
///       lib/src/core/convex_clip.dart  _keptBy
///       lib/src/ui/storyboard_playhead_mapping.dart  storyboardReadyRuns
///
/// The reading DISMISSES it: an empty list, then an index walk that reads
/// the list at the index — a polygon clipped against one edge, and the
/// storyboard's stretches walked to their owners' ready runs. Nothing the
/// two compute is the same; the run showed when the local function that
/// stood between the list and the walk went out of it (`_append`).
/// 🔬Measured on the lane against its base (`ebefaea8b`, at 88): this one
/// added, none gone. Measured again on the lane over master (`d13d76aa6`,
/// at 89): 90, this one added, none gone.
///
/// 88 → 87 (2026-10-22, F-433 pencils-draw-like-pencils — the pencils'
/// three new masks first came with a walk and a draw of their own each, 96;
/// the mask file now lays every texture and every square tip in ONE walk
/// (`_textureMask`) and reads the LCG as fractions in ONE place
/// (`_Draws`)). The pair gone:
///
///     43 tokens
///       lib/src/services/brush_tip_mask_defaults.dart
///         _generateCanvasWeaveMask
///       lib/src/ui/session/editor_voice_recording.dart
///         EditorVoiceRecording._playCountInBeeps
///
/// 🔬Measured on the lane over master (`22c980e4b`, at 88): none added,
/// that one
/// gone.
///
/// 87 → 88 (2026-10-22, I-13 2치화 — the colour edit list's knob rides at
/// its row's end, the threshold's bar beside the row's command). The new
/// pair is named:
///
///     45 tokens
///       lib/src/ui/dialogs/app_prompt_dialog.dart
///         _AppPromptDialogState._besideTrailing
///       lib/src/ui/widgets/panel_flyout.dart  _knobbed
///
/// The reading KEEPS it as a pair and does not merge it, by the rule of
/// three (CLAUDE.md): both lay a widget with something 8 px to its right,
/// or the widget alone where there is nothing — the same row. What sits on
/// the right differs: the prompt's field trailing is as wide as it is,
/// the knob is a fixed column that holds the press over its row's height
/// (「컨트롤 위에서 시작한 제스처는 그 컨트롤의 것이다」). A third such row
/// merges the three.
/// 🔬Measured on the lane over master (`7fde89b50`, at 87): this one
/// added, none gone.
/// 88 → 89 (2026-10-23, graph-box-handles-more ⓔ — AE's 「Show Transform
/// Box」, a header graph's second switch beside its pen). The new pair is
/// named:
///
///     46 tokens
///       lib/src/ui/session/session_row_button_presses.dart
///         SessionRowButtonPresses.penLaneGraph
///       lib/src/ui/session/session_row_button_presses.dart
///         SessionRowButtonPresses.transformBoxLaneGraph
///
/// They ARE one algorithm — "turn one switch of a group's open graph to
/// what the pressed one does not have, on every use of its row" — and the
/// reading KEEPS them a pair, by the rule of three (CLAUDE.md): merged, one
/// verb would take which switch it turns, a flag answering for two
/// buttons. The enlarge button is not the third — it lets every other
/// graph back as well. A third switch merges the three.
/// 🔬Measured on the lane over master (`05733d19d`, at 88): this one
/// added, none gone.
/// 89 → 90 (2026-10-24, D7-2-Q3=a — a frame's one picture, patched where
/// it stands). The new pair is named:
///
///     77 tokens
///       lib/src/ui/playback/frame_picture_store.dart
///         FramePictureStore.enforceBudget
///       lib/src/ui/playback/layer_frame_image_cache.dart
///         LayerFrameImageCache.enforceBudget
///
/// The reading CONFIRMS it: both hand the entries of a keyed map that no
/// screen pins to the one order a budget lets go by (`letGoWantedLatest`,
/// whose doc already says the pinned are not handed over), each entry's
/// recency and bytes its own. The order is shared; what the two spell is
/// the pin filter and the map's wiring onto it. ⛔Not merged: the SECOND
/// cache that pins, and the rule of three holds — the export's rows and a
/// viewer's pages take the order with no pins. 🔜The third pinned cache
/// moves the filter into the order (its entries less the pinned keys) and
/// lowers this back.
/// ↩️The pair left with `07bed0139` (one-picture-per-frame ②-5b — the
/// row cache keeps no pictures, so it has no budget), and the ceiling did
/// not follow it (91 → 90 below).
/// 🔬Measured on the lane over master (`a1317441e`, at 89): this one
/// added, none gone.
/// 90 → 91 (2026-10-24, D7-2 — the patches waiting at the cap laid as
/// one). The new pair is named:
///
///     43 tokens
///       lib/src/ui/playback/frame_picture_store.dart
///         FramePictureStore._layAsOne
///       lib/src/ui/playback/frame_picture_store.dart
///         FramePictureStore._landLevels
///
/// The reading CONFIRMS it: both take a picture's turn for its background
/// GPU work in the quiet between held frames — gone once the picture is
/// let go of, due once a caller waits for its levels (`settled`) — each
/// under its own span. ⛔Not merged: two kinds of one store's work, and
/// the rule of three holds. 🔜A third kind of the store's background work
/// takes the turn through one helper of the entry's, and lowers this
/// back.
/// 🔬Measured on the lane over master (`aa7160aa1`, at 90): this one
/// added, none gone.
/// 91 → 92 (2026-10-24, the-pill-cut-skips-text-and-keys — the shared
/// pill's cut takes the text, the rows, the keys or the frames its copy
/// takes). The new pair is named:
///
///     66 tokens
///       lib/src/ui/timeline/toolbar_panel_context.dart
///         _ClipboardAtThePanelsPlace.cutRun
///       lib/src/ui/timeline/toolbar_panel_context.dart
///         _ClipboardAtThePanelsPlace.copyFrame
///
/// They ARE one algorithm — "press the board the pill takes into
/// (`_boardTaken`) with this button's verb" — and WHICH board is already
/// said once, for both. The reading KEEPS the dispatch a pair, by the rule
/// of three (CLAUDE.md): merged, one press would take each board's verb as
/// an argument, four callbacks for a shape seen twice. A third button that
/// presses the board in hand merges the three.
/// 🔬Measured on the lane over master (`f1e746c91`, at 91): this one
/// added, none gone.
/// 92 → 91 (2026-10-26, F-465 picture-written-at-once — a step is written
/// into its picture's base and every level before it answers). The pair
/// laid at 90 → 91 is gone: no patch waits for a quiet turn, so neither
/// the cap's lay nor the levels' landing is left to take one.
/// 🔬Measured on the lane over master (`12f2dbcfd`, at 86): none added,
/// that one gone.
/// 91 → 90 (2026-10-27, one-picture-per-frame's ceiling). The pair gone:
///
///     46 tokens
///       lib/src/ui/conte/conte_picture_ink.dart
///         _canvasOnPaper
///       lib/src/ui/playback/camera_shot.dart
///         outlineThrough
///
/// A canvas's corners through a map — and a third spelling stood inline in
/// the live conte picture's clip — so the three are one: both conte sites
/// call [outlineThrough]. The pair came unnamed with `0633fca64` (②-5b-3,
/// the outline put back from a level's rect to the canvas's corners), in
/// slack the transition left: the ceiling stayed at 92 when `07bed0139`
/// took three pairs away (the cache budgets above, the row cache's two
/// halvings, the selection's stroke clip beside the stack view's row
/// paint), and came only to 91 when the store's turn pair left, the scan
/// then at 85 (`59469bbe0`).
/// ⚠️Six more came unnamed in that slack on 2026-10-27 (85 → 91 at
/// `dd6e1a1b4`), none of them read here:
///
///       brush_canvas_panel.dart  _landTraced · _showTraced
///       cut_envelope_edit_layer.dart  CutEnvelopeEditLayer.build
///         · timesheet_header_edit_layer.dart  TimesheetHeaderEditLayer.build
///       timeline_frame_range_gesture.dart  the two layers' _startDrag
///         — named below
///       effect_lane_editing.dart  _editInk · _editParameter, and
///         _editStand · _editInk — three bodies of one family
///       editor_canvas_area.dart  _referenceBox · _effectBox
///
/// 🔜Each lane that laid one names it here, or merges it.
/// 🔬Measured on the lane over master (`dd6e1a1b4`, at 91): none added,
/// this one gone.
/// Named at 90 (2026-10-27, clone-pairs-1027-timeline), the count kept:
///
///     43 tokens
///       lib/src/ui/timeline/timeline_frame_range_gesture.dart
///         _TimelineFrameRangeGestureLayerState._startDrag
///       lib/src/ui/timeline/timeline_frame_range_gesture.dart
///         _TimelineLaneRangeGestureLayerState._startDrag
///
/// I-57's pair (87 → 88 above), back. F-468 (`d6ae9d0e8` — one koma
/// selected by the hand's travel) told each select where it was pressed,
/// and that line took the tail both layers begin a select by — the mode,
/// the anchor, the press point, the grip taken — past the scan's floor
/// again. The reading is I-57's: one algorithm twice, each on callbacks of
/// its own, and ⛔not merged — two of them, and the third is what earns a
/// merge (CLAUDE.md 절대명령 1). 🔜A third range layer merges the three,
/// into the first step the two already share (`_RangeDragFirstStep`).
/// 🔬Measured on the lane over master (`556586179`, at 90): none added,
/// none gone.
///
/// 90 → 86 (2026-10-27, clone-pairs-1027 — four of the six, read by the
/// lane that laid them). Two families merged:
///
/// - `_editStand` · `_editInk` · `_editParameter` (three pairs): each found
///   the effect a lane addresses and rebuilt it — one walk, three bodies.
///   They are `_editLane` now, the write twin of `_readLane`.
/// - `_referenceBox` · `_effectBox`: each spelled a placement's way to the
///   canvas and back, which `_shownThrough` already said for the row's box.
///   Both call it, and every box's grabs — the row's, the reference's, the
///   effect's and the camera's — make their edits through `_movedTo`,
///   `_scaledTo`, `_turnedTo` and `_anchoredAt`, spelled four times before.
///
/// Two are named:
///
///     43 tokens
///       lib/src/ui/envelope/cut_envelope_edit_layer.dart
///         CutEnvelopeEditLayer.build
///       lib/src/ui/timesheet/timesheet_header_edit_layer.dart
///         TimesheetHeaderEditLayer.build
///
/// The reading finds NO copy: what the two share is already one — the
/// sheets' one in-place editor ([SheetTextEditLayer]) and the face the
/// paper prints in ([appFaceOf]) — and what each spells is its own sheet's
/// targets and keys. The conte's page is the editor's third caller, with
/// keys of another pattern and its own style, so no law of the call is
/// left to share.
///
///     40 tokens
///       lib/src/ui/brush/brush_canvas_panel.dart
///         _BrushCanvasPanelState._landTraced
///       lib/src/ui/brush/brush_canvas_panel.dart
///         _BrushCanvasPanelState._showTraced
///
/// They ARE one algorithm — "a traced shape lays as one stroke of the
/// brush or as every copy's area" ([ShapeShow]'s two pairs of verbs) — and
/// came over the floor when F-483 handed both the stroke's pressure
/// (`96661a9cc`). ⛔Not merged, by the rule of three (CLAUDE.md): merged,
/// one body would take the show's two verbs as callbacks for a dispatch
/// seen twice. 🔜A third verb of the show (or a shape kind beyond the
/// stroke and the area) moves the dispatch into one value [ShapeShow]
/// takes, and lowers this back.
/// 🔬Measured on the lane over master (`01f37d61d`, at 90): none added,
/// these four gone.
///
/// 86 → 87 (2026-10-28, I-140 — an S row's sound is the fifth home of its
/// keys). Named:
///
///     44 tokens
///       lib/src/ui/menu/opened_files_door.dart
///         sortOpened
///       lib/src/ui/session/lane_homes.dart
///         rowLaneHomes
///
/// The reading finds NO copy: the shared run is the empty lists each
/// begins with — the opened files' kinds, a span's homes — and what each
/// sorts by is its own question (`openedAs`, the lane-id grammar). The
/// fifth list (the 「오디오」 group's lanes) took `rowLaneHomes` over the
/// floor. The lane laid one more pair, `setSeNameTag` · `setSeSound`, and
/// merged it: with the row's clips that made three bodies of one guard,
/// which is `_requireSeRow` now.
/// 🔬Measured on the lane over master (`992516ed9`, at 86): this one added,
/// none gone.
///
/// 87 → 86 (2026-10-30, graph-key-drag-snaps — AE's Snap, a header graph's
/// third switch beside its pen and its transform box). The pair 88 → 89
/// kept by the rule of three left:
///
///     lib/src/ui/session/session_row_button_presses.dart
///       SessionRowButtonPresses.penLaneGraph
///       SessionRowButtonPresses.transformBoxLaneGraph
///
/// The snap is the third switch that note waited for, and the three turn
/// through one body now (`_turnLaneGraphSwitch`), each naming the field it
/// reads and the one it writes — no flag says which switch.
/// 🔬Measured on the lane over master (`f32fe4b06`, at 87): none added,
/// this one gone.
void main() {
  const ceiling = 86;

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
