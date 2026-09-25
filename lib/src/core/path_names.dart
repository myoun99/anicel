/// The last segment of [path], for either platform's separator — the same
/// normalise-then-split this repo already uses for asset paths.
///
/// Lives in `core/` because both halves of the app ask it: the services
/// that plan an import or stage a file cannot import `ui/`, and the
/// dialogs that name a picked file are in `ui/`. Seven hand-written
/// spellings of it drifted apart before this file existed — one of them
/// (the recent-projects row) split on `/` only, so a Windows path came
/// back whole.
String fileNameOfPath(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
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
