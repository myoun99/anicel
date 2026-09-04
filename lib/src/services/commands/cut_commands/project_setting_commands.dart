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

  /// Executes [command] only when the project setting [read] answers with
  /// something other than [value].
  ///
  /// ⛔EVERY SETTING HERE IS "ONE UNDO STEP, NO-OP WHEN UNCHANGED", AND
  /// FIVE WROTE IT OUT. Without the guard, a colour picker that reports
  /// the same swatch on every pointer move banks an undo step per move,
  /// and the user then walks back through presses that changed nothing.
  void _setIfChanged<T>(
    T value,
    T Function(Project project) read,
    Command Function() command,
  ) {
    if (read(_coordinator.repository.requireProject()) == value) {
      return;
    }
    _coordinator.historyManager.execute(command());
  }

  /// Project-level sheet-header text; one undo step, no-op when unchanged.
  void setTimesheetInfo(TimesheetInfo info) => _setIfChanged(
    info,
    (project) => project.timesheetInfo,
    () => UpdateTimesheetInfoCommand(
      repository: _coordinator.repository,
      info: info,
    ),
  );

  /// One undo step; no-op when unchanged (R10-⑥).
  void setProjectBackground(ProjectBackground background) => _setIfChanged(
    background,
    (project) => project.background,
    () => UpdateProjectBackgroundCommand(
      repository: _coordinator.repository,
      background: background,
    ),
  );

  /// One undo step; no-op when unchanged. The backdrop is opaque by
  /// contract (R3b) — the alpha byte is forced here, so no caller can
  /// thin the stage's final answer.
  void setProjectBackdrop(int argb) {
    final opaque = 0xFF000000 | argb;
    _setIfChanged(
      opaque,
      (project) => project.backdropArgb,
      () => UpdateProjectStageColorsCommand(
        repository: _coordinator.repository,
        backdropArgb: opaque,
      ),
    );
  }

  /// One undo step; no-op when unchanged. RGBA — a thinned pasteboard
  /// reveals the backdrop (R3b; project data since the promotion, R28 #9
  /// reversed).
  void setProjectPasteboard(int argb) => _setIfChanged(
    argb,
    (project) => project.pasteboardArgb,
    () => UpdateProjectStageColorsCommand(
      repository: _coordinator.repository,
      pasteboardArgb: argb,
    ),
  );

  /// How far past the canvas the pasteboard SHOWS, in canvas widths and
  /// heights. One undo step; no-op when unchanged.
  void setProjectPasteboardMargin(double margin) => _setIfChanged(
    margin,
    (project) => project.pasteboardMargin,
    () => UpdateProjectStageColorsCommand(
      repository: _coordinator.repository,
      pasteboardMargin: margin,
    ),
  );
}
