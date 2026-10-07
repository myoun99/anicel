import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/path_names.dart';
import '../../services/persistence/app_documents.dart';
import '../../services/persistence/app_export_settings.dart'
    show ExportDestination, ExportHandOver, ExportIntoFolder, ExportToFile;
import '../../services/persistence/folder_grant.dart';
import '../../services/persistence/move_into_folder.dart';
import '../../services/persistence/provider_documents.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import 'open_file_flow.dart';
import 'app_confirm_dialog.dart';

/// PICK-2: the folder request with its failures spoken out loud.
///
/// [FolderPicker.pick] deliberately reports four distinct outcomes; this is
/// where three of them become words. It exists because the alternative —
/// every caller writing `if (path == null) return;` — turns a Drive folder
/// with no filesystem path, a missing storage permission and a broken
/// channel into the same nothing-happened, which is precisely the failure
/// mode the old `on Object { safe default }` habit produced.
///
/// Returns a real directory path, or null when the user backed out or was
/// told why they cannot use what they chose.
Future<String?> pickFolderForUser(
  BuildContext context, {
  String? initialDirectory,
}) async => (await pickFolderGrantForUser(
  context,
  initialDirectory: initialDirectory,
))?.path;

/// Whether a folder pick has to clear a storage grant before it may even
/// open the picker.
///
/// Android alone: everywhere else the OS either attaches no permission to
/// a path (Windows, Linux) or grants one with the pick itself (iOS,
/// macOS). Pure over the OS name so BOTH answers can be pinned from the
/// Windows workstation this app is written on — the same seam
/// `FolderPicker.scopedForPlatform` uses, and for the same reason: a test
/// asserting `Platform.isAndroid` here would be asserting `false == false`.
bool folderPickNeedsStorageGrant(String operatingSystem) =>
    operatingSystem == 'android';

/// PICK-6: whether a CANCELLED folder pick might really be a person looking
/// for Google Drive, which no folder window can give them.
///
/// On Apple the Open button is DEAD in Drive: the delegate never fires, so
/// the app receives a plain cancel and cannot tell the two apart. On
/// Android Drive is not even LISTED — the system's folder window shows only
/// the providers that can hand over a folder, and Drive's cannot (Google's
/// own tracker, issue 135636079) — so a person looking for it can only
/// cancel. 🪦Android was left out until 2026-09-27 on the belief that its
/// window lists Drive and answers `noFilesystemPath` for it; that answer
/// only ever comes from a provider that DOES hand over a folder with no
/// path behind it, and it keeps its own notice.
///
/// Its own predicate, not borrowed from one that names the same platforms
/// for another reason — that would leave this silently wrong the day either
/// answer moves.
bool folderPickCancelMayBeDrive(String operatingSystem) =>
    operatingSystem == 'ios' ||
    operatingSystem == 'macos' ||
    operatingSystem == 'android';

/// What the Drive notice tells a person on [operatingSystem] to use instead:
/// where a folder CAN come from there — iCloud Drive and Dropbox on Apple
/// (실측 2026-08-13, iPhone), this device on Android, where a sync app can
/// keep a Drive folder.
String folderPickDriveNoticeFor(String operatingSystem) =>
    operatingSystem == 'android'
    ? AppText.strings.folderPickDriveNoticeAndroid
    : AppText.strings.folderPickDriveNotice;

/// Test seam for the OS the flow branches on.
///
/// The gate's whole job is to keep an Android user out of a picker that
/// would refuse every folder, and the notice it raises had NO coverage
/// after the in-app browser (its only test consumer) was deleted. Reset in
/// `test/flutter_test_config.dart` — a top-level left set by one file
/// would hand its answer to every file after it.
@visibleForTesting
String? debugOperatingSystemOverride;

String get _operatingSystem =>
    debugOperatingSystemOverride ?? Platform.operatingSystem;

/// Whether the Drive notice has already been shown this session.
///
/// Once, not once per picker: it is the same fact wherever folder mode
/// survives, and a user who has read it does not need it again on the next
/// import.
///
/// ⚠️Reset in `test/flutter_test_config.dart` — a top-level left true by one
/// test would silence the notice for every file after it.
@visibleForTesting
bool debugDriveNoticeShown = false;

bool get _driveNoticeShown => debugDriveNoticeShown;
set _driveNoticeShown(bool value) => debugDriveNoticeShown = value;

/// The same flow, keeping the whole grant.
///
/// The project open and Save-As paths need the BOOKMARK as well as the path:
/// on Apple platforms a recent-projects entry is refused after relaunch
/// unless the app can produce the security-scoped token it was granted. Every
/// other caller only ever wants somewhere to write, so [pickFolderForUser]
/// stays the short spelling.
Future<FolderGrant?> pickFolderGrantForUser(
  BuildContext context, {
  String? initialDirectory,
}) async {
  // Android resolves the system tree back to a real path, and that probe
  // fails without the All-Files grant — which would surface as "this
  // location has no folder path" and send the user hunting for a different
  // folder when the folder was never the problem. Ask first.
  if (!await _storageGrantCleared(context)) {
    return null;
  }
  final grant = await FolderPicker.pick(initialDirectory: initialDirectory);
  if (!context.mounted) {
    return null;
  }
  return _spokenFor(context, grant, folderMode: true);
}

