import 'dart:collection';
import 'dart:math' as math;

import '../../models/camera_instruction.dart';
import '../../models/cel_bank_lanes.dart' show layerJoined;
import '../../models/exposure_instruction.dart';
import '../../models/frame.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/timeline_coverage.dart';
import '../../models/timeline_exposure.dart';
import '../timeline/instruction_span_editing.dart';
import 'active_cut_controllers.dart';
import 'session_roles.dart';

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
  }) : _project = project,
       _selection = selection,
       _changes = changes,
       _frameIds = frameIds,
       _controllers = controllers;

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
  ) => switch (_directionRow(layerId)) {
    final layer? => instructionSpanCovering(layer.instructions, frameIndex),
    null => null,
  };

  /// Whether [createDefaultInstructionEventAtCurrentFrame] makes a block —
  /// the ONE sentence its press and the ＋ that lights for it read (T25).
  ///
  /// 🗣️F-107 (유저 2026-09-12): 「불가능한 버튼 비활성화 … 그 외도 있나
  /// 확인」. ↩️The ＋ lit on every direction cell while the press made
  /// nothing on a covered one (F-339: 「버튼 활성화되고 눌러도 아무반응없는데」).
  bool get canCreateDefaultInstructionEventAtCurrentFrame {
    final layer = _selection.activeLayer;
    if (layer == null || layer.kind != LayerKind.instruction) {
      return false;
    }
    final frameIndex = _controllers.timelineController.currentFrameIndex;
    return frameIndex >= 0 && instructionSpanAt(layer.id, frameIndex) == null;
  }

  /// Dialog-free instruction creation (UI-R25 #2, 조작 통일화): an EMPTY
  /// instruction cell gains a ONE-frame block that says nothing — the Edit
  /// Instance dialog tells it something afterwards, as an SE entry made here
  /// is named afterwards. Covered cells no-op (creation never edits).
  ///
  /// 🗣️I-72-block-without-instruction (유저 2026-10-08): 「생성시 기본값
  /// 없음」. ↩️The block took the vocabulary's first entry, and an emptied
  /// vocabulary left the ＋ dark.
  void createDefaultInstructionEventAtCurrentFrame() {
    if (!canCreateDefaultInstructionEventAtCurrentFrame) {
      return;
    }
    final layer = _selection.activeLayer!;
    final frameIndex = _controllers.timelineController.currentFrameIndex;
    upsertInstructionEventAt(
      layer.id,
      frameIndex,
      const InstructionEvent(instructionId: null, length: 1),
      createLengthFrames: 1,
    );
  }

  /// Creates or edits the instruction event at [frameIndex] in ONE undo
  /// step: a covered cell replaces what its block says — and what every
  /// block showing its drawing says, the blocks it is linked with (start
  /// and length stay, and so does the drawing) — an empty cell lays a new
  /// block on a cel of its own, holding for the dialog's length — clamped
  /// into the cut and at the next block.
  ///
  /// 🗣️I-72-direction-link: what a block says names its drawing
  /// ([linkNameOfWriting]), so an edit that would say what ANOTHER drawing
  /// of the row says writes nothing and hands back that drawing — the link
  /// is the user's to take ([linkInstructionEventAt]), as a rename onto a
  /// held name is (`FrameVerbs.renameSelectedFrame`). Null when it wrote.
  FrameId? upsertInstructionEventAt(
    LayerId layerId,
    int frameIndex,
    InstructionEvent event, {
    int? createLengthFrames,
  }) {
    final layer = _directionRow(layerId);
    if (layer == null) {
      return null;
    }

    // A resolvable instruction layer implies an active cut.
    final available = (_project.requireActiveCut.duration - frameIndex).clamp(
      1,
      1 << 20,
    );
    final covering = authoredDrawingBlockAt(layer.timeline, frameIndex);
    final edits = covering != null;
    final Layer Function(Layer row) spans;
    if (edits) {
      final drawing = covering.frameId;
      if (_drawingSaying(layer, event.writing, besides: drawing)
          case final held?) {
        return held;
      }
      spans = (row) => _sayingOnEveryBlockOf(row, drawing, event.writing);
    } else {
      // A new block saying what a drawing of the row says shows that one,
      // and says it with that one's blocks: nothing is thrown away, so
      // there is nothing to ask.
      final held = _drawingSaying(layer, event.writing);
      final cel = held ?? _frameIds.mintFrameId(layerId);
      final wanted = (createLengthFrames ?? available).clamp(1, available);
      spans = (row) {
        // A ghost is a hold's projection, not a block: it neither stops the
        // new one nor survives beside it (the edit re-derives it).
        final authored = SplayTreeMap.of(row.timeline)
          ..removeWhere((_, entry) => entry.ghost);
        final next = nextDrawingBlockAfter(authored, frameIndex)?.startIndex;
        final laid = row.copyWith(
          frames: [
            ...row.frames,
            if (held == null) Frame(id: cel, duration: 1, strokes: const []),
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
        return held == null
            ? laid
            : _sayingOnEveryBlockOf(laid, held, event.writing);
      };
    }
    // ⛔A direction writes nothing into the sheet's memo (I-72, 유저
    // 2026-10-05: 「디렉션레이어, 작성하거나 하면 타임시트용지에 해당 지시
    // 적어주는데 그 동작 잔재 안남도록 싹 삭제. 앞으론 디렉션레이어 만든게
    // 타임시트 용지의 메모란에 텍스트로 추가되지않음」). ↩️Its shorthand
    // ('A→B PAN memo') wrote itself into the cut note at creation (R5-⑥),
    // with a memo field of its own on the instruction to feed it.
    _project.cutCommandCoordinator.updateDirectionSpans(
      cutId: _project.requireActiveCut.id,
      layerId: layerId,
      spans: spans,
      description: edits ? 'Edit instruction' : 'Add instruction',
    );
    _changes.notifyChanged();
    return null;
  }

  /// Links the block covering [frameIndex] to [held] — the drawing of the
  /// row that already says what [event] says ([upsertInstructionEventAt]
  /// handed it back) — and says [event] on every block of [held]: the
  /// blocks of the drawing the block showed show [held], and that drawing
  /// goes from the bank unless a lane of it still shows it ([layerJoined],
  /// the rename's join). ONE undo step.
  void linkInstructionEventAt(
    LayerId layerId,
    int frameIndex,
    InstructionEvent event,
    FrameId held,
  ) {
    final drawing = _directionBlockAt(layerId, frameIndex)?.frameId;
    if (drawing == null) {
      return;
    }
    final bank = _controllers.timelineController.bankLanesOf(layerId);
    _project.cutCommandCoordinator.updateDirectionSpans(
      cutId: _project.requireActiveCut.id,
      layerId: layerId,
      spans: (row) => _sayingOnEveryBlockOf(
        layerJoined(row, {drawing: held}, bank: bank),
        held,
        event.writing,
      ),
      description: 'Link instruction',
    );
    _changes.notifyChanged();
  }

  /// [layerId]'s row where it is a direction row; null for any other.
  Layer? _directionRow(LayerId layerId) =>
      switch (_project.layerById(layerId)) {
        final layer? when layer.kind == LayerKind.instruction => layer,
        _ => null,
      };

  /// The block a person wrote covering [frameIndex] on the direction row
  /// [layerId] — what a link and a delete of a block stand on.
  TimelineDrawingBlock? _directionBlockAt(LayerId layerId, int frameIndex) =>
      switch (_directionRow(layerId)) {
        final layer? => authoredDrawingBlockAt(layer.timeline, frameIndex),
        null => null,
      };

  /// The drawing of [layer] — other than [besides] — that already says
  /// what [writing] says: the one holding the name it gives
  /// ([linkNameOfWriting]). None where it names no end.
  FrameId? _drawingSaying(
    Layer layer,
    ExposureInstruction? writing, {
    FrameId? besides,
  }) {
    final name = linkNameOfWriting(
      writing,
      switch (writing?.instructionId) {
        final id? => _project.repository
            .requireProject()
            .cameraInstructions
            .defById(id),
        null => null,
      },
    );
    if (name == null) {
      return null;
    }
    for (final frame in layer.frames) {
      if (frame.id != besides && frame.name == name) {
        return frame.id;
      }
    }
    return null;
  }

  /// [row] with [writing] said on every block that shows [drawing] — what
  /// the drawing's blocks say is one thing, as the drawing is.
  Layer _sayingOnEveryBlockOf(
    Layer row,
    FrameId drawing,
    ExposureInstruction? writing,
  ) => row.copyWith(
    timeline: {
      for (final MapEntry(key: start, value: entry) in row.timeline.entries)
        start: !entry.ghost && entry.frameId == drawing
            ? entry.copyWith(instruction: () => writing)
            : entry,
    },
  );

  /// Removes the instruction span covering [frameIndex] — the block it is,
  /// with its drawing, by the delete button's own code; one undo step.
  void removeInstructionEventAt(LayerId layerId, int frameIndex) {
    final covering = _directionBlockAt(layerId, frameIndex);
    if (covering == null) {
      return;
    }
    _controllers.timelineController.deleteBlocksForLayer(
      layerId: layerId,
      blockStartIndexes: [covering.startIndex],
    );
    _changes.notifyChanged();
  }
}
