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
void main() {
  const ceiling = 2123;

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
