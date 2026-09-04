// Lists the wide signatures the ratchet counts, so a failure names the
// declarations instead of leaving the author to guess which are new.
//   dart run tool/refactor/wide_list.dart
import 'dart:io';

import 'clean_code_scan.dart';

void main() {
  for (final finding in scanCleanCode('lib').wideSignatures) {
    stdout.writeln(finding.toString());
  }
}
