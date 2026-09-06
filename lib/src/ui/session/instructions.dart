import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timesheet_document.dart' show timesheetMemoInstructionLine;
import '../../models/timeline_frame_range.dart';
import '../../services/command.dart';
import '../../services/commands/update_layer_instructions_command.dart';
import '../timeline/instruction_span_editing.dart';
import 'session_roles.dart';
import 'cut_verbs.dart';
import 'camera.dart';

/// The INSTRUCTIONS — the events a layer carries on its instruction lane,
/// the span at a frame, and creating, upserting and removing them — as
/// their own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: no field of its own and eight
/// session members touched. It names the roles it needs in its constructor.
class Instructions {
  Instructions({
    required ProjectAccess project,
    required SelectionAccess selection,
    required ChangeSink changes,
    required TimelineAccess timeline,
    required CutVerbs cutVerbs,
    required Camera camera,
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _timeline = timeline,
       _cutVerbs = cutVerbs,
       _camera = camera;

  final CutVerbs _cutVerbs;
  final Camera _camera;

  final ProjectAccess _project;
  final SelectionAccess _selection;
  final ChangeSink _changes;
  final TimelineAccess _timeline;

  /// Replaces [layerId]'s instruction span map (instruction rows only).
  /// One undo step; no-op when unchanged. Never touches rendering caches —
  /// instruction spans are timeline annotations, not composite inputs.
  void updateLayerInstructions(
    LayerId layerId,
    Map<int, InstructionEvent> instructions, {
    String description = 'Edit instructions',
  }) {
    final cutId = _timeline.editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _project.cutCommandCoordinator.updateLayerInstructions(
      cutId: cutId,
      layerId: layerId,
      instructions: instructions,
      description: description,
    );
    _changes.notifyChanged();
  }

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
    final frameIndex = _timeline.timelineController.currentFrameIndex;
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
  /// step: a covered cell replaces its span's event (start/length stay), an
  /// empty cell starts a new span holding to the next one / the cut's end.
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

    // New events take the dialog's length (clamped into the cut; the add
    // helper clamps at the next span too); null fills to the cut end.
    // A resolvable instruction layer implies an active cut.
    final available = (_project.requireActiveCut.duration - frameIndex).clamp(
      1,
      1 << 20,
    );
    final covering = instructionSpanCovering(layer.instructions, frameIndex);
    final next = covering != null
        ? instructionMapWithEventReplaced(
            layer.instructions,
            spanStartIndex: covering.key,
            event: event,
          )
        : instructionMapWithEventAdded(
            layer.instructions,
            startIndex: frameIndex,
            event: event.copyWith(
              length: (createLengthFrames ?? available).clamp(1, available),
            ),
          );
    if (next == null) {
      return;
    }
    // The sheet's memo shorthand ('A→B PAN memo') writes itself ONCE at
    // creation and stays user-editable note text from then on (R5-⑥ — the
    // derived always-printed line could not be edited). Edits and removals
    // never rewrite the note; the user owns it. Event + note = ONE undo.
    String? appendedNote;
    if (covering == null) {
      final line = timesheetMemoInstructionLine(
        event,
        _camera.cameraInstructionSet.defById(event.instructionId),
      );
      if (line.isNotEmpty) {
        final note = _cutVerbs.activeCutNote ?? '';
        appendedNote = note.isEmpty ? line : '$note\n$line';
      }
    }
    _project.cutCommandCoordinator.updateLayerInstructions(
      cutId: _project.requireActiveCut.id,
      layerId: layerId,
      instructions: next,
      description: covering == null ? 'Add instruction' : 'Edit instruction',
      note: appendedNote,
    );
    _changes.notifyChanged();
  }

  /// Removes the instruction span covering [frameIndex]; one undo step.
  void removeInstructionEventAt(LayerId layerId, int frameIndex) {
    final layer = _project.layerById(layerId);
    if (layer == null || layer.kind != LayerKind.instruction) {
      return;
    }
    final covering = instructionSpanCovering(layer.instructions, frameIndex);
    if (covering == null) {
      return;
    }
    final next = instructionMapWithEventRemoved(
      layer.instructions,
      spanStartIndex: covering.key,
    );
    if (next == null) {
      return;
    }
    updateLayerInstructions(layerId, next, description: 'Delete instruction');
  }

  Command? instructionEventsCommandForRange(
    Layer layer,
    TimelineFrameRangeSelection selection,
  ) {
    final cutId = _timeline.editingSession.activeCutId;
    final defaultDef = _camera.cameraInstructionSet.defs.isEmpty
        ? null
        : _camera.cameraInstructionSet.defs.first;
    if (defaultDef == null || cutId == null) {
      return null;
    }
    bool covered(int index) {
      for (final entry in layer.instructions.entries) {
        if (index >= entry.key && index < entry.key + entry.value.length) {
          return true;
        }
      }
      return false;
    }

    final next = Map<int, InstructionEvent>.of(layer.instructions);
    var changed = false;
    int? gapStart;
    for (
      var index = selection.startIndex;
      index <= selection.endIndexExclusive;
      index += 1
    ) {
      final inGap =
          index < selection.endIndexExclusive && index >= 0 && !covered(index);
      if (inGap) {
        gapStart ??= index;
        continue;
      }
      if (gapStart != null) {
        next[gapStart] = InstructionEvent(
          instructionId: defaultDef.id,
          length: index - gapStart,
        );
        changed = true;
        gapStart = null;
      }
    }
    if (!changed) {
      return null;
    }
    return UpdateLayerInstructionsCommand(
      repository: _project.repository,
      cutId: cutId,
      layerId: layer.id,
      instructions: next,
      description: 'Create events',
    );
  }
}
