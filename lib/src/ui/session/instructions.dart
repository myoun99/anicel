import 'dart:collection';
import 'dart:math' as math;

import '../../models/camera_instruction.dart';
import '../../models/frame.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_coverage.dart';
import '../../models/timeline_exposure.dart';
import '../../models/timesheet_document.dart' show timesheetMemoInstructionLine;
import '../timeline/instruction_span_editing.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';
import 'cut_verbs.dart';
import 'camera.dart';

/// The INSTRUCTIONS — the spans a direction row carries, the span at a
/// frame, and creating, upserting and removing them — as their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: no field of its own and eight
/// session members touched. It names the roles it needs in its constructor.
///
/// ★A direction row's span IS its block (R27, [LayerKind.spansRideBlocks]),
/// so these verbs write blocks: creating one lays a block on a cel of its
/// own, editing one changes what its block says, and removing one is the
/// block delete — the delete button's own code.
class Instructions {
  Instructions({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required FrameIds frameIds,
    required ActiveCutControllers controllers,
    required CutVerbs cutVerbs,
    required Camera camera,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers,
       _cutVerbs = cutVerbs,
       _camera = camera;

  final CutVerbs _cutVerbs;
  final Camera _camera;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final FrameIds _frameIds;
  final ActiveCutControllers _controllers;

  /// The instruction span covering [frameIndex] on [layerId], as
  /// (startIndex, event); null on empty cells / non-instruction rows.
  MapEntry<int, InstructionEvent>? instructionSpanAt(
    LayerId layerId,
    int frameIndex,
  ) {
    final layer = _project.layerById(layerId);
    if (layer == null || layer.kind != LayerKind.instruction) {
      return null;
    }
    return instructionSpanCovering(layer.instructions, frameIndex);
  }

  /// Dialog-free instruction creation (UI-R25 #2, 조작 통일화): an EMPTY
  /// instruction cell gains a ONE-frame event of the vocabulary's first
  /// entry directly — the Edit Instance dialog changes it afterwards.
  /// Covered cells no-op (creation never edits).
  void createDefaultInstructionEventAtCurrentFrame() {
    final layer = _selection.activeLayer;
    if (layer == null || layer.kind != LayerKind.instruction) {
      return;
    }
    final frameIndex = _controllers.timelineController.currentFrameIndex;
    if (frameIndex < 0 ||
        instructionSpanAt(layer.id, frameIndex) != null ||
        _camera.cameraInstructionSet.defs.isEmpty) {
      return;
    }
    upsertInstructionEventAt(
      layer.id,
      frameIndex,
      InstructionEvent(
        instructionId: _camera.cameraInstructionSet.defs.first.id,
        length: 1,
      ),
      createLengthFrames: 1,
    );
  }

  /// Creates or edits the instruction event at [frameIndex] in ONE undo
  /// step: a covered cell replaces what its block says (start and length
  /// stay, and so does the drawing), an empty cell lays a new block on a
  /// cel of its own, holding for the dialog's length — clamped into the
  /// cut and at the next block.
  void upsertInstructionEventAt(
    LayerId layerId,
    int frameIndex,
    InstructionEvent event, {
    int? createLengthFrames,
  }) {
    final layer = _project.layerById(layerId);
    if (layer == null || layer.kind != LayerKind.instruction) {
      return;
    }

    // A resolvable instruction layer implies an active cut.
    final available = (_project.requireActiveCut.duration - frameIndex).clamp(
      1,
      1 << 20,
    );
    final covering = coveringDrawingBlockAt(layer.timeline, frameIndex);
    final edits = covering != null && !covering.entry.ghost;
    final Layer Function(Layer row) spans;
    if (edits) {
      spans = (row) => row.copyWith(
        timeline: {
          ...row.timeline,
          covering.startIndex: covering.entry.copyWith(
            instruction: () => event.writing,
          ),
        },
      );
    } else {
      final cel = _frameIds.mintFrameId(layerId);
      final wanted = (createLengthFrames ?? available).clamp(1, available);
      spans = (row) {
        // A ghost is a hold's projection, not a block: it neither stops the
        // new one nor survives beside it (the edit re-derives it).
        final authored = SplayTreeMap.of(row.timeline)
          ..removeWhere((_, entry) => entry.ghost);
        final next = nextDrawingBlockAfter(authored, frameIndex)?.startIndex;
        return row.copyWith(
          frames: [
            ...row.frames,
            Frame(id: cel, duration: 1, strokes: const []),
          ],
          timeline: {
            ...authored,
            frameIndex: TimelineExposure.drawing(
              cel,
              length: next == null
                  ? wanted
                  : math.min(wanted, next - frameIndex),
              instruction: event.writing,
            ),
          },
        );
      };
    }
    // The sheet's memo shorthand ('A→B PAN memo') writes itself ONCE at
    // creation and stays user-editable note text from then on (R5-⑥ — the
    // derived always-printed line could not be edited). Edits and removals
    // never rewrite the note; the user owns it. Event + note = ONE undo.
    String? appendedNote;
    if (!edits) {
      final line = timesheetMemoInstructionLine(
        event,
        _camera.cameraInstructionSet.defById(event.instructionId),
      );
      if (line.isNotEmpty) {
        final note = _cutVerbs.activeCutNote ?? '';
        appendedNote = note.isEmpty ? line : '$note\n$line';
      }
    }
    _project.cutCommandCoordinator.updateDirectionSpans(
      cutId: _project.requireActiveCut.id,
      layerId: layerId,
      spans: spans,
      description: edits ? 'Edit instruction' : 'Add instruction',
      note: appendedNote,
    );
    _changes.notifyChanged();
  }

  /// Removes the instruction span covering [frameIndex] — the block it is,
  /// with its drawing, by the delete button's own code; one undo step.
  void removeInstructionEventAt(LayerId layerId, int frameIndex) {
    final layer = _project.layerById(layerId);
    if (layer == null || layer.kind != LayerKind.instruction) {
      return;
    }
    final covering = coveringDrawingBlockAt(layer.timeline, frameIndex);
    if (covering == null || covering.entry.ghost) {
      return;
    }
    _controllers.timelineController.deleteBlocksForLayer(
      layerId: layerId,
      blockStartIndexes: [covering.startIndex],
    );
    _changes.notifyChanged();
  }
}
