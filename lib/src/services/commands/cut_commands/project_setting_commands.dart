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

  /// Project-level sheet-header text; one undo step, no-op when unchanged.
  void setTimesheetInfo(TimesheetInfo info) {
    if (_coordinator.repository.requireProject().timesheetInfo == info) {
      return;
    }
    _coordinator.historyManager.execute(
      UpdateTimesheetInfoCommand(
        repository: _coordinator.repository,
        info: info,
      ),
    );
  }

  /// One undo step; no-op when unchanged (R10-⑥).
  void setProjectBackground(ProjectBackground background) {
    if (_coordinator.repository.requireProject().background == background) {
      return;
    }
    _coordinator.historyManager.execute(
      UpdateProjectBackgroundCommand(
        repository: _coordinator.repository,
        background: background,
      ),
    );
  }

  /// One undo step; no-op when unchanged. The backdrop is opaque by
  /// contract (R3b) — the alpha byte is forced here, so no caller can
  /// thin the stage's final answer.
  void setProjectBackdrop(int argb) {
    final opaque = 0xFF000000 | argb;
    if (_coordinator.repository.requireProject().backdropArgb == opaque) {
      return;
    }
    _coordinator.historyManager.execute(
      UpdateProjectStageColorsCommand(
        repository: _coordinator.repository,
        backdropArgb: opaque,
      ),
    );
  }

  /// One undo step; no-op when unchanged. RGBA — a thinned pasteboard
  /// reveals the backdrop (R3b; project data since the promotion, R28 #9
  /// reversed).
  void setProjectPasteboard(int argb) {
    if (_coordinator.repository.requireProject().pasteboardArgb == argb) {
      return;
    }
    _coordinator.historyManager.execute(
      UpdateProjectStageColorsCommand(
        repository: _coordinator.repository,
        pasteboardArgb: argb,
      ),
    );
  }

  /// How far past the canvas the pasteboard SHOWS, in canvas widths and
  /// heights. One undo step; no-op when unchanged.
  void setProjectPasteboardMargin(double margin) {
    if (_coordinator.repository.requireProject().pasteboardMargin == margin) {
      return;
    }
    _coordinator.historyManager.execute(
      UpdateProjectStageColorsCommand(
        repository: _coordinator.repository,
        pasteboardMargin: margin,
      ),
    );
  }
}
