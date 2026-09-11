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
  const wideSignatures = 380;
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
  const longClasses = 52;

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
