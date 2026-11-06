import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/pinned_fingerprints.dart';

/// 🚨THE FINGERPRINT LEDGER HAS ONE FORM (gpu-engine-skeleton, 2026-11-05).
///
/// Lanes on two machines add rows to `test/fixtures/fingerprints.json`. One
/// row a line, sorted by id, is what lets two of them land without a
/// conflict — each row goes where its id puts it, not at the end both would
/// write to — and a lookup by id needs every id once.
void main() {
  final ledger = readFingerprintLedger();
  final rows = parseFingerprintLedger(ledger);

  test('a row a line, sorted by id, in the one spelling', () {
    String line(PinnedRow row) => jsonEncode({
      'id': row.id,
      'fixture': row.fixture,
      'what': row.what,
      'hash': row.hash,
      'pinned_on': row.pinnedOn,
    });
    final sorted = [...rows]..sort((a, b) => a.id.compareTo(b.id));
    expect(ledger, '{"rows":[\n${sorted.map(line).join(',\n')}\n]}\n');
  });

  test('no two rows share an id', () {
    final ids = [for (final row in rows) row.id];
    expect(ids.toSet().length, ids.length, reason: '$ids');
  });

  test('every id is <area>/<what>', () {
    final shape = RegExp(r'^[^/\s]+/[^/\s]+$');
    expect([
      for (final row in rows)
        if (!shape.hasMatch(row.id)) row.id,
    ], isEmpty);
  });

  test('every hash is a CRC-32 in eight lowercase hex digits', () {
    final shape = RegExp(r'^[0-9a-f]{8}$');
    expect([
      for (final row in rows)
        if (!shape.hasMatch(row.hash)) row.id,
    ], isEmpty);
  });

  test('every row says what it is and what pinned it', () {
    bool blank(String field) => field.trim().isEmpty;
    expect([
      for (final row in rows)
        if ([row.fixture, row.what, row.pinnedOn].any(blank)) row.id,
    ], isEmpty);
  });
}
