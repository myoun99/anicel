import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_instruction.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/services/commands/cut_command_coordinator.dart';
import 'package:anicel/src/services/editing/editing_session_state.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';

/// **⛔EVERY EQUALITY-GUARDED SETTER IS "ONE UNDO STEP, NO-OP WHEN
/// UNCHANGED".**
///
/// Fifteen verbs across the coordinator and its collaborators wrote that
/// guard out by hand; the repo had already unified it twice (layer- and
/// project-addressed) and left the cut-addressed ones written out. This
/// sweeps every one of them so the shared guard cannot go missing from a
/// verb without a red test — the failure it prevents is invisible in the
/// project state and shows up only as an undo stack full of steps that
/// changed nothing.
void main() {
  ({CutCommandCoordinator coordinator, HistoryManager history, Project project})
  fixture() {
    final project = createDefaultProject();
    final repository = ProjectRepository(initialProject: project);
    final history = HistoryManager();
    return (
      coordinator: CutCommandCoordinator(
        repository: repository,
        editingSession: EditingSessionState(
          activeCutId: project.tracks.first.cuts.first.id,
        ),
        historyManager: history,
      ),
      history: history,
      project: repository.requireProject(),
    );
  }

  /// Runs [write] twice: the first call must bank exactly one undo step,
  /// the second — the same value again — must bank nothing.
  void banksOnce(
    String name,
    void Function(CutCommandCoordinator coordinator) write,
  ) {
    test('$name banks once, then nothing', () {
      final f = fixture();
      write(f.coordinator);
      expect(
        f.history.undoCount,
        1,
        reason: 'LIVENESS — $name has to have changed something first',
      );
      write(f.coordinator);
      expect(
        f.history.undoCount,
        1,
        reason: 'the second write is the same value: no second undo step',
      );
    });
  }

  group('cut-addressed', () {
    CutId cutOf(CutCommandCoordinator coordinator) =>
        coordinator.repository.requireProject().tracks.first.cuts.first.id;

    banksOnce(
      'updateCutNote',
      (c) => c.updateCutNote(cutId: cutOf(c), note: 'a note'),
    );
    banksOnce(
      'updateCutThumbnailFrame',
      (c) => c.updateCutThumbnailFrame(cutId: cutOf(c), frameIndex: 3),
    );
    banksOnce(
      'resizeCutCanvas',
      (c) => c.resizeCutCanvas(
        cutId: cutOf(c),
        canvasSize: const CanvasSize(width: 640, height: 480),
      ),
    );
    banksOnce(
      'updateCutCamera',
      (c) => c.updateCutCamera(
        cutId: cutOf(c),
        camera: CutCamera.empty().withKeyframe(2, CameraPose(center: CanvasPoint(x: 10, y: 10), zoom: 2)),
      ),
    );
    banksOnce(
      'setCutCameraKeyframe',
      (c) => c.setCutCameraKeyframe(
        cutId: cutOf(c),
        frameIndex: 1,
        pose: CameraPose(center: CanvasPoint(x: 5, y: 5), zoom: 1.5),
      ),
    );

    test('removeCutCameraKeyframe banks once, then nothing', () {
      final f = fixture();
      final cutId = cutOf(f.coordinator);
      f.coordinator.setCutCameraKeyframe(
        cutId: cutId,
        frameIndex: 1,
        pose: CameraPose(center: CanvasPoint(x: 5, y: 5), zoom: 1.5),
      );
      final before = f.history.undoCount;
      f.coordinator.removeCutCameraKeyframe(cutId: cutId, frameIndex: 1);
      expect(f.history.undoCount, before + 1);
      f.coordinator.removeCutCameraKeyframe(cutId: cutId, frameIndex: 1);
      expect(
        f.history.undoCount,
        before + 1,
        reason: 'removing a keyframe that is already gone banks nothing',
      );
    });

    test('clearCutCamera banks once, then nothing', () {
      final f = fixture();
      final cutId = cutOf(f.coordinator);
      f.coordinator.setCutCameraKeyframe(
        cutId: cutId,
        frameIndex: 1,
        pose: CameraPose(center: CanvasPoint(x: 5, y: 5), zoom: 1.5),
      );
      final before = f.history.undoCount;
      f.coordinator.clearCutCamera(cutId: cutId);
      expect(f.history.undoCount, before + 1);
      f.coordinator.clearCutCamera(cutId: cutId);
      expect(
        f.history.undoCount,
        before + 1,
        reason: 'an already-empty camera has nothing to clear',
      );
    });
  });

  group('layer-addressed (the ⚠️anywhere lookup)', () {
    ({CutId cutId, LayerId layerId}) rowOf(CutCommandCoordinator coordinator) {
      final cut = coordinator.repository.requireProject().tracks.first.cuts
          .first;
      return (cutId: cut.id, layerId: cut.layers.first.id);
    }

    // The target is FIXED (not read back per call): writing the negation of
    // whatever is there would flip the flag twice and bank twice for the
    // right reason, which is not what this measures.
    final sheetTarget = !createDefaultProject()
        .tracks
        .first
        .cuts
        .first
        .layers
        .first
        .onTimesheet;
    banksOnce('setLayerTimesheet', (c) {
      final row = rowOf(c);
      c.setLayerTimesheet(
        cutId: row.cutId,
        layerId: row.layerId,
        onTimesheet: sheetTarget,
      );
    });

    banksOnce('setLayerFillReference', (c) {
      final row = rowOf(c);
      c.setLayerFillReference(
        cutId: row.cutId,
        layerId: row.layerId,
        isFillReference: true,
      );
    });

    banksOnce('setLayerMark', (c) {
      final row = rowOf(c);
      c.setLayerMark(
        cutId: row.cutId,
        layerId: row.layerId,
        mark: const LayerMark(process: LayerProcess.layout),
      );
    });

    test('a TRACK-owned SE row is reachable — it is in no cut layer list', () {
      final f = fixture();
      final se = f.coordinator.repository
          .requireProject()
          .tracks
          .first
          .seLayers
          .first;
      f.coordinator.setLayerMark(
        cutId: f.coordinator.repository
            .requireProject()
            .tracks
            .first
            .cuts
            .first
            .id,
        layerId: se.id,
        mark: const LayerMark(process: LayerProcess.conte),
      );
      expect(
        f.history.undoCount,
        1,
        reason: 'the anywhere lookup is why this does not throw',
      );
    });
  });

  group('project-addressed', () {
    banksOnce(
      'setTimesheetInfo',
      (c) => c.setTimesheetInfo(const TimesheetInfo(title: 'T')),
    );
    banksOnce(
      'setProjectBackground',
      (c) => c.setProjectBackground(const ProjectBackground.color(0xFF123456)),
    );
    banksOnce('setProjectBackdrop', (c) => c.setProjectBackdrop(0xFF102030));
    banksOnce('setProjectPasteboard', (c) => c.setProjectPasteboard(0x80112233));
    banksOnce(
      'setProjectPasteboardMargin',
      (c) => c.setProjectPasteboardMargin(0.75),
    );
    // Also a FIXED value: appending to what is there would grow the set on
    // every call and bank every time for the right reason.
    final grownSet = CameraInstructionSet(
      defs: [
        ...createDefaultProject().cameraInstructions.defs,
        const CameraInstructionDef(id: 'zz', name: 'ZZ', iconKey: 'bar'),
      ],
    );
    banksOnce(
      'updateCameraInstructionSet',
      (c) => c.updateCameraInstructionSet(grownSet),
    );
  });
}
