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
/// of the folder, and of the dependencies the hook reports none lies
/// under it (build_inputs.dart — ↩️one did till 2026-11-13, and the hook
/// ran again for every `flutter test`).
///
/// [linked] — a build for Windows, which link.exe links — measures first
/// whether link.exe can reach the folder's deepest input through the link,
/// and fails before anything is built when it cannot
/// ([whyTheLinkCannotReach]).
Future<T> withTargetAimed<T>(
  Uri outputDirectory,
  Uri folder,
  Future<T> Function() build, {
  bool linked = false,
}) async {
  final target = outputDirectory.resolve('target').toFilePath();
  if (linked) {
    final why = whyTheLinkCannotReach(target, Directory.fromUri(folder));
    if (why != null) throw StateError(why);
  }
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

/// The longest path link.exe opens a file by: Windows' 260, less the
/// terminating null.
const kLinkReach = 259;

/// Why a build into [target], a link to [folder], would die at the link —
/// or null when link.exe reaches the folder's deepest input through it, or
/// the folder has built none yet.
///
/// 📏SAID WHERE THE BUILD IS, BEFORE IT COMPILES (card
/// the-link-fit-check-measures-the-app-depth-only, 관제 · 보드/인프라
/// 2026-11-19). tool/lane.sh's `fits_the_link` refuses a lane whose APP
/// would not reach — the depth every lane's tests build at. The probe in
/// packages/gpu_engine/example builds 28 characters deeper: in
/// `lane-two-textures-fill` its link stood at 266 and died with LNK1104
/// after its compile, words that read like a full disk. Holding every lane
/// to the probe's depth would refuse names that build the app well, so the
/// build says it instead, with the number to cut.
/// ⚠️TWO READERS, NOT THREE: `fits_the_link` counts the same files with
/// `find` before a lane is made — change both or neither.
String? whyTheLinkCannotReach(String target, Directory folder) {
  final deepest = deepestLinkInput(folder);
  if (deepest == null) return null;
  final path = '$target${Platform.pathSeparator}$deepest';
  final over = path.length - kLinkReach;
  if (over <= 0) return null;
  return 'gpu_engine: link.exe cannot reach this build\'s deepest input — '
      '$path is ${path.length} characters, past Windows\' $kLinkReach, and '
      'the build would die at the link with LNK1104. Build it from a '
      'checkout $over character(s) shallower: a lane with a shorter name.';
}

/// The deepest library link.exe opens under [folder], relative to it: the
/// longest in a Windows `deps`, the target's (`<triple>/<profile>/deps`)
/// or the host's (`<profile>/deps`, where build scripts and proc macros
/// link) — never what lies in a folder within, nor Android's. Null when
/// there is none.
String? deepestLinkInput(Directory folder) {
  if (!folder.existsSync()) return null;
  String? deepest;
  void look(String deps) {
    final libraries = Directory('${folder.path}/$deps');
    if (!libraries.existsSync()) return;
    for (final file in libraries.listSync(followLinks: false)) {
      final name = file.uri.pathSegments.last;
      if (file is! File || !(name.endsWith('.rlib') || name.endsWith('.lib'))) {
        continue;
      }
      final path = '$deps/$name';
      if (path.length > (deepest?.length ?? 0)) deepest = path;
    }
  }

  for (final entry in folder.listSync(followLinks: false)) {
    if (entry is! Directory) continue;
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (name.endsWith('-pc-windows-msvc')) {
      for (final profile in entry.listSync(followLinks: false)) {
        if (profile is! Directory) continue;
        final named = profile.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        look('$name/$named/deps');
      }
    } else if (name == 'release' || name == 'debug') {
      look('$name/deps');
    }
  }
  return deepest;
}

/// ⛔The link itself, never through it: it is the trunk's folder.
void _letGo(String target) {
  if (FileSystemEntity.typeSync(target, followLinks: false) ==
      FileSystemEntityType.link) {
    Link(target).deleteSync();
  }
}
