import 'dart:io';

/// Runs [build] with `target` of the hook's [outputDirectory] a link to
/// [folder]: the builder builds into `target` there, and the folder is fixed
/// on its command line.
///
/// 🚨THE LINK STANDS WHILE [build] RUNS AND NO LONGER, whether it fails or
/// not (the-hook-folder-lost-an-android-dep-file, 2026-11-08). It lies in
/// the checkout's `.dart_tool`, and Git for Windows deletes through a
/// junction: a lane landed at 10:04:19 took its worktree away and with it
/// the trunk's hook folder in readdir order, till a path past 259
/// characters stopped it — arm64's lock and its fingerprints from
/// `allocator-api2` on, while another checkout built for Android there.
/// cargo, a path crate's fingerprint gone, deletes the library's `.d` and
/// exits 0 all the same (output_depinfo.rs), and the hook failed reading
/// it. Nothing reads the link after the build: the library is copied out
/// of the folder, and the dependencies the hook reports are the sources.
Future<T> withTargetAimed<T>(
  Uri outputDirectory,
  Uri folder,
  Future<T> Function() build,
) async {
  final target = outputDirectory.resolve('target').toFilePath();
  _aim(target, folder);
  try {
    return await build();
  } finally {
    _letGo(target);
  }
}

void _aim(String target, Uri folder) {
  // A link a killed run left.
  _letGo(target);
  // A hook from before the link built there itself.
  if (FileSystemEntity.typeSync(target, followLinks: false) ==
      FileSystemEntityType.directory) {
    Directory(target).deleteSync(recursive: true);
  }
  Directory.fromUri(folder).createSync(recursive: true);
  if (!Platform.isWindows) {
    Link(target).createSync(folder.toFilePath());
    return;
  }
  // ⛔A junction, not the symbolic link Dart's Link makes on Windows:
  // rust/build.rs unpacks the DXC zip into its OUT_DIR, inside this
  // folder, with Windows' tar, which will not unpack through a symbolic
  // link ("too many symbolic link levels") and does through a junction
  // (measured 2026-11-07). A junction needs no privilege either.
  final made = Process.runSync('cmd', [
    '/c',
    'mklink',
    '/J',
    target,
    folder.toFilePath(),
  ]);
  if (made.exitCode != 0) {
    throw StateError('mklink /J $target: ${made.stdout}${made.stderr}');
  }
}

/// ⛔The link itself, never through it: it is the trunk's folder.
void _letGo(String target) {
  if (FileSystemEntity.typeSync(target, followLinks: false) ==
      FileSystemEntityType.link) {
    Link(target).deleteSync();
  }
}
