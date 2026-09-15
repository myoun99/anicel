import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/native_engine_provenance.dart';

/// 🚨AN ENGINE BUILD SAYS WHICH C IT CAME FROM, and the name is the C's
/// content — ⛔not a file time, ⛔not the ABI number. The incidents that
/// decided it are at the head of `tool/native_engine_provenance.dart`.
///
/// Two checkouts are two directories here, because that is the case the
/// name exists for: `open` copies the trunk's engine into a lane, and the
/// lane has to recognise the trunk's C as its own.
void main() {
  late Directory sandbox;
  late String trunk;
  late String lane;

  File source(String checkout, String path) =>
      File('$checkout/$nativeSourceDir/$path');

  void write(String checkout, String path, List<int> bytes) =>
      source(checkout, path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

  void writeText(String checkout, String path, String text) =>
      write(checkout, path, text.codeUnits);

  void holdTheC(String checkout) {
    writeText(checkout, 'qa_engine.c', 'int abi(void) { return 35; }\n');
    writeText(checkout, 'qa_compress.c', 'int zstd;\n');
    writeText(checkout, 'third_party/zstd.h', '#define ZSTD 1\n');
  }

  void stampWith(String checkout, String id) =>
      File('$checkout/$engineStampPath')
        ..createSync(recursive: true)
        ..writeAsStringSync('$id\n');

  String nameOf(String checkout) => nativeSourceId(checkout)!;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('native_provenance_');
    trunk = '${sandbox.path}/trunk';
    lane = '${sandbox.path}/lane';
    holdTheC(trunk);
    holdTheC(lane);
    File('$lane/app.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('// dart\n');
  });
  tearDown(() => sandbox.deleteSync(recursive: true));

  test('⛔fixture premise: a checkout holding C gets a name', () {
    expect(nameOf(trunk), matches(RegExp(r'^[0-9a-f]{16}$')));
  });

  group('the name of the C', () {
    test('two checkouts holding the same C give it the same name — the copy '
        '`open` makes is recognised in the lane', () {
      expect(nameOf(lane), nameOf(trunk));
    });

    test('an edit is other C, and undoing it is the same C again whatever '
        'the file time says', () {
      final before = nameOf(lane);
      writeText(lane, 'qa_engine.c', 'int abi(void) { return 36; }\n');
      expect(nameOf(lane), isNot(before));
      writeText(lane, 'qa_engine.c', 'int abi(void) { return 35; }\n');
      source(lane, 'qa_engine.c').setLastModifiedSync(DateTime(2001));
      expect(nameOf(lane), before);
    });

    test('a new file is part of it — CMake compiles what is on disk', () {
      final before = nameOf(lane);
      writeText(lane, 'qa_new.c', 'int added;\n');
      expect(nameOf(lane), isNot(before));
    });

    test('a deleted file is other C', () {
      final before = nameOf(lane);
      source(lane, 'qa_compress.c').deleteSync();
      expect(nameOf(lane), isNot(before));
    });

    test('a renamed file is other C, though no byte in it changed', () {
      final before = nameOf(lane);
      source(lane, 'qa_compress.c')
          .renameSync(source(lane, 'qa_compressor.c').path);
      expect(nameOf(lane), isNot(before));
    });

    test('a file in a folder below counts', () {
      final before = nameOf(lane);
      writeText(lane, 'third_party/zstd.h', '#define ZSTD 2\n');
      expect(nameOf(lane), isNot(before));
    });

    test('where a name ends and its bytes begin is part of the name', () {
      // `ab` holding `c` against `a` holding `bc`: one byte stream, two
      // different directories.
      writeText(trunk, 'ab', 'c');
      writeText(lane, 'a', 'bc');
      expect(nameOf(lane), isNot(nameOf(trunk)));
    });

    test('where one file ends and the next begins is part of the name', () {
      // `a` = `b` then `c` = `d`, against one `a` holding all of it — the
      // second file's name included, down to the separator byte.
      writeText(trunk, 'a', 'b');
      writeText(trunk, 'c', 'd');
      write(lane, 'a', [...'b'.codeUnits, ...'c'.codeUnits, 0, ...'d'.codeUnits]);
      expect(nameOf(lane), isNot(nameOf(trunk)));
    });

    test('a change outside the C is not a change to it', () {
      final before = nameOf(lane);
      File('$lane/app.dart').writeAsStringSync('// edited\n');
      expect(nameOf(lane), before);
    });

    test('a checkout with no C has no name', () {
      expect(nativeSourceId('${sandbox.path}/nothing'), isNull);
    });
  });

  group('what the engine in a checkout is', () {
    test('no build here at all: absent', () {
      expect(engineProvenance(lane, nameOf(lane)), EngineProvenance.absent);
    });

    test('a build nobody stamped: unstamped', () {
      Directory('$lane/$engineBuildDir').createSync(recursive: true);
      expect(engineProvenance(lane, nameOf(lane)), EngineProvenance.unstamped);
    });

    test("the trunk's stamp, copied into a lane holding the trunk's C: "
        'current', () {
      stampWith(trunk, nameOf(trunk));
      stampWith(lane, engineStampOf(trunk)!);
      expect(engineProvenance(lane, nameOf(lane)), EngineProvenance.current);
    });

    test('stamped with this C, and then the C moved: foreign', () {
      stampWith(lane, nameOf(lane));
      writeText(lane, 'qa_engine.c', 'int abi(void) { return 36; }\n');
      expect(engineProvenance(lane, nameOf(lane)), EngineProvenance.foreign);
    });
  });

  group('the line tool/lane.sh reads', () {
    test("current: exit 0, the C's name and then the verdict", () {
      stampWith(lane, nameOf(lane));
      final report = checkReport(lane);
      expect(report.line, '${nameOf(lane)} current');
      expect(report.exitCode, 0);
    });

    test('not current: exit 1, still naming the C so the build can stamp it',
        () {
      final report = checkReport(lane);
      expect(report.line, '${nameOf(lane)} absent');
      expect(report.exitCode, 1);
    });

    test('no C: exit 2, and nothing for a build to stamp', () {
      final report = checkReport('${sandbox.path}/nothing');
      expect(report.line, isNull);
      expect(report.exitCode, 2);
    });

    test('tool/lane.sh asks this tool and writes the stamp where it reads it',
        () {
      final laneScript = File('tool/lane.sh').readAsStringSync();
      // The ASSIGNMENT, not the path: the header comment spells the path
      // too, and a drifted variable under a correct comment passed a plain
      // `contains` (mutant, 2026-09-15).
      final stampVariable = RegExp(
        '^ENGINE_STAMP=${RegExp.escape(engineStampPath)}\\r?\$',
        multiLine: true,
      );
      expect(laneScript, matches(stampVariable));
      expect(
        laneScript,
        matches(RegExp(r'tool/native_engine_provenance\.dart"? check ')),
      );
    });
  });
}
