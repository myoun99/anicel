import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/native_engine_provenance.dart';

/// 🚨AN ENGINE BUILD SAYS WHICH C IT CAME FROM, and the name is the C's
/// content — ⛔not a file time, ⛔not the ABI number. The five incidents that
/// decided it are at the head of `tool/native_engine_provenance.dart`.
///
/// Measured against a real git repository, because the answer IS git's: a
/// stand-in would pin whatever the stand-in does.
void main() {
  late Directory repo;

  ProcessResult git(List<String> args) =>
      Process.runSync('git', ['-C', repo.path, ...args]);

  File source(String name) => File('${repo.path}/$nativeSourceDir/$name');

  String committedTree() =>
      (git(['rev-parse', 'HEAD:$nativeSourceDir']).stdout as String).trim();

  String nameOfTheC() => nativeSourceId(repo.path)!;

  void stampWith(String id) => File('${repo.path}/$engineStampPath')
    ..createSync(recursive: true)
    ..writeAsStringSync('$id\n');

  setUp(() {
    repo = Directory.systemTemp.createTempSync('native_provenance_');
    git(['init', '-q']);
    git(['config', 'user.email', 'lane@example.invalid']);
    git(['config', 'user.name', 'lane']);
    source('qa_engine.c')
      ..createSync(recursive: true)
      ..writeAsStringSync('int abi(void) { return 35; }\n');
    source('qa_compress.c').writeAsStringSync('int zstd;\n');
    File('${repo.path}/app.dart').writeAsStringSync('// dart\n');
    git(['add', '--', nativeSourceDir, 'app.dart']);
    git(['commit', '-q', '-m', 'fixture']);
  });
  tearDown(() => repo.deleteSync(recursive: true));

  test('⛔fixture premise: the C is committed and git names its tree', () {
    expect(committedTree(), matches(RegExp(r'^[0-9a-f]{40}$')));
  });

  group('the name of the C', () {
    test('a clean checkout names it exactly as the commit does', () {
      expect(nativeSourceId(repo.path), committedTree());
    });

    test('an edit nobody committed is other C, and undoing it is the same C '
        'again — the name is the content, not a file time', () {
      final committed = committedTree();
      source('qa_engine.c').writeAsStringSync('int abi(void) { return 36; }\n');
      expect(nameOfTheC(), isNot(committed));
      source('qa_engine.c').writeAsStringSync('int abi(void) { return 35; }\n');
      expect(nameOfTheC(), committed);
    });

    test('a file nobody added is part of it — CMake compiles what is on disk',
        () {
      final committed = committedTree();
      source('qa_new.c').writeAsStringSync('int added;\n');
      expect(nameOfTheC(), isNot(committed));
    });

    test('a file deleted from disk is other C', () {
      final committed = committedTree();
      source('qa_compress.c').deleteSync();
      expect(nameOfTheC(), isNot(committed));
    });

    test('a file git tracks counts even when the ignore rules match it — the '
        'commit is read first, and what is on disk is added over it', () {
      File('${repo.path}/.gitignore').writeAsStringSync('*.lib\n');
      source('zstd.lib').writeAsStringSync('prebuilt');
      git(['add', '-f', '--', '.gitignore', '$nativeSourceDir/zstd.lib']);
      git(['commit', '-q', '-m', 'a tracked file the ignore rules match']);
      expect(nameOfTheC(), committedTree());
    });

    test('a change outside the C is not a change to it', () {
      final committed = committedTree();
      File('${repo.path}/app.dart').writeAsStringSync('// edited\n');
      expect(nameOfTheC(), committed);
    });

    test("naming it stages nothing: the checkout's own index is untouched",
        () {
      source('qa_engine.c').writeAsStringSync('int abi(void) { return 36; }\n');
      source('qa_new.c').writeAsStringSync('int added;\n');
      nameOfTheC();
      final staged = git(['diff', '--cached', '--name-only']).stdout as String;
      expect(staged.trim(), isEmpty);
    });
  });

  group('what the engine in a checkout is', () {
    test('no build here at all: absent', () {
      expect(
        engineProvenance(repo.path, nameOfTheC()),
        EngineProvenance.absent,
      );
    });

    test('a build nobody stamped: unstamped', () {
      Directory('${repo.path}/$engineBuildDir').createSync(recursive: true);
      expect(
        engineProvenance(repo.path, nameOfTheC()),
        EngineProvenance.unstamped,
      );
    });

    test('stamped with this C: current', () {
      stampWith(nameOfTheC());
      expect(
        engineProvenance(repo.path, nameOfTheC()),
        EngineProvenance.current,
      );
    });

    test('stamped with this C, and then the C moved: foreign', () {
      stampWith(nameOfTheC());
      source('qa_engine.c').writeAsStringSync('int abi(void) { return 36; }\n');
      expect(
        engineProvenance(repo.path, nameOfTheC()),
        EngineProvenance.foreign,
      );
    });
  });

  group('the line tool/lane.sh reads', () {
    ProcessResult check() => Process.runSync(
          'dart',
          ['tool/native_engine_provenance.dart', 'check', repo.path],
          runInShell: true,
        );

    test("current: exit 0, the line is the C's name and then the verdict", () {
      final id = nameOfTheC();
      stampWith(id);
      final result = check();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect((result.stdout as String).trim(), '$id current');
    });

    test('not current: exit 1, still naming the C so the build can stamp it',
        () {
      final result = check();
      expect(result.exitCode, 1, reason: '${result.stderr}');
      expect((result.stdout as String).trim(), '${nameOfTheC()} absent');
    });

    test('tool/lane.sh asks this tool and writes the stamp where it reads it',
        () {
      final lane = File('tool/lane.sh').readAsStringSync();
      expect(lane, contains(engineStampPath));
      expect(
        lane,
        matches(RegExp(r'tool/native_engine_provenance\.dart"? check ')),
      );
    });
  });
}
