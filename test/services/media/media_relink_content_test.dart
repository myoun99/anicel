import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_identity.dart';
import 'package:anicel/src/services/media/media_relink_matcher.dart';

/// RELINK, the confirmation step: what the FOLDERS could not tell apart,
/// the CONTENT can.
///
/// The narrowing half is tested next door. This file is only about what
/// happens when the tail walk gives up — which on a production drive is the
/// interesting case, because `A1.png` under `C-045` and `A1.png` under
/// `C-045_r2` are exactly as deep and exactly as named.
///
/// ⛔ The rule the older half is built on does not bend here: an unforced
/// choice is still not made. Evidence narrows; it never breaks a tie by
/// picking first.
void main() {
  /// The tail walk cannot separate these — same name, same depth, and no
  /// suffix of the original path picks one.
  const missing = 'D:/old/C-045/A1.png';
  const left = 'E:/new/C-045_take1/A1.png';
  const right = 'E:/new/C-045_take2/A1.png';

  MediaRelinkPlan planWith({
    required Map<String, MediaIdentity> recorded,
    required Map<String, MediaIdentity> onDisk,
    List<String>? reads,
  }) {
    return planMediaRelink(
      missingPaths: const [missing],
      candidatePaths: const [left, right],
      recordedIdentity: (path) => recorded[path],
      candidateIdentity: (candidate, wanted) {
        final found = onDisk[candidate];
        if (found == null ||
            found.lengthBytes != wanted.lengthBytes ||
            wanted.crc32 == null) {
          // The production reader's early exits, reproduced so the tests
          // measure the same cost story the real one has.
          return found == null
              ? null
              : MediaIdentity(lengthBytes: found.lengthBytes);
        }
        reads?.add(candidate);
        return found;
      },
    );
  }

  test('without the confirm step the tie is still refused', () {
    // The behaviour before this existed, and still the behaviour when the
    // caller hands over no way to look.
    final plan = planMediaRelink(
      missingPaths: const [missing],
      candidatePaths: const [left, right],
    );
    expect(plan.matched, isEmpty);
    expect(plan.unmatched, [missing]);
  });

  test('🚨 LENGTH alone breaks the tie, and opens no file', () {
    // The cheap half carrying the common case. Two different drawings that
    // happen to share a name almost never weigh the same, so this is the
    // shape the feature actually meets — and it costs a `stat`.
    final reads = <String>[];
    final plan = planWith(
      recorded: {missing: const MediaIdentity(lengthBytes: 4096)},
      onDisk: {
        left: const MediaIdentity(lengthBytes: 512),
        right: const MediaIdentity(lengthBytes: 4096),
      },
      reads: reads,
    );

    expect(plan.matched, {missing: right});
    expect(
      reads,
      isEmpty,
      reason: 'no recorded CRC, so reading any candidate could only have '
          'produced "unknown" — the read must not happen',
    );
  });

  test('a recorded CRC decides when the lengths also match', () {
    final reads = <String>[];
    final plan = planWith(
      recorded: {
        missing: const MediaIdentity(lengthBytes: 4096, crc32: 0xAAAA),
      },
      onDisk: {
        left: const MediaIdentity(lengthBytes: 4096, crc32: 0xBBBB),
        right: const MediaIdentity(lengthBytes: 4096, crc32: 0xAAAA),
      },
      reads: reads,
    );

    expect(plan.matched, {missing: right});
    expect(
      reads,
      [left, right],
      reason: 'both had to be opened — that is what a recorded CRC buys, '
          'and it is only spent once the cheap half has failed',
    );
  });

  test('⛔ TWO byte-identical candidates are refused, not raced', () {
    // The same cel handed to two cuts is a real thing in a production
    // folder. Either would render correctly; the PATH written down would
    // not be the same path, and choosing it for the user is the one thing
    // this matcher exists to never do.
    final plan = planWith(
      recorded: {
        missing: const MediaIdentity(lengthBytes: 4096, crc32: 0xAAAA),
      },
      onDisk: {
        left: const MediaIdentity(lengthBytes: 4096, crc32: 0xAAAA),
        right: const MediaIdentity(lengthBytes: 4096, crc32: 0xAAAA),
      },
    );

    expect(plan.matched, isEmpty);
    expect(plan.unmatched, [missing]);
  });

  test('⛔ nothing recorded means nothing concluded', () {
    // A project written before fingerprints existed, or a video nobody
    // ever read. The answer has to be the old one — report, do not guess.
    final plan = planWith(
      recorded: const {},
      onDisk: {
        left: const MediaIdentity(lengthBytes: 4096),
        right: const MediaIdentity(lengthBytes: 4096),
      },
    );

    expect(plan.matched, isEmpty);
    expect(plan.unmatched, [missing]);
  });

  test('⛔ same length on both candidates and no CRC stays ambiguous', () {
    final plan = planWith(
      recorded: {missing: const MediaIdentity(lengthBytes: 4096)},
      onDisk: {
        left: const MediaIdentity(lengthBytes: 4096),
        right: const MediaIdentity(lengthBytes: 4096),
      },
    );

    expect(plan.matched, isEmpty);
    expect(plan.unmatched, [missing]);
  });

  test('a candidate that cannot be read is not ruled OUT', () {
    // Unreadable is not "different". A permission error on one file must
    // not hand the other one a walkover.
    final plan = planMediaRelink(
      missingPaths: const [missing],
      candidatePaths: const [left, right],
      recordedIdentity: (_) =>
          const MediaIdentity(lengthBytes: 4096, crc32: 0xAAAA),
      candidateIdentity: (candidate, wanted) => candidate == right
          ? const MediaIdentity(lengthBytes: 4096, crc32: 0xAAAA)
          // Same length, no hash: "could be, cannot tell".
          : const MediaIdentity(lengthBytes: 4096),
    );

    expect(
      plan.matched,
      {missing: right},
      reason: 'one is PROVEN and the other only possible — proof wins',
    );
  });

  test('the tail walk still gets first say', () {
    // Content is the fallback, not the rule. Where the folders DO force an
    // answer, no identity is consulted at all — otherwise a stale recorded
    // fingerprint could overturn a decision the paths already made.
    var asked = false;
    final plan = planMediaRelink(
      missingPaths: const ['D:/old/C-045/A1.png'],
      candidatePaths: const ['E:/new/C-045/A1.png', 'E:/new/C-099/B2.png'],
      recordedIdentity: (path) {
        asked = true;
        return const MediaIdentity(lengthBytes: 1);
      },
      candidateIdentity: (_, _) => const MediaIdentity(lengthBytes: 1),
    );

    expect(plan.matched, {'D:/old/C-045/A1.png': 'E:/new/C-045/A1.png'});
    expect(asked, isFalse, reason: 'the name was already unique');
  });
}
