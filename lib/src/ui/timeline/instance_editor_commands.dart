import 'package:flutter/material.dart';

import '../../models/camera_instruction.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_id.dart';
import '../../models/media_asset.dart' show mediaAssetDefaultName;
import '../../models/text_cel_style.dart';
import '../../services/camera_pose_resolver.dart';
import '../dialogs/camera_key_dialog.dart';
import '../dialogs/frame_name_conflict_dialog.dart';
import '../dialogs/instruction_event_dialog.dart';
import '../dialogs/instruction_set_editor_dialog.dart';
import '../dialogs/rename_frame_dialog.dart';
import '../dialogs/se_instance_dialog.dart';
import '../dialogs/text_cel_dialog.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import 'camera_key_edit.dart';

/// THE instance editor, in one place: what a double-tap on a cell opens, and
/// what the frame pill's `Edit Instance` opens at the playhead.
///
/// Free functions because BOTH frame panels' bars carry that entry now
/// (2026-08-10). They were private methods of the timeline's host — the panel
/// that grew them first — and the storyboard had to pass null and grey the
/// entry out because there was no way to reach them. Nothing in the dispatch
/// is about the timeline: it asks what row you are standing on and what kind
/// of layer owns it, which are session questions.
///
/// [previewAxis] is the one thing a HOST still decides: the miniature inside
/// the SE and instruction dialogs follows the surface's own orientation.
Future<void> activateCellEditor(
  BuildContext context,
  EditorSessionManager session, {
  required LayerId layerId,
  required int frameIndex,
  Axis previewAxis = Axis.horizontal,
}) async {
  final layer = session.activeLayer;
  if (layer == null || layer.id != layerId) {
    return;
  }
  // Pin the EDITING selection to the tapped cell: during playback the tap's
  // select routes to the playback clock and leaves the editing playhead
  // parked elsewhere — every editor below reads/writes selectedFrame, and a
  // stale playhead made the dialog edit the wrong cell (worst on text rows,
  // where Save overwrites the cel).
  if (frameIndex >= 0 && session.currentFrameIndex != frameIndex) {
    session.selectFrameIndex(frameIndex);
  }
  // A LANE row's instance is its KEY. Asked BEFORE the kind switch, because
  // "which row am I standing on" is a different question from "what kind of
  // layer owns it" — a drawing row standing on its Rotation lane would
  // otherwise rename the frame, which is the row's cell and not the thing
  // under the cursor at all.
  if (session.canNameLaneKeys) {
    await _renameLaneKey(context, session);
    return;
  }
  switch (layer.kind) {
    case LayerKind.se:
      await _editSeLabel(context, session, previewAxis);
    case LayerKind.instruction:
      await _editInstructionEvent(
        context,
        session,
        layerId,
        frameIndex,
        previewAxis,
      );
    case LayerKind.camera:
      await _editCameraKeys(context, session, frameIndex);
    case LayerKind.text:
      await _editTextCel(context, session);
    case LayerKind.folder:
    case LayerKind.adjustment:
      // A folder's band is the members' aggregate and an adjustment's is
      // empty: neither has a cell of its own to edit. Their work lives in
      // the twirl-down.
      break;
    case LayerKind.transition:
      // READ-ONLY inside a cut. The cut view windows the track's spans for
      // reading; a double-tap here must not open the editor, or the
      // "컷 타임라인은 보여주기만" law would be broken by the one gesture
      // that looks harmless.
      //
      // ⚠️Reaching the row's editor is NOT this switch's job even on the
      // global axis, because this whole function dispatches on
      // [EditorSessionManager.activeLayer] — the CUT's drawing target — and the
      // storyboard rail's standing row is deliberately separate state (user
      // 2026-07-27: picking a rail row never moves the drawing target). The
      // storyboard host dispatches [editTransitionSpanInstance] off
      // `selectedRow` instead.
      break;
    case LayerKind.animation || LayerKind.storyboard || LayerKind.image:
      await _renameSelectedFrame(context, session);
  }
}

