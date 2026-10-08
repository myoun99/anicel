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
  const wideSignatures = 386;

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
  const longBodies = 410;
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
  const longClasses = 60;

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
