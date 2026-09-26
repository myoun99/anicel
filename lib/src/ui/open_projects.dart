import 'package:flutter/foundation.dart';

import '../models/project.dart';
import '../services/persistence/same_file.dart';
import 'editor_session_manager.dart';

/// The projects open in this window — a SESSION per project, one of them on
/// screen.
///
/// 🗣️유저 2026-09-26 (I-7): 「여러 프로젝트 열수있게할거야 … 상단띠에 프로젝트
/// 리스트있고 닫기버튼있고. 그래서 새 프로젝트는 현재 프로젝트 냅두고 새로
/// 여는거야 … 프로젝트 열기로 열면 지금 프로젝트가 교체되는데 새로 여는걸로」.
/// So New, Open and the recent list each add a tab and never replace one,
/// and a tab's close button is the only close there is.
///
/// ⛔A tab is a whole SESSION, not a project swapped in and out of one. The
/// session is where a project's history, stores, selections and caches
/// live; carrying several projects through one session would be the
/// replace-and-reset the Open door did, whose resets kept missing state.
///
/// What this object owns is the LIST, which tab is shown, and what each tab
/// may cache. Making a session and letting one go are the shell's ([open]
/// and [close] call back into it), because the shell hangs things on each
/// one — its history hooks, its autosave — and a closed session may only
/// go once nothing on screen is still showing it.
class OpenProjects extends ChangeNotifier {
  OpenProjects({
    required Project first,
    required EditorSessionManager Function(Project project) openSession,
    required void Function(EditorSessionManager session) letGo,
  }) : _openSession = openSession,
       _letGo = letGo {
    _admit(_openSession(first));
    _shareTheAllowance();
  }

  final EditorSessionManager Function(Project project) _openSession;
  final void Function(EditorSessionManager session) _letGo;
  final List<EditorSessionManager> _sessions = [];
  int _active = 0;

  /// Every open project, in tab order.
  List<EditorSessionManager> get sessions => List.unmodifiable(_sessions);

  /// The project on screen.
  EditorSessionManager get active => _sessions[_active];

  /// Opens [project] in a tab of its own after the others, and shows it.
  EditorSessionManager open(Project project) {
    final session = prepare(project);
    adopt(session);
    return session;
  }

  /// A session born for [project] that is NOT in a tab yet — what an opened
  /// file becomes before it shows: the file is read first, with no session,
  /// and the session is born with what it read (`ProjectFileDoor.settle`,
  /// `TvppImportDoor.bake`). [adopt] shows it; [discard] lets it go, for a
  /// conversion that failed on the way or a window that went away.
  EditorSessionManager prepare(Project project) => _openSession(project);

  /// Puts a [prepare]d session in a tab of its own after the others, and
  /// shows it.
  void adopt(EditorSessionManager session) {
    _admit(session);
    _show(_sessions.length - 1);
  }

  /// Lets a [prepare]d session go without ever showing it.
  void discard(EditorSessionManager session) {
    assert(_indexOf(session) < 0, 'an open tab closes through close()');
    _letGo(session);
  }

  /// Shows [session]'s tab. A no-op for a session that is not open, or
  /// already shown.
  void activate(EditorSessionManager session) {
    final index = _indexOf(session);
    if (index < 0 || index == _active) {
      return;
    }
    _show(index);
  }

  /// Closes [session]'s tab and lets the session go — the shell asked about
  /// unsaved work BEFORE this; nothing here asks anything. Closing the
  /// shown tab shows the one that took its place, or the one before it at
  /// the end of the row.
  ///
  /// The LAST tab closing leaves an untitled project from [fresh] (유저
  /// 2026-09-26, board I-7-Q1: 「닫으면 이름 없는 새 프로젝트가 남는다」),
  /// so there is always a project on screen.
  void close(
    EditorSessionManager session, {
    required Project Function() fresh,
  }) {
    var index = _indexOf(session);
    if (index < 0) {
      return;
    }
    if (_sessions.length == 1) {
      open(fresh());
      index = _indexOf(session);
    }
    final shown = active;
    if (identical(shown, session)) {
      _stopBehind(session);
    }
    _sessions.removeAt(index);
    _active = identical(shown, session)
        ? (index < _sessions.length ? index : _sessions.length - 1)
        : _indexOf(shown);
    _untitledNumbers.remove(session);
    _shareTheAllowance();
    notifyListeners();
    _letGo(session);
  }

  /// The number an untitled tab wears — 「Untitled 2」 — or null for a
  /// project that came from a file.
  ///
  /// Minted when the tab is added, one after the last this run, and kept:
  /// a tab's name does not change because another closed. Only a project
  /// with no file takes one, so the untitled ones count 1, 2, 3 however
  /// many files are open between them.
  int? untitledNumberOf(EditorSessionManager session) =>
      _untitledNumbers[session];

  final Map<EditorSessionManager, int> _untitledNumbers = {};
  int _untitledMinted = 0;

  void _admit(EditorSessionManager session) {
    _sessions.add(session);
    if (session.projectFile.path == null) {
      _untitledNumbers[session] = _untitledMinted += 1;
    }
  }

  /// The open project bound to the file at [path], or null — so a file
  /// already open is shown rather than opened a second time. Two sessions
  /// on one file would be two writers on one archive.
  EditorSessionManager? boundTo(String path) {
    for (final session in _sessions) {
      final bound = session.projectFile.path;
      if (bound != null && namesTheSameFile(bound, path)) {
        return session;
      }
    }
    return null;
  }

  /// Lets every session go — the window is closing.
  @override
  void dispose() {
    for (final session in _sessions) {
      _letGo(session);
    }
    _sessions.clear();
    _untitledNumbers.clear();
    super.dispose();
  }

  void _show(int index) {
    if (index != _active && _active < _sessions.length) {
      _stopBehind(_sessions[_active]);
    }
    _active = index;
    _shareTheAllowance();
    notifyListeners();
  }

  /// A tab going behind stops playing — every transport it has, the canvas
  /// run and the viewers' alike: what plays is the project on screen.
  static void _stopBehind(EditorSessionManager session) =>
      session.playbackRig.transports.stopAll();

  /// The project on screen takes the whole allowance for its own caches;
  /// the ones behind it share a quarter between them, so opening tabs does
  /// not multiply what the app may hold ([EditorSessionManager.cacheShare]).
  void _shareTheAllowance() {
    final behind = _sessions.length - 1;
    for (final session in _sessions) {
      session.cacheShare = identical(session, active)
          ? 1
          : backgroundCacheShare / (behind < 1 ? 1 : behind);
    }
  }

  /// What the tabs behind the one on screen share, in allowances.
  static const double backgroundCacheShare = 0.25;

  int _indexOf(EditorSessionManager session) {
    for (var index = 0; index < _sessions.length; index += 1) {
      if (identical(_sessions[index], session)) {
        return index;
      }
    }
    return -1;
  }
}
