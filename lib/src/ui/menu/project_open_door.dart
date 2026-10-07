import 'dart:io' show FileSystemException;

import 'package:flutter/material.dart';

import '../../models/import/import_warning.dart';
import '../../services/audio/audio_conform_pipeline.dart'
    show ProjectAssetLayout;
import '../../services/persistence/anicel_project_archive.dart'
    show anicelProjectExtension;
import '../../services/persistence/folder_grant.dart';
import '../../services/persistence/provider_documents.dart';
import '../../services/persistence/recent_projects.dart';
import '../../services/persistence/recent_projects_store.dart';
import '../dialogs/app_confirm_dialog.dart';
import '../dialogs/app_progress_dialog.dart';
import '../dialogs/cloud_wait.dart';
import '../editor_session_manager.dart';
import '../open_projects.dart';
import '../session/project_file_door.dart' show readProjectFile;
import '../session/tvpp_import_door.dart' show readTvppProject;
import '../text/app_strings.dart';
import '../text/model_vocabulary.dart' show ImportWarningWords;

/// A chosen project, plus the token that reopens it next launch.
///
/// The bookmark travels with the path because the recent-projects list is
/// worthless without it on Apple platforms — a stored path outside the app
/// container is refused after relaunch unless the app can produce the
/// security scope it was granted.
///
/// [placed] says the archive is ALREADY there: the scoped picker moves a
/// file the app wrote rather than handing back an empty destination, so
/// the bytes at [path] are the ones just serialized and writing them a
/// second time is at best waste — see [promptSaveProjectAs].
typedef ProjectPick = ({String path, String? folderBookmark, bool placed});

/// What 「열기」 opens — and what a file dropped on the window is asked by,
/// so the two entrances read one list (F-247, 유저 2026-09-30: 「드래그앤드롭으로
/// 외부파일 임포트시 확장자?에 맞도록. anicel이면 배치창이아니라 새 프로젝트로
/// 열도록. tvpp도 똑같이」).
///
/// TVPaint projects open through the same door (the user's call: ONE
/// entry, the Open button — the import pickers retire later). A .tvpp
/// converts into cuts rather than loading as a project.
///
/// 🚨These are now what the open ACCEPTS, not what the dialog SHOWS —
/// 유저 2026-08-29 named this exact dialog: 「특히 윈도우 열기시 anicel
/// 이랑 tvp만 설정따라서 보이게 되있는데 그게아니라 … 어떤 확장자던
/// 선택할수 있게」.
const List<String> projectOpenExtensions = [anicelProjectExtension, 'tvpp'];

/// Whether [path] names a file 「열기」 opens ([projectOpenExtensions]) —
/// by NAME, the way the door tells a .tvpp: a provider document's URI says
/// nothing of what it is (PICK-7).
bool opensAsProject(String path) {
  final name = ProviderDocuments.nameOf(path).toLowerCase();
  return projectOpenExtensions.any((extension) => name.endsWith('.$extension'));
}

/// THE OPEN DOOR — the one way a picked project file becomes a tab, with
/// every guard on the way. Every entrance comes through it: the Project
/// menu's Open, a Recent row, and a project file dropped on the window
/// (F-247). It was the top strip's own until the drop needed it.
final class ProjectOpenDoor {
  ProjectOpenDoor(this.projects);

  final OpenProjects projects;

