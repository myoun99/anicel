part of '../cut_command_coordinator.dart';

/// THE PROJECT SETTING COMMANDS — the project's background, backdrop,
/// pasteboard and timesheet info — as their own object.
///
/// 🚨A collaborator carved out of `CutCommandCoordinator` (the audit's SRP
/// cut, 2026-09-02). Measured before cutting: the repository and the
/// history manager shared, nothing else. It reaches the coordinator
/// through `_coordinator`.
class _ProjectSettingCommands {
  _ProjectSettingCommands(this._coordinator);

  final CutCommandCoordinator _coordinator;

  /// The subject every setter here reads its field off.
  Project get _project => _coordinator.repository.requireProject();

  /// Project-level sheet-header text; one undo step, no-op when unchanged.
  void setTimesheetInfo(TimesheetInfo info) => _coordinator._executeIfChanged(
    subject: _project,
    value: info,
    read: (project) => project.timesheetInfo,
    command: (_) => UpdateTimesheetInfoCommand(
      repository: _coordinator.repository,
      info: info,
    ),
  );

  /// One undo step; no-op when unchanged (R10-⑥).
  void setProjectBackground(ProjectBackground background) =>
      _coordinator._executeIfChanged(
        subject: _project,
        value: background,
        read: (project) => project.background,
        command: (_) => UpdateProjectBackgroundCommand(
          repository: _coordinator.repository,
          background: background,
        ),
      );

  /// One undo step; no-op when unchanged. A picked colour is a plane that is
  /// THERE, so the pick clears none in the same step — and picking the kept
  /// colour on a none plane still lands.
  ///
  /// 🚨The backdrop was opaque by contract (R3b): the alpha byte was forced
  /// here so no caller could thin the stage's final answer. F-114 (유저
  /// 2026-09-15) gave it the opacity the other planes have —
  /// 「페이스트보드, 백그라운드 설정에도 동일적용」.
  void setProjectBackdrop(int argb) => _coordinator._executeIfChanged(
    subject: _project,
    value: (argb, false),
    read: (project) => (project.backdropArgb, project.backdropNone),
    command: (_) => UpdateProjectStageColorsCommand(
      repository: _coordinator.repository,
      backdropArgb: argb,
      backdropNone: false,
    ),
  );

  /// One undo step; no-op when the backdrop is already none (F-114). The
  /// colour stays kept for the next pick.
  void setProjectBackdropNone() => _coordinator._executeIfChanged(
    subject: _project,
    value: true,
    read: (project) => project.backdropNone,
    command: (_) => UpdateProjectStageColorsCommand(
      repository: _coordinator.repository,
      backdropNone: true,
    ),
  );

  /// One undo step; no-op when unchanged. RGBA — a thinned pasteboard
  /// reveals the backdrop (R3b; project data since the promotion, R28 #9
  /// reversed). A pick clears none, as the backdrop's does.
  void setProjectPasteboard(int argb) => _coordinator._executeIfChanged(
    subject: _project,
    value: (argb, false),
    read: (project) => (project.pasteboardArgb, project.pasteboardNone),
    command: (_) => UpdateProjectStageColorsCommand(
      repository: _coordinator.repository,
      pasteboardArgb: argb,
      pasteboardNone: false,
    ),
  );

  /// One undo step; no-op when the pasteboard is already none (F-114).
  void setProjectPasteboardNone() => _coordinator._executeIfChanged(
    subject: _project,
    value: true,
    read: (project) => project.pasteboardNone,
    command: (_) => UpdateProjectStageColorsCommand(
      repository: _coordinator.repository,
      pasteboardNone: true,
    ),
  );
}
