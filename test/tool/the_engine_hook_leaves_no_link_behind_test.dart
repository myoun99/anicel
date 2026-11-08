import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../packages/gpu_engine/hook/target_link.dart';
import '../helpers/temp_dir.dart';

/// THE ENGINE'S BUILD HOOK TAKES DOWN ITS LINK INTO THE TRUNK'S HOOK FOLDER
/// WHEN ITS BUILD ENDS (the-hook-folder-lost-an-android-dep-file,
/// 2026-11-08).
///
/// The builder builds into `target` of the hook's output folder, inside the
/// checkout's `.dart_tool`, and the hook makes that a link to the folder
/// every checkout shares. Git for Windows deletes through a junction: a
/// lane landed at 10:04:19 took its worktree away, and with it the trunk's
/// files in readdir order till a path past 259 characters stopped it —
/// arm64's lock and fingerprints `allocator-api2` … `anicel-fx` while an
/// Android build of another checkout ran there. cargo, finding a path
/// crate's fingerprint gone, deletes the library's `.d` and still exits 0
/// (output_depinfo.rs), and the hook failed reading it.
void main() {
  late Directory root;
  late Directory shared;
  late String repo;
  late String worktree;
  late Uri output;

  void git(List<String> args) {
    final run = Process.runSync('git', args);
    expect(run.exitCode, 0, reason: 'git $args: ${run.stderr}');
  }

  List<String> sharedFiles() => [
        for (final entity in shared.listSync(recursive: true))
          if (entity is File) entity.uri.pathSegments.last,
      ]..sort();

  void removeTheWorktree() =>
      git(['-C', repo, 'worktree', 'remove', worktree, '--force']);

  setUp(() {
    root = Directory.systemTemp.createTempSync('hook-link');
    shared = Directory('${root.path}/shared')..createSync();
    File('${shared.path}/kept').writeAsStringSync('the trunk');
    repo = '${root.path}/repo';
    git(['init', '-q', repo]);
    git(['-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@t', 'commit',
        '-q', '--allow-empty', '-m', 'trunk']);
    worktree = '$repo/lane';
    git(['-C', repo, 'worktree', 'add', '-q', worktree, '-b', 'lane']);
    output = Directory('$worktree/.dart_tool/hooks_runner/shared/gpu_engine/'
            'build/0123456789/')
        .absolute
        .uri;
    Directory.fromUri(output).createSync(recursive: true);
  });

  tearDown(() => deleteTempQuietly(root));

  test('🧪a worktree removed while the link stands takes the shared '
      'folder\'s files with it', () async {
    await withTargetAimed(output, shared.uri, () async {
      removeTheWorktree();
    });
    expect(sharedFiles(), isEmpty);
  }, skip: Platform.isWindows ? false : 'git deletes through a junction on '
      'Windows alone — elsewhere the link is a symbolic one it unlinks');

  test('🚨the build writes through the link, and once it ends the checkout '
      'holds none: removing the worktree takes nothing shared', () async {
    final target = output.resolve('target').toFilePath();
    await withTargetAimed(output, shared.uri, () async {
      expect(
        FileSystemEntity.typeSync(target, followLinks: false),
        FileSystemEntityType.link,
      );
      File('$target/built').writeAsStringSync('a build');
    });
    expect(
      FileSystemEntity.typeSync(target, followLinks: false),
      FileSystemEntityType.notFound,
    );
    removeTheWorktree();
    expect(sharedFiles(), ['built', 'kept']);
  });

  test('a build that fails takes the link down too', () async {
    await expectLater(
      withTargetAimed(output, shared.uri, () async {
        throw StateError('cargo failed');
      }),
      throwsStateError,
    );
    removeTheWorktree();
    expect(sharedFiles(), ['kept']);
  });
}