/// PICK-5: the same flow for FILES, keeping the grants whole.
///
/// Every caller here used to reach `file_selector` directly, and on both
/// mobile platforms that plugin COPIES the chosen file — into the iOS
/// sandbox (`.import` mode) or into `getCacheDir()` on Android — and hands
/// back the copy. An asset imported "by reference" therefore referenced a
/// temporary duplicate that the next cache sweep removes. Routing through
/// [FolderPicker.pickFiles] is what makes a reference reference the file
/// the user actually chose.
///
/// 🚨 The GRANT is the difference between a reference that survives a
/// relaunch and one that does not. `pickFiles` mints a security-scoped
/// bookmark on Apple platforms, and a path-only spelling of this call
/// threw it away at the door — so an asset imported by REFERENCE recorded
/// a path, and a recorded path on iOS or macOS is refused the next time
/// the app starts. Every piece of the machine existed; the answer simply
/// never reached the code that could write it down. ⚠️That spelling is
/// GONE (2026-09-10: nothing in the app called it, and a door that drops
/// the token is a door someone reaches for by accident) — there is one
/// file door and it hands back what it was granted, paths included.
///
/// Opening a PROJECT wants it for the same reason: a recent-projects entry
/// is refused after relaunch unless the app can produce the token it was
/// granted.
///
/// [acceptsDocuments] answers ONE question — can the caller work from a
/// file with no filesystem path (PICK-7, Drive on Android)? The media
/// import can: it reads one through a copy of its own and carries it
/// (유저 2026-09-27: 「안한것 다 해줘. 임포트 드라이브로 할때라던가」). A
/// relink cannot — a reference has to point at a file that is still there
/// next time — and is told what a Drive folder is told.
///
/// Empty when the user backed out or was told why they cannot use what
/// they chose.
Future<List<FolderGrant>> pickFileGrantsForUser(
  BuildContext context, {
  required List<String> supportedExtensions,
  bool allowMultiple = false,
  bool acceptsDocuments = false,
}) async {
  final grants = await _pickedFileGrants(
    context,
    allowMultiple: allowMultiple,
  );
  if (grants == null || !context.mounted) {
    return const [];
  }
  return _grantsTheCallerTakes(
    context,
    grants,
    supportedExtensions,
    acceptsDocuments: acceptsDocuments,
  );
}

/// The PROJECT door's pick (PICK-7): one file — and a file with no
/// filesystem path is taken too, as the provider document it is. A project
/// opens one through a working copy ([ProviderDocuments]).
///
/// Null when the user backed out or was told why they cannot use what
/// they chose.
Future<FolderGrant?> pickProjectGrantForUser(
  BuildContext context, {
  required List<String> supportedExtensions,
  String? initialDirectory,
}) async {
  final grants = await _pickedFileGrants(
    context,
    allowMultiple: false,
    initialDirectory: initialDirectory,
  );
  if (grants == null || !context.mounted) {
    return null;
  }
  final taken = await _grantsTheCallerTakes(
    context,
    grants,
    supportedExtensions,
    acceptsDocuments: true,
  );
  return taken.isEmpty ? null : taken.first;
}

/// The pick itself, behind the storage gate, with a failure that answers
/// for the whole batch said out loud — null when there is nothing to take.
Future<List<FolderGrant>?> _pickedFileGrants(
  BuildContext context, {
  required bool allowMultiple,
  String? initialDirectory,
}) async {
  // The same gate as the folder flow, for the same reason: Android resolves
  // the system document back to a real path, and that probe fails without
  // the All-Files grant.
  if (!await _storageGrantCleared(context)) {
    return null;
  }
  // 🚨★★★**NO TYPE FILTER — the dialog shows everything.** 유저 2026-08-29:
  // 「픽커는 어떤플랫폼이든 어떤 확장자던 선택할수 있게하고, 대응만
  // 지원안되는 확장자면 그 때 해당 파일 지원안된다고 안내창 띄우게」.
  //
  // ⛔`acceptedTypeGroups` used to come in from every caller, and it
  // answered TWO questions with one value: what the dialog SHOWS and what
  // the caller ACCEPTS. Those are different questions and the user has
  // separated them — a greyed-out file is a wall with no explanation,
  // while a notice can name the file and the formats.
  final grants = await FolderPicker.pickFiles(
    acceptedTypeGroups: const [],
    allowMultiple: allowMultiple,
    initialDirectory: initialDirectory,
  );
  if (!context.mounted) {
    return null;
  }
  // Never empty, and a failure arrives as ONE grant carrying the status —
  // so the first entry answers for the batch. A document answers for
  // itself ([_grantsTheCallerTakes]): a batch can hold real files beside it.
  if (grants.first.document == null &&
      await _spokenFor(context, grants.first) == null) {
    return null;
  }
  return grants;
}

