import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'pinned_fingerprints.dart';

void main() {
  group('fingerprintHex', () {
    // The standard check value of CRC-32/ISO-HDLC — the same pin the
    // engine's Rust side carries (`fingerprint.rs`, `native/ledger`), so
    // both sides are the one CRC the ledger's rows are written in.
    test('gives the published CRC of the check string', () {
      expect(fingerprintHex(ascii.encode('123456789')), 'cbf43926');
    });

    test('keeps its leading zeros', () {
      expect(fingerprintHex(Uint8List(0)), '00000000');
    });
  });

  group('parseFingerprintLedger', () {
    const row = '"id":"a/b","fixture":"f","what":"w","hash":"00000000"';

    test('reads a row', () {
      final rows = parseFingerprintLedger(
        '{"rows":[{$row,"pinned_on":"p"}]}',
      );
      expect(rows.single.id, 'a/b');
      expect(rows.single.pinnedOn, 'p');
    });

    test('refuses a row missing a key, holding another, or not a string', () {
      for (final bad in [
        '{$row}',
        '{$row,"pinned_on":"p","note":"n"}',
        '{$row,"pinned_on":7}',
      ]) {
        expect(
          () => parseFingerprintLedger('{"rows":[$bad]}'),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });

  test('pinnedFingerprint names an id the ledger does not hold', () {
    expect(
      () => pinnedFingerprint('no/such-row'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('no/such-row'),
        ),
      ),
    );
  });
}
