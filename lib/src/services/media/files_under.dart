import 'dart:io';

/// Every file under [root], recursively — what a missing file is looked
/// for among: under the folder the user points at (`runMediaRelinkFlow`),
/// and under the folder of the .tvpp that names it
/// (`readTvppProject`).
///
/// Recursive because a production folder splits by cut — the drawing being
/// hunted is almost never at the top. ASYNC rather than `listSync` because
/// a shot folder holds thousands of files and this runs on the UI isolate.
///
/// A folder that vanishes mid-walk yields what was found so far: a partial
/// candidate list makes for a smaller match, which the preview reports
/// honestly, and that beats failing the whole pass.
Future<List<String>> filesUnder(String root) async {
  final paths = <String>[];
  try {
    await for (final entity in Directory(
      root,
    ).list(recursive: true, followLinks: false)) {
      if (entity is File) {
        paths.add(entity.path);
      }
    }
  } on Object {
    // Permission, a race with the user, a vanished mount.
  }
  return paths;
}
