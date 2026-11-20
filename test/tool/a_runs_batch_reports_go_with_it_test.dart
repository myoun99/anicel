@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/affected_tests.dart' show kReportsParent, takeReportsFolder;
import '../../tool/test_queue.dart'
    show RunTemp, kRunTempLock, kRunTempWhere, runTempName;
import '../helpers/temp_dir.dart';

/// 🆕2026-11-20 (card the-wide-check-takes-five-hours): a run's batch
/// reports were a new `affected-times*` folder each run, removed when the
/// run ended — every run cut short left its own, 174 of them, 334 MB.
void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('reports_tmp'));
  tearDown(() => deleteTempQuietly(temp));
  final here = Directory.current.path;

  test("what a killed run left in its reports goes when the checkout's "
      'next run takes the folder', () {
    final left = Directory(
      '${temp.path}/$kReportsParent/${runTempName(here, 0)}',
    )..createSync(recursive: true);
    File('${left.path}/$kRunTempLock').writeAsStringSync('1\n');
    File('${left.path}/$kRunTempWhere').writeAsStringSync(here);
    final report = File('${left.path}/batch3.json')..writeAsStringSync('{}');

    final reports = takeReportsFolder(temp: temp);
    addTearDown(reports.end);
    expect(reports.folder.uri, left.uri);
    expect(report.existsSync(), isFalse);
  });

  test("⛔the batches' temps keep their names beside it — the hooks runner "
      'keeps a build only while TEMP is what it was', () {
    final reports = takeReportsFolder(temp: temp);
    addTearDown(reports.end);
    final batch = RunTemp.take(parent: temp);
    addTearDown(batch.end);
    expect(
      batch.folder.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
      runTempName(here, 0),
    );
  });

  test('a run writes its reports there, and empties it when it ends', () {
    final source = File('tool/affected_tests.dart').readAsStringSync();
    expect(source, contains('final reports = takeReportsFolder();'));
    expect(
      source,
      contains(r"final report = File('${reports.folder.path}/batch$i.json');"),
    );
    expect(source, contains('  reports.end();'));
  });
}
