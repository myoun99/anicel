import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/project.dart';
import '../../models/project_font_file.dart';
import '../font_library_service.dart' show isFontLibraryFileName;
import '../persistence/anicel_incremental_writer.dart'
    show
        AnicelZipLayout,
        anicelCrc32Finish,
        anicelCrc32Start,
        anicelCrc32Update;
import '../persistence/anicel_project_archive.dart';
import '../persistence/media_staging_store.dart';
import 'media_byte_source.dart';
import 'project_media_sources.dart'
    show entriesLeftBehind, readableAnicelLayout;

/// WHAT A SAVE SHOULD DO ABOUT THE FONTS A PROJECT CARRIES (R9-rest, the
/// text tool's faces): the entry names the project may hold, and where the
/// bytes of each one that can be read are right now.
///
/// 🚨TWO FIELDS, ASKED TWO QUESTIONS. [held] is every font file registered
/// with the project (`Project.fonts`) — WHAT LEAVES is asked of it, and of
/// nothing else. [entries] is the ones whose bytes could be found — what
/// the save can write. A font whose bytes are nowhere this machine can
/// reach is held and has no entry: the save writes nothing for it, takes
/// nothing away, and does not fail.
///
/// ⛔Not one map whose keys answer both, as a conform's is
/// (`ProjectConforms`: "one field cannot disagree with itself" — and its
/// second set was buried there). That works for a conform because losing
/// one to a wrong "nothing here" costs a rebuild. A font cannot be made
/// again and may be on no device but the one it came from, so what takes it
/// out of a file has to be the one thing that is a person's decision — the
/// project's own list (유저 2026-10-06: 「뺄때까지 두는게 맞지않나 싶은데.
/// 글꼴을 사실상 등록하는거잖아」) — and never whether this save happened to
/// find bytes: a file that could not be read at that moment would otherwise
/// read as a font taken out. ⚠️[held] is a pure reading of the list, with
/// one name a font, so it cannot keep what the list let go of — which is
/// how the conforms' second set leaked.
@immutable
class ProjectFontsToStore {
  const ProjectFontsToStore({required this.held, required this.entries});

  /// A project that carries no font: every font entry in the file leaves.
  const ProjectFontsToStore.none() : held = const {}, entries = const {};

  /// Every archive ENTRY NAME the project may hold.
  final Set<String> held;

  /// **Archive entry name** → where those bytes are right now
  /// ([storedFontBytesFor]).
  final Map<String, MediaByteSource> entries;
}

/// The fonts of [project] this app keeps bytes for: the ones registered
/// under a name a font file can be kept under ([isFontLibraryFileName]).
///
/// 🚨A PROJECT IS A FILE FROM ANYWHERE, and the name it gives a font becomes
/// a file's name here — in this run's room, in this device's library. So a
/// name that is not of the one shape this app mints is not kept under, not
/// looked for and not let go of: such a font is in the project's list and
/// nowhere else. (The list itself is not set right: `Project.fonts`.)
Iterable<ProjectFontFile> projectFontsKept(Project project) =>
    project.fonts.where((font) => isFontLibraryFileName(font.carriedAs));

/// The archive entry names [project] may hold of its fonts — what
/// [ProjectFontsToStore.held] is, and what the session remembers a file
/// was written with (`ProjectFile.fontsInFile`).
Set<String> projectFontEntryNames(Project project) => {
  for (final font in projectFontsKept(project))
    anicelFontEntryName(font.carriedAs),
};

/// A project file as it is read NOW: where it is, and the layout its
/// entries lie in. One thing, because neither means anything without the
/// other — an entry's place is a place in THAT file, as it stood at THAT
/// read.
typedef ProjectFileAsRead = ({String path, AnicelZipLayout layout});

/// The project file at [path] as it reads now — null when there is none to
/// read ([readableAnicelLayout]).
ProjectFileAsRead? projectFileAsRead(String? path) {
  final layout = readableAnicelLayout(path);
  return layout == null ? null : (path: path!, layout: layout);
}

