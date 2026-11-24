import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨The ledger of files whose tests leave screens of the engine only
/// shrinks (test/helpers/screens_left_of_the_engine.dart has the law and
/// the count it began from, 🗣️관제 2026-11-24 「총 개수 고정」). A file
/// taken out of it lowers [ledgered]; a file that leaves a screen frees it
/// instead of joining.
const ledgered = 162;

final _declares = RegExp(
  r'^  itsTestsLeaveScreensOfTheEngine\(',
  multiLine: true,
);

void main() {
  test('the files that declare they leave screens of the engine are the '
      'ledger\'s $ledgered', () {
    final declaring = [
      for (final file in Directory('test').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('_test.dart') &&
            _declares.hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(
      declaring.length,
      ledgered,
      reason:
          'a file joined the ledger, or one left it and the total was not '
          'lowered with it',
    );
  });
}
