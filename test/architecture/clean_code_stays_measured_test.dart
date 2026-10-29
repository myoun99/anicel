import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/refactor/app_sources.dart';
import '../../tool/refactor/clean_code_scan.dart';

/// Round 2 of the audit (clean code, 2026-09-03) measured three numbers
/// and holds them here as WARNING ratchets — ceilings, not gates: a
/// signature with five or more parameters (constructors and copyWith
/// excluded), a body over sixty lines, a class over six hundred. The
/// numbers may only fall; a session that pushes one up reads the
/// offenders it added, and a session that brings one down lowers the
/// ceiling so the ratchet keeps its bite. ⛔Not a reason to split for
/// the score — the cognitive-complexity round said why.
void main() {
  /// ⚠️378 → 380 on 2026-09-11, the offenders named as the rule above asks.
  ///
  /// The placement round added three and one left. `importedMediaAsset`
  /// (ten) is the pool record's ONE spelling — the still, the sequence and
  /// now the expanded PSD each built it by hand — and its parameters are
  /// the record's own fields, which the record's constructor (excluded
  /// here) takes as well. `ProjectImportDoors.importPsdExpanded` (five)
  /// gained `copyIntoProject` because an expanded PSD registers in the pool
  /// now, the parameter its image and PDF siblings already take.
  /// `_ImportFileTableState._tableLine` (five) is the ONE line shape the
  /// header and every row are laid out through — the fix for a header that
  /// sat 16px off its rows — and its parameters are that line's four slots
  /// and the widths they share. `importModeAllowed` left the list, down to
  /// the two questions it still answers.
  ///
  /// ⚠️380 → 381 the same day, the drop round's stage 2a:
  /// `resolvedImportSettings` (five) took where a drop put the file, because
  /// what a file can give depends on it — a row's frames lock the bake on
  /// and the PSD to merge — and "what this file means" is that function's
  /// one job. Its inputs are four facts from three places: the file's kind
  /// and whether it is a PSD, whether anything is placed, and the drop. The
  /// two landing verbs that grew with it went back under by reading the drop
  /// off the arrival, where "where does this land" already lived.
  ///
  /// ⚠️381 → 383 on 2026-09-15: F-102 added three (the tree stood at 380),
  /// named as the rule above asks. An SE row is one row on its track and a
  /// cut shows a projection of it, so a key or a typed value from either
  /// panel now lands through ONE pair of verbs on `LaneVerbs` instead of
  /// each host's copy. `toggleLaneKeyAt` (five) and `setLaneValueAt` (six,
  /// with the typed input) take the lane cell — row, lane, frame — the axis
  /// that frame was pressed on (the storyboard presses global frames, the
  /// timeline cut-local ones) and the undo label the host words.
  /// `_editLaneAt` (eight) is the one dispatch both run through: the same
  /// five, plus the edit each keyed family — the name tag, the effect chain,
  /// the transform track — makes.
  ///
  /// ⚠️383 → 385 on 2026-09-16, two named as the rule above asks. The same
  /// lines ride in both lanes, so whichever lands first carries the other's
  /// count. F-18: `timelineDrawnEndPreviewFrameCount` (five) took the
  /// movie's trailing gap, because the storyboard's end line, its grip and
  /// its ruler now read a movie-end drag through the cut end's one function
  /// instead of a second one beside it (`movieEndPreviewTotalFrames`, gone);
  /// the drawn end is that cut end plus the のりしろ, and its fifth input is
  /// the one the cut end gained. F-101: `propertyLanesForRow` (five) is the
  /// lane list both panels now build an SE row's lanes from — the row, the
  /// rows an attach base is found among, which groups are open, where a lane
  /// reads its value and where a keyless pose is centred. The last two are
  /// the answers the two rails give differently: the cut's canvas, the
  /// camera frame.
  /// ⚠️385 → 386 on 2026-09-22, and this one is not the app's design: the
  /// five parameters are `PageTransitionsBuilder.buildTransitions`'s, an
  /// SDK override the app cannot re-shape, and the body it carries is
  /// `=> child` — it uses NONE of them. `_NoPageTransition` exists because
  /// a completed page transition keeps a full-window layer for ever (a
  /// `FadeTransition` is a repaint boundary at alpha 255 too), and the app
  /// has no page routes to transition; `app_theme.dart` has the
  /// measurement. Shrinking it is not available, and skipping the override
  /// means keeping four offscreens over the window on every frame.
  ///
  /// ⚠️386 → 387 on 2026-09-23, one named as the rule above asks.
  /// `_ImportDialogState._placeThrough` (six) is the ONE dispatch every
  /// placed file goes through, and a trimmed file carried in now goes
  /// through it as its PIECE (유저 2026-09-23: 자른 구간만 품는다, 「비디오든
  /// 이미지든 오디오든 관계없이 법 하나로」) — the span cut into a file of
  /// its own and placed whole by the same doors, which is why the doors know
  /// nothing of pieces. The two it gained are the piece's: the settings it
  /// is placed with — the original's, re-based onto the piece — which it
  /// used to read off the path, and where it was cut from, the parameter
  /// every door takes for the pool's provenance. The sound and movie cutters
  /// the same round wrote came in under the line: the frame rate and the
  /// audio speed travel as the one clock they are (`ProjectClock`), and the
  /// window's IN/OUT as one trim.
  ///
  /// ⚠️387 → 388 on 2026-09-24, one named as the rule above asks.
  /// `layerRowHiddenBy` (eight) is the ONE answer to 「is this layer's row on
  /// screen」 that the grids draw by and the standing law lands by (F-169 —
  /// the two answering it apart is what stood a hand-off inside a shut
  /// group). It is the row builder's own four checks lifted out whole, so
  /// its inputs are the ones that loop already took: the row, the rail's
  /// three view facts, the row the filter spares and the fx answer the
  /// filter asks — plus the folder index and attach base the builder
  /// computes once for the indent too, passed in rather than asked twice.
  ///
  /// ⚠️388 → 391 on 2026-09-24, three named as the rule above asks — the
  /// block frame lines round (유저: a switch, and 「좀 더 성능적으로
  /// 개선해주면 좋아」). `TimelineGridTileOpWriter.boxFill` (five) and
  /// `.runFill` (eight) are the writer's cheap spellings of `rrectFill` — the
  /// same bytes, pinned by `qa_grid_split_fills_test` — so they take its
  /// operands in its order: the box's four numbers and the colour, and for a
  /// run its radius and corner mask and which way the run runs. Every fill
  /// the writer writes takes that positional shape, and a pair of helpers
  /// taking a `Rect` of their own would be the one odd pair in it.
  /// `timelineBlockFrameLine` (eight) is the ONE line every block asks for:
  /// the four inputs of the sheet's own ink law (the frame, the cell
  /// extent, the fps, the scheme — `timelineFrameBoundaryLineInk`'s), where
  /// the line lies (the axis, the boundary, the paper's cross span) and the
  /// paper it is inked onto. Asking the ink apart from placing it would put
  /// that composition back at each block that draws the line — the copy the
  /// function exists to end.
  ///
  /// ⚠️391 → 389 on 2026-09-25, lowered as the rule asks: master stood at
  /// 390, and the carry round (`recarry-after-remove-reads-the-old`) took
  /// one off — `storedMediaBytesFor` asks by the carry now, and a carry
  /// knows its path, so the path left its parameters. 🔬`clean_code_diff`
  /// between master and the lane names that one and nothing added.
  /// (The 390 was the block frame lines round's: it retired the unused
  /// `rrectStroke` op, whose writer took eight, and left the ceiling where
  /// it was — the in-between mark round noticed it too, and adds none.)
  ///
  /// ⚠️389 → 387 on 2026-09-25, following two down: the panel writing moved
  /// into the cut block's bands and the bands stopped folding, so the
  /// folded block's `_paintAnchoredLabel` and the plates' `_paintPlatedGlyph`
  /// went with what used them. 🔬`clean_code_diff` named those two, nothing
  /// added.
  ///
  /// ⚠️387 → 385 on 2026-09-26, lowered as the rule asks: the conte sheet
  /// engine round made the page ONE list of marks that every printer
  /// replays, and the text helper each printer kept for itself went —
  /// `ContePagePainter.text` and `_ContePdfPageWriter._text`. The Canvas
  /// printer it added takes its face, strata and images once
  /// (`SheetCanvasPrinter`) rather than on every call. 🔬`clean_code_diff`
  /// between master and the lane names those two and nothing added.
  ///
  /// ⚠️385 → 384 on 2026-10-01, lowered as the rule asks: F-244's x-sheet
  /// columns build their cells row through the timeline's
  /// (`timelineCellsRowFrom`), and the sheet's own builder — `_columnFor`
  /// (five) — went with the copy it held. 🔬`clean_code_diff` between master
  /// (`6dce949f7`, at 385) and the lane named that one and nothing added.
  ///
  /// ⚠️384 → 385 on 2026-10-01, the offender named as the rule asks: F-222
  /// ①'s `TransformBoxLaw.scaled` (five). It is the transform tool's scale
  /// solve moved out of the selection layer into the box law, where every
  /// box will take it, and its two named flags are the two questions the
  /// solve always asked — which point stays put, and whether the axes keep
  /// one scale. In the layer it read them off the widget state
  /// (`_scaleModifierHeld`, `transformOptions.isUniform`), so the same
  /// inputs were there and uncounted; as a law they are parameters. Folding
  /// them into one value would be a split for the score. 🔬The lane's scan
  /// against master: that one added, nothing else.
  ///
  /// ⚠️385 → 383 on 2026-10-01, lowered as the rule asks (F-222 ②~④, one
  /// box for every row): the round took three off and put one on. Gone with
  /// the handles they built: `_gizmoHandle` (the point gizmo),
  /// `_LayerTransformBoxState._handle` and the canvas area's
  /// `_transformBox`. Added: `boxPressAt` (six) — the one order a press on
  /// any box is read in: the press, the four things a box may wear (a
  /// cross, handles, an inside, a stage) and whether it turns; a box with
  /// fewer passes fewer. 🔬The lane's scan against master (`25fdf5106`, at
  /// 385).
  ///
  /// ⚠️383 → 381 on 2026-10-06, lowered as the rule asks (F-289, the export
  /// preview as a canvas-base panel): the window's
  /// `_requestCompositePreview` (five) went with the preview loop it fed —
  /// a tab's file is a document the panel asks a page of now — and the
  /// string `exInOut` (five) with the line under the picture that said it.
  /// 🔬The lane's scan against the tabs lane (`3eebdddec`, at 383) named
  /// those two gone and nothing added.
  ///
  /// ⚠️381 → 380 on 2026-10-07, lowered as the rule asks (F-309, the camera
  /// row's keys move on their lanes): `shiftKeysInRange` (five) went with
  /// its last caller — the camera's keys shift by the lanes' own range move
  /// now, and the instruction rows' spans enter the shared walk by the keys
  /// they hold (`shiftKeysAt`). 🔬The lane's scan against master
  /// (`6cd83353a`, at 381) named that one gone and nothing added.
  ///
  /// ⚠️380 → 381 on 2026-10-07, one named as the rule above asks (F-256, a
  /// layer's Scale lane holds two numbers).
  /// `transformTrackWithLaneValueEdited` (six) took how the row's Scale
  /// reads what was typed: its form — a camera's one zoom, a layer's two
  /// scales — and whether the chain is on. The other four are the lane
  /// cell and the text, as they were. The two are asked apart because the
  /// lane list prints and scrubs by the form alone, while the chain is the
  /// transform tool's one switch, read where a value lands. 🔬The lane's
  /// scan against master (`bdb2136ad`, at 380) named that one added and
  /// nothing gone.
  ///
  /// ⚠️381 → 382 on 2026-10-07, one named as the rule above asks
  /// (F-289-Q21, a video run holds the rows its held pictures are made
  /// of): `ExportFrameRenderer._composite` (five) took `rows` — where a
  /// held canvas-size picture's row pictures come from — beside the output
  /// size and the name tags the picture route already passed. The other
  /// route of that one render (`renderComposite`) hands none, so the one
  /// body serves both rather than a second copy of it. 🔬The lane's scan
  /// against master (`7916affa5`, at 381) named that one added and nothing
  /// gone.
  ///
  /// ⚠️382 → 383 on 2026-10-08, one named as the rule above asks (F-282-Q1,
  /// an import waits in the window a bake and a save wait in):
  /// `CutFolderImportDoor.importCutFolder` (five) took `onProgress` — the
  /// scans it bakes are what the window's % counts, and only the door knows
  /// how many there are. The other four are the folder and the window's
  /// three answers for it, as they were. The dialog's two that grew with it
  /// (`_placeCarryingOnlyTheSpan`, `_placeMovie`) went back under: what a
  /// door could not render and how far it is go down the same doors
  /// together, and are handed down as one (`_FileReport`). 🔬The lane's
  /// scan against its base (`4b6fa8ff5`, at 382) named that one added and
  /// nothing gone.
  ///
  /// ⚠️383 → 384 on 2026-10-08, one named as the rule above asks (card
  /// `csp-clip-import-analysis`, a CLIP STUDIO file planned as the project
  /// it opens as): `planClipImport` (five) — a whole project's planner, as
  /// `planTvpImport` (five) is a cut's. The document; the name the one cut
  /// of a file with no timeline takes; the program language's word for the
  /// folder hidden layers stand in (the planner is below the string
  /// tables); the track its link members name, which the door builds; and
  /// the id mint. 🔬The lane's scan against master (`94d72eef8`, at 383)
  /// named that one added and nothing gone.
  ///
  /// ⚠️384 stays on 2026-10-08 with one more under it, named as the rule
  /// above asks (I-73, one line joins a row's keys): master (`676b0fcd4`)
  /// scanned at 383 under this ceiling, and `timelineUnionKeyMarkerSpans`
  /// (five) took the row's `axis`. The camera row's summary lays the keys'
  /// line along the row it sits in — across in the timeline, down in the
  /// x-sheet — and the line cannot read that off the box it is laid out in:
  /// two narrow cells are taller than they are long. The other four are the
  /// marks', as they were. 🔬The lane's scan against master named that one
  /// added and nothing gone.
  ///
  /// ⚠️384 → 386 on 2026-10-08, two named as the rule above asks (I-76, a
  /// picture's numbered run comes in as one layer):
  /// `ProjectImportDoors.importPictureRun` (six) is a door like its
  /// neighbours — the run's files and its layer's name, the row's answers
  /// as ONE (`settings`, as `importVideoFile` takes them), the drop's spot,
  /// and the two the window's % and its failure count read, as the movie
  /// and PDF doors take them. `importBakeLocked` (five) took `together`: a
  /// run that comes in together is baked for the reason an expanded PSD
  /// is, and the bake column asks this one function. The window's own
  /// `_placeRun` stayed under (four: the row's answers are read inside).
  /// 🔬The lane's scan against master (`1018781b8`, at 384) named those
  /// two added and nothing gone.
  ///
  /// ⚠️386 → 387 on 2026-10-09, one named as the rule above asks (I-73 ④,
  /// the storyboard's camera row): master (`6e7d619a7`) scanned at 386 —
  /// at this ceiling — and `timelineUnionKeySpan` (eight)
  /// is the ONE key mark the timeline's union row and the storyboard's
  /// camera row lay out — `timelineUnionKeyMarkerSpans` drew it inline. Its
  /// eight are whose key it is (the layer, the lane, the frame, the prefix
  /// its keys are named under), where it stands (`at`, the cell on the
  /// row's own axis — a cut's own frame stands elsewhere on the track's —
  /// and `crossInset`/`crossExtent`, the band across that holds one of the
  /// camera row's two lines over an O.L) and whether its name is printed
  /// (`named`: two lines leave no room for a word). The line beside it
  /// stayed under: `timelineKeysLineCourse` takes the line it draws.
  /// 🔬The lane's scan against master named that one added and nothing
  /// gone. ↩️It is `timelineLaneKeySpan` since 2026-10-09 (I-73 ④ⓔ), and
  /// nine: the storyboard's camera LANES lay their keys out with it too, and
  /// a member's mark rings while its lane selection holds it (`selected`)
  /// — still the one name under this ceiling.
  ///
  /// ⚠️387 → 388 on 2026-10-09, one named as the rule above asks (F-282,
  /// the one door): `pickFileGrantsForUser` (five) took `initialDirectory`.
  /// 「파일 열기」 is that pick now — every kind, several at once — and it
  /// keeps the starting folder the project Open had on a desktop, which
  /// `pickProjectGrantForUser` already takes for the same reason. The Open
  /// pick that passed it, `pickProjectToOpen`, is gone.
  ///
  /// ⚠️388 → 389 the same day, one named as the rule above asks
  /// (playback-plays-the-screen-material — a cut played alone plays on the
  /// canvas): `LayerFrameImageCache.peek` (five) is the look the warmer, the
  /// ruler's bar and a waiting run share — what `prepareSyncOrNull` would
  /// hand from what is held, WITHOUT counting as a use, which is what keeps
  /// their counting from reordering the order the budget lets go by. Its
  /// five are the slot (the cel, the level) and the three facts that decide
  /// whether a held image is valid and drawable on the asking route — what
  /// its two prepare siblings take.
  ///
  /// ⚠️389 → 390, the other one the same round added: `letGoWantedLatest`
  /// (eight) is the ONE order a playback budget lets go by — the composites
  /// and the canvas's layer images both trim through it, where each had
  /// written it out. Generic over the entry, it is handed the entries, what
  /// is held and the line, the three things it asks of an entry (when it is
  /// next wanted, when it was last used, its bytes), the letting go, and the
  /// floor no picture wanted that soon goes under.
  ///
  /// ⚠️390 → 387 on 2026-10-10, following them down (I-68 — the fit is a
  /// pose): `rasterizeImageToSurface`, `planCutFolderImport` and
  /// `planTvpImport` lost the fit a planned bake no longer carries — one
  /// placement says where the picture goes. One came, named as the rule
  /// asks: `poseWithLaneValueEdited` (five) is a value typed into a lone
  /// pose's lane, a reference fx's — the pose, which lane, the input and the
  /// two the Scale lane's form reads it with, the transform lanes' own. 389
  /// had been measured under 390 before this round.
  ///
  /// ⚠️387 → 388 on 2026-10-10 (a-picture-is-made-once), named as the rule
  /// asks: `LayerFrameImageCache._prepareNow` (six) is the body `prepare`
  /// had, under the join that makes a picture once now (`_Makings`) — its
  /// parameters are `prepare`'s own, handed on whole. 🔬`clean_code_diff`
  /// between the lane's base and the lane names it and no other: the walk's
  /// ask ahead, which first took its context as nine parameters, lives on an
  /// object of its own (`_AskedAhead`).
  ///
  /// ⚠️388 → 389 on 2026-10-10, one named as the rule above asks (I-89 ②,
  /// a key's mark): `paintKeyMark` (seven) is the ONE drawing every key on
  /// the frame axis wears — the lanes, the unions, the storyboard's camera
  /// rows and the flip window — and the key window's choices cut it in
  /// half. Its seven are the canvas, the mark, the box it stands in (its
  /// middle and its size), whether it stands on the sheet, its colour label
  /// and the selection's ring. 🔬The lane's scan against its base
  /// (`3fa5a239b`, at 388) named that one added and nothing gone.
  ///
  /// ⚠️389 → 388 on 2026-10-11, following them down (I-89 ③ — rows sit
  /// where one table of edges says): the grid's virtualization adapter
  /// (`calculateLayerTimelineGridVirtualizationPlan`, eleven) went, nothing
  /// calling it, and `uniformRailRowsIn` (six) is `railRowsAlong` (five),
  /// the rail's walk over the edges — the one name the scan sees added.
  /// The frame side takes its rows as laid (`TimelineLaidRows`) and the grid
  /// its cells read, and the playhead reads its range hooks where it reads
  /// every other hook. 🔬The lane's scan against its base (`fceb34c9e`, at
  /// 389) named those three.
  ///
  /// ⚠️388 → 389 on 2026-10-11, one named as the rule above asks (I-89 ③,
  /// a lane's pin): `timelineSwipeColumns` (five) took the grid's AXIS —
  /// a member lane's pin is laid by its cell, which lays its value a
  /// different length on each axis, so the band the sweep finds it by is
  /// measured along the axis it stands on. 🔬The scan against the lane's
  /// last commit (`bcceefcd2`, at 388) named that one added and nothing
  /// gone.
  ///
  /// ⚠️389 → 392 on 2026-10-12, four named as the rule above asks (I-89 ④,
  /// the camera's path on the canvas). A camera's work is ONE drawing every
  /// surface writes (`camera_work_marks.dart`, 유저 2026-09-30 「공용화 잘
  /// 해주고」), so the sizes and the stratum the conte held as constants are
  /// each surface's to say: `cameraCrossMarks` (six — the frame it stands
  /// square to, where, its colour, its arm and its line, the stratum) and
  /// `_label` (five — the words, the frame, the colour, the sizes, the
  /// stratum). The canvas writes the path through `cameraPathMarks` (six —
  /// the path, where a canvas point lies on the surface, the sizes, the
  /// stratum and the frames it keeps to) and its crosses in time through
  /// `cameraPathTicks` (nine — those but the sizes, how many frames apart,
  /// the playhead they are coloured against, and their arm and line).
  /// 🔬`clean_code_diff` against the lane's base (`7f40aad8e`, at 388)
  /// named those four added and nothing gone.
  ///
  /// ⚠️392 → 393 on 2026-10-12, named as the rule above asks (I-89 ④, a
  /// position key bends its path). `cubicAt` (five — the parameter and the
  /// four control values) is the ONE Bernstein cubic a key's ease, a
  /// TVPaint camera's profile and path, and a position's path in space
  /// evaluate; TVPaint's own (`bez`, the same five) went into it.
  /// `PropertyTrack.withKey` (five) takes the key's path beside its two
  /// sides — the key's own fields, which `PropertyKey`'s constructor
  /// (excluded here) takes as well — so a name collapsing a range lands one
  /// path with its value. 🔬`clean_code_diff` against the lane's last
  /// commit before it (`91c98de18`, at 392) named those two added and `bez`
  /// gone.
  ///
  /// ⚠️393 → 394 on 2026-10-12, at the landing of I-89 ④ onto master
  /// `09cb64a24`: the trunk had come to 389 under its own ceiling — while it
  /// stood one above the count, `PresentClaims.claim` (five — now, the real
  /// vblank, the refresh period, the budget and the hand-off; `c1ffcd789`,
  /// the display's real vblank) landed unnamed — so the lane's five come on
  /// top of it. 🔬`clean_code_diff` between the lane's base (`7f40aad8e`, at
  /// 388) and that master named it added and nothing gone.
  ///
  /// ⚠️394 → 395 on 2026-10-12, named as the rule above asks (I-89 ④, a
  /// cross in time wears its frame — 유저 2026-10-12: 「그 상황에서
  /// 십자가쪽에도 프레임번호 아까말한대로 보여주도록」). `cameraCrossLabel`
  /// (eight — the words, the frame it stands square to, the cross it stands
  /// by, the crosses it keeps clear of, its colour, its size, its gap off
  /// the cross, the stratum): each surface says its sizes and its stratum,
  /// as for `cameraCrossMarks` and `_label` above. `cameraPathTicks` took
  /// its labels' size and gap, already counted. 🔬`clean_code_diff` against
  /// the lane's base (`07101e54a`, at 394) named that one added and nothing
  /// gone.
  ///
  /// ⚠️395 → 394 on 2026-10-12, following one down (F-341, a track's sound
  /// plays where no cut is): the schedule reads a run's sound through ONE
  /// window onto its track, and asks a file's length as one question — the
  /// rate and the lookup bound once (`_fileFramesAt`) — which took
  /// `_clampToFileLength` (six) under the line.
  ///
  /// ⚠️394 → 395 on 2026-10-12, named as the rule above asks (I-89-Q18, the
  /// camera's work laid over a drawing — the export's CAM):
  /// `ExportCelsCutDelta._with` (five) takes the drawings the camera's work
  /// is laid over beside the four sets it took — the delta's own fields,
  /// which its constructor (excluded here) takes as well, as for
  /// `PropertyTrack.withKey` above. 🔬`clean_code_diff` against master
  /// (`d0baee08e`, at 394) named that one added and nothing gone.
  ///
  /// ⚠️395 → 396 on 2026-10-12, named as the rule above asks (F-313, a cel
  /// carried onto another row shows its own picture before the release —
  /// 유저 2026-10-08: 「다른행이동하면 일시적으로 빈 블록으로 만드는 로직
  /// 있는거같은데 싹 삭제하고 법 통일. 항상 보여야함」).
  /// `EditingCanvas.stackAt` (five) takes the drag its shown cut shows beside
  /// that cut: the cut says which cel stands where, and only the drag says
  /// whose row a carried cel's pixels are still under — the list the
  /// release re-keys them by. Read back off the two cuts it would be a
  /// second answer to that question. 🔬`clean_code_diff` against master
  /// (`3ef2f8da7`, at 395) named that one added and nothing gone.
  ///
  /// ⚠️396 → 397 on 2026-10-15, named as the rule above asks (I-97, a photo
  /// laid on a sheet stays a photo — 유저 2026-10-15: 「사진으로 남게(셀의
  /// 텍스트처럼)」). `paintSheetInkWindow` (six) is the one way an export
  /// lays a sheet's window, and a window is its raster and the photos
  /// under it now: the canvas, the raster, where the window lays them, the
  /// photos, the files they are drawn from and how many target pixels a
  /// unit of the paper is — the last three what the screen's
  /// `paintSheetPhotos` takes, so an export samples a photo as the screen
  /// does. 🔬`clean_code_diff` against the lane's last commit before it
  /// (`93327c20a`, at 396) named that one added and nothing gone.
  ///
  /// ⚠️397 → 398 on 2026-10-15, named as the rule above asks (I-97, a pool
  /// picture dropped on a sheet's band is a photo in it — 유저 2026-10-15:
  /// 「원본 크기, 칸보다 크면 칸에 맞게」). `SheetInkController.putPhoto`
  /// (five) is `commitStroke` (five) said of a photo: the plane and the cel
  /// a window writes to, what goes on it, the history it is one step of and
  /// the sink a stroke's commit tells — so a photo lands through the door a
  /// stroke does. 🔬`clean_code_diff` against the lane's last commit before
  /// it (`f99fdc4ff`, at 397) named that one added and nothing gone.
  ///
  /// ⚠️398 → 399 on 2026-10-16, named as the rule above asks (card
  /// storyboard-thumbnails-let-go-by-the-one-order — the storyboard's
  /// pictures let go by the one order). `letGoLeastRecentlyUsed` (five) is
  /// `letGoWantedLatest` (eight) said of a cache no step wants anything of:
  /// the entries in the order they were used, what is held and the line, an
  /// entry's bytes and the letting go — the law's own, less the three a
  /// playhead answers (when an entry is next wanted, when it was last used,
  /// the floor), which the order the entries come in answers instead.
  /// 🔬`clean_code_diff` against master (`8d4b7c1fa`, at 398) named that one
  /// added and nothing gone.
  ///
  /// ⚠️399 → 398 on 2026-10-16, following that one down (card
  /// every-bounded-cache-is-one-lru — every bounded cache lets go by one
  /// LRU). `letGoLeastRecentlyUsed` is gone: the sheet's images and the
  /// storyboard's pictures keep an `Lru` (core), which says the same with
  /// three — what an entry costs, the limit, the letting go — and keeps the
  /// order in its own map. 🔬`clean_code_diff` against master (`8d4b7c1fa`,
  /// at 398): nothing added, nothing gone.
  ///
  /// ⚠️398 → 400 on 2026-10-16, named as the rule above asks (F-371, every
  /// picture Save As writes stands on the paper — 유저 2026-10-16: 「바탕
  /// 앱에서 설정한 캔버스 색 따라감. 캔버스색이 없으면 투명인거고 그런식」 ·
  /// 「jpg도 바탕 흰색고정말고 용지색으로 가자」). `writeFrameImage` (five)
  /// is the image tab's picture and Save As's, one call, and what the two
  /// hand it differs in the spec and now the paper: Save As's stands on the
  /// project's, the tab's on its own ground. `renderComposite` (five) lays
  /// that paper under the rows as the canvas lays it — the parameter the
  /// video stage's `_composite` already takes, handed on. 🔬`clean_code_diff`
  /// against master (`6ceb2a7ac`, at 398) named those two added and nothing
  /// gone.
  ///
  /// ⚠️400 → 402 on 2026-10-16, two named as the rule above asks
  /// (vanishing-point-types-Q4 — 유저 2026-10-16: 「가이드마다 막대 하나」).
  /// `GuideOverlayPainter._paintVanishingFan` (five) and
  /// `_paintParallelFamily` (five) take the guide's line density: how many
  /// rays a point sends and how many lanes a family stands either side of
  /// the middle, the number Q4 made the guide's own. It is the guide's, not
  /// the painter's — two guides on one canvas draw at their own — so it
  /// travels with the point being drawn. 🔬`clean_code_diff` against master
  /// (`ebefaea8b`, at 398, before F-371's two landed) named those two added
  /// and nothing gone.
  ///
  /// ⚠️402 → 403 on 2026-10-17, named as the rule above asks (F-370-Q3, a
  /// CLIP STUDIO text layer comes in as the app's own texts — 유저
  /// 2026-10-17: 「이제 들인다(앱의 글자로)」). `clipCelTextsOf` (five) is
  /// one layer's texts set as the app's: the layer, the resolution its
  /// point sizes are counted in, the opacity its cel bakes them at, and the
  /// name and the list what the app cannot keep of a setting is said by —
  /// the pair every warning of the plan is said with. 🔬`clean_code_diff`
  /// against master (`42ceeb00d`, at 402) named that one added and nothing
  /// gone.
  ///
  /// ⚠️403 → 404 on 2026-10-17, two named and one gone as the rule above
  /// asks (F-374 — 유저 2026-10-17: 「참조fx도 똑같이 fx로서 법 통일」).
  /// `EditorCanvasAreaState._handleLandings` (five) is the one landing every
  /// canvas box takes, and it says now which home the box keys: the
  /// reference fx's box kept a copy of it, and lands through it beside the
  /// layer's, the SE row's and the camera's.
  /// `LaneVerbs._transformTrackWithKeyToggled` (five) freezes a key where
  /// the lane's home stands the picture — a reference fx's where its file
  /// stands, a row's own lanes where the row does — for the ◆ and the range
  /// Create alike. `poseWithLaneValueEdited` left: a reference lane's value
  /// is a transform lane's value now. 🔬`clean_code_diff` against master
  /// (`0df66289b`, at 403) named those two added and that one gone.
  /// The same day the span verbs became one code over a row's homes, at
  /// 404 still — two named, two gone: `PropertyLaneLens.keysWritten`
  /// (five) is the key window's one write of a lane that is a field of its
  /// track, the transform's body, which the name tag's lanes take now, and
  /// `seNameTagTrackWithLaneKeysWritten` (six) is the name tag's door to it
  /// as `transformTrackWithLaneKeysWritten` is the transform's. The effect
  /// chain's and the name tag's span shifts left: every home moves through
  /// `LaneHome.shifted`. 🔬`clean_code_diff` against master (`7fe69eac7`,
  /// at 403) named the four added and the three gone of the two commits.
  ///
  /// ⚠️404 → 403 on 2026-10-18, following one down (F-374-Q10, every use of
  /// a reference's cel rasterized with it): `_bakeMovieRowIntoCels` (seven)
  /// left — a movie's rasterize plans each use of its cel
  /// (`_plannedMovieUse`) and bakes them from the door that opened their
  /// files. 🔬`clean_code_diff` against master (`38f473e11`, at 404) named
  /// that one gone and nothing added.
  ///
  /// ⚠️403 → 404 on 2026-10-18, named as the rule above asks (F-374-Q8 —
  /// 유저 2026-10-17: 「맞춘다 — 참조 그림은 벽 밖까지 통째로」).
  /// `rasterizeImageToSurface` (five) is five again: the image, the canvas,
  /// where it goes and the grid — and whether it is a reference's file,
  /// laid whole past the wall (the reference doors and a movie's frames),
  /// or a picture a door draws a row of, cut at the wall as a tool's is (a
  /// cut folder, a PSD expanded, a text's letters). The answer scoped the
  /// whole lay to reference rows' cels. 🔬`clean_code_diff` against master
  /// (`b6cbe550e`, at 403) named that one added and nothing gone.
  /// ⛔Not two functions to fit: the cut is the one line that differs, and
  /// a second name would be a second copy of the rest.
  ///
  /// ⚠️404 → 405 on 2026-10-18, named as the rule above asks
  /// (text-letters-lean-and-underline ⑥ — 유저 2026-10-17 「일곱 전부」:
  /// a text's letters drawn as wide as its horizontal scale says).
  /// `CanvasLetterPasses.paint` (five) takes how wide the letters are
  /// drawn beside where the hard ones are cut, what draws a setting, and
  /// the lines they wear: the width is laid on INSIDE each pass, under the
  /// hard passes' cut, so that a hard letter is cut as far past itself in
  /// the canvas's pixels at every width. ⛔Not the caller's to lay on: a
  /// canvas narrowed before the passes narrows the cut with the letters,
  /// and a draw that narrows itself leaves the lines it wears as wide as
  /// they were. `paintAt` keeps its four — the one setting that narrows
  /// (a text in lines) asks `paint` itself. 🔬`clean_code_diff` against
  /// the lane under it (`17f66740b`, at 404) named that one added and
  /// nothing gone.
  ///
  /// ⚠️405 → 407 on 2026-10-18, two named as the rule above asks (I-105 —
  /// 유저 2026-10-16: 「셀 출력시 CAM 적용 하는거랑 똑같이 … 가이드 버튼」).
  /// `paintGuidesAtRest` (five) is the one picture 래스터라이즈 bakes and a
  /// cel's export lays over a drawing (I-105-Q2: 「법 통일」): the guides,
  /// the paper and the colour they are drawn on and in, and how many of its
  /// own pixels a canvas pixel is — the bake at one, a file at the CAM's
  /// sizes. `_ExportDialogState._celLaying` (five) is the one answer the
  /// band's direction, CAM and guide pills give: the cut, the sheet shown,
  /// whether there is anything to lay, and how the cut's list reads and
  /// writes it. 🔬`clean_code_diff` against master (`9a7a8e3de`, at 404)
  /// named those two added and nothing gone; stood on ⑥'s 405 above when
  /// the lane was rebased onto it (10-19).
  ///
  /// ⚠️407 → 408 on 2026-10-19, named as the rule above asks (board
  /// `F-287`, 유저 「다른 합성모드도 똑같으니 완벽하게 검사」).
  /// `LayerStackPaintPass._layLevelPixels` (five) is the one lay of a
  /// level's pixels one texel to a pixel: the patch's base, the scroll
  /// carry's overlap and a region composed apart were three draws of one
  /// copy, which the raw image draw ratchet caught at the third. Its five
  /// are the draw's own — the canvas, the image, where it lands, which part
  /// of the image (the scroll carry's overlap; the other two lay it whole)
  /// and `src` for a region laid in place of the carried pixels.
  /// 🔬`clean_code_diff` against master (`37cd01b30`, at 407) named that
  /// one added and nothing gone. ⛔Not split to fit: a second name for the
  /// `src` lay would be a second copy of the rest.
  ///
  /// ⚠️408 → 409 on 2026-10-19, named as the rule above asks (I-58 — 유저
  /// 2026-10-01: 「버튼누르면 창 열려서 숫자만 입력가능한창」). `_askFrameCount`
  /// (six) is the one window that asks for a count of frames, the N commas'
  /// and the ● every n koma's: the context, the session it reads the frames
  /// a second from and keeps the last entry in, and what the window is
  /// keyed, titled, iconned and its field called. The N commas asked
  /// inline; the ● asks the same, so the window is one. 🔬`clean_code_diff`
  /// against master (`11209d525`, at 407) named that one added and nothing
  /// gone; stood on F-287's 408 above when the lane was rebased onto it.
  ///
  /// ⚠️409 → 408 on 2026-10-20, lowered as the rule asks (F-176 · F-418,
  /// the brush lanes): `tipMaskFromPatternArray` (six) left the list. It
  /// became two when a brush took several tips — the array's reader and
  /// one material's — and both carried the brush's name, the part's words
  /// and the warnings, the three every warning about a part is made of;
  /// those travel as one `_BrushPart` now, and the four 「imported without
  /// it」 sentences are one (`_leftOut`). 🔬`clean_code_diff` against the
  /// lanes' base (`243dd8074`, at 409) named that one gone.
  ///
  /// ⚠️408 → 407 on 2026-10-21, lowered as the rule asks (F-398 ⑤): the
  /// 겸용 conversion's `_celKey` (five) left the list — it takes the side
  /// a key is in. 🔬The lane's scan against master (`5cd21708d`, at 408)
  /// named that one gone and nothing added.
  ///
  /// ⚠️407 → 408 on 2026-10-21 (400 → 401 on 2026-10-17, where the lane was
  /// cut), named as the rule above asks (F-364-Q1 b, a run behind its clock
  /// shows every picture — 유저 2026-10-15: 「하나도 안 건너뛴다 — 소리를
  /// 그림에 다시 맞춘다」). `playheadWay` (five) is the ONE way a run's playhead goes,
  /// the canvas's run and the media viewer's: the walk's three numbers
  /// (where it stands, where its clock says, how long the run is), what
  /// stops it (a frame that waits for its picture), and now how far a look
  /// may take it — every frame its clock went over, or one.
  /// 🔬`clean_code_diff` against the lane's base (`34c6233f6`, at 400) named
  /// that one added and nothing gone; stood on the brush lanes' and F-398's
  /// 407 above when the lane was rebased onto them (10-21). ⛔Not bundled to
  /// fit: a run that cut its clock's frame short itself would walk the lap
  /// the way walks, once in each of the two runs.
  ///
  /// ⚠️408 → 410 on 2026-10-22, two named as the rule above asks (I-117 —
  /// 유저 2026-10-21: 「psd 내보내기 내용물」). `PsdBuilder.addLayer` (five)
  /// and `PsdBuilder.openGroup` (five) write a Photoshop document's two
  /// kinds of row as its records keep them: a name, what the row holds
  /// (a picture's packed pixels, a folder shown shut or open), and how it
  /// is laid over the rows under it — its strength, its eye and its blend,
  /// the three every record carries and the app's own row keeps
  /// (`Layer.opacity` · `isVisible` · `blendMode`). 🔬`clean_code_diff`
  /// against master (`66c6c2063`, at 408) named those two added and
  /// nothing gone. ⛔Not bundled to fit: a writer that took the three as
  /// one value would have every caller build that value out of a row's
  /// three fields first.
  /// ⚠️410 → 412 on 2026-10-22, named as the rule above asks (card
  /// box-sized-by-two-picks): two of `axis_turn.dart`'s turns, the home
  /// that says a box by the axis once instead of the nineteen hand-turned
  /// pairs it replaced. `stripAcross` (seven) is a turned `Positioned`:
  /// the axis, where across and how thick, the child, its key, and the two
  /// ends — `fromEnd` for a lane at a panel's far edge or a caret after a
  /// row, `alongStart` for a drop's line held past a rail row's section
  /// slot (F-423②). `sizedAlong` (five) is a turned `SizedBox`, and took
  /// its child's key as `stripAlong` does. 🔬`clean_code_diff` against
  /// master (`41c4dfa72`, at 410) named those two added and nothing gone.
  /// ⛔Not split to fit: each parameter is one of the widget it turns.
  /// ⚠️412 → 413 on 2026-10-22, named as the rule above asks (F-176-Q7 —
  /// the brush cursor is the tip a hovering pen would lay down).
  /// `brushInputFactor` (five) takes the sources the reading HAS: a pen
  /// that has not touched yet has only how it is held, so its pressure and
  /// speed rows are skipped as a source the device cannot answer is.
  /// ⛔Not bundled with `random`: the throw is the stroke's, which sources
  /// a reading has is the reading's — two questions. 🔬`clean_code_diff`
  /// against the lane's base (`fdbdd1a3d`, at 408) named that one added and
  /// nothing gone; the lane laid over master at 412, 413.
  /// ⚠️413 → 415 on 2026-10-22, named as the rule above asks (card
  /// a-blurred-folder-cut-by-the-view-moves-on-vulkan — a row in an
  /// advanced blend is composed over its backdrop in the shader).
  /// `drawBlendOverBackdrop` (eight) is `drawSubtreeAsImage` with two
  /// pictures where that has one: the canvas, the grid's bounds, scale and
  /// cap, the backdrop and the row, the blend, and what the canvas still
  /// shows. `_composeInTheFrame` (six) is its road where the engine reads
  /// the backdrop: the canvas, the grid and its scale, the backdrop, the row
  /// already rasterised, the blend. `LayerBlendShader.shaderFor` (five)
  /// hands the program what its formula reads: the two pictures, the blend
  /// and the grid's size. 🔬`clean_code_diff` against master (`44668f9da`,
  /// at 413) named those three added and
  /// `LayerStackPaintPass._layLevelPixels` gone. ⛔Not bundled to fit: each
  /// parameter is one the draw reads, and a value made of them would be
  /// built by every caller out of the same fields first.
  /// ⚠️415 → 416 on 2026-10-23, named as the rule above asks (the same
  /// card — the row handed to the shader as it is where it lands texel for
  /// texel). `_composeInARaster` (five) is `_composeInTheFrame`'s sibling,
  /// the road where the frame cannot be read: the canvas, the grid, the
  /// backdrop already rasterised, the row (made inside, so a raster of it
  /// is disposed with the rest), the blend. The same change widened two
  /// already counted: `drawBlendOverBackdrop` (nine) takes the row's own
  /// image, and `LayerBlendShader.shaderFor` (six) where the row lies on
  /// the draw; the row `_composeInTheFrame` takes may now be that image.
  /// 🔬`clean_code_diff` against the lane's base (`6f900eab3`, at 415)
  /// named that one added and nothing gone. ⛔Not kept inside
  /// `drawBlendOverBackdrop` to save the count: there its body ran past
  /// sixty lines, and the two roads read better side by side, each named.
  /// ⚠️416 → 420 on 2026-10-23, five named as the rule above asks (card
  /// nested-folder-buffers-read-past-the-view — a buffered row inside a
  /// blurred folder holds its ink past the view, as the camera's does).
  /// The editing stack's walk carries what reads the nodes, beside the
  /// scale it already carried, and each node hands its own buffer down:
  /// `_paintNodesWith` (five) — the canvas, the nodes, the scale, what
  /// reads them, and the walk that paints a node's children;
  /// `_paintGroupNode`, `_paintAdjustmentNode` and
  /// `_paintBackdropBlendNode` (five each) — the canvas, the node, the
  /// scale, what reads it and that walk; `_paintSplit` (five) — the canvas,
  /// the nodes, the depth its slots are named by, the scale and what reads
  /// them. 🔬`clean_code_diff` against master (`f8e059c22`, at 415) named
  /// those five added and nothing gone. ⛔Not bundled to fit: the camera's
  /// walk carries the same scale and reader side by side
  /// (`renderThroughCamera`'s `paintNodes`), and a buffer hands its
  /// children a scale of its own (`drawSubtreeAsImage`'s `paintSubtree`),
  /// so a value of the two would be built at every hand-down first.
  /// ⚠️420 → 421 → 420 on 2026-10-24 (card one-picture-per-frame — a
  /// frame's one picture is drawn by the canvas's own paint body):
  /// `frameDrawingOf` came in at five — the frame's nodes and the four the
  /// canvas draws them on, its size, how far its pasteboard reaches,
  /// whether it paints paper and which paper — and was not bundled to fit,
  /// the four being `CanvasLayerStackView`'s own fields. ↩️Bundled the same
  /// day (`FramePage`) for a reason of its own: the frame's picture is
  /// KEYED by the four (`FramePictureKey`), so they are one value already.
  /// ⚠️420 → 422 on 2026-10-25, two named as the rule above asks (I-92 — a
  /// row clipped to the layer below): `drawClipAsImage` (six) — the canvas,
  /// the bounds, the scale, what paints the base, what paints what clips to
  /// it and the paint the group is laid by — the shape of
  /// `drawBlendOverBackdrop` beside it, whose two halves are the same two
  /// walks; `LayerStackPaintPass._paintClipNode` (five) — the shape of the
  /// three node painters the 10-23 note names. 🔬`clean_code_diff` against
  /// master (`3354f5258`, at 420) named those two added and nothing gone.
  /// ⚠️422 → 425 on 2026-10-25, three named as the rule above asks (card
  /// one-picture-per-frame ②-3 · ②-4 — every screen draws a frame's one
  /// picture, and a canvas that stands patches its strokes into it).
  /// `drawOnTheDisplay` (eight) is the ONE blit the display lays an image
  /// it is handed by — the canvas's display buffer and a frame's picture —
  /// and each parameter is one the draw reads: the canvas, the image, what
  /// of it and where, the view and the device's ratio its sampling and its
  /// edge are read off, the level it was composed at, and how it lays (a
  /// patch still landing lays its clear texels too). `FramePictures._make`
  /// (five) — what the frame is stacked of, which frame, when its maker
  /// gives up, when its turn is due, and whether it goes to the front of
  /// the store's line — is the one road `make` (a run's frame, ahead) and
  /// `makeShown` (the frame a screen stands on) take; `_lay` (five) takes
  /// the key and the drawing and hands the last three on.
  /// 🔬`clean_code_diff` against the lane's base (`3cee149eb`, at 420) named
  /// those three added and nothing gone. ⛔Not bundled to fit: the turn
  /// reads two of the three (`QuietTurns.inAQuiet`) and the store the third
  /// (`FramePictureStore.lay`), so a value of them would be taken apart at
  /// the one place it is handed to.
  /// ⚠️425 → 427 on 2026-10-25, two named as the rule above asks (I-65 — a
  /// cel number stands on a transform's Position and Scale lanes, edited by
  /// the transform's own verbs): `effectsWithLaneValueEdited` (five) takes
  /// the transform tool's 「배율 연동」 for the Scale it hands
  /// `transformTrackWithLaneValueEdited` (seven), and
  /// `effectsWithGroupReset` (five) the paper the number rests on, for
  /// `transformTrackWithGroupReset` (five) — each the shape of the
  /// transform verb it hands to. 🔬`clean_code_diff` against master
  /// (`c28ff5db3`, at 422, before the three above) named those two added
  /// and nothing gone. ⛔Not
  /// bundled to fit: the session reads the switch from the tool and the
  /// paper from the row's cut, each at the call (`LaneVerbs`), so a value
  /// of the two would be built at every call first.
  /// ⚠️426 → 427 on 2026-10-28 under the same ceiling (F-489 — 유저
  /// 2026-10-27: 「이름 없는 블록의 기본 마크1,2인지 설정할수있게」):
  /// `timelineCellMarker` (five) takes the mark an unnamed drawing wears,
  /// as the row's host heard the pick. 🔬`clean_code_diff` against the
  /// lane's base (`f2d4f1e21`) named that one added and nothing gone.
  /// ⛔Not bundled to fit: the name and the mark meet only in the head's
  /// one case ([drawingHeadOf]), and a value of the two would be built for
  /// every cell first.
  ///
  /// ⚠️427 → 428 on 2026-10-28 under the same ceiling (F-489-Q1 — 유저
  /// 2026-10-27 「둘 다 따라간다」): `planTvpImport` (five) takes the mark a
  /// TVPaint dot wears, as its door heard the pick — the planner is pure
  /// and reads no setting. 🔬`clean_code_diff` against the lane's base
  /// (`7111911e6`) named that one added and nothing gone. ⛔Not bundled to
  /// fit: the clip, the file key, the mint and the mark are each the
  /// door's own, at the one call.
  ///
  /// ⚠️428 → 432 on 2026-10-28, four named as the rule above asks (I-132-Q3
  /// — AE's Radial Blur, its centre a point of its own, Q12 b).
  /// `_effectPictureBox` (eight) and `_effectPointBox` (seven) are the two
  /// boxes an effect declares — a cel number's letters, a point's cross —
  /// the halves of `_effectBox`, which went under sixty lines with them:
  /// each takes what every box of the host takes (its frame, view and
  /// canvas size), where the row shows, the effect's name and its landing
  /// (`_EffectLanding`), and its own — the row and the number sampled, or
  /// the point. `radialBlurPasses` (six) takes the centre as the pass's
  /// own two fields, which way it blurs, how far, how finely (the farthest
  /// a pixel lies) and Draft. `resolveAdjustmentScopePass` (five) gained the
  /// paper, as every plan did: how far a radial blur reaches is how far the
  /// paper's farthest corner lies from its centre. 🔬`clean_code_diff`
  /// against master (`2dc3430ce`, at 428) named those four added and
  /// nothing gone. ⛔Not bundled to fit: each is handed on at the one call
  /// it is read at, so a value of them would be taken apart there.
  ///
  /// ⚠️432 → 434 on 2026-10-28, two named as the rule above asks
  /// (the-walk-draws-off-the-grid-on-impeller): `BitmapSurfacePainter
  /// .paintContentInto` and `_SurfacePaintPass.paintContentInto` (five
  /// each) take `pixelRatio`, the device pixels a unit of the canvas's space
  /// lands on past its transform — the grid a coordinate's edge is cut on
  /// where its grid falls off the pixels, which no caller may leave to a
  /// default (a wrong one cuts on the logical grid). 🔬`clean_code_diff`
  /// against master (`d36fa35ba`, at 432) named those two added and
  /// nothing gone.
  /// ⛔Not bundled with `scale` to fit: the scale is the row's before its
  /// pose and picks the filter, the ratio is the canvas's past every
  /// transform and picks the grid — one value of the two would answer two
  /// questions.
  ///
  /// ⚠️434 → 435 on 2026-10-28, one named as the rule above asks (I-131,
  /// the palette's fold and lock): `NamedPalette._with` (five) is a
  /// palette's copy — every field it has, the folded and the locked among
  /// them — the copyWith idiom the rule leaves out, under a private name.
  /// ⛔Not split to fit: a copy that takes half the fields is two copies.
  ///
  /// ⚠️435 → 436 on 2026-10-29, one named as the rule above asks (I-138,
  /// an animation row born with its first cel): `plannedAddLayerCommand`
  /// (five) takes `bornWithACel` — whether each 겸용 copy is born with a
  /// cel of its own — beside the row, its cut, its slot and the repository.
  /// ⛔Not bundled into the row: it is a fact of the ADD, not of the layer
  /// (the same row pasted hands its copies its lane).
  ///
  /// ⚠️436 → 445 on 2026-10-29, nine named as the rule above asks (I-132
  /// ⑫b·⑫c — a camera lens blur reads its blur map off the row it names,
  /// where that row shows, 🗣️Q16 a · Q21 a). `_CompositeTreeWalk._group`
  /// and `._adjustment` (six each) take what the walk hands a folder or an
  /// adjustment whose chain reads rows (`CompositeReadsRows`): the painter
  /// of those rows and the node it is held as — the one the cells below a
  /// pen were kept under. `._reading` (six) is the one that hands them: the
  /// reader, the rows, where it is held. `effectPropertyLanes` (five) takes
  /// the cut's rows a row parameter's menu names. `_LayerStackPaintPass
  /// ._paintSurfaceRow`, `steppedForChain`, `applyEffectSteps`,
  /// `_stepDraws` and `_leadDraws` (five each) carry the rows a step reads
  /// from the walk down to the pass that gathers by them — the painter,
  /// then the row laid on the step's grid. 🔬`clean_code_diff` against
  /// master (`2a9750ac3`, at 436) named those nine added and nothing gone.
  /// ⛔Not bundled to fit: the row a step reads is the step's, the space,
  /// paper and width it rasters at the chain's — one value of them would
  /// answer two questions; so would one of where a node is held (its cells
  /// kept) and what it reads (drawn afresh, kept nowhere).
  ///
  /// ⚠️445 → 448 on 2026-10-29, three named as the rule above asks (F-494 —
  /// 유저 2026-10-28: 「하고있는 과정을 투명하게 … 퍼센테이지에 반영하면서」).
  /// `TrimmedPieces.cut` and `writeMovieSpan` (five each) take who hears
  /// how far a movie's piece is encoded — the wait that stood behind the
  /// import window at 0% (61 s of a 3.4GB file's two minutes) — beside the
  /// file, its kind or its piece's path, and the span kept and its clock.
  /// `_movieSoundAlone` (five) hands a movie brought as its sound alone to
  /// the sound's door with what the movie's door was handed for it, who
  /// hears its bytes held among them. 🔬`clean_code_diff` against master
  /// (`b885cdce4`, at 435) named those three added and nothing gone; the
  /// door's save roads took the two reporters as one value instead
  /// (`_SaveTold`), and the blob's writer stayed as it was — its reads are
  /// measured from outside, as an append's are (`mediaBlobReadsAtMost`).
  /// ⛔Not bundled to fit: the in and out are read off a row's settings one
  /// by one at each call, and a value of them and the reporter would be
  /// taken apart again inside the cut. (Measured at 435 → 438 on its own
  /// lane; it landed after I-132 ⑫b·⑫c, so it counts on from 445.)
  ///
  /// ⚠️448 → 450 on 2026-10-29, two named as the rule above asks (card
  /// a-step-drawn-in-place-reads-short-of-the-one-picture): a composite
  /// route's row painter takes what of the canvas the buffer holding the
  /// row reads — `_LayerStackPaintPass._paintRow` and the camera render's
  /// `paintRow` (five each), the one type both fill. A row's raster that
  /// stopped at what is shown stopped short of what a blurred folder
  /// reads past it. ⛔Not bundled to fit: where the row is read is the
  /// walk's, the rows its chain reads are its own.
  const wideSignatures = 450;

  /// ⚠️437 → 436 on 2026-09-25, following one down: the storyboard panel's
  /// head became a step of its own (the in-between mark round), which took
  /// `_paintPanelWriting` under the line. 🔬Measured on the lane rebased
  /// onto `8ead3d87d`, where master stood at the ceiling.
  ///
  /// ⚠️436 → 433 on 2026-09-25: master stood at 435, and two of those were
  /// the brush lab's — the scan's `lib/dev/` exclusion never matched the
  /// relative root this test hands it (`appDartFiles` answers for every
  /// scan now; ratchet-dev-exclusion-relative-root).
  ///
  /// ⚠️433 → 434 on 2026-09-25, ONE name, as the rule above asks:
  /// `_StillLayer._signatureOf` (still_raster.dart) — what a dock region's
  /// layer tree IS, as values to compare: a case per layer type Flutter
  /// has, each naming the properties that can change in place. A flat
  /// dispatch, the shape the complexity round refused to penalise; split by
  /// type it would scatter the one list a reader checks against Flutter's
  /// own layer classes. 🔬`clean_code_diff` between master and the lane
  /// named it and `_capture`, which had three jobs (take the image, build
  /// the picture that shows it, report a refusal) and was given one each.
  ///
  /// ⚠️434 → 433 on 2026-09-25, following one down: the storyboard's
  /// `_paintPanelPictures` fell under the line when the panel writing left
  /// it for the bands (and the fold gates with it).
  ///
  /// ⚠️433 → 432 on 2026-09-26, following one down: the ruler's
  /// `TimelineFrameRulerPainter.paint` fell under the line when both
  /// strips' window pass became one call (`TimelineRulerScale.paintWindow`,
  /// I-22). 🔬`clean_code_diff` between master (`0e6fd93f2`, at 433) and
  /// the lane named that one and nothing added.
  ///
  /// ⚠️432 → 430 on 2026-09-26 (I-7 ③, a file opens as a session of its
  /// own): `ProjectFileDoor.openProjectFromFile` and
  /// `TvppImportDoor.openAsProject` went — each replaced a live project and
  /// carried the reset that went with it — and what took their place is
  /// read, settle and bake, each in named steps (`_landCels`,
  /// `_standWhereItWasSaved`, `_bakeEveryCel`, `_registerSounds`,
  /// `_projectOf`). 🔬`clean_code_diff` between master (`2907ac360`, at 432)
  /// and the lane: those two gone, nothing added.
  ///
  /// ⚠️430 → 431 on 2026-09-27, two named as the rule above asks (I-22, a
  /// row reads each cell once a pass). A tile's ink was ONE body,
  /// `_emitForeground` (161), that wrote the ops and awaited each word's
  /// bake in the same loop. The ops are written inside the painter's one
  /// pass now (`readInOnePass`), which cannot await, so the writing stays
  /// `_emitForeground` (86, synchronous) and the bake after it is
  /// `_bakeGlyphs` (69: bake the distinct words, stack them into the
  /// tile's atlas, write their glyph ops). `_raster` (65) is where that
  /// pass opens, around the paper and the ink both. 🔬`clean_code_diff`
  /// between master (`76bf3351f`, at 429) and the lane named those two and
  /// nothing else.
  ///
  /// ⚠️431 → 432 on 2026-09-27, one named as the rule above asks (F-192, a
  /// fade clears from its own black or white screen). The printed sheet's
  /// `_paintInstructionMarkSlice` (62) draws each mark kind in one switch,
  /// and W.I and W.O became kinds of their own that share the fade wedge's
  /// case — two case labels and the line that names the mark once for the
  /// wedge's direction. 🔬`clean_code_diff` between master (`87a5d3c21`, at
  /// 431) and the integration lane: that one added, nothing else.
  ///
  /// ⚠️432 → 426 on 2026-09-30, lowered as the rule asks: master stood at
  /// 427, and the camera-work round took one off. What a render looks
  /// through — the camera there, or a camera standing square over the whole
  /// canvas — is asked in one place now (`ExportFrameRenderer._viewFor`),
  /// so `renderCelGroup` gave up its own copy of that choice and fell under
  /// the line. 🔬`clean_code_diff` between master (`2757f5455`, at 427) and
  /// the lane named that one and nothing added.
  ///
  /// ⚠️426 → 423 on 2026-10-01, lowered as the rule asks: master stood at
  /// 426, and F-244's cells-row round took three off — the x-sheet's
  /// `_columnFor` (its copy of the cells row), the timeline's `_layeredRow`
  /// (its memo, now `keptTimelineCellsRow`, the sheet's too) and
  /// `_buildFrameRowsBody` (thirty answers handed over one by one, now the
  /// hooks bundle). 🔬`clean_code_diff` between master (`6dce949f7`, at 426)
  /// and the lane named those three and nothing added.
  ///
  /// ⚠️423 → 422 on 2026-10-01, lowered as the rule asks (I-55 · I-28, the
  /// pixel copy round): two off, one on. `celPixelWalkFor` fell under the
  /// line when every pixel reader's box-and-mask became one reading
  /// (`selectionMaskOnPasteboard`), and the cell verbs' `pixelVerbCellKeys`
  /// when the ladder it walked became a step of its own that the paste
  /// shares. `PixelVerbs._pastePixels` (62) is the one added: the board
  /// landing on every cel the ladder names, each through the marquee on its
  /// own row, one landing per physical cel, folded into one undo. 🔬The
  /// lane's scan against master (`1bde29155`, at 423) named those three.
  ///
  /// ⚠️Held at 422 on 2026-10-01 (F-222 ②~④): the round traded two for
  /// two, and the two it put on are named because the rule above asks it.
  /// Off: the camera frame's painter (`CameraFramePainter.paint`, its
  /// handles and lever gone into the box) and the canvas area's
  /// `_cameraOverlay` (its pose subscription now the one `_atTheCameraPose`
  /// the frame and its box both stand on). On: `_RowTransformBoxState.build`
  /// (62 — the claim, the finger gate, the pan and the chrome, in that
  /// order) and the canvas area's `_layerBox` (116 — the row's pose under
  /// its folders and the four landings, each with the decision it
  /// carries). 🔬The lane's scan against master (`25fdf5106`, at 422).
  ///
  /// ⚠️422 → 421 on 2026-10-06, lowered as the rule asks (F-280, the one
  /// fold): the selection layer's `_commitTransform` — three branches, one
  /// per shape a box can be, each with its own copy of the landing — is
  /// gone into `_foldOpenBox`, which every ending of a transform now takes.
  /// 🔬The lane's scan against master (`973c69ed8`, at 422) named that one
  /// and nothing added.
  ///
  /// ⚠️421 → 420 on 2026-10-06, lowered as the rule asks (F-289, the
  /// viewer's transport): `pageTurnStrip` left the list with its leading
  /// run — the media viewer's PLAY was its one tenant, and a document that
  /// runs stands on the transport now. 🔬The lane's scan against master
  /// (`5ebc1afe6`, at 421) named that one gone and nothing added.
  ///
  /// ⚠️420 → 419 on 2026-10-06, lowered as the rule asks (F-293, the piece
  /// door): the pixel verbs' `_pastePixels` — the ladder walk, the selection
  /// read a row, the cut and the landing in one body — is `pieceLandings`
  /// and a reader of its selection, each under the line. 🔬The lane's scan
  /// against master (`0b620fa9a`, at 420) named that one and nothing added.
  ///
  /// ⚠️419 → 418 on 2026-10-06, lowered as the rule asks (F-299, the mapped
  /// buttons): the canvas tap's `toolTapHandler` — a tap per tool, with the
  /// stamp's landing and the eyedropper's pick written out in its cases —
  /// handed the stamp to `_stampAt` (F-293) and the pick to
  /// `eyedropperPick`, which a held button asks too. 🔬The lane's scan
  /// against master (`0b620fa9a`, at 420) named that one and the paste's,
  /// and nothing added.
  ///
  /// ⚠️418 → 417 on 2026-10-06, lowered as the rule asks (F-289, the kinds
  /// of the Cels tab): `paintInstructionCel` went with the renderer that
  /// drew a direction block's WRITING — a direction row writes the pictures
  /// drawn on it now, as every cel is written. 🔬The lane's scan against
  /// master (`9683cd75e`, at 420) named that one gone and nothing added.
  ///
  /// ⚠️417 → 415 on 2026-10-06, lowered as the rule asks (F-289, the Cels
  /// list under its preview): the window's `_previewZone` lost the list
  /// that stood beside the preview, and `_celBundleItem` — a row of that
  /// list — went with it. The board that took their place is cut into
  /// named parts (`export_cels_board.dart`). 🔬The lane's scan against the
  /// kinds lane (`0079de186`, at 419) named those two gone and nothing
  /// added.
  ///
  /// ⚠️415 → 412 on 2026-10-06, lowered as the rule asks (F-289, the
  /// timesheet and the cut envelope as kinds of the Cels tab): three
  /// bodies of the export window went with the two tabs — `_envelopeModules`
  /// (the strata picker and the layered files), and the envelope's and the
  /// timesheet's arms of `_transportLine` and `_navBar`. 🔬The lane's scan
  /// against the list lane (`4084bf788`, at 417) named those three gone and
  /// nothing added.
  ///
  /// ⚠️412 → 411 on 2026-10-06, lowered as the rule asks (F-289, the export
  /// preview as a canvas-base panel): the scrub bar's painter
  /// (`_ExportScrubPainter.paint`) went with the bar — the preview's own
  /// transport turns the picture. 🔬The lane's scan against the tabs lane
  /// (`3eebdddec`, at 414) named that one gone and nothing added.
  ///
  /// ⚠️411 → 410 on 2026-10-06, lowered as the rule asks (F-289, the export
  /// window without its name bar): `_nameBar` went — the name is a module
  /// of the settings column and the place is asked when Export is pressed.
  /// 🔬The lane's scan against its own preview commit (`8743ae700`, at 413)
  /// named that one gone and nothing added.
  ///
  /// ⚠️410 → 409 on 2026-10-09, lowered as the rule asks (F-282, a numbered
  /// run's span picked on the preview's IN/OUT): the import window's
  /// `_twoZones` gave its preview to `_preview` — the run made the picture
  /// zone a question of its own. 🔬The lane's scan against master
  /// (`34f161c64`, at 410) named that one gone and nothing added.
  ///
  /// ⚠️409 → 408 on 2026-10-10, lowered as the rule asks (board
  /// long-sound-conform-memory, a conform made as it is decoded):
  /// `resampleAudioReference` left — its filter design and its loop are the
  /// `_ResamplerDesign` the piece-at-a-time stream runs too. 🔬The lane's
  /// scan against its base (`e5074ed43`, at 410) named that one gone and
  /// nothing added.
  ///
  /// ⚠️408 → 407 on 2026-10-10, lowered as the rule asks
  /// (playback-plays-the-screen-material ②, a run seen through the camera
  /// plays on the canvas): the composite playback view's `build` went with
  /// the view. 🔬The lane's scan against master (`a81501886`, at 410 before
  /// the two lowerings above landed) named that one gone and `_cutFadeWash`
  /// held at sixty — the camera's frame for its unit — not added.
  ///
  /// ⚠️407 → 408 on 2026-10-15, named as the rule above asks
  /// (playback-frame-raster-is-the-whole-window — background GPU work takes
  /// its turn in the quiet between a run's held frames): the asynchronous
  /// road's chain left `LayerFrameImageCache._prepareNow` (still over: its
  /// thaw, its content checks and its keys are the CPU's half) as
  /// `_composed` (70), so the turn is taken before it and given back once
  /// it lands. It is the twin of `_composedNow` (65, already counted) in
  /// shape — a plain function of the surface, the plan and the quality,
  /// banked by the caller. 🔬`clean_code_diff` against master (`01986af08`)
  /// named that one added and nothing gone. ⛔Not split to fit: the chain's
  /// law (one wait an image, at any level) is one statement over the whole
  /// chain, and its sync twin keeps the same shape.
  ///
  /// ⚠️408 → 409 on 2026-10-17, named as the rule above asks (F-370-Q3, the
  /// same text layers): the tree stood at 407, and two crossed.
  /// `planClipImport` (65) is the plan's one assembly, and each bake it
  /// hands out now carries a text layer's texts — read where the bake is
  /// addressed, so what they cannot keep is the plan's to say, before a
  /// pixel is read. `ClipImportDoor._workOf` (72) finds each bake's bytes in
  /// the file, an arm a kind of source, and a text layer's is the third:
  /// the pictures CLIP STUDIO drew of its texts, beside a stored picture's
  /// blocks and a vector layer's strokes. 🔬`clean_code_diff` against master
  /// (`42ceeb00d`, at 407) named those two added and nothing gone. ⛔Not
  /// split to fit: the arms answer the one question the loop asks — where a
  /// bake's pixels are — side by side, and one taken out would answer it
  /// somewhere the other two do not.
  ///
  /// ⚠️409 → 408 on 2026-10-17, following one down (F-374): the lane range
  /// move's `LaneRangeMoveDrag.update` shifted each family through an arm
  /// of its own; every home moves through one `LaneHome.shifted` now, and
  /// the update is a preview of what that answers. 🔬`clean_code_diff`
  /// against master (`7fe69eac7`, at 409) named that one gone and nothing
  /// added.
  ///
  /// ⚠️408 → 409 on 2026-10-18, named as the rule above asks (F-374-Q10,
  /// every use of a reference's cel rasterized with it):
  /// `ProjectImportDoors.rasterizeMovieReference` (66) opens each file the
  /// uses of its cel show, once, and bakes them all through one bank — the
  /// one row's tail `_bakeMovieRowIntoCels` held is planned a use apiece
  /// now (`_plannedMovieUse`, folded by `_movieCelsOf`), and the door keeps
  /// the bake's own call. 🔬`clean_code_diff` against master (`38f473e11`,
  /// at 408) named that one added and nothing gone. ⛔Not split to fit:
  /// the movies it opens it closes, in its own `finally` — a helper that
  /// opened them would leave the closing to a scope it cannot see.
  ///
  /// ⚠️409 → 411 on 2026-10-18, two named as the rule above asks (I-105,
  /// the guides laid over a cel as CAM lays the camera's work).
  /// `ExportFrameRenderer.renderCelGroup` stood at the line — the stack's
  /// one picture a layer, with the decisions on blends and effects beside
  /// it — and crossed it handing the camera's work and the guides over as
  /// one pass, in the guides' colour. `_exportCels` crossed it reading that
  /// colour off the theme where the run starts and handing it to each
  /// cel's render. 🔬`clean_code_diff` against master (`9a7a8e3de`, at 409)
  /// named those two added and nothing gone. ⛔Not split to fit: each says
  /// one thing — the stack and what is laid over it; the files a run
  /// writes — and a part taken out would be read beside the rest anyway.
  ///
  /// ⚠️411 → 412 on 2026-10-20, named as the rule above asks (F-176 ·
  /// F-418, the brush lanes). `BrushSettings.toJson` crossed the line with
  /// a brush's further tips, their order and its correction — a key a line
  /// and, beside the three, why each is written only off its default.
  /// 🔬`clean_code_diff` against the lanes' base (`243dd8074`, at 411)
  /// named that one added and nothing gone. ⛔Not split to fit: it is one
  /// flat list of what a preset keeps, and a list cut in two is read as
  /// one anyway.
  ///
  /// ⚠️412 → 416 on 2026-10-20, four named as the rule above asks
  /// (F-418-Q10, 유저 「모든 그룹 머리가 접힌다」). The brush's settings fold
  /// by Clip Studio's categories, so the panel's one list of rows — its
  /// `build`, 465 lines — is a list a category now, which the category's
  /// header shows or folds away: `_tipRows` (86), `_textureRows` (124) and
  /// `_correctionRows` (77) stand over the line, and `build` (66), a group
  /// a category, still does. The text tool's `TextToolSettings.build` (63)
  /// crossed it taking its folds from the tool's store around the section.
  /// 🔬`clean_code_diff` against the lane's base (`d890f68b0`, at 412)
  /// named those four added and nothing gone. ⛔Not split to fit: a
  /// category's rows are what its header folds, and a list cut in two
  /// would fold as one anyway.
  ///
  /// ⚠️416 → 413 on 2026-10-21, lowered as the rule asks (F-398 ⑤): the
  /// 겸용 conversion's `execute` is its steps now — the pairs, the rows one
  /// side holds and the write — and master stood at 414, two under the
  /// ceiling. 🔬The lane's scan against master (`5cd21708d`, at 414) named
  /// `execute` gone and nothing added.
  ///
  /// ⚠️413 → 412 on 2026-10-22, lowered as the rule asks (I-117, a cel's
  /// PSD): `ExportFrameRenderer.renderCelGroup` fell under the line when
  /// the walk that finds a cel's rows became its own (`_celGroupOf`) — the
  /// one the cel's picture and its PSD's rows are both laid from.
  /// 🔬`clean_code_diff` against master (`66c6c2063`, at 413) named that one
  /// gone and nothing added.
  ///
  /// ⚠️412 → 414 on 2026-10-22, three named as the rule above asks (card
  /// a-blurred-folder-cut-by-the-view-moves-on-vulkan — a row in an
  /// advanced blend is composed over its backdrop in the shader, a node
  /// kind every walk of the tree answers for). `composeOverTheirBackdrops`
  /// (70) is the law that gathers it: a list is a scope, a group's and an
  /// adjustment's lists are scopes of their own, and a row in such a blend
  /// takes what stands before it in its list. `mapCompositeLeaves` (66) and
  /// `_EditorCanvasAreaState._stackNodesWithGhosts` (90) crossed the line
  /// taking that node's case — the fold leaves what lay below a row that
  /// mapped to nothing where it was, the onion ghosts go under the active
  /// row where it is the blend's source. 🔬`clean_code_diff` against master
  /// (`44668f9da`, at 411 — one under the ceiling) named those three added
  /// and nothing gone. ⛔Not split to fit: each is one switch over the node
  /// kinds, and a case taken out would be read beside the rest anyway.
  ///
  /// ⚠️414 → 415 on 2026-10-23, named as the rule above asks (card
  /// nested-folder-buffers-read-past-the-view). The editing stack's
  /// `LayerStackPaintPass._paintNodesWith` (65) crossed the line handing
  /// what reads the nodes to each buffered kind's case — a group, an
  /// adjustment, a row composed over its backdrop — whose calls no longer
  /// fit a line. 🔬`clean_code_diff` against master (`f8e059c22`, at 414)
  /// named that one added and nothing gone. ⛔Not split to fit: it is the
  /// walk's one switch over the node kinds, the shape the camera's walk
  /// keeps too.
  ///
  /// ⚠️412 → 415 on 2026-10-25 under the same ceiling, three named as the
  /// rule above asks (I-92 — a row clipped to the layer below).
  /// `clippedOnto` is the clip law's join: which rows read the base's whole
  /// colour, then a group joined or begun — two switches over the node
  /// kinds. `LayerStackPaintPass._paintNodesWith` crossed again with the
  /// clip's and the opaque base's cases. `LazyCanvasRasterRgb`'s
  /// constructor reads a clipped row cut by its base's layers.
  /// 🔬`clean_code_diff` against master (`3354f5258`, at 412) named those
  /// three added and nothing gone. ⛔Not split to fit: each is one walk or
  /// one switch over the node kinds, as the notes above say of their kin.
  ///
  /// ⚠️One in and one out on 2026-10-27 under the same ceiling (F-475 —
  /// the button a press lands on says which column it sweeps).
  /// `_StoryboardRailSweep._hooks` (66) crossed the line handing the conte
  /// rail's sweep the two folds the timeline's sweeps — a group's at the
  /// end of a name and a lane group's twirl — and `railSwipeColumns` went
  /// under it with the bands it no longer works out. 🔬`clean_code_diff`
  /// against the lane's base (`e059586e1`) named those two and no other.
  /// ⛔Not split to fit: it is one record of what this rail reads and
  /// presses, field for field the grids' (`timelineRailSwipeHooks`).
  ///
  /// ⚠️409 → 411 on 2026-10-28 under the same ceiling (F-489 — the mark an
  /// unnamed block wears is a pick): `TimelineRowCellsPainter
  /// ._resolveCellModelAt` (63) hands the pick to the head's two writers —
  /// a ghost's and every other cell's — and `_RowCellsPicture.build` (61)
  /// hands the row the pick its grid law heard. 🔬`clean_code_diff`
  /// against the lane's base (`f2d4f1e21`) named those two and no other
  /// (the Display section's grows none: its two grid rows read the one
  /// setting under one listener). ⛔Not split to fit: each is the one
  /// table of what a cell writes, and of what a row is drawn by.
  ///
  /// ⚠️415 → 414 on 2026-10-28, following one down (I-132-Q12 b):
  /// `_effectBox` went under the line as a point's cross came beside a cel
  /// number's box — the wide signatures' note names the two halves.
  ///
  /// ⚠️414 → 413 on 2026-10-28, following one down (I-131): the brush
  /// rail's `_buildRailFresh` went with its reorderable list into
  /// `StandOnReorderList`, which the palette panel stands on too.
  ///
  /// ⚠️413 → 416 on 2026-10-29, four named and one gone, as the rule above
  /// asks (I-132 ⑫b·⑫c — a lens blur's blur map names a row of its cut).
  /// `withTheRowsTheyRead` (70) is new: how each kind of node is laid anew
  /// with the rows its chain reads beside it, as the fold
  /// (`mapCompositeLeaves`) lays each kind with its leaves mapped.
  /// `CutCommandCoordinator.layerEffectsCommands` (70) crossed carrying a
  /// chain to another cut with the rows it names renamed to that cut's.
  /// `_nodeSignaturesOf` (62) crossed with the case of a node that reads
  /// rows, and `LinkDuplicateLayerCommand._laid` (62) with a copy's
  /// effects naming the copies of the rows they named.
  /// `_LayerStackPainter._whereTheRowShows` went under as each node it
  /// stands in came to be asked of by `_whereItShowsIn`. 🔬`clean_code_diff`
  /// against master (`2a9750ac3`, at 413) named those four added and that
  /// one gone. ⛔Not split to fit: each is one table — of a node's kinds,
  /// of what every row a chain's write reaches takes, of a member's copy
  /// field for field.
  ///
  /// ⚠️416 → 417 on 2026-10-30, two named as the rule above asks (card
  /// an-imported-pencil-drops-its-second-brush — a brush's second tip lays
  /// a stroke of its own, with a spacing, a turn, a roundness and a scatter
  /// of its own, eight fields). `BrushSettings.copyWith` (64) and
  /// `BrushToolState.clamped` (68) crossed carrying them. The reference
  /// pile that grew a second plane was split instead (`_Pile`: the first
  /// plane, the second, the view), and the .sut reader of a tip's way
  /// handed its spin columns to `_spinOf`. 🔬`clean_code_diff` against
  /// master (`ce21fca6d`, at 415) named those two added and nothing gone.
  /// ⛔Not split to fit: each is one table — of a brush's fields, copied
  /// or held to their ranges field for field.
  const longBodies = 417;
  /// ⚠️52 → 53 on 2026-09-09, and the offender is named because the rule
  /// above says a session that pushes one up reads what it added.
  ///
  /// `ActiveStrokeOverlayModel` sat at 598 lines — one under the line — and
  /// gained a THIRD landing for a tile decode (`_refuseDecodedTile`) plus
  /// the decisions behind it, from the round that gave a refused upload
  /// somewhere to land. ⛔Most of the growth is DOCUMENTATION: the scan
  /// measures a class from its own doc comment, and the largest single
  /// addition is the paragraph explaining why `_decoding.clear()`
  /// deliberately does not touch `_pendingDecodeCount` — correct since it
  /// was written, recorded nowhere, and re-derived from scratch by that
  /// round precisely because nobody had. Cutting it back to buy a number is
  /// the trade this repo does not make (「결정 주석은 절대 지우지 않는다」),
  /// and shrinking the class to fit is a different round on the app's
  /// hottest file.
  ///
  /// ⚠️53 → 52 on 2026-09-10: `EdgeDrag` (1,350 lines) left the list when
  /// its two gestures became objects in `session/drags/`, and neither
  /// replacement joined it — the biggest, `ExposureEdgeDrag`, is 508. The
  /// rule above cuts both ways, so the ceiling follows it down.
  ///
  /// ⚠️52 → 53 on 2026-09-15, the offender named: `ProjectFileDoor` sat at
  /// 583 lines and F-128 took it to 602. The round made 「unsaved」 a
  /// comparison of edit counts, and the door is where a save COUNTS — at the
  /// settle, before it reads the project — so the capture, the staged
  /// archive's count and the adoption that hands it back are door code. Most
  /// of the nineteen lines are the decisions beside them: why the count is
  /// taken at the settle and nowhere else, and the gravestone on the sentence
  /// that claimed the dirty mark kept the work while the save was clearing
  /// it. Cutting those to buy a number is the trade this repo does not make,
  /// and shrinking the door is a round of its own.
  ///
  /// ⚠️53 → 56 on 2026-09-16, three named, one per lane, the same lines in
  /// each so the first to land carries the others' count. F-115:
  /// `FrameClipboard` crossed the line taking copy, cut and paste of SE
  /// blocks onto the row's own axis, which from the second cut on had read
  /// a cut-local index. F-81: `Standing` crossed it becoming the ONE body a
  /// fold hands the current row off through (`handOffOnFold`) — the lane
  /// folds, the folder fold and the attach group's fold had three.
  /// F-90: `_TimesheetTabHostState` stood at the line and crossed it
  /// printing the cut under the playhead — its document, its playhead row
  /// and its ink — rather than only the open cut. Shrinking any of the
  /// three to fit is a round of its own.
  ///
  /// ⚠️56 → 57 on 2026-09-16 — the paragraph above had its ARITHMETIC wrong,
  /// and this adds no fourth name. Measured when F-81 came back through the
  /// gate after the 3.47 upgrade: master already stood at 56 with two of the
  /// three landed (`FrameClipboard` and `TimesheetTabHostState` are both in
  /// the scan), and `Standing` had not landed. So the base that count started
  /// from was 54, not 53, and the three named crossings need 57 between them.
  /// ⛔Nothing was shrunk to fit and nothing new was allowed through: the
  /// third name is the one already written above.
  ///
  /// ⚠️57 → 58 on 2026-09-17 (F-110), ONE name: `StoryboardPanel` crossed
  /// taking `playbackFrame` — the listenable that says whether playback is
  /// running, which is what gates the strip turning its page. That class is
  /// a constructor and its parameter docs and almost nothing else, so it
  /// crosses on a field and a comment.
  /// 🔬Measured, not assumed: `clean_code_diff.dart` between master and the
  /// lane names exactly one addition, and the eight other files this round
  /// touches add none.
  /// ⛔Shrinking it is a round of its own, and a real one: the timeline
  /// already hands its two grids ONE bundle (`TimelineGridHooks`) for this
  /// exact reason and the storyboard has no such thing — every one of its
  /// parameters is spelled at the call site. Bundling them is a change to
  /// every caller, not to this round.
  ///
  /// ⚠️58 → 59 on 2026-09-24, ONE name: `FlipHudPainter` sat at 596 and the
  /// block-frame-lines switch (유저 2026-09-24) took it to 610 — the field and
  /// its decision, and the strip's grid drawn under the bodies or over them
  /// by it. 🔬`clean_code_diff.dart` between HEAD and the lane names it and
  /// no other class this round touches. ⛔Splitting the flip window's
  /// painter to get back under is a round of its own, not this one's.
  ///
  /// ⚠️59 → 60 on 2026-09-25, ONE name: `MediaPool` crossed (560 → 605)
  /// in the carry round (`recarry-after-remove-reads-the-old`). It took in
  /// the question the placement doors and the cut folder had each spelled
  /// — which arriving carried files need their bytes held
  /// (`holdCarriedBytes`), so `ProjectImportDoors` shrank as it grew — and
  /// the decisions on why `_admit` waits only when something is to be held
  /// and why a relink keeps the carry's token. 🔬`clean_code_diff` between
  /// master and the lane names this one and no other. ⛔Not split to fit:
  /// the pool's verbs are one conversation (its header says why), and the
  /// question joined it.
  ///
  /// ⚠️60 → 59 on 2026-09-25: the one long class the brush lab owns left
  /// the count. The scan's `lib/dev/` exclusion never matched this test's
  /// relative `'lib'` — the diff tool, handed an absolute root, read one
  /// class fewer on both trees — and `appDartFiles` answers for both now
  /// (ratchet-dev-exclusion-relative-root).
  ///
  /// ⚠️59 → 60 on 2026-10-07, ONE name: `CutFrameCompositeCache` crossed
  /// (589 → 605) in F-289-Q21 — an export run borrows playback's line of the
  /// memory allowance, and may hold no more than the caches will give back.
  /// What the composites will not give back is what `enforceBudget` never
  /// evicts, so its predicate came out of that method into one place
  /// (`_isProtected`) that the eviction and the new count
  /// (`protectedBytes`) both read — a second spelling of 「protected」 is the
  /// thing the round would not write. 🔬`clean_code_diff` between master
  /// and the lane names this one and no other class. ⛔Not split to fit:
  /// the cache's eviction and what it holds back are one question.
  ///
  /// ⚠️60 → 61 on 2026-10-08, ONE name: `CutVerbs` crossed (590 → 603) in
  /// I-79 D2b — a canvas resized on the canvas lands through
  /// `placeActiveCutCanvas`, the active cut's canvas at a size with the
  /// picture moved by an offset, beside `resizeActiveCutCanvas` that the
  /// size window's anchors take. Both land through the coordinator's one
  /// `placeCutCanvas`. 🔬`clean_code_diff` between master and the lane
  /// names this one and no other class. ⛔Not split to fit: the active
  /// cut's verbs are one conversation (its header says why), and folding
  /// the anchor verb into the offset one would move the anchor's sum into
  /// every caller that resizes about the middle.
  ///
  /// ⚠️61 → 60 on 2026-10-08, following one down (I-73, the conte row):
  /// `_StoryboardTrackRow` left the count. Everything a conte PANEL answers
  /// to — its press, its sweep, its edges, the button that makes a conte
  /// layer — went to a row of its own (`_StoryboardConteRow`), and the cut
  /// row kept what is the cut's. 🔬`clean_code_diff` between master and the
  /// lane names that one gone and none added.
  ///
  /// ⚠️60 → 61 on 2026-10-09, ONE name: `Transitions` crossed (591 → 607)
  /// in I-73-ol-index-space — the cut view's marks are laid on the cut's
  /// OWN frames, which begin its head のりしろ before its place on the
  /// track, so the projection walk takes that lead beside the place, and
  /// the sheet's projection says its own (none) out loud.
  /// 🔬`clean_code_diff` between master and the lane names this one and no
  /// other class. ⛔Not split to fit: it is one more number through the
  /// walk the class already owns, and a seam cut for it would put the
  /// projection's origin in a different file from the walk that reads it.
  ///
  /// ⚠️61 → 60 on 2026-10-10: `CutFrameCompositeCache` left the count — the
  /// whole film plays on the canvas's own pictures, and the composite cache
  /// went (playback-plays-the-screen-material). 🔬`clean_code_diff` between
  /// the lane's base and the lane names that one gone and none added.
  ///
  /// ⚠️60 → 61 on 2026-10-12, ONE name: `LayerFrameImageCache` crossed
  /// (576 → 617) in F-313 — a cel's pictures travel with its pixels when a
  /// move re-keys them, so the frame a carried cel lands on draws it
  /// (🔬0 of 32 columns there before). The move is the cache's own map, and
  /// the settle that finds an entry where a rekey carried it is the cache's
  /// own settle. 🔬`clean_code_diff` between the lane's base (`3ef2f8da7`)
  /// and the lane names this one and no other class. ⛔Not split to fit: a
  /// seam cut for it would put the re-homing of the entries in a different
  /// file from the map that holds them.
  ///
  /// ⚠️61 → 62 on 2026-10-14, ONE name: `TimelineLayerControlsHeader`
  /// crossed (582 → 626) in I-57 — the legend keeps itself (`KeptPiece`),
  /// so a notify that changed nothing builds none of its ~15 tooltip and
  /// flyout cells again on any grid, and what it grew by is its `facts`:
  /// every field it shows, and the mutants three of them outlive.
  /// 🔬`clean_code_diff` between the lane's base (`501bf027c`) and the lane
  /// names this one and no other class. ⛔Not split to fit: the facts stand
  /// in the class that declares the fields they name — the scan holding
  /// every kept piece to naming its fields reads them there
  /// (`a_kept_piece_names_every_field_in_its_facts_test`).
  ///
  /// ⚠️62 → 63 on 2026-10-14, ONE name: `_BrushEditStroke` crossed
  /// (600 → 604) in I-61's finger half — the stroke asks whether Shift is
  /// held in ONE place, where it advances, and a finger resting on the
  /// glass is the second answer there beside the keyboard (I-61-Q3), with
  /// the comment saying whose answer it is. The keyboard half had left the
  /// class at exactly 600 (`e916f1cef`). 🔬`clean_code_diff` between master
  /// (`279933153`) and the lane names this one and no other class. ⛔Not
  /// split to fit: both answers belong where the one question is asked, and
  /// the comment that keeps it in one place stands beside them.
  ///
  /// ⚠️63 → 62 on 2026-10-15, following one down: `LayerFrameImageCache`
  /// left the count — the asynchronous road's chain went out of the class
  /// beside its synchronous twin as a plain function (`_composed`, counted
  /// among the long bodies above). 🔬`clean_code_diff` against master
  /// (`01986af08`) named that one gone and none added.
  ///
  /// ⚠️62 → 63 on 2026-10-15, ONE name: `_ConteTabHostState` crossed
  /// (569 → 624) in I-97 — a pool picture dropped on the pages on screen is
  /// a photo in the band a stroke started there writes in, so the drop asks
  /// the windows the ink layer draws (the same bands, picture slots and
  /// refusals) and makes the block or the next cut the stroke would; the
  /// growth is the drop's mount and the helpers the ink layer now shares
  /// with it. 🔬`clean_code_diff` against `f99fdc4ff` names this one and no
  /// other class. ⛔Not split to fit: the windows are the host's state, read
  /// where the ink layer reads them.
  ///
  /// ⚠️63 → 64 on 2026-10-17, ONE name: `LayerVerbs` crossed (588 → 601)
  /// in F-369 — a cut's conte row is born at the bottom of ACTION from
  /// every door, so the verb that puts a new row in the stack takes WHERE
  /// from its caller (`addRow`): above the active row is one answer
  /// (`placementAboveActive`), the conte row's birthplace the other.
  /// 🔬`clean_code_diff` against master (`34c6233f6`) names this one and
  /// no other class. ⛔Not split to fit: a row is inserted in one place,
  /// and a door that inserted its own would be the second.
  ///
  /// ⚠️64 → 65 on 2026-10-17, ONE name: `LayerFrameImageCache` crossed
  /// again (588 → 642) in playback-picture-weight-estimates — the warmer
  /// asks for room by what a picture will be made as: the plan `prepare`
  /// makes its image by (`plannedBytes`, read off the same `_levelPlan`),
  /// once what `prepare` reads first is read (`readIn`), and both roads that
  /// make an image hold it to that plan (`_isAsPlanned`). 🔬`clean_code_diff`
  /// between master (`76fbb39e8`) and the lane names this one and no other
  /// class. ⛔Not split to fit: the weight is the plan the image is made by,
  /// and it stands beside the making so the two cannot part.
  ///
  /// ⚠️65 → 66 on 2026-10-16, ONE name: `PixelVerbs` crossed (581 → 613)
  /// in vanishing-point-types-Q5 — 래스터라이즈 lays a guide's lines on the
  /// cels the paste's ladder names (유저 2026-10-16: 「지금 레이어의 지금
  /// 셀에」), through the door the paste lands through: the paste's landing
  /// moved into `_land`, which both call now, and the new verb is the
  /// crossing a canvas picture makes onto a posed row. 🔬`clean_code_diff`
  /// against master (`ebefaea8b`, before the two above landed) names this
  /// one and no other class. ⛔Not split to fit: a picture that lands as a
  /// paste lands stands beside the paste, where
  /// `a_piece_lands_through_one_door_test` reads them both.
  ///
  /// ⚠️66 → 67 on 2026-10-17, ONE name: CLIP STUDIO's `_Planner` crossed
  /// (597 → 618) in the-clip-import-drops-layer-effects-silently — what
  /// CLIP STUDIO draws over a layer that comes in without it (an effect of
  /// its properties, its layer colour, its clipping) is said in every
  /// decoder's words (유저 10-07 「없는 기능은 알리는거 ok」), by the name
  /// the reader sees: the three places the planner makes one — a folder's
  /// row, a folder inside a cel, a layer that comes in — call one
  /// `_sayNotApplied`. 🔬`clean_code_diff` against master (`42ceeb00d`)
  /// names this one and no other class. ⛔Not split to fit: the name a
  /// warning is said by is made where the row is, and the planner makes it.
  ///
  /// ⚠️67 → 68 on 2026-10-17, ONE name: CLIP STUDIO's `_DocumentReader`
  /// crossed (585 → 609) in the-masks-are-baked-and-locks-said — a layer's
  /// mask comes in baked as Photoshop's does, and a lock is said (유저 10-09
  /// 「다른 디코드 마찬가지 통일해서」): the reader asks the row for the
  /// mask's columns and its lock with the others, and reads where the mask
  /// stands (`_maskOf`: the layer's offset, the mask's own, the offscreen's).
  /// 🔬`clean_code_diff` against master (`4c997b9cc`) names this one and no
  /// other class. ⛔Not split to fit: a column is asked for in the one list
  /// the row is read by, and read off that row beside the others.
  ///
  /// ⚠️68 → 69 on 2026-10-18, ONE name: `CelTextTool` crossed (590 → 618)
  /// in text-letters-lean-and-underline ④⑤ — a text's paragraphs are set
  /// each their own way, and the alignment and the line pitch in the tool's
  /// settings are made on the paragraphs of the letters a letter setting
  /// speaks for: `changeParagraphs` beside `changeLetters`,
  /// `paragraphsSpokenFor` beside `letterStylesSpokenFor`, both through the
  /// one range (`_lettersSpokenFor`). 🔬`clean_code_diff` against master
  /// (`17f66740b`) names this one and no other class. ⛔Not split to fit:
  /// what a paragraph setting speaks for is what a letter setting does, and
  /// the two are read in one place.
  ///
  /// It grew again in F-377, no new name: a text held by its BOX writes
  /// what it lands (a carry, a turn, a corner, a setting come to rest) as
  /// a run of history (`HistoryRun`): undo takes the last one back while
  /// the box holds it (`canStepBack` · `stepBack`), and they are ONE step
  /// once the box lets go — the transform tool's law said of a text (유저
  /// 10-17 「텍스트 변형이든 뭐든」). ⛔Not split to fit: whose step a
  /// landing is (`_StepOf`) is decided where the tool lands the text it
  /// holds, and the run is the holding's own.
  ///
  /// ⚠️69 → 70 on 2026-10-20, ONE name: the brush's settings panel state
  /// crossed (543 → 609) when its groups came to fold (F-418-Q10, 유저
  /// 「모든 그룹 머리가 접힌다」) — each of Clip Studio's six categories a
  /// list of its own, called by its header, and the brush's own folds
  /// read and written (`_foldOf`). 🔬`clean_code_diff` against the lane's
  /// base (`d890f68b0`) names this one and no other class. ⛔Not split to
  /// fit: the rows are the panel's, written from the one state it shows,
  /// and the categories are read in the one place the panel lists them.
  ///
  /// ⚠️70 → 71 on 2026-10-21 (65 → 66 on 2026-10-17, where the lane was
  /// cut), ONE name:
  /// `MediaRun` crossed (588 → 632) in playback-waits-for-its-sound — the
  /// media viewer's run waits for its sound by the canvas's law (유저
  /// 2026-10-16: 「소리가 준비될 때까지 기다린다」): a press stands where it
  /// was put while the sound is on its way (`_start`), each look asks for it
  /// again, and the run goes on from there once it has come
  /// (`_soundHasCome`). 🔬`clean_code_diff` against master (`4c0fed1e3`)
  /// names this one and no other class; stood on the brush panel's 70 above
  /// when the lane was rebased onto it (10-21). ⛔Not split to fit: going on
  /// restarts the run's own film clock, its clock's lateness and its parked
  /// state — what the class is — so a collaborator for the wait would be
  /// handed all three. (The canvas's transport, which only hears the sound
  /// land, gave that hearing to one: `_SoundOnItsWay`.)
  ///
  /// ⚠️71 found on 2026-10-22 under the same ceiling, ONE name: `CutVerbs`
  /// crossed (579 → 611) when a canvas resize came to work out the cut's
  /// kept cels ahead, behind its wait window (card
  /// `a-canvas-resize-rewrites-kept-cels-on-the-ui-thread` — S5_BA saved and
  /// opened again took 4.2 s on the UI thread): each canvas verb gained the
  /// half its window runs first (`resizeActiveCutCanvasAhead` ·
  /// `placeActiveCutCanvasAhead`). 🔬`clean_code_diff` against the lane's
  /// base (`fdbdd1a3d`) names this one and no other class. ⛔Not split to
  /// fit: the half ahead asks its step's own question of the cut the step
  /// reads in one place (`ActiveCutEdits`), so the two are read side by side.
  ///
  /// ⚠️71 → 72 on 2026-10-24, ONE name: `QaAudioDevice` crossed (584 → 601)
  /// when a recording cue's end silenced a viewer's sound it did not make
  /// (card `a-cue-ending-silences-a-viewer-sound-it-did-not-make`): `play`
  /// now hands back the run it starts, and every player's end silences its
  /// own run alone (`stopRun`, bound beside `stop`). 🔬`clean_code_diff`
  /// against the lane's base (`d719704c1`) names this one and no other
  /// class. ⛔Not split to fit: the class is the engine's audio surface, one
  /// binding a native call, and the run's end is one more native call.
  ///
  /// ⚠️72 → 73 on 2026-10-24, ONE name: `_StoryboardSeRow` crossed
  /// (590 → 624) when it came to build the pieces of its window's sounds
  /// alone (card `frame-panels-build-in-one-frame` — the row spans the whole
  /// film and built every sound's paper, waveform, words, grips and drop
  /// places, about a fifth of reopening the storyboard on the AMMI OP): the
  /// window is read where the row builds, and each kind of piece is held to
  /// it. 🔬`clean_code_diff` against master (`f6c483e4d`) names this one and
  /// no other class. ⛔Not split to fit: the window is the row's own panel
  /// window, and every piece of the row is held to it in the one build.
  ///
  /// ⚠️73 → 74 on 2026-10-24, ONE name: `_StoryboardConteRow` crossed
  /// (599 → 605) when its cells came to bake on the timeline's tile store
  /// (card `the-conte-row-bakes-its-cells-into-tiles` — it painted every
  /// cell it showed by hand at every opening, the storyboard's largest
  /// paint): the four arguments the timeline's rows already hand the same
  /// painter. 🔬`clean_code_diff` against master (`b0a486341`) names this
  /// one and no other class. ⛔Not split to fit: the row's painter is built
  /// in the one place its other arguments are.
  ///
  /// ⚠️74 → 75 on 2026-10-25, ONE name: `FramePictureStore` crossed
  /// (588 → 627) when a frame's one picture came to be every screen's (card
  /// one-picture-per-frame ②-2 · ②-4): a frame's picture is weighed by the
  /// bytes the store holds for it (`holds` · `bytesOf`), and a stroke that
  /// lands moves the picture it was patched into to the frame's next key
  /// (`move` · `landingOf`), in line behind the patches still landing.
  /// 🔬`clean_code_diff` against the lane's base (`3cee149eb`) names this
  /// one and no other class. ⛔Not split to fit: a move is the store's own
  /// hold on a picture's texture, renamed in the one line its patches land
  /// in, under the one count of who pins it.
  ///
  /// ⚠️One crossed on 2026-10-27 under the same ceiling: `TimelineGridHooks`
  /// (600 → 611) when the column sweep came to read a row's two folds live
  /// (F-475 — a group's fold at the end of a name and a lane group's twirl
  /// are swept as the eye is): `groupFoldOpenOf` · `laneGroupOpenOf`, beside
  /// the live read of every other column. 🔬`clean_code_diff` against the
  /// lane's base (`e059586e1`) names this one and no other class. ⛔Not split
  /// to fit: it is the one bundle both grids take (`one_grid_hooks_test`),
  /// and a read their sweep needs is one more of its answers.
  ///
  /// ⚠️75 → 76 on 2026-10-27, ONE name: `BrushShape` crossed (587 → 609)
  /// when mixing came to open onto two methods (I-75 — 유저 Q1 「섞기
  /// 그룹에 「흐리기」」): the method beside the gate (`mixingMethod`), and
  /// the two questions every reader asks of the pair (`picksUpGround` ·
  /// `blurs`). 🔬`clean_code_diff` against the lane's base (`635015833`)
  /// names this one and no other class. ⛔Not split to fit: a brush's
  /// settings are one value, and the method is one more field of it.
  ///
  /// ⚠️76 → 77 on 2026-10-28, ONE name: `FramePictures` crossed (600 → 606)
  /// when a frame's three questions — there, given up on, its red — came to
  /// be read off one walk of its stack (`standingOf`, card frame-panels-
  /// build-in-one-frame: the storyboard's bar walked every span of the film
  /// two or three times whenever the panel was shown again). It stood AT
  /// 600, and the ladder the three read is one helper now (`_stateAt`)
  /// where `partsToMake` and `gaveUpAt` each wrote it. 🔬`clean_code_diff`
  /// against the lane's base (`84a5c6197`) names this one and no other
  /// class. ⛔Not split to fit: it is the one keeper of a frame's picture
  /// and the key it is kept under.
  ///
  /// ⚠️77 → 78 on 2026-10-28, ONE name: `_FramePictureViewState` crossed
  /// (600 → 601) when a stroke's step came to keep the cells of what lies
  /// below its pen (card a-scrub-prepares-every-frame-it-crosses): once a
  /// step is patched in, the frames' pictures give way to what it kept
  /// (`FramePictures.giveWayToSteps`). 🔬`clean_code_diff` against the
  /// lane's base (`95cd93423`) names this one and no other class. ⛔Not
  /// split to fit: the step is patched in here, and so is told here.
  ///
  /// ⚠️78 → 79 on 2026-10-29, ONE name: `_CompositeTreeWalk` crossed
  /// (552 → 623) when a node whose chain reads rows came to be walked
  /// (I-132 ⑫c, 🗣️Q21 a — a lens blur's blur map read where its row
  /// shows): the rows painted afresh into the step that reads them
  /// (`_painterOf`), the reader handed them (`_reading`), and the pen's
  /// cells kept through it. 🔬`clean_code_diff` against master
  /// (`2a9750ac3`) names this one and no other class. ⛔Not split to fit:
  /// the walk is one recursion over the tree, and a node that reads rows is
  /// one more kind of node in it.
  const longClasses = 79;

  late CleanCodeScan scan;
  setUpAll(() {
    scan = scanCleanCode('lib');
  });

  test('the premise: it read the real tree', () {
    expect(scan.functions, greaterThan(9000));
  });

  test('the premise: the brush lab is not the app, from any root', () {
    expect(
      Directory('lib/dev').existsSync(),
      isTrue,
      reason: 'LIVENESS — there is a lab to leave out',
    );
    final relative = appDartFiles('lib');
    expect(
      relative.where((path) => path.contains('lib/dev/')),
      isEmpty,
      reason: 'the ratchets hand the scans a relative root',
    );
    expect(
      relative.length,
      appDartFiles(Directory('lib').absolute.path).length,
      reason: 'a relative root and an absolute one read the same tree',
    );
  });

  void ratchet(String what, List<CleanCodeFinding> found, int ceiling) {
    expect(
      found.length,
      lessThanOrEqualTo(ceiling),
      reason:
          '$what grew past the round\'s count — the worst of them:\n'
          '${found.take(12).join('\n')}',
    );
    expect(
      ceiling - found.length,
      lessThan(25),
      reason:
          'the $what ceiling is slack — lower it to ${found.length} so the '
          'ratchet keeps its bite',
    );
  }

  test('signatures of five or more parameters do not multiply', () {
    ratchet('wide signatures', scan.wideSignatures, wideSignatures);
  });

  test('bodies over sixty lines do not multiply', () {
    ratchet('long bodies', scan.longBodies, longBodies);
  });

  test('classes over six hundred lines do not multiply', () {
    ratchet('long classes', scan.longClasses, longClasses);
  });
}