/// The frame pill's `Edit Instance`: the same entrance at the playhead.
Future<void> editActiveInstance(
  BuildContext context,
  EditorSessionManager session, {
  Axis previewAxis = Axis.horizontal,
}) async {
  final layer = session.activeLayer;
  if (layer == null) {
    return;
  }
  await activateCellEditor(
    context,
    session,
    layerId: layer.id,
    frameIndex: session.currentFrameIndex,
    previewAxis: previewAxis,
  );
}

/// Camera cells: per-lane key/value/interpolation dialog at the frame; the
/// edited states fold into ONE track commit (one undo).
Future<void> _editCameraKeys(
  BuildContext context,
  EditorSessionManager session,
  int frameIndex,
) async {
  if (frameIndex < 0) {
    return;
  }
  final cut = session.activeCutOrNull;
  if (cut == null) {
    return;
  }
  final before = cameraKeyLaneStatesAt(
    cut.camera.track,
    frameIndex: frameIndex,
    resolvedPose: resolveCameraPoseAt(
      camera: cut.camera,
      canvasSize: cut.canvasSize,
      frameIndex: frameIndex,
    ),
  );

  final after = await showDialog<List<CameraKeyLaneState>>(
    context: context,
    builder: (context) =>
        CameraKeyDialog(frameIndex: frameIndex, lanes: before),
  );
  if (!context.mounted || after == null) {
    return;
  }

  // Re-read after the dialog: the track may have changed underneath.
  final trackAfterDialog = session.activeCutOrNull?.camera.track;
  if (trackAfterDialog == null) {
    return;
  }
  final next = transformTrackWithKeyDialogApplied(
    trackAfterDialog,
    frameIndex: frameIndex,
    before: before,
    after: after,
  );
  if (next != null) {
    session.updateActiveCutCameraTrack(
      next,
      description: 'Edit camera keys at frame ${frameIndex + 1}',
    );
  }
}

/// SE cells: covered cells edit the covering entry's name/dialogue in the
/// dialog; EMPTY cells create a default one-frame entry DIRECTLY (UI-R25 #2 —
/// creation never opens a dialog; edit it afterwards).
Future<void> _editSeLabel(
  BuildContext context,
  EditorSessionManager session,
  Axis previewAxis,
) async {
  final creating = session.selectedFrame == null;
  if (creating) {
    if (session.canCreateDrawingAtCurrentFrame) {
      session.createSeEntryAtCurrentFrame(name: '', lengthFrames: 1);
    }
    return;
  }

  // R5 #19: the block says what sound it carries. The clip's INDEX is the
  // token — a clip has no id, and it is read once here so the dialog and the
  // unlink below address the same list.
  final linked = session.selectedSeAudioClips;
  final result = await showDialog<SeInstanceDialogResult>(
    context: context,
    builder: (context) => SeInstanceDialog(
      creating: false,
      initialSeName: session.selectedFrameSeName ?? '',
      initialDialogue: session.selectedFrameName ?? '',
      previewAxis: previewAxis,
      linkedAudio: [
        for (final entry in linked)
          (label: mediaAssetDefaultName(entry.clip.filePath), token: entry.index),
      ],
    ),
  );
  if (!context.mounted || result == null) {
    return;
  }

  final seName = result.seName.isEmpty ? null : result.seName;
  // SE edits never hit the link-conflict flow (duplicates allowed).
  session.updateSelectedSeEntry(dialogue: result.dialogue, seName: seName);
  if (result.unlinkedAudioTokens.isNotEmpty) {
    session.unlinkAudioClipsFromActiveLayer(result.unlinkedAudioTokens);
  }
}