/// What the caller takes of [grants]: the files of a kind it supports —
/// judged by NAME, a document's own, since its URI says nothing of what it
/// is — and the documents only where [acceptsDocuments]. What it turns away
/// is said once for the documents and once for the unsupported files.
///
/// A document taken is REMEMBERED here, by its name: every step after the
/// pick has only its URI, and the copy it is read from is named after it
/// ([ProviderDocuments.copyIn]) — an asset or a tab called by a URI's id
/// would be the result of a caller forgetting.
Future<List<FolderGrant>> _grantsTheCallerTakes(
  BuildContext context,
  List<FolderGrant> grants,
  List<String> supportedExtensions, {
  required bool acceptsDocuments,
}) async {
  final accepted = <FolderGrant>[];
  final refused = <String>[];
  var documentsRefused = false;
  for (final grant in grants) {
    final document = grant.document;
    if (document != null && !acceptsDocuments) {
      documentsRefused = true;
      continue;
    }
    final name = grant.path ?? document?.name;
    if (name == null) {
      continue;
    }
    if (fileIsSupported(name, supportedExtensions)) {
      if (document != null) {
        ProviderDocuments.remember(document);
      }
      accepted.add(grant);
    } else {
      refused.add(name);
    }
  }
  if (documentsRefused) {
    await _showNoFilesystemPathNotice(context);
    if (!context.mounted) {
      return const [];
    }
  }
  if (refused.isNotEmpty) {
    await noticeUnsupportedFiles(context, refused, supportedExtensions);
  }
  return accepted;
}

/// PICK-6: hands a finished file to the location the user picks — the road
/// of the SCOPED platforms, which have no save dialog that answers with a
/// path: the file is made first and the OS places it. Save As goes through
/// it there, and so does every file that is handed over once it is made.
///
/// ⚠️[sourcePath] is CONSUMED on success — the file is MOVED, not copied.
/// From then on the returned grant's path is the only copy.
///
/// The grant is returned whole rather than as a path, because Save As is
/// exactly the caller that needs the bookmark: it is what lets every later
/// save write there with no UI at all.
///
/// [keepsSavingThere] is [placeStagedFileForUser]'s question — will the
/// caller go on saving into what it placed? — and it is what Android's
/// storage grant hangs on. A file that is SAVED AGAIN is rewritten in place
/// through its real path, and Android resolves none without the grant, so
/// that caller is asked for it before the window opens. A file that is
/// handed over and never written again is poured into the document the
/// window made, which asks no grant at all.
///
/// ↩️Every caller was asked for the grant, because this was Save As's road
/// alone when the gate went in (2026-08-14); the exports that came to use
/// it inherited a permission nothing of theirs needed.
Future<FolderGrant?> exportFileForUser(
  BuildContext context, {
  required String sourcePath,
  required bool keepsSavingThere,
  String? suggestedName,
}) async {
  if (keepsSavingThere && !await _storageGrantCleared(context)) {
    return null;
  }
  final grant = await FolderPicker.exportFile(
    sourcePath: sourcePath,
    suggestedName: suggestedName,
  );
  if (!context.mounted) {
    return null;
  }
  // A document is a place the bytes LANDED (PICK-7: poured in through the
  // provider), not a refusal.
  return _spokenFor(context, grant, acceptsDocuments: true);
}

/// What became of finished outputs handed to the user
/// ([handOverFilesForUser]).
enum HandOver {
  /// They stand where the user put them — moved there, or poured into the
  /// document a save window made. What was handed over is spent.
  placed,

  /// The user let them go — backing out of the window is not that, it is
  /// asked about ([placedOrLetGo]) — or the caller was torn down.
  declined,
}

/// The windows that can take finished outputs.
enum HandOverRoad {
  /// iOS's export picker: any number, files and folders alike, and the mode
  /// that reaches Google Drive (실측 2026-08-13 — folder mode does not).
  exportPicker,

  /// Android's save window: ONE file, anywhere a document can be made —
  /// Google Drive included.
  saveWindow,

  /// A folder window, and the outputs moved there: Android's road for
  /// SEVERAL finished outputs, which only a queue ends on — several jobs of
  /// one file each (F-221-Q5, 유저 2026-10-06: 「큐가 끝날때 한번 위치
  /// 묻는건 어떻지?」). No Android window places more than one file, and
  /// its folder window does not list Google Drive.
  folderWindow,
}

/// The road finished outputs take to the user on [operatingSystem] —
/// [oneFile] when they are a single file. Pure over the OS name so every
/// road can be pinned from the Windows workstation this is written on,
/// the seam [folderPickNeedsStorageGrant] uses for the same reason.
///
/// ⛔ONLY THE PLATFORMS THAT HAND OVER HAVE A ROAD. A desktop is asked
/// before anything is made, whatever it is ([outputsAskedTheirPlaceFirst]),
/// so nothing finished waits for a window there — asking for its road is a
/// caller that made outputs it had nowhere to put.
///
/// 🪦Two roads went with F-221 (유저 2026-10-06, 「최종통일안」): Android's
/// share sheet for several files — it unpacked a folder into loose files,
/// and only OFFERED them — and the desktops' 「make, then a folder window
/// moves them」.
HandOverRoad handOverRoadFor(
  String operatingSystem, {
  required bool oneFile,
}) => switch (operatingSystem) {
  'ios' => HandOverRoad.exportPicker,
  'android' => oneFile ? HandOverRoad.saveWindow : HandOverRoad.folderWindow,
  _ => throw StateError(
    '$operatingSystem is asked where outputs go before they are made; '
    'nothing is handed over there.',
  ),
};

