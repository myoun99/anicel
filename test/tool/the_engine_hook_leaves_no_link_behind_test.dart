import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../packages/gpu_engine/hook/target_link.dart';
import '../helpers/dart_sources.dart';
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
/// (output_depinfo.rs), and the hook failed reading it. A worktree removed
/// with the link standing is tool/lane_test.sh's section X — a run of git,
/// which no test here starts.
void main() {
  late Directory root;
  late Directory shared;
  late Uri output;
  late String target;

  List<String> sharedFiles() => [
        for (final file in filesUnder(shared.path)) file.uri.pathSegments.last,
      ]..sort();

  FileSystemEntityType standing() =>
      FileSystemEntity.typeSync(target, followLinks: false);

  setUp(() {
    root = Directory.systemTemp.createTempSync('hook-link');
    shared = Directory('${root.path}/shared')..createSync();
    File('${shared.path}/kept').writeAsStringSync('the trunk');
    output = Directory('${root.path}/lane/.dart_tool/hooks_runner/shared/'
            'gpu_engine/build/0123456789/')
        .absolute
        .uri;
    Directory.fromUri(output).createSync(recursive: true);
    target = output.resolve('target').toFilePath();
  });

  tearDown(() => deleteTempQuietly(root));

  test('🚨the build writes through the link, and once it ends the checkout '
      'holds none — what it built stays in the folder', () async {
    await withTargetAimed(output, shared.uri, () async {
      expect(standing(), FileSystemEntityType.link);
      File('$target/built').writeAsStringSync('a build');
    });
    expect(standing(), FileSystemEntityType.notFound);
    expect(sharedFiles(), ['built', 'kept']);
  });

  test('a build that fails takes the link down too', () async {
    await expectLater(
      withTargetAimed(output, shared.uri, () async {
        throw StateError('cargo failed');
      }),
      throwsStateError,
    );
    expect(standing(), FileSystemEntityType.notFound);
    expect(sharedFiles(), ['kept']);
  });
}