/// Text cells (R5): covered cells open the parameter editor; EMPTY cells
/// create a blank cel directly (UI-R25 #2) — the next double-tap types into
/// it.
Future<void> _editTextCel(
  BuildContext context,
  EditorSessionManager session,
) async {
  if (session.selectedFrame == null) {
    if (session.canCreateDrawingAtCurrentFrame) {
      session.createDrawingAtCurrentFrame();
    }
    return;
  }

  final cut = session.activeCutOrNull;
  final content = session.selectedTextCelContent;
  final result = await showDialog<TextCelContent>(
    context: context,
    builder: (context) => TextCelDialog(
      creating: content == null,
      initialContent: content,
      defaultPosition: cut == null
          ? null
          : Offset(cut.canvasSize.width / 2, cut.canvasSize.height / 2),
    ),
  );
  if (!context.mounted || result == null) {
    return;
  }
  session.setTextCelContentForSelectedFrame(result);
}

/// Instruction cells: covered cells edit/delete the covering event in the
/// dialog; EMPTY cells create a default one-frame event DIRECTLY (UI-R25 #2).
/// The vocabulary editor is reachable from the picker.
Future<void> _editInstructionEvent(
  BuildContext context,
  EditorSessionManager session,
  LayerId layerId,
  int frameIndex,
  Axis previewAxis,
) async {
  final covering = session.instructionSpanAt(layerId, frameIndex);
  if (covering == null) {
    session.createDefaultInstructionEventAtCurrentFrame();
    return;
  }

  final result = await showDialog<InstructionEventDialogResult>(
    context: context,
    builder: (dialogContext) => InstructionEventDialog(
      instructionSet: session.cameraInstructionSet,
      initialInstructionId: covering.value.instructionId,
      initialText: covering.value.text,
      initialValueA: covering.value.valueA,
      initialValueB: covering.value.valueB,
      initialMemo: covering.value.memo,
      editing: true,
      onEditInstructionSet: () => _editInstructionSet(dialogContext, session),
      previewAxis: previewAxis,
    ),
  );
  if (!context.mounted || result == null) {
    return;
  }

  if (result.delete) {
    session.removeInstructionEventAt(layerId, frameIndex);
    return;
  }
  final instructionId = result.instructionId;
  if (instructionId == null) {
    return;
  }
  session.upsertInstructionEventAt(
    layerId,
    frameIndex,
    InstructionEvent(
      instructionId: instructionId,
      length: 1,
      text: result.text,
      valueA: result.valueA,
      valueB: result.valueB,
      memo: result.memo,
    ),
    createLengthFrames: 1,
  );
}

/// The TRANSITION row's instance: the span at the playhead on the GLOBAL axis.
///
/// The direction row's flow ([_editInstructionEvent]) with three differences,
/// each forced by what a transition IS:
/// - the frame is [EditorSessionManager.editingGlobalFrame], the one
///   track-global reader — a parked playhead sits in a gap with no active cut,
///   and a gap is a legitimate transition partner
/// - the picker's vocabulary is filtered to the 場面転換 terms, and the
///   vocabulary EDITOR is not offered: it commits the whole set, so editing a
///   filtered copy would drop every camera-work term
/// - LENGTH is not taken from the dialog. The grips own it, so a re-pick can
///   never resize a span out from under the boundary it fires across.
///
/// An EMPTY cell creates, exactly as the direction row's does. That is the whole
/// of the user's 2026-08-11 ask: 「프레임생성하는거 행에 버튼만들어서 넣은거같은데,
/// 그게아니라 인스턴스편집버튼으로 작동하도록. 삭제나 그런거 다 똑같이」 — one verb
/// for create, edit and delete, reached from whatever button the rail grows.
Future<void> editTransitionSpanInstance(
  BuildContext context,
  EditorSessionManager session, {
  int? globalFrame,
  Axis previewAxis = Axis.horizontal,
}) async {
  final frame = globalFrame ?? session.editingGlobalFrame;
  final covering = session.transitionSpanAt(frame);
  if (covering == null) {
    session.createTransitionSpanAtPlayhead();
    return;
  }
  final result = await showDialog<InstructionEventDialogResult>(
    context: context,
    builder: (dialogContext) => InstructionEventDialog(
      instructionSet: session.transitionInstructionSet,
      initialInstructionId: covering.value.instructionId,
      initialText: covering.value.text,
      initialValueA: covering.value.valueA,
      initialValueB: covering.value.valueB,
      initialMemo: covering.value.memo,
      editing: true,
      previewAxis: previewAxis,
    ),
  );
  if (!context.mounted || result == null) {
    return;
  }
  if (result.delete) {
    session.removeTransitionSpanAt(frame);
    return;
  }
  final instructionId = result.instructionId;
  if (instructionId == null) {
    return;
  }
  session.replaceTransitionEventAt(
    frame,
    InstructionEvent(
      instructionId: instructionId,
      length: covering.value.length,
      text: result.text,
      valueA: result.valueA,
      valueB: result.valueB,
      memo: result.memo,
    ),
  );
}