/// Whether outputs can be asked their place BEFORE they are made on
/// [operatingSystem] — [oneFile] when the run writes a single file.
///
/// The ORDER is the OS's (F-221, closed 2026-10-06 — 유저: 「최대한
/// 멀티플랫폼 통일하고싶음」): a place is asked at the earliest moment the
/// platform lets it be asked.
///
/// - ONE FILE is asked first where a save window answers with a path and
///   makes nothing ([FolderPicker.aSaveWindowAnswersAPathOn]): the
///   desktops, macOS among them (유저: 「맥도 그럼 윈도랑 통일할수있으면
///   통일」). Android's save window makes the file the moment a place is
///   picked, and iOS has no window that asks before: 「ios는 어차피 먼저
///   위치지정이 안된단거지」.
/// - SEVERAL are asked a folder first everywhere but iOS, whose folder
///   window cannot reach Google Drive — there everything is made first and
///   handed over (F-221-Q2).
///
/// Pure over the OS name, as [handOverRoadFor] is, so every platform's
/// answer is pinned from the workstation this is written on.
bool outputsAskedTheirPlaceFirst(
  String operatingSystem, {
  required bool oneFile,
}) => oneFile
    ? FolderPicker.aSaveWindowAnswersAPathOn(operatingSystem)
    : operatingSystem != 'ios';

/// [outputsAskedTheirPlaceFirst] on the machine the app runs on.
bool outputsAskedTheirPlaceFirstHere({required bool oneFile}) =>
    outputsAskedTheirPlaceFirst(_operatingSystem, oneFile: oneFile);

/// Whether a file asked its place through the save window is MADE
/// ELSEWHERE AND MOVED ONTO IT on this machine, instead of written where it
/// was told.
///
/// Where the pick is a grant — macOS's sandbox — the answer is the one path
/// the app may write: no folder made around it, no temp file beside it. The
/// writers do both, so the file is made in the run's room and one move puts
/// it where the window said ([moveFileOnto]). Windows and Linux write
/// straight at the place: a move there is a second copy across volumes for
/// nothing.
///
/// ⚠️UNVERIFIED ON DEVICE: written on the Windows workstation
/// ([FolderPicker.aSaveWindowAnswersAPathOn]).
bool get aPlacedFileIsMovedOntoItsPlaceHere => FolderPicker.grantsAreScoped;

/// The two windows [askWhereOutputsGo] opens, as functions: a folder
/// window, and a save window offering a name — each answering null when
/// the user backed out.
///
/// The system's, unless a caller hands the door its own (the export
/// window's test seam). ⛔The windows are handed in, never an ANSWER: which
/// window opens, and whether one opens at all, is the door's to say for
/// every caller.
typedef OutputPlaceWindows = ({
  Future<String?> Function(String? initialDirectory) folder,
  Future<String?> Function(String suggestedName, String? initialDirectory)
  file,
});

/// THE DOOR EVERY EXPORT ASKS ITS PLACE AT (F-221, 유저 2026-10-06: 「최대한
/// 멀티플랫폼 통일하고싶음」 — 「입구만 통일하면 됨」): what is about to be
/// written says which window, and the platform says when.
///
/// - [loneFileName] is the name of the ONE file the run writes, or null
///   when it writes several. One file is asked a save window, that name
///   written in it; several are asked a folder.
/// - A platform that can be asked before the files are made is asked HERE
///   ([outputsAskedTheirPlaceFirst]), and the answer is an [ExportPlace].
///   One that cannot answers [ExportHandOver] without a window: its
///   outputs are made first and handed over ([handOverFilesForUser]).
///
/// Null when the user backed out of the window, or was told why what they
/// chose cannot be used. [initialDirectory] is where the window opens — a
/// hint, as everywhere.
Future<ExportDestination?> askWhereOutputsGo(
  BuildContext context, {
  required String? loneFileName,
  String? initialDirectory,
  OutputPlaceWindows? windows,
}) async {
  final oneFile = loneFileName != null;
  if (!outputsAskedTheirPlaceFirst(_operatingSystem, oneFile: oneFile)) {
    return const ExportHandOver();
  }
  final ask = windows ?? _systemPlaceWindows(context);
  if (oneFile) {
    final file = await ask.file(loneFileName, initialDirectory);
    return file == null ? null : ExportToFile(file);
  }
  final folder = await ask.folder(initialDirectory);
  return folder == null ? null : ExportIntoFolder(folder);
}

