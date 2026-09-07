import 'dart:io';

/// The app-support path for [fileName]:
/// `<base>/anicel/<fileName>`, where base is `%APPDATA%` on
/// Windows, `$HOME` or `%USERPROFILE%` elsewhere, and the temp directory as
/// a last resort.
///
/// Every settings store and file service resolves its default location
/// through here so "where app state lives" is one fact, not a dozen copies
/// of the same path assembly.
///
/// 🚨**IT IS NOT ONLY SETTINGS, and this doc used to claim「never project
/// data」.** What actually lives here today:
///
/// • fourteen settings files (accent, audio sync, brush hand, brush
///   presets, colour palette, export, input, language, recent projects,
///   save, shortcut overrides, UI scale, workspace colours, layout)
/// • `brush_tips/` — the user's own tip images
/// • `Recovery/` — **recovery snapshots, which are project data.** This is
///   where the autosave sidecar went when it stopped living beside the
///   project file as `<project>.anicel.autosave`; that path is still READ
///   so a crash on an older build is still offered.
/// • `Conformed/` — **audio conformed from project media**, also project
///   data, and the one entry the user can point somewhere else.
/// • `Sessions/<pid>/` — **one room per RUN of the app**, holding staged
///   media on its way into the next save and volatile payloads that die
///   with the run. See [SessionScratch].
///
/// ⚠️So a proposal to stage something project-shaped here is not asking
/// for a new category — three of these already are. What it IS asking for
/// is a lifetime: settings live forever, `Recovery` is swept, `Conformed`
/// is a cache, and `Sessions/` is the shortest of the four — one run.
/// Anything new has to say which it is.
///
/// 🚨유저 2026-09-07 named the tenants this container should have: **이사
/// 대기**(waiting to move into the project file), **휘발성**(gone when the
/// session closes) and **유저설정**. The first two are `Sessions/`; the
/// third is everything else listed above bar the two project-data
/// entries, which D and E are moving out.
String appSupportFilePath(String fileName) {
  final environment = Platform.environment;
  final base =
      environment['APPDATA'] ??
      environment['HOME'] ??
      environment['USERPROFILE'] ??
      Directory.systemTemp.path;
  final normalizedBase = base.replaceAll('\\', '/');
  return '$normalizedBase/anicel/$fileName';
}

/// [appSupportFilePath], except that a test run gets its own sandbox under
/// the temp directory: `<temp>/qa_test_<sandbox>_<pid>/<fileName>`.
///
/// Every store that resolves an app-support path goes through here rather
/// than writing the `FLUTTER_TEST` branch out again. Tests reach these
/// stores through the PRODUCTION wiring, so without the redirect a test run
/// would read and write the real user's files — and `pid` keeps two runs on
/// one machine out of each other's sandbox.
String testRedirectedAppSupportPath(
  String fileName, {
  required String sandbox,
}) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    final temp = Directory.systemTemp.path.replaceAll('\\', '/');
    return '$temp/qa_test_${sandbox}_$pid/$fileName';
  }
  return appSupportFilePath(fileName);
}