  /// Opens [pick] in a tab of its own, from a staged copy if the file will
  /// not read in place, and records it in Recents afterwards.
  ///
  /// Shared with the Recent-projects rows on purpose: opening from Recent is
  /// the ONE-TAP common case PICK-4 exists to make, and every guard this
  /// door has has to be on that path too.
  ///
  /// 🪦It offered autosave RECOVERY first until 2026-09-08, and that is the
  /// whole of what it lost.
  ///
  /// 🪦And the UNSAVED-WORK GATE stood here while opening REPLACED the
  /// project on screen — 「opening ANOTHER project closes this one as surely
  /// as the window's X」. 유저 2026-09-26 (I-7): 「프로젝트 열기로 열면 지금
  /// 프로젝트가 교체되는데 새로 여는걸로」. Opening closes nothing now, so
  /// there is nothing to ask; the question went to the tab's ✕.
  Future<void> open(
    BuildContext context,
    ProjectPick pick,
  ) async {
    final path = pick.path;
    // By NAME: a provider document's URI says nothing of what it is (PICK-7).
    if (ProviderDocuments.nameOf(path).toLowerCase().endsWith('.tvpp')) {
      await _openTvppAsProject(context, path);
      return;
    }
    // A file already open is SHOWN, not opened again: two sessions on one
    // file would be two writers on one archive. A document's session is
    // bound to its working copy.
    if (projects.boundTo(ProviderDocuments.workingCopyOf(path) ?? path)
        case final open?) {
      projects.activate(open);
      return;
    }
    final ({({EditorSessionManager session, bool staged}) value})? opened;
    try {
      opened = await _openBehindWindow<
        ({EditorSessionManager session, bool staged})
      >(context, (wait, _) => _readProject(path, wait));
    } on Object catch (error) {
      // The archive's own complaint — a file that would not parse.
      if (context.mounted) {
        showFileError(context, error);
      }
      return;
    }
    if (opened == null) {
      return;
    }
    final session = opened.value.session;
    if (!context.mounted) {
      projects.discard(session);
      return;
    }
    projects.adopt(session);
    await _afterOpened(context, pick, staged: opened.value.staged);
  }

  /// The read itself, from wherever the bytes are, and the session born for
  /// what it read — not in a tab yet, so a read that fails or a wait that is
  /// cancelled leaves the tabs exactly as they were, with no session made.
  ///
  /// The same materializer every open uses: a File Provider pick can be a
  /// placeholder a plain read refuses, and the archive reader needs random
  /// access — so an unreadable pick opens from a staged local copy, and the
  /// session is bound back to the real file so saves land there.
  Future<({EditorSessionManager session, bool staged})> _readProject(
    String path,
    CloudWait wait,
  ) async {
    final source = await FolderPicker.materializeOpenedFile(
      path,
      within: null,
      onWaiting: wait.report,
      isCancelled: wait.isCancelled,
    );
    // The bytes are here; the read that follows is the app's own.
    wait.ended();
    final read = await readProjectFile(
      source.path,
      // Only when they differ: binding is what says「saves go back THERE」,
      // and a session reading its own file has nowhere else.
      bindTo: source.staged ? path : null,
      isCancelled: wait.isCancelled,
    );
    final session = projects.prepare(read.project);
    try {
      session.projectDoor.settle(read);
    } on Object {
      projects.discard(session);
      rethrow;
    }
    return (session: session, staged: source.staged);
  }

  /// The three things that follow a SUCCESSFUL open: Recents, the word
  /// about a staged copy, the word about a legacy assets folder.
  Future<void> _afterOpened(
    BuildContext context,
    ProjectPick pick, {
    required bool staged,
  }) async {
    final path = pick.path;
    // Recorded AFTER the open succeeds, not at pick time: a file that
    // fails to parse has no business sitting at the top of the menu.
    // `path` rather than the staged copy — reading out of a copy still
    // means the user opened the project, not the copy.
    recordRecentProject(
      RecentProject(path: path, folderBookmark: pick.folderBookmark),
    );
    if (staged) {
      // Said out loud on purpose (유저 2026-08-27): the wait is meant to
      // make this road unreachable, so a build that still takes it must be
      // visible rather than quietly slower. A copy also means every cel
      // ref points into a temp file for the session — the one case where
      // the user deserves to know before they draw.
      await showAppNotice(
        context,
        windowKey: const ValueKey<String>('opened-from-staged-copy'),
        title: AppText.strings.commonNotice,
        message:
            '제자리에서 읽지 못해 임시 사본으로 열었습니다 — '
            '이 문구가 보이면 알려주세요.',
      );
      if (!context.mounted) {
        return;
      }
    }
    // A project from a build that kept its media in a sibling folder.
    // Said AFTER the open, because a file that failed to parse has no
    // media to absorb and the folder is still the only copy. A provider
    // document (PICK-7) has no folder around it to hold one.
    if (ProviderDocuments.isDocumentUri(path)) {
      return;
    }
    final layout = ProjectAssetLayout(path);
    if (layout.hasLegacyAssetsDirectory) {
      final name = layout.assetsDirectory.split('/').last;
      await showAppNotice(
        context,
        windowKey: const ValueKey<String>('legacy-assets-folder-notice'),
        title: AppText.strings.commonNotice,
        message: AppText.strings.projectLegacyAssetsFolder.replaceAll(
          '{name}',
          name,
        ),
      );
    }
  }