/// The system's two windows ([OutputPlaceWindows]).
///
/// PICK-2: the folder has to be a durable real path — `getDirectoryPath`
/// gave a SAF tree URI on Android and threw on iOS — so it comes through
/// the app's own folder pick, which is also what opens the folder to this
/// run on macOS (the pick is the grant; nothing is kept of it, because
/// nothing is written there once the run is over).
OutputPlaceWindows _systemPlaceWindows(BuildContext context) => (
  folder: (initialDirectory) =>
      pickFolderForUser(context, initialDirectory: initialDirectory),
  file: (suggestedName, initialDirectory) async => (await pickSaveFileForUser(
    context,
    suggestedName: suggestedName,
    initialDirectory: initialDirectory,
  ))?.path,
);

/// Hands finished outputs — [paths], files or folders — to wherever the
/// user picks, AFTER they were made (drive-folder-windows-Q1, 유저
/// 2026-09-27: 「내보내기가 끝나면 드라이브로 넘긴다 — 파일 창을 거쳐」):
/// all a platform that cannot be asked first can do, and the one way an
/// export reaches Google Drive on iOS. The road is [handOverRoadFor]'s.
///
/// Backing out of the window lets nothing go: it is opened again until the
/// outputs are placed or the user says to let them go ([placedOrLetGo]).
///
/// The caller owns [paths] afterwards: gone when [HandOver.placed] (moved,
/// or poured and theirs to clear), and theirs to let go when
/// [HandOver.declined].
Future<HandOver> handOverFilesForUser(
  BuildContext context, {
  required List<String> paths,
}) async {
  final placed = await placedOrLetGo(
    context,
    () => _placedThroughItsRoad(context, paths),
  );
  return placed == null ? HandOver.declined : HandOver.placed;
}

/// [paths] through the window their road opens, once: where they landed,
/// or null when nothing was placed — the user backed out of the window, or
/// was told why it could not take them.
Future<Object?> _placedThroughItsRoad(
  BuildContext context,
  List<String> paths,
) async {
  final oneFile =
      paths.length == 1 && FileSystemEntity.isFileSync(paths.single);
  switch (handOverRoadFor(_operatingSystem, oneFile: oneFile)) {
    case HandOverRoad.exportPicker:
      final grant = await FolderPicker.exportFiles(paths);
      if (!context.mounted) {
        return null;
      }
      return _spokenFor(context, grant);
    case HandOverRoad.saveWindow:
      return exportFileForUser(
        context,
        sourcePath: paths.single,
        // Handed over, and never written again.
        keepsSavingThere: false,
      );
    case HandOverRoad.folderWindow:
      final folder = await pickFolderForUser(context);
      if (folder == null) {
        return null;
      }
      for (final path in paths) {
        moveIntoFolder(path, folder);
      }
      return folder;
  }
}

/// A FINISHED OUTPUT IS ASKED ITS PLACE UNTIL IT HAS ONE, OR THE USER LETS
/// IT GO (F-221-Q6, 유저 2026-10-07: 「취소하면 바로 묻는다 — [다시 고르기]
/// · [버리기]」).
///
/// [window] opens the window the output is handed over through and answers
/// where it landed — or null when nothing was placed: the user backed out,
/// was told why what they chose cannot be used, or would not give Android
/// the grant its folder window needs. The output is still where it was
/// made then, and it took a whole run to make — so nothing but the answer
/// to [_wouldPickAgain] lets it go, and 「다시 고르기」 opens the same
/// window again.
///
/// Null when the user let it go — or the caller was torn down, and what it
/// made goes with it.
///
/// ↩️Backing out of the window used to BE letting go: one stray press of
/// its cancel, or a grant the user had to leave the app to give, and the
/// export had to be run again (F-221-Q2).
///
/// ⚠️What [window] THROWS is not asked about — a move that failed half way
/// has placed some of what it was handed, and that is the caller's to say.
Future<T?> placedOrLetGo<T extends Object>(
  BuildContext context,
  Future<T?> Function() window,
) async {
  while (true) {
    final placed = await window();
    if (placed != null || !context.mounted) {
      return placed;
    }
    if (!await _wouldPickAgain(context)) {
      return null;
    }
  }
}

/// The question a backed-out hand-over is put: the window again, or let
/// what was made go. It stands until one of the two is pressed — walking
/// away from it would be a third answer, and that one throws the output
/// away without anyone having said so.
///
/// True for 「다시 고르기」. ⛔ONLY 「버리기」 ANSWERS FALSE while the caller
/// stands: a window taken down from outside (a pop meant for some other
/// route) answered nothing, and the window is opened again rather than the
/// output let go.
Future<bool> _wouldPickAgain(BuildContext context) async {
  final strings = AppText.strings;
  final again = await askUntilAnswered(
    context,
    ConfirmQuestion(
      keys: (
        window: const ValueKey<String>('hand-over-pending-dialog'),
        decline: const ValueKey<String>('hand-over-pending-discard'),
        accept: const ValueKey<String>('hand-over-pending-pick-again'),
      ),
      // The export window's own name and mark: this is still that export.
      title: strings.exExport,
      titleIcon: Icons.upload_file_outlined,
      message: strings.exHandOverPending,
    ),
    accept: ConfirmChoice(strings.exHandOverPickAgain),
    decline: ConfirmChoice(
      strings.exHandOverDiscard,
      emphasis: AppWindowActionEmphasis.danger,
    ),
  );
  return again != false && context.mounted;
}

