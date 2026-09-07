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
