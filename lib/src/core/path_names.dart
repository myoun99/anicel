/// The last segment of [path], for either platform's separator — the same
/// normalise-then-split this repo already uses for asset paths.
///
/// Lives in `core/` because both halves of the app ask it: the services
/// that plan an import or stage a file cannot import `ui/`, and the
/// dialogs that name a picked file are in `ui/`. Seven hand-written
/// spellings of it drifted apart before this file existed — one of them
/// (the recent-projects row) split on `/` only, so a Windows path came
/// back whole. ↩️Five more stood after it, found with the save's folder
/// (2026-10-08): a conform's name, a project's name without its extension
/// (the old assets folder), the notice naming that folder, a recent's
/// bookmark, and an opened copy's extension — which split on the platform's
/// separator alone. They ask here now, and `path_names_test` counts the
/// files that cut a path.
String fileNameOfPath(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}

/// The folder [path] stands in, for either platform's separator — the half
/// [fileNameOfPath] leaves off. Empty when [path] names no folder at all (a
/// bare file name). A root keeps its slash: `C:/a.png` stands in `C:/`, not
/// in `C:` — which a window asked to open there reads as 「wherever that
/// drive last was」.
///
/// ↩️Save As spelled this out twice to find where its window opens; it asks
/// here now (2026-10-07). The conform cache spelled it a third time, to
/// make a folder its writer makes for itself — that line went instead.
/// ↩️The save spelled it a fourth time, as a prefix to join names onto
/// (`AnicelFileService._parentDirectory`), and answered differently: `.` for
/// a bare name, `C:` for a root — and `.` for `/a.anicel` too, the working
/// directory rather than the root, so a project kept at the top of a Mac's
/// or Linux's disk kept none of its media by the relative road. It asks here
/// and joins with [pathInFolder] now (board
/// `the-save-keeps-its-own-folder-of-a-path`, 2026-10-08).
String folderOfPath(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final slash = normalized.lastIndexOf('/');
  if (slash < 0) {
    return '';
  }
  final folder = normalized.substring(0, slash);
  return folder.isEmpty || folder.endsWith(':') ? '$folder/' : folder;
}

/// [name] — a path relative to [folder] — inside [folder], as
/// [folderOfPath] answers folders: an empty folder (a bare file name's)
/// adds nothing, and a root's slash is not doubled — `C:/` and `a.wav` are
/// `C:/a.wav`, `/` and `a.wav` are `/a.wav`.
String pathInFolder(String folder, String name) {
  if (folder.isEmpty) {
    return name;
  }
  return folder.endsWith('/') ? '$folder$name' : '$folder/$name';
}

/// FNV-1a over [text] — the one hash a derived name in the app is built
/// from, so two of them cannot disagree about what "the same path" means.
///
/// 🚨★★★**ONE, AND IT SAID SO WHILE THERE WERE THREE** (audit 09-25): the
/// archive's media entry names and the staging room's file names each
/// spelled this loop out for themselves, beside `AppSave.pathHash` whose
/// doc called itself the one. It lives here now, where every layer can ask.
///
/// 🪦It had a sibling, `encodeProjectKey`, that turned a project path into
/// `basename.<hash>` for the two per-project folders. Both are gone with
/// the recovery snapshots.
int pathHash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