/// ONE FILE's place through the system save window — the DESKTOP half of
/// Save As, and of everything else that writes one file where it is told:
/// the window answers with a path, nothing is created, and the caller
/// writes there itself (see [FolderPicker.pickSaveDestination] for why
/// desktop stopped staging a file and moving it). The grant is for that
/// path, or null when the user backed out — of the window, or of the
/// question below.
///
/// On Windows and Linux the name the window answers with is not yet the
/// file's:
///
/// 1. **THE SUFFIX IS THE CALLER'S.** Windows shows the type filter and
///    never appends the extension it names
///    ([FolderPicker.pickSaveDestination]), so a name typed bare comes back
///    bare. The extension is [suggestedName]'s — what is being written
///    decides it, not what was typed — and it is appended where missing.
/// 2. **THE REPLACE QUESTION IS ASKED AGAIN (F-14).** Appending claims a
///    DIFFERENT path than the one the window's own replace prompt asked
///    about — 「type Foo over an existing Foo.anicel」 was a silent
///    overwrite — so when the suffixed name is taken, the question is asked
///    about it.
///
/// ⚠️Where the pick is a GRANT (macOS's sandbox) the answer is taken as it
/// stands, bare name and all: the path the window answered is the one path
/// the app may write, and the same name with a suffix is a file it was
/// never handed ([FolderPicker.aSaveWindowAnswersAPathOn]).
///
/// ⛔THE ONE DOOR TO THE SAVE WINDOW. ↩️There was a barer one beside it
/// (`pickSaveDestinationForUser`: the pick, said out loud, and no more),
/// and its three callers each answered the two points above for
/// themselves: Save As answered both; the brush export answered the first
/// and wrote over whatever stood at the suffixed name; the WAV export
/// answered neither, and a name typed bare was written bare. An export's
/// lone file is the fourth to ask (F-221, 2026-10-07) — so the answers are
/// here, and the barer door is gone.
Future<FolderGrant?> pickSaveFileForUser(
  BuildContext context, {
  required String suggestedName,
  String? initialDirectory,
  List<XTypeGroup> acceptedTypeGroups = const [],
}) async {
  final answer = await FolderPicker.pickSaveDestination(
    suggestedName: suggestedName,
    initialDirectory: initialDirectory,
    acceptedTypeGroups: acceptedTypeGroups,
  );
  if (!context.mounted) {
    return null;
  }
  final grant = await _spokenFor(context, answer);
  final picked = grant?.path;
  if (picked == null || !context.mounted) {
    return null;
  }
  final suffix = _suffixOf(suggestedName);
  if (suffix.isEmpty ||
      picked.toLowerCase().endsWith(suffix.toLowerCase()) ||
      FolderPicker.grantsAreScoped) {
    return grant;
  }
  final suffixed = '$picked$suffix';
  if (File(suffixed).existsSync()) {
    final strings = AppText.strings;
    final replace = await askConfirm(
      context,
      ConfirmQuestion(
        keys: (
          window: const ValueKey<String>('save-as-replace-dialog'),
          decline: const ValueKey<String>('save-as-replace-cancel'),
          accept: const ValueKey<String>('save-as-replace-confirm'),
        ),
        title: strings.replaceFileTitle,
        titleIcon: Icons.save_as_outlined,
        message: strings.replaceFileMessageTemplate.replaceAll(
          '{name}',
          fileNameOfPath(suffixed),
        ),
      ),
      accept: ConfirmChoice(
        strings.commonReplace,
        emphasis: AppWindowActionEmphasis.danger,
      ),
    );
    if (replace != true || !context.mounted) {
      return null;
    }
  }
  return FolderGrant.granted(
    path: suffixed,
    bookmark: grant!.bookmark,
    kind: GrantKind.file,
  );
}

/// The extension [name] ends in, its dot included — empty for a name that
/// has none (a leading dot is a name, not an extension).
String _suffixOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 || dot == name.length - 1 ? '' : name.substring(dot);
}

/// Android alone has to clear a storage grant before a picker is worth
/// opening — everywhere else the OS either attaches no permission to a path
/// (Windows, Linux) or grants one with the pick itself (iOS, macOS).
///
/// Returns false when the caller should stop (the user was told why).
Future<bool> _storageGrantCleared(BuildContext context) async {
  if (!folderPickNeedsStorageGrant(_operatingSystem) ||
      await AppStorage.isAllFilesAccessGranted()) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  await _showStorageGrantNotice(context);
  return false;
}