/// Where the bytes of the font a project carries as [carriedAs] are right
/// now, in the ONE ORDER every reader and the save look in — the order a
/// carried medium's are looked for in (`storedMediaBytesFor`):
///
/// the project file's own entry ([projectFile]);
/// the copy this run's room keeps of a font a save took out of that file
/// ([MediaStagingStore.keepLeftBehind]); the file this device's library
/// keeps under the same name ([deviceFontFile] —
/// `FontLibraryService.pathOfFontHeld`, which answers by the disk).
///
/// One name is one set of bytes wherever it is found (`ProjectFontFile`),
/// so the order decides nothing but which copy is read. Null when they are
/// nowhere this machine can reach — and for a name this app keeps nothing
/// under ([projectFontsKept]).
MediaByteSource? storedFontBytesFor(
  String carriedAs, {
  required ProjectFileAsRead? projectFile,
  required MediaStagingStore? staging,
  required String? Function(String file) deviceFontFile,
}) {
  if (!isFontLibraryFileName(carriedAs)) {
    return null;
  }
  final inFile = projectFile?.layout.entryNamed(
    anicelFontEntryName(carriedAs),
  );
  if (inFile != null) {
    return MediaArchiveBytes.ofEntry(
      archivePath: projectFile!.path,
      entry: inFile,
    );
  }
  final kept = staging?.findNamed(carriedAs);
  if (kept != null) {
    return MediaAppFileBytes(path: kept.path, framed: kept.framed);
  }
  final onDevice = deviceFontFile(carriedAs);
  return onDevice == null ? null : MediaFileBytes(onDevice);
}

/// What a save of [project] onto — or away from — the file at
/// [projectFilePath] should do about its fonts ([storedFontBytesFor] for
/// each).
///
/// ⚠️Resolved fresh at every save, like the media sources: the archive
/// half is a byte range, and offsets belong to one layout.
ProjectFontsToStore projectFontSources({
  required Project project,
  required String? projectFilePath,
  required MediaStagingStore? staging,
  required String? Function(String file) deviceFontFile,
}) {
  final fonts = projectFontsKept(project).toList();
  if (fonts.isEmpty) {
    return const ProjectFontsToStore.none();
  }
  final projectFile = projectFileAsRead(projectFilePath);
  return ProjectFontsToStore(
    held: {for (final font in fonts) anicelFontEntryName(font.carriedAs)},
    entries: {
      for (final font in fonts)
        anicelFontEntryName(font.carriedAs): ?storedFontBytesFor(
          font.carriedAs,
          projectFile: projectFile,
          staging: staging,
          deviceFontFile: deviceFontFile,
        ),
    },
  );
}

/// The names — as the room keeps them ([MediaStagingStore.findNamed]) — of
/// the fonts a save that was handed [fonts] has put, or left, in its file:
/// the ones it had bytes for.
///
/// What that save lets go of in the room afterwards: a copy the room kept
/// of a font a save took out, which an undo then brought back, is a second
/// copy once the file holds it again (유저 08-27, of every copy this app
/// makes for itself: 「사본 남으면 진짜 용서안할게」).
Iterable<String> fontNamesStored(ProjectFontsToStore fonts) => [
  for (final name in fonts.entries.keys)
    if (name.startsWith(anicelFontEntryPrefix))
      name.substring(anicelFontEntryPrefix.length),
].where(isFontLibraryFileName);

/// The font entries of the project file at [projectFilePath] that a write
/// holding [held] does not carry forward — those its record ([fontsInFile],
/// the names it was last written or opened with) holds that the project's
/// list no longer says — and where each lies in that file now.
///
/// 🚨WHAT A SAVE HANDS TO THE ROOM BEFORE IT WRITES, beside the media it
/// leaves behind (`mediaLeftBehind`), and by the law that was written for
/// those — 유저 2026-09-25 「이번 실행의 앱 룸으로 옮겨 둔다」 (board
/// `undo-after-save-reads-the-original`): taking a font out of a project is
/// a step of history, an undo brings its name back, and the file will not
/// hold its bytes. On a machine that was never brought that font they would
/// then be nowhere.
///
/// ⛔Only an entry under a name this app keeps a file under
/// ([projectFontsKept]): what comes back is WRITTEN, under that name, into
/// the room — so the name is asked here, where it becomes a file's, and
/// not trusted to whoever made the record.
List<MediaLeftBehind> fontsLeftBehind({
  required String? projectFilePath,
  required Set<String> fontsInFile,
  required Set<String> held,
}) => entriesLeftBehind(
  projectFilePath,
  {
    for (final name in fontsInFile.difference(held))
      if (name.startsWith(anicelFontEntryPrefix) &&
          isFontLibraryFileName(name.substring(anicelFontEntryPrefix.length)))
        name,
  },
  under: anicelFontEntryPrefix,
);

