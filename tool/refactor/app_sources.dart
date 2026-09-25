// The app's own Dart files, as the scans that measure the app read them.
import 'dart:io';

/// Every `.dart` file under [root] with forward slashes, sorted — and
/// `lib/dev/` left out: the brush lab is a harness, not the app.
///
/// 🚨ONE answer for the clean-code scan, the clone scan and the unreferenced
/// sweep. Each spelled the exclusion itself as `path.contains('/lib/dev/')`,
/// which a RELATIVE root never matches — `lib/dev/…` has no slash before
/// it — so both ratchets, which scan `'lib'`, counted the lab
/// (ratchet-dev-exclusion-relative-root, 2026-09-25).
List<String> appDartFiles(String root) => [
  for (final file in Directory(root).listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart'))
      file.path.replaceAll('\\', '/'),
]..removeWhere(isDevSource)..sort();

/// Whether [path] (forward slashes, absolute or relative) is in `lib/dev/`.
bool isDevSource(String path) => '/$path'.contains('/lib/dev/');
