import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_pen_ledger.dart';

/// H43: the native pen ledger (`qa_pen_ledger_apple.m`) answers with codes.
/// This is the Dart half of that contract — the half this host can run; the
/// C half keeps its codes beside its own answers.
void main() {
  test('the ledger\'s codes read as what they mean', () {
    expect(QaPenLedger.decode(null), isNull, reason: 'no ledger on this run');
    expect(QaPenLedger.decode(-1), isNull, reason: 'no record of the sample');
    expect(QaPenLedger.decode(-2), (
      state: PenLedgerState.estimated,
      value: 0.0,
    ));
    expect(QaPenLedger.decode(-3), (
      state: PenLedgerState.noPressure,
      value: 0.0,
    ));
    // An estimate UIKit says it will never correct (build 1065).
    expect(QaPenLedger.decode(-4), (
      state: PenLedgerState.estimatedFinal,
      value: 0.0,
    ));
    // Every real answer is a force, a pressure or an angle: zero included.
    expect(QaPenLedger.decode(0), (state: PenLedgerState.measured, value: 0.0));
    expect(QaPenLedger.decode(1.39), (
      state: PenLedgerState.measured,
      value: 1.39,
    ));
  });
}