/// Opens the vocabulary editor and commits the edited set immediately (its
/// own undo step), so it sticks even when the event dialog is then cancelled.
/// The already-open picker keeps its old list until reopened.
Future<void> _editInstructionSet(
  BuildContext dialogContext,
  EditorSessionManager session,
) async {
  final edited = await showDialog<CameraInstructionSet>(
    context: dialogContext,
    builder: (context) =>
        InstructionSetEditorDialog(initialSet: session.cameraInstructionSet),
  );
  if (!dialogContext.mounted || edited == null) {
    return;
  }
  session.updateCameraInstructionSet(edited);
}

/// A lane KEY's name — the frame-name flow said of a keyframe, down to the
/// dialog and the confirmation: the same rename prompt, the same
/// [FrameNameConflictDialog] when the name is taken, and joining ADOPTS the
/// value that name already holds instead of imposing this key's (user
/// 2026-08-10: "프레임블록이랑 같은 규칙이면됨").
///
/// An emptied field UN-names the key, which is the only way back to an
/// ordinary unlinked one.
Future<void> _renameLaneKey(
  BuildContext context,
  EditorSessionManager session,
) async {
  if (!session.canNameLaneKeys) {
    return;
  }
  final strings = AppText.strings;
  final nextName = await showDialog<String>(
    context: context,
    builder: (context) => RenameFrameDialog(
      // What the covered keys already AGREE on; blank when they disagree,
      // the same thing the group header says with its `…`.
      initialName: session.laneKeyNameForSelection ?? '',
      title: strings.renameKeyTitle,
      fieldLabel: strings.renameKeyField,
    ),
  );
  if (!context.mounted || nextName == null) {
    return;
  }

  // The RANGE form is the only one called: a single key is the one-frame
  // span at the playhead, so naming one and naming five is the same verb
  // (user 2026-08-10, "선택범위로 통하는 조작이 모두 다른것들이랑 동일한
  // 로직"). The covered keys of a lane land on ONE value, which is what a
  // shared name means.
  final trimmed = nextName.trim();
  final taken = session.setLaneKeyNamesForSelection(
    trimmed.isEmpty ? null : trimmed,
  );
  if (!taken) {
    return;
  }

  // Asked ONCE for the whole range, never once per key.
  final shouldLink = await showDialog<bool>(
    context: context,
    builder: (context) => const FrameNameConflictDialog(),
  );
  if (!context.mounted || shouldLink != true) {
    return;
  }

  session.linkLaneKeyNamesForSelection(trimmed);
}

Future<void> _renameSelectedFrame(
  BuildContext context,
  EditorSessionManager session,
) async {
  if (session.selectedFrame == null ||
      !session.canRenameFrameAtCurrentFrame) {
    return;
  }

  final nextName = await showDialog<String>(
    context: context,
    builder: (context) =>
        RenameFrameDialog(initialName: session.selectedFrameName ?? ''),
  );
  if (!context.mounted || nextName == null) {
    return;
  }

  final conflictingFrameId = session.renameSelectedFrame(nextName);
  if (conflictingFrameId == null) {
    return;
  }

  final shouldLink = await showDialog<bool>(
    context: context,
    builder: (context) => const FrameNameConflictDialog(),
  );
  if (!context.mounted || shouldLink != true) {
    return;
  }

  session.linkSelectedFrame(conflictingFrameId);
}
