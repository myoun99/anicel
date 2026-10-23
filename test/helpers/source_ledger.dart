/// 🔎board `ledger-ratchets-count-by-hand` (2026-10-23): twenty-two
/// ratchets compared what their scan found with their ledger by hand, three
/// ways for the same verdict — one `expect` of the whole map or set, a list
/// of offenders beside a list of paid-off lines, and a second test that read
/// each ledgered file again. One never saw a ledgered file that was deleted,
/// and one asked its ledger of the raw text while its scan cut the comments
/// off. A ledger is compared here, both ways, for every ratchet.
library;

import 'package:flutter_test/flutter_test.dart';

/// Fails unless every count in [found] is the one [ledger] holds for it.
///
/// A file over its ledger — or found and not ledgered at all — fails with
/// [grew]; a ledgered file under its count, or not found at all, fails with
/// [paidOff]. Each is listed as `path: found N, ledger M`, with its [hits],
/// if given, under it as `path:hit`.
void expectCountsMatchLedger(
  Map<String, int> found,
  Map<String, int> ledger, {
  required String grew,
  required String paidOff,
  Map<String, Iterable<Object>>? hits,
}) {
  String counted(String path) =>
      '$path: found ${found[path] ?? 0}, ledger ${ledger[path] ?? 0}';
  _expectNone(
    [
      for (final MapEntry(key: path, value: count) in found.entries)
        if (count > (ledger[path] ?? 0)) path,
    ],
    grew,
    counted,
    hits,
  );
  _expectNone(
    [
      for (final MapEntry(key: path, value: count) in ledger.entries)
        if ((found[path] ?? 0) < count) path,
    ],
    paidOff,
    counted,
    hits,
  );
}

/// Fails unless [found] and [ledger] hold the same items.
///
/// An item found and not ledgered fails with [unledgered]; one ledgered and
/// not found fails with [paidOff]. Each is listed with its [hits], if
/// given, under it as `item:hit`.
void expectSetMatchesLedger<K>(
  Iterable<K> found,
  Iterable<K> ledger, {
  required String unledgered,
  required String paidOff,
  Map<K, Iterable<Object>>? hits,
}) {
  final foundSet = found.toSet();
  final ledgerSet = ledger.toSet();
  String named(K item) => '$item';
  _expectNone(foundSet.difference(ledgerSet), unledgered, named, hits);
  _expectNone(ledgerSet.difference(foundSet), paidOff, named, hits);
}

/// Fails for each entry of [reasons] whose why is 20 characters or fewer — a
/// ledger whose lines say nothing is a list of exceptions.
void expectEveryEntrySaysWhy(Map<Object?, String> reasons) {
  for (final MapEntry(:key, value: why) in reasons.entries) {
    expect(
      why.length,
      greaterThan(20),
      reason: '$key needs a reason, not a slot',
    );
  }
}

/// [line] up to its first `//` — its code, a comment cut off.
String codeOf(String line) {
  final comment = line.indexOf('//');
  return comment < 0 ? line : line.substring(0, comment);
}

/// Every line of [source] cut at its first `//` ([codeOf]), the lines kept,
/// so a line number read off the code is the source's.
String codeOfLines(String source) =>
    source.split('\n').map(codeOf).join('\n');

/// Fails with [reason] and every one of [items] listed, if there are any.
void _expectNone<K>(
  Iterable<K> items,
  String reason,
  String Function(K item) named,
  Map<K, Iterable<Object>>? hits,
) {
  final sorted = items.toList()
    ..sort((a, b) => named(a).compareTo(named(b)));
  final listed = [
    for (final item in sorted) ...[
      named(item),
      for (final hit in hits?[item] ?? const <Object>[]) '    $item:$hit',
    ],
  ];
  expect(listed, isEmpty, reason: '$reason\n  ${listed.join('\n  ')}');
}
