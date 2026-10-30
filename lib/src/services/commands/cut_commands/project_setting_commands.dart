part of '../cut_command_coordinator.dart';

/// THE PROJECT SETTING COMMANDS — the project's background, backdrop,
/// pasteboard, timesheet info and its sheets' formats — as their own object.
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

  /// The 타임시트 서식 window's save: the work's sheet format and the paper
  /// of the cut the sheet shows ([cutId]; none in the gap) — each only if
  /// it changed, ONE undo step together ([HistoryManager.runAsOneStep]).
  void setTimesheetFormat({
    required TimesheetInfo info,
    CutId? cutId,
    TimesheetSheetKind? kind,
  }) {
    final repository = _coordinator.repository;
    final history = _coordinator.historyManager;
    final project = repository.requireProject();
    history.runAsOneStep('Set timesheet format', () {
      if (project.timesheetInfo != info) {
        history.execute(
          UpdateTimesheetInfoCommand(repository: repository, info: info),
        );
      }
      if (cutId != null &&
          kind != null &&
          LinkedCutFieldCommand.linkedCutsOf(project, [cutId]).any(
            (id) => requireCut(project, id).metadata.sheetKind != kind,
          )) {
        history.execute(
          UpdateCutSheetKindCommand(
            repository: repository,
            cutIds: [cutId],
            kind: kind,
          ),
        );
      }
    });
  }

  /// The 콘티 용지 서식 window's save: the work's format and, where one was
  /// picked, the room [cutIds]' conte cells take ([cameraRoom] — its `to`
  /// null for the format's, I-82-Q1), on the 겸용 pair as one — each only
  /// if it changed, ONE undo step together.
  void setConteFormat({
    required TimesheetInfo info,
    required List<CutId> cutIds,
    ({ConteCameraRoom? to})? cameraRoom,
  }) {
    final repository = _coordinator.repository;
    final history = _coordinator.historyManager;
    final project = repository.requireProject();
    history.runAsOneStep('Set conte format', () {
      if (project.timesheetInfo != info) {
        history.execute(
          UpdateTimesheetInfoCommand(repository: repository, info: info),
        );
      }
      if (cameraRoom case (:final to)
          when LinkedCutFieldCommand.linkedCutsOf(project, cutIds).any(
            (id) => requireCut(project, id).metadata.conteCameraRoom != to,
          )) {
        history.execute(
          UpdateCutConteCameraRoomCommand(
            repository: repository,
            cutIds: cutIds,
            room: to,
          ),
        );
      }
    });
  }

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

  /// The pasteboard's size (I-109) — one undo step with every picture its
  /// wall cuts ([SetProjectPasteboardCommand]); no-op when unchanged.
  void setProjectPasteboardSize(PasteboardSize size) =>
      _coordinator._executeIfChanged(
        subject: _project,
        value: size,
        read: (project) => project.pasteboardSize,
        command: (_) => _pasteboard(size: size),
      );

  /// What the pasteboard at [size] or [inUse] — the setters' — will cut of
  /// the pictures, worked out ahead as the step itself asks
  /// ([SetProjectPasteboardCommand.workAhead]): for a wait window to hold up
  /// while it runs, hearing through [report] how much is done (F-432).
  Future<void> cutProjectPasteboardAhead({
    PasteboardSize? size,
    bool? inUse,
    void Function(double done)? report,
  }) async {
    await _pasteboard(
      size: size,
      inUse: inUse,
    ).workAhead(undo: false)?.run(report ?? (_) {});
  }

  SetProjectPasteboardCommand _pasteboard({
    PasteboardSize? size,
    bool? inUse,
  }) => SetProjectPasteboardCommand(
    repository: _coordinator.repository,
    brushFrameStore: _coordinator.brushFrameStore,
    size: size,
    inUse: inUse,
  );

  /// Whether the pasteboard is there at all (I-109) — off, nothing reaches
  /// past the paper; one undo step, no-op when unchanged.
  void setProjectPasteboardInUse(bool inUse) => _coordinator._executeIfChanged(
    subject: _project,
    value: inUse,
    read: (project) => project.pasteboardInUse,
    command: (_) => _pasteboard(inUse: inUse),
  );
}