/// The one place a pick's outcome becomes words.
///
/// Three entry points used to spell this switch out themselves, which is
/// how a fourth (export) would have quietly grown a fourth dialect of "the
/// user backed out" — and the whole reason [FolderGrant] reports four
/// distinct outcomes is that three of them deserve to be said out loud.
Future<FolderGrant?> _spokenFor(
  BuildContext context,
  FolderGrant grant, {
  bool folderMode = false,
  bool acceptsDocuments = false,
}) async {
  switch (grant.status) {
    case FolderPickStatus.granted:
      return grant;
    case FolderPickStatus.providerDocument:
      if (acceptsDocuments) {
        return grant;
      }
      await _showNoFilesystemPathNotice(context);
      return null;
    case FolderPickStatus.cancelled:
      // Backing out is not an event — except in the one case the app cannot
      // see. Google Drive gives no folder to any folder window — Open is
      // dead in it on Apple, and on Android it is not listed at all — so a
      // person who went looking for it arrives here looking exactly like
      // someone who changed their mind ([folderPickCancelMayBeDrive]).
      //
      // Said ONCE per session, and only where it can happen: a real cancel
      // costs the user one line they can ignore, and the alternative is
      // never telling them at all.
      if (folderMode &&
          !_driveNoticeShown &&
          folderPickCancelMayBeDrive(_operatingSystem)) {
        _driveNoticeShown = true;
        await showAppNotice(
          context,
          windowKey: const ValueKey<String>('folder-pick-drive-notice'),
          title: AppText.strings.commonNotice,
          message: folderPickDriveNoticeFor(_operatingSystem),
        );
      }
      return null;
    case FolderPickStatus.noFilesystemPath:
      await _showNoFilesystemPathNotice(context);
      return null;
    case FolderPickStatus.unavailable:
      await showAppNotice(
        context,
        title: AppText.strings.commonNotice,
        message: AppText.strings.folderPickUnavailable,
      );
      return null;
  }
}

