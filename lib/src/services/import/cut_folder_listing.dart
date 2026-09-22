// What a delivery FOLDER on disk looks like to [parseCutFolder]: the
// walk's result, and the address the parse is asked at.
//
// 🚨ONE LAW, TWO WALKS. The import door listed the folder asynchronously
// (an import must not block the frame) and the import dialog's live
// preview listed it synchronously (it re-reads on every knob change), and
// each then wrote out the same three things: slice the root off every
// path, spell it with forward slashes, and address the parse with the
// folder's own name plus its parent's. The LISTING stays each caller's —
// that is a real difference in what they may afford — and everything a
// listed entity MEANS lives here (round 8, G1, 2026-09-06).

import 'dart:io';

import '../../models/import/cut_folder_parse.dart';
import '../../models/media_asset.dart'
    show mediaFileName, mediaParentFolderName;

/// [entities] as the parser reads them: paths relative to [folderPath],
/// one spelling, directories marked.
List<CutFolderEntry> cutFolderEntriesFrom(
  String folderPath,
  Iterable<FileSystemEntity> entities,
) {
  final prefixLength = Directory(folderPath).path.length + 1;
  return [
    for (final entity in entities)
      CutFolderEntry(
        (entity.path.length > prefixLength
                ? entity.path.substring(prefixLength)
                : entity.path)
            .replaceAll('\\', '/'),
        isDirectory: entity is Directory,
      ),
  ];
}

/// [parseCutFolder] addressed at a real folder: its own name is the cut's,
/// and its PARENT's name is the process hint some studios put there
/// (rule I — see [CutFolderParseConfig.parentFolderProcessHint]).
CutFolderParseResult parseCutFolderAt(
  String folderPath, {
  required List<CutFolderEntry> entries,
  CutFolderParseConfig config = const CutFolderParseConfig(),
}) {
  return parseCutFolder(
    folderName: mediaFileName(folderPath),
    entries: entries,
    config: config,
    // ⚠️The parent's name is read with the SAME rule as the folder's own
    // ([mediaParentFolderName]), not asked of `Directory.parent`: two
    // spelling rules in one address is what let the process hint come back
    // `.` where the platform does not know `\` (Linux CI, 2026-09-21).
    parentFolderName: mediaParentFolderName(folderPath),
  );
}
