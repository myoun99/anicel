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

/// The container's **유저설정** folder: `<container>/Settings/<fileName>`.
///
/// 🚨★★★**THE THIRD TENANT GETS A ROOM TOO** (유저 2026-09-07, naming the
/// three: 이사대기 · 휘발성 · **유저설정**). Fifteen loose files and a
/// `brush_tips/` folder sat at the container root beside the folders that
/// hold project data, so 「what is mine and what is the app's working
/// space」 could only be answered by knowing each name.
///
/// ⛔It is a LOCATION, not a lifetime — these live forever, which is
/// exactly what the other two rooms do not. Putting them under a name says
/// so without a comment.
String appSettingsFilePath(String fileName) =>
    appSupportFilePath('Settings/$fileName');

/// Every entry [appSettingsFilePath] is asked for, so the migration below
/// knows what to look for at the old address.
///
/// ⚠️**One list, and a test keeps it honest.** A store that asks for a
/// name missing here would simply never be migrated — harmless for a NEW
/// setting (there is nothing at the old address) and silent for an old
/// one, which is the bad half. `settings_live_in_one_room_test` reads the
/// `appSettingsFilePath('…')` literals out of the source and compares.
const List<String> appSettingsEntries = <String>[
  'accent_settings.json',
  'audio_sync_settings.json',
  'brush_hand_settings.json',
  'brush_presets.json',
  'brush_tips',
  'color_palette.json',
  'export_settings.json',
  'input_settings.json',
  'language_settings.json',
  'recent_projects.json',
  'save_settings.json',
  'shortcut_overrides.json',
  'ui_scale.json',
  'workspace_colors.json',
  'workspace_layout.json',
];

/// Moves any settings entry still at the container root into `Settings/`.
///
/// 🚨★★★**MOVE ONLY INTO AN EMPTY SPOT, AND NEVER DELETE.** 유저
/// 2026-09-07 approved this on exactly that shape: these are not project
/// files, they are the shortcut overrides, brush presets, imported tips
/// and palettes on somebody's machine, and 「새로 만들 수는 있어도 되돌릴
/// 수는 없는」 things. So every step is a `rename` into a name that does
/// not exist yet — if the destination is already there the old one is left
/// alone, and if the rename fails nothing happened at all. There is no
/// delete anywhere in this function, by construction rather than by care.
///
/// ⚠️Called ONCE PER LAUNCH, before anything reads a setting. Answers how
/// many entries moved (diagnostics and the test).
///
/// 🚨★★★**[containerRoot] IS NOT A CONVENIENCE — IT IS WHY A TEST CAN
/// EXIST AT ALL.** [appSupportFilePath] deliberately does NOT redirect
/// under `FLUTTER_TEST` (only the two stores that need a sandbox ask for
/// the redirected form), so a test that called this with the real root
/// would move the DEVELOPER'S OWN settings — the exact irreversible thing
/// the user weighed before approving this. ⛔Production passes nothing.
int migrateSettingsIntoTheirRoom({String? containerRoot}) {
  var moved = 0;
  String under(String name) =>
      containerRoot == null ? appSupportFilePath(name) : '$containerRoot/$name';
  for (final name in appSettingsEntries) {
    final from = under(name);
    final to = under('Settings/$name');
    final source = FileSystemEntity.typeSync(from, followLinks: false);
    if (source == FileSystemEntityType.notFound) {
      continue;
    }
    if (FileSystemEntity.typeSync(to, followLinks: false) !=
        FileSystemEntityType.notFound) {
      // Somebody is already there. ⛔The old one stays: choosing between
      // two copies of a person's settings is not a choice code gets to
      // make silently.
      continue;
    }
    try {
      Directory(under('Settings')).createSync(recursive: true);
      if (source == FileSystemEntityType.directory) {
        Directory(from).renameSync(to);
      } else {
        File(from).renameSync(to);
      }
      moved += 1;
    } on Object {
      // A locked file (a sync client mid-upload), a permission, a
      // read-only volume: the entry stays where it is and keeps working,
      // and the next launch tries again.
    }
  }
  return moved;
}

/// [appSettingsFilePath] with the test sandbox, for the two stores that
/// need one (a test run must not read the developer's own recents or
/// export defaults).
String testRedirectedAppSettingsPath(
  String fileName, {
  required String sandbox,
}) => testRedirectedAppSupportPath('Settings/$fileName', sandbox: sandbox);