/// Only reachable on Android: iOS and macOS grant a real path through the
/// security scope, so a document provider there is a working folder rather
/// than a dead end. The wording is the sync-app guidance the in-app browser
/// used to carry in its footer, promoted to the moment it actually applies.
Future<void> _showNoFilesystemPathNotice(BuildContext context) {
  final strings = AppText.strings;
  return showDialog<void>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: const ValueKey<String>('folder-no-path-dialog'),
      title: strings.folderNoPathTitle,
      titleIcon: Icons.cloud_off_outlined,
      message: strings.fileCloudNoticeOpen,
      actions: [
        AppWindowAction(
          label: strings.commonClose,
          actionKey: const ValueKey<String>('folder-no-path-close'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// The All-Files grant, which the in-app browser used to own. Deleting that
/// browser without moving this would have left Android users with a picker
/// that silently refuses every folder outside the app's own directory.
Future<void> _showStorageGrantNotice(BuildContext context) {
  final strings = AppText.strings;
  return showDialog<void>(
    context: context,
    builder: (context) => AppConfirmDialog(
      windowKey: const ValueKey<String>('storage-grant-dialog'),
      // `fileStorageOffNotice` is a two-clause sentence, authored as a BODY
      // — it was the browser's banner text. Using it as a heading and then
      // filling the body with the cloud-sync notice made the one dialog
      // whose job is "grant storage access" answer a different question.
      title: strings.folderStorageOffTitle,
      titleIcon: Icons.folder_off_outlined,
      message: strings.fileStorageOffNotice,
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('storage-grant-cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.fileOpenSettings,
          actionKey: const ValueKey<String>('storage-grant-settings'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: () {
            Navigator.of(context).pop();
            unawaited(AppStorage.requestAllFilesAccess());
          },
        ),
      ],
    ),
  );
}

/// Hands the user a file called [suggestedName], written by [write], and
/// answers where it landed — or null when it failed, or the user would not
/// have it: backed out of the save window that asks before it is made, or
/// let it go once it was ([placedOrLetGo]).
///
/// 🚨★★★**THE SAME TWO HALVES AS SAVE AS, WITHOUT THE PROJECT.** Save As
/// grew both roads and then wrapped them in project-specific work — staging
/// the archive, adopting the placed path, minting a bookmark for later
/// saves. An export has none of that: the file leaves and is never written
/// to again.
///
/// So the roads are the same and the reasons are the ones already written
/// down: desktop has a save panel, so [pickSaveFileForUser] answers
/// with a path and this writes there. iOS has none — Apple never built one
/// — so the file is written into the app container FIRST and
/// [exportFileForUser] moves it where the picker says.
///
/// ⛔The container copy is deleted on the desktop road and MOVED on the
/// scoped one, so neither leaves a second copy behind (유저 08-27: 「사본
/// 남으면 진짜 용서안할게」) — the scoped half IS
/// [placeStagedFileForUser] now, shared with Save As, which is what the
/// heading above always claimed and this used to re-implement by hand.
///
/// ⚠️No bookmark comes back on purpose. A caller that wanted to write there
/// again would be a caller that should have used Save As.
///
/// 🚨**[write] takes a PATH, not bytes.** Some exports are hundreds of
/// megabytes — an hour of dialogue is 691MB of PCM — and a signature that
/// took a `Uint8List` would have re-created, in a brand new place, exactly
/// the whole-file allocation the carry and staging rounds spent themselves
/// removing. It answers false when it could not produce a real file, and
/// then nothing is handed over.
Future<String?> handWrittenFileToUser(
  BuildContext context, {
  required String suggestedName,
  required Future<bool> Function(String path) write,
  List<XTypeGroup> acceptedTypeGroups = const [],
}) async {
  if (!FolderPicker.grantsAreScoped) {
    final grant = await pickSaveFileForUser(
      context,
      suggestedName: suggestedName,
      acceptedTypeGroups: acceptedTypeGroups,
    );
    final picked = grant?.path;
    if (picked == null) {
      return null;
    }
    // Straight to the destination — the desktop law, and the reason Save
    // As stopped staging and moving (a cross-volume rename cannot work).
    if (await write(picked)) {
      return picked;
    }
    _discardQuietly(File(picked));
    return null;
  }
  final grant = await placeStagedFileForUser(
    context,
    suggestedName: suggestedName,
    write: write,
  );
  // A document (PICK-7) is where it landed too — by its URI, having no
  // path.
  return grant?.path ?? grant?.document?.uri;
}

/// THE SCOPED ROAD: writes a file called [suggestedName] into a staging
/// directory of its own via [write], hands it to the OS picker, and
/// answers the grant for wherever it landed — or null when [write] failed,
/// the caller went away, or the user would not have it placed.
///
/// ⛔The staged copy is deleted on the desktop road and MOVED on this one,
/// so neither leaves a second copy behind (유저 08-27: 「사본 남으면 진짜
/// 용서안할게」).
///
/// 🚨**[write] takes a PATH, not bytes.** Some exports are hundreds of
/// megabytes — an hour of dialogue is 691MB of PCM — and a signature that
/// took a `Uint8List` would have re-created, in a brand new place, exactly
/// the whole-file allocation the carry and staging rounds spent themselves
/// removing. It answers false when it could not produce a real file, and
/// then nothing is handed over.
///
/// ⚠️The DESKTOP halves are deliberately NOT here. They ask through the one
/// save window ([pickSaveFileForUser]) and then part ways: Save As keeps
/// the path for the atomic temp+rename save that follows, an export writes
/// at it at once. Two laws, and a flag choosing between them would be the
/// invented kind.
///
/// [keepsSavingThere] answers ONE question — will the caller go on saving
/// into what it placed? Only Save As does, and three things follow from
/// the answer. Android's storage grant is asked of that caller alone
/// ([exportFileForUser]). Where the picker answered with a document that
/// has no filesystem path (PICK-7, Drive on Android), the staged file is
/// poured into it and then either becomes that document's working copy —
/// moved, never copied, and answered as a path — or goes with the staging
/// folder like any other placed file. And what will NOT be saved again is
/// a finished output, with nothing of it anywhere but this staging folder:
/// backing out of its window is asked about before it is let go
/// ([placedOrLetGo]). Save As backs out to a project that is still open,
/// and is asked nothing.
Future<FolderGrant?> placeStagedFileForUser(
  BuildContext context, {
  required String suggestedName,
  required Future<bool> Function(String stagingPath) write,
  bool keepsSavingThere = false,
}) async {
  // Its own directory so the cleanup below cannot reach anything else.
  final stagingDirectory = Directory.systemTemp.createTempSync(
    'anicel_stage_',
  );
  final staged = File('${stagingDirectory.path}/$suggestedName');
  if (!await write(staged.path)) {
    _discardStaging(stagingDirectory);
    return null;
  }
  if (!context.mounted) {
    _discardStaging(stagingDirectory);
    return null;
  }
  Future<FolderGrant?> window() => exportFileForUser(
    context,
    sourcePath: staged.path,
    suggestedName: suggestedName,
    keepsSavingThere: keepsSavingThere,
  );
  final grant = keepsSavingThere
      ? await window()
      : await placedOrLetGo(context, window);
  final document = grant?.document;
  final placed = keepsSavingThere && document != null
      ? FolderGrant.granted(
          path: ProviderDocuments.adoptAsWorkingCopy(document, staged.path),
          kind: GrantKind.file,
        )
      : grant;
  // On success the staged file was MOVED out and only the empty directory
  // is left; backed out of or let go it is still in it — and poured into a
  // document it is still in it too, unless it became the working copy.
  // Same cleanup.
  _discardStaging(stagingDirectory);
  return placed;
}

/// A leaked file must never fail an export — or a cancel, which is the path
/// that reaches it most often. The DESKTOP road's cleanup: it writes
/// straight to the destination, so what it sweeps is one file it created
/// there, never a directory.
void _discardQuietly(File file) {
  try {
    if (file.existsSync()) {
      file.deleteSync();
    }
  } on Object {
    // The container is the app's to sweep if this ever loses the race.
  }
}

/// Removes the staging directory. A leak here must never fail a save — or a
/// cancel, which is the path that reaches it most often.
void _discardStaging(Directory directory) {
  try {
    directory.deleteSync(recursive: true);
  } on Object {
    // Temp is the OS's to reclaim if this ever loses the race.
  }
}
