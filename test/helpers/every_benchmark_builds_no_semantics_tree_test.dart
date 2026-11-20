import 'package:flutter_test/flutter_test.dart';

import 'dart_sources.dart';

/// 🚨A benchmark measures the app — so a file under the `benchmark` tag
/// hands each of its `testWidgets` calls `semanticsAsTheAppRuns`
/// (semantics_as_the_app_runs.dart).
void main() {
  test('every benchmark that pumps widgets builds no semantics tree', () {
    final tagged = RegExp(r"@Tags\(\[[^\]]*'benchmark'");
    final calls = RegExp(r'testWidgets\(');
    final handed = RegExp(r'semanticsEnabled:\s*semanticsAsTheAppRuns\b');
    final missing = <String>[];
    var read = 0;
    for (final file in dartFilesUnder('test')) {
      if (!file.path.endsWith('_test.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      if (!tagged.hasMatch(source)) {
        continue;
      }
      read++;
      final asked = calls.allMatches(source).length;
      final given = handed.allMatches(source).length;
      if (given < asked) {
        missing.add('${file.path}: $given of $asked');
      }
    }
    expect(read, greaterThan(0), reason: 'no benchmark was read');
    expect(missing, isEmpty);
  });
}
