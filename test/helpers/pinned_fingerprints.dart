import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show anicelCrc32Finish, anicelCrc32Start, anicelCrc32Update;

/// 🚨THE LEDGER OF PINNED FINGERPRINTS (gpu-engine-skeleton, 2026-11-05):
/// bytes every device must reproduce, pinned once on the first device that
/// made them. Dart tests and the engine's Rust tests, every crate's through
/// one reader (`packages/gpu_engine/rust/native/ledger`), read this one file.
///
/// ⛔A row is never pinned again to make a device pass — a device that
/// differs fails. A new value needs its reason in the commit that changes
/// it.
const fingerprintLedgerPath = 'test/fixtures/fingerprints.json';

/// One row: [id] is `<area>/<what>`, [fixture] the input, [what] whose
/// bytes were fingerprinted, [hash] their [fingerprintHex], [pinnedOn] the
/// device, backend and date that pinned it.
typedef PinnedRow = ({
  String id,
  String fixture,
  String what,
  String hash,
  String pinnedOn,
});

/// The keys a row holds, in the order the file writes them.
const pinnedRowKeys = ['id', 'fixture', 'what', 'hash', 'pinned_on'];

/// The ledger's text with Windows line endings read as `\n`, since a
/// checkout under `core.autocrlf` hands it back with CRLF.
String readFingerprintLedger() =>
    File(fingerprintLedgerPath).readAsStringSync().replaceAll('\r\n', '\n');

/// Every row of [ledger] (the file's text), in the file's order. Throws a
/// [FormatException] naming what is wrong when a row is not one.
List<PinnedRow> parseFingerprintLedger(String ledger) {
  final decoded = jsonDecode(ledger);
  if (decoded is! Map || decoded.keys.join(',') != 'rows') {
    throw const FormatException('the ledger is {"rows": [...]} and no more');
  }
  final rows = decoded['rows'];
  if (rows is! List) {
    throw const FormatException('"rows" is not a list');
  }
  return [for (final row in rows) _pinnedRow(row)];
}

PinnedRow _pinnedRow(Object? row) {
  if (row is! Map ||
      row.keys.join(',') != pinnedRowKeys.join(',') ||
      row.values.any((value) => value is! String)) {
    throw FormatException(
      'a row holds ${pinnedRowKeys.join(', ')}, all strings, in that order: '
      '$row',
    );
  }
  return (
    id: row['id'] as String,
    fixture: row['fixture'] as String,
    what: row['what'] as String,
    hash: row['hash'] as String,
    pinnedOn: row['pinned_on'] as String,
  );
}

/// The ledger's hash for [id]. Throws naming [id] when there is no such row.
String pinnedFingerprint(String id) {
  for (final row in parseFingerprintLedger(readFingerprintLedger())) {
    if (row.id == id) return row.hash;
  }
  throw StateError('$fingerprintLedgerPath has no row $id');
}

/// The fingerprint of [bytes] as the ledger writes it: CRC-32 (the app's
/// one, `anicelCrc32*`), eight lowercase hex digits.
String fingerprintHex(Uint8List bytes) => anicelCrc32Finish(
  anicelCrc32Update(anicelCrc32Start, bytes),
).toRadixString(16).padLeft(8, '0');
