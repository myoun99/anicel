import 'package:flutter/widgets.dart';

import '../../native/app_gpu_engine.dart' show appGpuEngineIsGone;
import '../../native/engine_refusals.dart';
import '../../native/lost_screen.dart';
import '../dialogs/app_confirm_dialog.dart'
    show NoticeDetails, askedWithWindows;
import '../editor_session_manager.dart';
import '../menu/editor_top_strip.dart'
    show promptSaveProjectAs, saveProjectShowingProgress;
import '../text/app_strings.dart';

/// 🗣️a-lost-gpu-leaves-the-window-unpainted-Q1 (유저 2026-11-16): 「윈도 창으로
/// 알리고 저장하고 다시 시작할지 묻는다」 — 「화면을 그리는 그래픽 장치가
/// 멈췄습니다」 + [저장하고 다시 시작] [닫기]; 「파일이 있는 프로젝트는 그 파일에
/// 저장하고, 한 번도 저장 안 한 프로젝트는 윈도 저장 창으로 자리를 묻은 뒤, 앱을
/// 다시 켜서 같은 프로젝트들을 다시 연다」.
///
/// Asked once the screen's device went ([LostScreen]), with a window Windows
/// draws. [저장하고 다시 시작] saves every project of [sessions] that would
/// lose work — THE save a person's Save is, through its own doors, which ask
/// with Windows' windows once the screen went: into its file, or, never
/// saved, where the save window says — and starts Anicel again for every
/// project that has a file.
///
/// ⚠️A project that did not save is said, and Anicel is not started again:
/// a save its file refuses lands in this run's failed copy, which a restart
/// would throw away (`ProjectFileDoor._saveSomewhere`). The question is
/// asked again, as it is after a save window closed without a place.
///
/// [닫기] — and the window closed — take the question down; what more they
/// do is a-lost-gpu-leaves-the-window-unpainted-Q5's.
Future<void> keepTheWorkOfALostScreen(
  BuildContext context,
  List<EditorSessionManager> Function() sessions,
) async {
  final strings = AppText.strings;
  while (context.mounted) {
    final pressed = await LostScreen.askWithWindows(
      strings.screenWentTitle,
      strings.screenWentMessage,
      [strings.screenWentSaveAndRestart, strings.commonClose],
    );
    if (pressed != 0 || !context.mounted) {
      return;
    }
    final files = <String>[];
    final unsaved = <String>[];
    for (final session in sessions()) {
      if (!await _keptInItsFile(context, session)) {
        unsaved.add(session.repository.requireProject().name);
      } else if (session.projectFile.path case final path?) {
        files.add(path);
      }
      if (!context.mounted) {
        return;
      }
    }
    if (unsaved.isNotEmpty) {
      await askedWithWindows(
        strings.commonNotice,
        strings.screenWentNotSaved,
        [NoticeDetails(unsaved)],
        [strings.commonClose],
      );
      continue;
    }
    if (await LostScreen.startAgainFor(files)) {
      return;
    }
    await askedWithWindows(
      strings.commonNotice,
      strings.screenWentNotStarted,
      const [],
      [strings.commonClose],
    );
    return;
  }
}

/// Whether [session] would lose nothing torn down: nothing to lose to
/// begin with, or saved now.
///
/// 🚨The canvas engine's device goes with the screen's — a reset takes the
/// whole adapter — and a save reads the drawings back from that engine. So
/// the save stands on an engine not gone first ([EngineRefusals]), and once
/// more where the save's own read was the first to hear it go.
Future<bool> _keptInItsFile(
  BuildContext context,
  EditorSessionManager session,
) async {
  if (!session.projectFile.wouldLoseWork()) {
    return true;
  }
  await EngineRefusals.standOnAnEngineNotGone();
  if (!context.mounted) {
    return false;
  }
  if (await _savedOnce(context, session)) {
    return true;
  }
  if (!appGpuEngineIsGone || !context.mounted) {
    return false;
  }
  await EngineRefusals.standOnAnEngineNotGone();
  return context.mounted && await _savedOnce(context, session);
}

/// [session] saved as a person's Save saves it: into its file, or where
/// the save window says.
Future<bool> _savedOnce(
  BuildContext context,
  EditorSessionManager session,
) async {
  if (session.projectFile.path case final path?) {
    return saveProjectShowingProgress(context, session, path);
  }
  await promptSaveProjectAs(context, session);
  return !session.projectFile.wouldLoseWork();
}
