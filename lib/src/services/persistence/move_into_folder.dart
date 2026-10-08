import 'dart:io';

import '../../core/path_names.dart';

/// Moves [source] — a file, or a folder and everything in it — into
/// [folder] under its own name. A file already there by the same name is
/// replaced, as an export into that folder replaces it; a folder already
/// there takes the moved one's contents beside its own.
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
  moveFileOnto(source, target);
}

/// Moves the FILE at [source] onto [target] — to that path, under that
/// name: a rename where the two share a volume, a copy and a delete where
/// they do not (the run's room and a Google Drive letter are two volumes).
/// A file standing at [target] is replaced; a folder there refuses both.
///
/// ONE spelling for the three that move a file to a named place. Two wrote
/// 「rename, else copy and delete」 out for themselves and each said so of
/// the other — [moveIntoFolder]'s file, and the working copy a document's
/// staged file becomes (`ProviderDocuments.adoptAsWorkingCopy`) — to be
/// joined when a third came. It came 2026-10-07: the lone file of an export
/// made in the run's room for a place it may only be moved onto (F-221,
/// macOS).
void moveFileOnto(String source, String target) {
  final file = File(source);
  try {
    file.renameSync(target);
  } on FileSystemException {
    file.copySync(target);
    file.deleteSync();
  }
}
