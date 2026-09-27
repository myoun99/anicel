import 'dart:io';

import '../../core/path_names.dart';

/// Moves [source] — a file, or a folder and everything in it — into
/// [folder] under its own name: a rename where the two share a volume, a
/// copy and a delete where they do not (the run's room and a Google Drive
/// letter are two volumes). A file already there by the same name is
/// replaced, as an export into that folder replaces it; a folder already
/// there takes the moved one's contents beside its own.
///
/// ⚠️The rename-else-copy step has a twin in
/// `ProviderDocuments.adoptAsWorkingCopy` (a file to a named destination,
/// not into a folder). Two, so they stay apart — the third joins them.
void moveIntoFolder(String source, String folder) {
  final target = '$folder${Platform.pathSeparator}${fileNameOfPath(source)}';
  if (FileSystemEntity.isDirectorySync(source)) {
    Directory(target).createSync(recursive: true);
    for (final child in Directory(source).listSync()) {
      moveIntoFolder(child.path, target);
    }
    Directory(source).deleteSync();
    return;
  }
  // Both replace a FILE standing at [target]; a folder there refuses both.
  final file = File(source);
  try {
    file.renameSync(target);
  } on FileSystemException {
    file.copySync(target);
    file.deleteSync();
  }
}