  /// A TVPaint project opens AS A PROJECT (the user's rule — a .tvpp holds
  /// several cuts), in a tab of its own like any open (I-7). No recents
  /// entry — the result is a NEW unsaved project until its first save.
  Future<void> _openTvppAsProject(BuildContext context, String path) async {
    // Decoding and baking a whole project is a save-sized wait; a frozen
    // screen before the cuts appear reads as a hang (hands-on, 288's 96
    // frames × 19 layers).
    final opened =
        await _openBehindWindow<
          ({EditorSessionManager session, List<ImportWarning> warnings})?
        >(context, (wait, report) => _convertTvpp(path, wait, report));
    if (opened == null) {
      return;
    }
    final converted = opened.value;
    if (converted == null) {
      if (context.mounted) {
        showFileError(context, AppText.strings.imNotTvpp);
      }
      return;
    }
    if (!context.mounted) {
      projects.discard(converted.session);
      return;
    }
    projects.adopt(converted.session);
    if (converted.warnings.isNotEmpty) {
      await showAppNotice(
        context,
        windowKey: const ValueKey<String>('tvpp-import-warnings-notice'),
        title: AppText.strings.commonNotice,
        message: converted.warnings
            .take(6)
            .map((warning) => warning.textFor(AppText.language))
            .join('\n'),
      );
    }
  }

  /// The .tvpp read and converted, and the session born for the project it
  /// became with every cel baked into it — not in a tab yet, the .anicel
  /// open's reason. Null when the file is not a TVPaint project.
  Future<({EditorSessionManager session, List<ImportWarning> warnings})?>
  _convertTvpp(
    String path,
    CloudWait wait,
    void Function(double) report,
  ) async {
    final read = await readTvppProject(
      tvppPath: path,
      onWaiting: wait.report,
      isCancelled: wait.isCancelled,
    );
    if (read == null) {
      return null;
    }
    final session = projects.prepare(read.project);
    try {
      final warnings = await session.tvppDoor.bake(
        read,
        onProgress: (fraction) {
          // Baking has started, so the waiting line has nothing left to
          // say.
          wait.ended();
          report(fraction);
        },
      );
      return (session: session, warnings: warnings);
    } on Object {
      projects.discard(session);
      rethrow;
    }
  }

  /// The ONE window every open stands behind, up from the first frame, for
  /// a .anicel and a .tvpp alike.
  ///
  /// 🚨IT USED TO COVER ONLY THE WAIT FOR A PROVIDER'S BYTES and stay silent
  /// for a local pick, on the premise that an open is instant. A 74MB
  /// project on a cloud drive is not, and the person could not tell an open
  /// from nothing (유저 2026-09-13: 「로딩창 안 떠서 여는 중인지 아닌지
  /// 모르겠어」). F-53 had already said what a wait window does — it goes
  /// up at once — and this is that law with its one exception removed. The
  /// status line still says whose work a cloud wait is ([CloudWait]); once
  /// the bytes are here the rest is the app's own.
  ///
  /// The two answers every open can end in are given HERE: the user stopped
  /// waiting (nothing was applied, the door closes without a word), or the
  /// file could not be read (access, not format — the same file opens once
  /// it is readable: a cloud placeholder mid-download, a provider signed
  /// out). Null is either of those; anything else wraps [task]'s own answer,
  /// so a task whose answer is itself null is not mistaken for a cancel.
  Future<({T value})?> _openBehindWindow<T>(
    BuildContext context,
    Future<T> Function(CloudWait wait, void Function(double) report) task,
  ) async {
    final wait = CloudWait();
    try {
      final value = await runWithAppProgress<T>(
        context: context,
        title: AppText.strings.fileOpenTitle,
        titleIcon: Icons.folder_open_outlined,
        runningLabel: AppText.strings.openProgressRunning,
        doneLabel: AppText.strings.openProgressDone,
        windowKey: const ValueKey<String>('open-progress-dialog'),
        runningStatus: wait.status,
        onCancel: wait.cancel,
        task: (report) => task(wait, report),
      );
      return (value: value);
    } on MaterializeCancelled {
      return null;
    } on FileSystemException {
      if (context.mounted) {
        showFileError(context, AppText.strings.imFileUnreadable);
      }
      return null;
    } finally {
      wait.dispose();
    }
  }
}
