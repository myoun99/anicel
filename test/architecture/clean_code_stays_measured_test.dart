import 'package:flutter_test/flutter_test.dart';

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
  const wideSignatures = 388;
  const longBodies = 437;
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
  const longClasses = 58;

  late CleanCodeScan scan;
  setUpAll(() {
    scan = scanCleanCode('lib');
  });

  test('the premise: it read the real tree', () {
    expect(scan.functions, greaterThan(9000));
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
