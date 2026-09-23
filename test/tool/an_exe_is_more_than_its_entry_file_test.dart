import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/board_server.dart';
import '../helpers/temp_dir.dart';

/// 🚨★★★AN EXE IS MADE OF MORE THAN ITS ENTRY FILE.
///
/// The board replaces itself when its own source changes — that mechanism
/// exists because 유저 asked 「매번 너가 갱신해줘야 반영되는건가? **좀 약한
/// 구조 아닌가**」, and because 「a fix that merged and never reached the
/// screen」 is a shape this project keeps stepping in.
///
/// ⛔It compared the ENTRY FILE ALONE. 🧪2026-08-31, measured: #1433 changed
/// only `board_model.dart` — which both binaries compile in — and
/// `board_server.exe` went on serving code built from the previous one.
/// `board_server.dart` was byte-identical, so neither the running server nor
/// `board_up.sh` had any reason to look. **Nothing anywhere would ever have
/// noticed.** The self-replace was a lie for every change that missed one
/// file.
///
/// ⚠️WHAT THIS FILE CANNOT TEST: `board_up.sh` WRITES the stamp and lives in
/// the memory folder, outside this repository, so CI cannot see it. Its
/// `sources_of` is the same rule in shell. They were verified byte-identical
/// by measurement on 2026-08-31 (170815 bytes each) — ⛔and if they ever
/// disagree the server relaunches on EVERY request, so the two comments point
/// at each other and say「change both or neither」.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('exe-src'));
  tearDown(() => deleteTempQuietly(dir));

  File write(String name, String body) =>
      File('${dir.path}/$name')..writeAsStringSync(body);

  List<String> namesOf(File entry) => [
        for (final f in sourcesOfEntry(entry)) f.path.split('/').last,
      ];

  test('🚨the entry AND the files it imports from its own directory', () {
    write('board_model.dart', 'const x = 1;\n');
    final entry = write(
      'board_server.dart',
      "import 'dart:io';\n"
      "import 'package:flutter/material.dart';\n"
      "import 'board_model.dart';\n"
      'void main() {}\n',
    );
    expect(namesOf(entry), ['board_model.dart', 'board_server.dart']);
  });

  test('⛔dart: and package: imports are not ours to watch', () {
    final entry = write(
      'board_check.dart',
      "import 'dart:convert';\nimport 'package:x/y.dart';\nvoid main() {}\n",
    );
    expect(namesOf(entry), ['board_check.dart']);
  });

  test('🚨sorted, because the stamp is a byte compare', () {
    // ⛔Two readers concatenate these — this one and `board_up.sh`'s
    // `sources_of | sort -u`. An order that depends on how the imports
    // happened to be typed would make the two disagree, and a disagreement
    // here is not a stale exe, it is a relaunch on every request.
    write('a_model.dart', '1');
    write('z_model.dart', '2');
    final entry = write(
      'board_server.dart',
      "import 'z_model.dart';\nimport 'a_model.dart';\nvoid main() {}\n",
    );
    expect(namesOf(entry), ['a_model.dart', 'board_server.dart', 'z_model.dart']);
  });

  test('⛔an import written mid-file is still an import', () {
    // The regex is anchored per LINE, not to the top of the file.
    write('board_model.dart', '1');
    final entry = write(
      'board_server.dart',
      '// a comment first\n'
      '\n'
      "import 'board_model.dart';\n"
      'void main() {}\n',
    );
    expect(namesOf(entry), contains('board_model.dart'));
  });

  test('⛔a commented-out import is not compiled in', () {
    write('board_model.dart', '1');
    final entry = write(
      'board_server.dart',
      "// import 'board_model.dart';\nvoid main() {}\n",
    );
    expect(namesOf(entry), ['board_server.dart']);
  });

  test('🚨★★★the REAL board_server names board_model — the case that broke',
      () {
    // ⛔premise and regression in one: if this ever returns the entry alone
    // again, the running board can serve code nobody rebuilt.
    final entry = File('${Directory.current.path}/tool/board_server.dart');
    expect(entry.existsSync(), isTrue, reason: '⛔premise: the file is there');
    expect(namesOf(entry), contains('board_model.dart'));
    expect(namesOf(entry), contains('board_server.dart'));
  });
}