/// What [read] makes of where [find] says a font's bytes are — and, when
/// they will not read there, of where [find] says they are THEN: looked
/// for and read again, up to [attempts] times in all.
///
/// 🚨WHY AGAIN: WHERE A FONT'S BYTES ARE IS TRUE FOR A MOMENT, because a
/// save can end between the look and the read.
/// · A range into the project file is of one layout, and a save may pack
///   the file under the very read ([readStoredFontBytes] checks the
///   entry's CRC, and answers null for bytes that are not the entry's).
///   The font is then somewhere else in the file, and whole.
/// · A copy in the ROOM is let go of by the save that puts its bytes into
///   the file (`ProjectFileDoor`, `MediaStagingStore.retireNamed`): found a
///   moment before that save ended, it is gone when it is opened — and the
///   font is in the file, where the next look finds it first
///   ([storedFontBytesFor]).
///
/// ⚠️Bytes that stay where they were said to be and still will not read
/// are a font nobody has — [attempts] is where this gives up on them.
Future<Uint8List?> readLookingAgain({
  required MediaByteSource? Function() find,
  required Future<Uint8List?> Function(MediaByteSource source) read,
  int attempts = 3,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    final source = find();
    if (source == null) {
      return null;
    }
    final bytes = await read(source);
    if (bytes != null) {
      return bytes;
    }
  }
  return null;
}

/// The bytes [source] holds — [source] being where a font a project carries
/// was found ([storedFontBytesFor]) — read a block at a time, so that a
/// font of tens of megabytes does not hold the UI isolate while it is read.
/// Null when they would not read, or are not the bytes the project file
/// says its entry holds.
///
/// 🚨AN ENTRY OF THE PROJECT FILE IS CHECKED AGAINST ITS OWN CRC. Its range
/// was resolved from one layout, and a save can pack the file while this
/// reads it: what slid into that window is whole, well-formed, and
/// somebody else's bytes. A null from here is then a font to look for
/// AGAIN, where it is now (`ProjectFile.fontBytes`) — the tripwire a
/// carried sound's conform is read behind (`mediaByteSourceFor`).
Future<Uint8List?> readStoredFontBytes(MediaByteSource source) async {
  try {
    return switch (source) {
      MediaArchiveBytes() => await _readEntryChecked(source),
      MediaFileBytes(:final path) ||
      MediaAppFileBytes(:final path, framed: false) => await File(
        path,
      ).readAsBytes(),
      // Nothing keeps a font framed: these are not a font's bytes.
      MediaAppFileBytes() || MediaFramedBytes() => null,
    };
  } on Object {
    return null;
  }
}

Future<Uint8List?> _readEntryChecked(MediaArchiveBytes entry) async {
  final bytes = Uint8List(entry.length);
  var filled = 0;
  var running = anicelCrc32Start;
  final blocks = File(
    entry.archivePath,
  ).openRead(entry.dataOffset, entry.dataOffset + entry.length);
  await for (final block in blocks) {
    bytes.setRange(filled, filled + block.length, block);
    filled += block.length;
    running = anicelCrc32Update(
      running,
      block is Uint8List ? block : Uint8List.fromList(block),
    );
  }
  final expected = entry.entryCrc32;
  final whole =
      filled == bytes.length &&
      (expected == null || anicelCrc32Finish(running) == expected);
  return whole ? bytes : null;
}
