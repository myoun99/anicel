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

  /// One undo step; no-op when unchanged. The backdrop is opaque by
  /// contract (R3b) — the alpha byte is forced here, so no caller can
  /// thin the stage's final answer.
  void setProjectBackdrop(int argb) {
    final opaque = 0xFF000000 | argb;
    _coordinator._executeIfChanged(
      subject: _project,
      value: opaque,
      read: (project) => project.backdropArgb,
      command: (_) => UpdateProjectStageColorsCommand(
        repository: _coordinator.repository,
        backdropArgb: opaque,
      ),
    );
  }

  /// One undo step; no-op when unchanged. RGBA — a thinned pasteboard
  /// reveals the backdrop (R3b; project data since the promotion, R28 #9
  /// reversed).
  void setProjectPasteboard(int argb) => _coordinator._executeIfChanged(
    subject: _project,
    value: argb,
    read: (project) => project.pasteboardArgb,
    command: (_) => UpdateProjectStageColorsCommand(
      repository: _coordinator.repository,
      pasteboardArgb: argb,
    ),
  );

  /// How far past the canvas the pasteboard SHOWS, in canvas widths and
  /// heights. One undo step; no-op when unchanged.
  void setProjectPasteboardMargin(double margin) =>
      _coordinator._executeIfChanged(
        subject: _project,
        value: margin,
        read: (project) => project.pasteboardMargin,
        command: (_) => UpdateProjectStageColorsCommand(
          repository: _coordinator.repository,
          pasteboardMargin: margin,
        ),
      );
}
