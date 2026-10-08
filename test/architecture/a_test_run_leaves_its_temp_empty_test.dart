import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/os_file_modes.dart';
import '../helpers/project_scratch_folder.dart';
import '../helpers/temp_dir.dart';

/// 🚨★★★**A TEST RUN LEAVES ITS TEMP EMPTY** (2026-10-08).
///
/// `flutter test` runs every file in a process of its own, and all of them
/// made folders in ONE temp directory and left some there: on the machine
/// it was measured on, 1,135 folders of test runs, 696 of them older than
/// six hours — the stores' sandboxes, the documents home, staged files the
/// product made on its way, and folders a late write made again after the
/// test had removed them.
///
/// `flutter_test_config.dart` holds it while the suite runs: each run gets
/// a temp of its own ([giveTheRunItsOwnTemp]) and its last `tearDownAll`
/// fails the file for whatever is still in it ([whatTheRunLeftIn]). This
/// file holds the two halves of that — the helper answers what it should,
/// and the harness still asks it — because an absence nobody checks is not
/// a law.
void main() {
  test("Directory.systemTemp is this run's own folder", () {
    final name = Directory.systemTemp.path
        .replaceAll(r'\', '/')
        .split('/')
        .last;
    expect(
      name,
      startsWith('qa_run_${pid}_'),
      reason: 'without it every run shares one temp, and what a file left '
          'behind cannot be told from what the runs beside it did',
    );
  });

  test('what nothing deleted is named, with what it holds', () async {
    final temp = Directory.systemTemp.createTempSync('left-behind');
    deleteAfterSessionEnds(temp);
    Directory('${temp.path}/forgotten').createSync();
    File('${temp.path}/forgotten/data.json').writeAsStringSync('{}');
    File('${temp.path}/loose.wav').writeAsBytesSync(const [0]);
    final deleted = Directory('${temp.path}/deleted')..createSync();
    deleteTempQuietly(deleted);

    expect(await whatTheRunLeftIn(temp), [
      'forgotten — nothing deleted it (data.json)',
      'loose.wav — nothing deleted it',
    ]);
  });

  test('a folder that came back after its delete — a write still on its way '
      'makes it again — is asked again when the run ends, and goes', () async {
    final temp = Directory.systemTemp.createTempSync('left-again');
    deleteAfterSessionEnds(temp);
    final again = Directory('${temp.path}/again')..createSync();
    deleteTempQuietly(again);
    expect(again.existsSync(), isFalse, reason: 'CONTROL: it went');
    File('${again.path}/late.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');

    expect(
      await whatTheRunLeftIn(temp),
      isEmpty,
      reason: 'the test removed it; the write it set off made it again — '
          'that is not a folder left behind',
    );
    expect(again.existsSync(), isFalse, reason: 'asked again, and gone');
  });

  test('a folder a quiet delete lost is asked again when the run ends, and '
      'named only if the run is still holding it', () async {
    final temp = Directory.systemTemp.createTempSync('left-held');
    deleteAfterSessionEnds(temp);
    final letGo = Directory('${temp.path}/let-go')..createSync();
    final kept = Directory('${temp.path}/kept')..createSync();
    final releaseLetGo = _grip(File('${letGo.path}/a.bin'));
    final releaseKept = _grip(File('${kept.path}/b.bin'));
    if (releaseLetGo == null || releaseKept == null) {
      markTestSkipped('this user can delete anything (root)');
      return;
    }
    addTearDown(releaseKept);
    deleteTempQuietly(letGo);
    deleteTempQuietly(kept);
    expect(
      [letGo.existsSync(), kept.existsSync()],
      [isTrue, isTrue],
      reason: 'CONTROL: both deletes lost',
    );

    releaseLetGo();
    expect(
      await whatTheRunLeftIn(temp, patience: Duration.zero),
      ['kept — still held when the run ended (b.bin)'],
      reason: "losing a delete to a moment's grip is not leaving a folder "
          'behind; holding it until the run ends is',
    );
    expect(letGo.existsSync(), isFalse, reason: 'asked again, and gone');
  });

  test('the harness asks it last, and its answer fails the file', () {
    final config = File('test/flutter_test_config.dart').readAsStringSync();
    final declared = config.indexOf('await testMain()');
    final own = config.indexOf('giveTheRunItsOwnTemp()');
    final asked = config.indexOf('whatTheRunLeftIn(');
    expect(declared, isNonNegative);
    expect(
      own,
      allOf(isNonNegative, lessThan(declared)),
      reason: 'the run takes its own temp before a single test is declared',
    );
    final registered = config.lastIndexOf('tearDownAll(', asked);
    expect(
      [registered, asked],
      everyElement(allOf(isNonNegative, lessThan(declared))),
      reason: 'asked from a tearDownAll registered BEFORE the file declares '
          'its own, so it runs after every one of them',
    );
    expect(
      config.indexOf('expect(', asked),
      allOf(greaterThan(asked), lessThan(declared)),
      reason: 'and what it answers is held to empty — a check that only '
          'cleans up is a check nobody hears',
    );
  });
}

/// Makes [file] something a delete of its folder loses to, the way the
/// platform does it, and answers how to let go — or null where nothing can
/// be refused (root deletes anything).
///
/// ⚠️Windows by a handle, as the suite meets it (errno 32): a read-only file
/// is no refusal there — a recursive delete clears the flag on its way.
void Function()? _grip(File file) {
  file.writeAsBytesSync(const [1]);
  if (Platform.isWindows) {
    return file.openSync(mode: FileMode.append).closeSync;
  }
  if (!setUndeletable(file.path, on: true)) {
    return null;
  }
  return () => setUndeletable(file.path, on: false);
}
