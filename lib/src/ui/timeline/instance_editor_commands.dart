import 'package:flutter/material.dart';

import '../../models/camera_instruction.dart';
import '../../models/edit_instance_subject.dart';
import '../../models/frame.dart' show Frame;
import '../../models/frame_id.dart';
import '../../models/layer_kind.dart';
import '../../models/property_track.dart' show PropertyKeyInterpolation;
import '../../models/layer_id.dart';
import '../../models/media_asset.dart' show mediaAssetDefaultName;
import '../../models/text_cel_style.dart';
import '../../models/timeline_coverage.dart' show coveringDrawingBlockAt;
import '../../services/project_lookup.dart' show layerAnywhereOrNull;
import '../editor_command_actions.dart' show createActiveInstance;
import '../dialogs/dialog_verb.dart';
import '../dialogs/frame_name_conflict_dialog.dart';
import '../dialogs/instruction_event_dialog.dart';
import '../dialogs/instruction_set_editor_dialog.dart';
import '../dialogs/rename_frame_dialog.dart';
import '../dialogs/se_instance_dialog.dart';
import '../dialogs/text_cel_dialog.dart';
import '../editor_session_manager.dart';
import '../export/export_settings_modules.dart'
    show ExportPillItem, ExportPillStrip;
import '../text/app_strings.dart';
import 'layer_name_commands.dart'
    show renameActiveCutWithDialog, renameActiveLayerWithDialog;

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
  //
  // ⚠️And a lane cell with NO key has no instance: the answer is nothing,
  // not the owner's cel, which is where this used to fall through to. The
  // camera row answers here too — it IS its transform header (F-17), and
  // the lane verbs say so.
  if (session.laneVerbs.laneVerbRange != null) {
    if (session.laneVerbs.canNameLaneKeys) {
      await _renameLaneKey(context, session);
    }
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
      // 🗣️F-17 (유저 2026-09-01): 「카메라레이어 헤더에서 편집작동시키면
      // 아직도 카메라 키 창 뜸. 이거 없애라고. 공통창 키 이름변경 창
      // 뜨게하라고. 다른 fx헤더에서 그렇게 뜨잖아」. The camera row's
      // instance is its KEY, answered by the lane branch above through the
      // common window; this arm is reached only under a cell band holding
      // more than the camera, which claims the press as cells.
      break;
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

/// 🚨★★★I-9 — WHAT A DOUBLE TAP ON A CELL MEANS: 「빈 칸이면 만들고, 찬 칸
/// 이면 연다」.
///
/// 유저 확정 2026-08-29 (I-9-Q2 = `all-kinds`): every row kind creates, each
/// through the verb it already has. 유저 원문: 「타임라인의 se행이랑
/// 트랜지션행이었는데 통일되서 사라졌을수도? 아무튼 **새로만들자.**」
///
/// ⛔SEPARATE from [activateCellEditor] on purpose, and this is the whole
/// reason: that function is ALSO the shared pill's `Edit Instance`, which
/// must never create. A fork inside it made the button author a camera key
/// instead of opening the key dialog — one entrance answering two gestures.
/// The double tap is a gesture with two meanings; the button has one.
Future<void> activateCellOnDoubleTap(
  BuildContext context,
  EditorSessionManager session, {
  required LayerId layerId,
  required int frameIndex,
  Axis previewAxis = Axis.horizontal,
}) async {
  // The tap already seeked here (the press-seek gate), so the session's
  // 「is something in this cell」 is asked of the cell that was tapped.
  if (frameIndex >= 0 && session.currentFrameIndex != frameIndex) {
    session.selectFrameIndex(frameIndex);
  }
  // ⚠️Asked AFTER the seek, and of the ROW you stand on: a LANE row's
  // instance is its KEY (the camera row's too — it IS its transform
  // header), so a lane cell with no key is EMPTY whatever cel its owner
  // holds under the playhead, and the double tap keys it. 유저 2026-09-11:
  // 「트랜스폼행에서 더블클릭으로 편집창 안열리는것등 이런거 싹 법 하나로
  // 통일」 — the frame block's 「빈 칸이면 만들고, 찬 칸이면 연다」 on every
  // row.
  final instanceHere = session.laneVerbs.laneVerbRange != null
      ? session.laneVerbs.canNameLaneKeys
      : session.cellInstances.activeCellHoldsAnInstance;
  if (!instanceHere) {
    createActiveInstance(session);
    return;
  }
  await activateCellEditor(
    context,
    session,
    layerId: layerId,
    frameIndex: frameIndex,
    previewAxis: previewAxis,
  );
}

/// 🚨T25 — the SHARED pill's `Edit Instance`: whatever is selected, renamed.
///
/// 유저 확정 2026-08-14: 「인스턴스 편집 버튼도 공통버튼으로 이동. 그래서
/// **선택범위 통해 동사통일화** 가능하게. 그러고 **레이어 이름변경 버튼
/// 필요없어지니 삭제**」.
///
/// ★The ladder is delete's ([EditInstanceSubject]), and each rung was
/// already a working verb — this gives the three of them one door.
///
/// ⚠️The layer rung in particular was ALREADY the batch confirmed #20 asks
/// for (「선택된 편집가능 레이어 전부를 같은 이름으로 일괄 변경」):
/// `renameActiveLayerWithDialog` reads `renameableSelectedLayerIds` and
/// commits `renameSelectedLayers`. Deleting the loose rename button is safe
/// BECAUSE of that — the successor does the predecessor's whole job, which
/// is the condition [[duplication-program]] makes the last step wait for.
Future<void> editSelectionInstance(
  BuildContext context,
  EditorSessionManager session, {
  Axis previewAxis = Axis.horizontal,
  // R5q1: the TIMELINE's Edit does not reach for cuts — they are the
  // storyboard's noun. Defaulted true so the storyboard's own callers keep
  // the rung; the timeline host passes false.
  bool cutsAreThisPanels = true,
}) async {
  switch (session.cellInstances.editInstanceSubjectFor(
    cutsAreThisPanels: cutsAreThisPanels,
  )) {
    case EditInstanceSubject.cuts:
      await renameActiveCutWithDialog(context, session);
    case EditInstanceSubject.layers:
      await renameActiveLayerWithDialog(context, session);
    case EditInstanceSubject.cells:
      await editActiveInstance(context, session, previewAxis: previewAxis);
    case EditInstanceSubject.nothing:
      break;
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
    if (session.frameVerbs.canCreateDrawingAtCurrentFrame) {
      session.seEntries.createSeEntryAtCurrentFrame(name: '', lengthFrames: 1);
    }
    return;
  }

  // R5 #19: the block says what sound it carries. The clip's INDEX is the
  // token — a clip has no id, and it is read once here so the dialog and the
  // unlink below address the same list.
  final linked = session.audioClips.selectedSeAudioClips;
  await _editSeEntryWithDialog(
    context,
    initialSeName: session.seEntries.selectedFrameSeName ?? '',
    initialDialogue: session.selectedFrameName ?? '',
    linkedAudio: [
      for (final entry in linked)
        (label: mediaAssetDefaultName(entry.clip.filePath), token: entry.index),
    ],
    previewAxis: previewAxis,
    commit: (dialogue, seName) =>
        session.seEntries.updateSelectedSeEntry(dialogue: dialogue, seName: seName),
    unlink: session.audioClips.unlinkAudioClipsFromActiveLayer,
  );
}

/// The SE instance editor addressed on the GLOBAL axis — the storyboard's
/// door (B6 2026-08-17: 「스토리보드 SE 레이어 … 더블클릭 편집창 미동작」).
///
/// The SAME dialog and the same commits as the timeline's cell double-tap
/// ([_editSeLabel]), addressed by (layer, global frame) because the
/// storyboard rail's standing row never moves the drawing target (유저
/// 2026-07-27) — the transition row's [editTransitionSpanInstance] pattern,
/// said of sounds — and I-9 (2026-08-29) finished that likeness: an EMPTY
/// cell CREATES here too, through the row's own cursor verb, exactly as the
/// transition row has done since 2026-08-11.
Future<void> editSeEntryInstance(
  BuildContext context,
  EditorSessionManager session, {
  required LayerId layerId,
  required int globalFrame,
  Axis previewAxis = Axis.horizontal,
}) async {
  final layer = layerAnywhereOrNull(
    session.repository.requireProject(),
    layerId,
  );
  if (layer == null || layer.kind != LayerKind.se) {
    return;
  }
  final block = coveringDrawingBlockAt(layer.timeline, globalFrame);
  if (block == null) {
    // 🚨★★★I-9 (유저 확정 2026-08-29, I-9-Q2 = `all-kinds`): an EMPTY cell
    // CREATES — the sentence [editTransitionSpanInstance] has said since
    // 2026-08-11, now said of sounds too. The doc above used to end 「COVERED
    // frames only: creation stays the timeline's cut-scoped entrance」, and
    // that was the asymmetry the user hit: 「타임라인의 se행이랑
    // 트랜지션행이었는데 통일되서 사라졌을수도? 아무튼 **새로만들자.**」
    //
    // The cursor verb, not these arguments: the first tap of the double
    // already stood on this row and seeked to this frame, which is the pair
    // the frame `＋` acts on. Passing them again would be a second address
    // for one cell.
    session.storyboardCursor.createSeEntryAtStoryboardCursor();
    return;
  }
  Frame? entry;
  entry = layer.frameById(block.frameId);
  if (entry == null) {
    return;
  }
  final entryId = entry.id;
  await _editSeEntryWithDialog(
    context,
    initialSeName: entry.seName ?? '',
    initialDialogue: entry.name ?? '',
    linkedAudio: [
      for (var index = 0; index < layer.audioClips.length; index += 1)
        if (layer.audioClips[index].frameId == entryId)
          (
            label: mediaAssetDefaultName(layer.audioClips[index].filePath),
            token: index,
          ),
    ],
    previewAxis: previewAxis,
    commit: (dialogue, seName) => session.seEntries.updateSeEntryForLayer(
      layerId,
      entryId,
      dialogue: dialogue,
      seName: seName,
    ),
    unlink: (tokens) => session.audioClips.unlinkAudioClipsFromLayer(layerId, tokens),
  );
}

/// The dialog + commit core BOTH SE entrances share — the timeline's
/// standing-addressed one and the storyboard's row-addressed one. One body,
/// so "delete works from one door but not the other" has nowhere to start.
Future<void> _editSeEntryWithDialog(
  BuildContext context, {
  required String initialSeName,
  required String initialDialogue,
  required List<({String label, int token})> linkedAudio,
  required Axis previewAxis,
  required void Function(String dialogue, String? seName) commit,
  required void Function(Iterable<int> tokens) unlink,
}) async {
  final result = await showDialogVerb<SeInstanceDialogResult>(
    context,
    (_) => SeInstanceDialog(
      creating: false,
      initialSeName: initialSeName,
      initialDialogue: initialDialogue,
      previewAxis: previewAxis,
      linkedAudio: linkedAudio,
    ),
  );
  if (result == null) {
    return;
  }

  final seName = result.seName.isEmpty ? null : result.seName;
  // SE edits never hit the link-conflict flow (duplicates allowed).
  commit(result.dialogue, seName);
  if (result.unlinkedAudioTokens.isNotEmpty) {
    unlink(result.unlinkedAudioTokens);
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
    if (session.frameVerbs.canCreateDrawingAtCurrentFrame) {
      session.createDrawingAtCurrentFrame();
    }
    return;
  }

  final cut = session.activeCutOrNull;
  final content = session.textCelBakes.selectedTextCelContent;
  return askThenCommit<TextCelContent>(
    context,
    dialog: (_) => TextCelDialog(
      creating: content == null,
      initialContent: content,
      defaultPosition: cut == null
          ? null
          : Offset(cut.canvasSize.width / 2, cut.canvasSize.height / 2),
    ),
    commit: session.textCelBakes.setTextCelContentForSelectedFrame,
  );
}

/// Instruction cells: covered cells edit/delete the covering event in the
/// dialog; EMPTY cells create a default one-frame event DIRECTLY (UI-R25 #2).
/// The vocabulary editor is reachable from the picker.
/// The instruction dialog, opened on a span that already exists.
///
/// ⛔BOTH EDITORS PASS THE SAME SIX FIELDS off the covering span — the
/// camera row's events and the transition row's — so a field added to the
/// dialog would otherwise have to be remembered in two places, and the
/// one that forgot would silently open on a blank.
///
/// The set and the span travel together because neither means anything
/// alone: an instruction id is only readable against its own set.
///
/// ⚠️[span]`.editsSet` is NOT decoration: the camera editor offers a way
/// into the instruction set and the transition editor does not, and
/// folding them without carrying that would have grown the transition
/// dialog a button nobody asked for.
Future<InstructionEventDialogResult?> _showInstructionEditor(
  BuildContext context,
  EditorSessionManager session,
  Axis previewAxis,
  ({CameraInstructionSet set, InstructionEvent covering, bool editsSet}) span,
) => showDialogVerb<InstructionEventDialogResult>(
  context,
  (dialogContext) => InstructionEventDialog(
    instructionSet: span.set,
    initialInstructionId: span.covering.instructionId,
    initialText: span.covering.text,
    initialValueA: span.covering.valueA,
    initialValueB: span.covering.valueB,
    initialMemo: span.covering.memo,
    editing: true,
    onEditInstructionSet: span.editsSet
        ? () => _editInstructionSet(dialogContext, session)
        : null,
    previewAxis: previewAxis,
  ),
);

/// THE INSTRUCTION SPAN FLOW, once: an empty cell CREATES, a covered one
/// opens the editor, and the editor's answer either deletes the span or
/// replaces it with the six fields it hands back.
///
/// Every difference between the two rows that wear it — which span finder
/// answers, which set the picker reads, whether the vocabulary editor is
/// offered, where the length comes from, and the three session verbs — is
/// a value or a collaborator passed in. Nothing here chooses between two
/// behaviours: a fourth step added to this sequence lands on both rows,
/// which is the whole point of it being one sequence.
typedef _SpanRow = ({
  MapEntry<int, InstructionEvent>? covering,
  CameraInstructionSet set,
  bool editsSet,
  void Function() create,
  void Function() remove,
  int Function(InstructionEvent covering) length,
  void Function(InstructionEvent event) commit,
});

Future<void> _editSpanInstance(
  BuildContext context,
  EditorSessionManager session,
  Axis previewAxis,
  _SpanRow row,
) async {
  final covering = row.covering;
  if (covering == null) {
    row.create();
    return;
  }
  final result = await _showInstructionEditor(context, session, previewAxis, (
    set: row.set,
    covering: covering.value,
    editsSet: row.editsSet,
  ));
  if (result == null) {
    return;
  }
  if (result.delete) {
    row.remove();
    return;
  }
  final instructionId = result.instructionId;
  if (instructionId == null) {
    return;
  }
  row.commit(
    InstructionEvent(
      instructionId: instructionId,
      length: row.length(covering.value),
      text: result.text,
      valueA: result.valueA,
      valueB: result.valueB,
      memo: result.memo,
    ),
  );
}

Future<void> _editInstructionEvent(
  BuildContext context,
  EditorSessionManager session,
  LayerId layerId,
  int frameIndex,
  Axis previewAxis,
) => _editSpanInstance(context, session, previewAxis, (
  covering: session.instructionVerbs.instructionSpanAt(layerId, frameIndex),
  set: session.camera.cameraInstructionSet,
  editsSet: true,
  create: session.instructionVerbs.createDefaultInstructionEventAtCurrentFrame,
  remove: () => session.instructionVerbs.removeInstructionEventAt(layerId, frameIndex),
  // The direction row's events are one frame each; the cell you opened
  // is the span.
  length: (_) => 1,
  commit: (event) => session.instructionVerbs.upsertInstructionEventAt(
    layerId,
    frameIndex,
    event,
    createLengthFrames: 1,
  ),
));

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
}) {
  final frame = globalFrame ?? session.editingGlobalFrame;
  return _editSpanInstance(context, session, previewAxis, (
    covering: session.transitions.transitionSpanAt(frame),
    set: session.transitions.transitionInstructionSet,
    editsSet: false,
    create: session.transitions.createTransitionSpanAtPlayhead,
    remove: () => session.transitions.removeTransitionSpanAt(frame),
    // LENGTH is not taken from the dialog. The grips own it, so a re-pick
    // can never resize a span out from under the boundary it fires across.
    length: (covering) => covering.length,
    commit: (event) => session.transitions.replaceTransitionEventAt(frame, event),
  ));
}

/// Opens the vocabulary editor and commits the edited set immediately (its
/// own undo step), so it sticks even when the event dialog is then cancelled.
/// The already-open picker keeps its old list until reopened.
Future<void> _editInstructionSet(
  BuildContext dialogContext,
  EditorSessionManager session,
) => askThenCommit<CameraInstructionSet>(
  dialogContext,
  dialog: (_) =>
      InstructionSetEditorDialog(initialSet: session.camera.cameraInstructionSet),
  commit: session.camera.updateCameraInstructionSet,
);

/// A lane KEY's name — the frame-name flow said of a keyframe, down to the
/// dialog and the confirmation: the same rename prompt, the same
/// [FrameNameConflictDialog] when the name is taken, and joining ADOPTS the
/// value that name already holds instead of imposing this key's (user
/// 2026-08-10: "프레임블록이랑 같은 규칙이면됨").
///
/// An emptied field UN-names the key, which is the only way back to an
/// ordinary unlinked one.
/// THE RENAME-THEN-OFFER-TO-LINK FLOW, once: prompt for the name, attempt
/// the rename, and when the name is already taken ask ONCE — never once per
/// key — whether to join what holds it.
///
/// The two rows that wear it differ only in what the rename verb hands
/// back when it collides ([bool] for a lane key, the conflicting
/// [FrameId] for a frame — one nullable conflict token either way) and in
/// which link verb takes it. Both are collaborators, not modes; this
/// template is the ONE place holding the guard between the two dialogs.
///
/// [fieldTrailing] is content confirmed alongside the name — the key
/// window's TYPE — built with the window's own setState so it can show its
/// pick. [onLinkDeclined] is what the flow still owes when the user keeps
/// the name as it was: the part of the window that did not collide.
Future<void> _renameThenOfferLink<T extends Object>(
  BuildContext context, {
  required ({String initialName, String? title, String? fieldLabel}) prompt,
  required T? Function(String nextName) rename,
  required void Function(T conflict) link,
  Widget Function(StateSetter setLocal)? fieldTrailing,
  VoidCallback? onLinkDeclined,
}) async {
  final nextName = await showDialogVerb<String>(
    context,
    (_) => StatefulBuilder(
      builder: (context, setLocal) => RenameFrameDialog(
        initialName: prompt.initialName,
        title: prompt.title,
        fieldLabel: prompt.fieldLabel,
        fieldTrailing: fieldTrailing?.call(setLocal),
      ),
    ),
  );
  if (nextName == null) {
    return;
  }
  final conflict = rename(nextName);
  if (conflict == null || !context.mounted) {
    return;
  }
  // Asked ONCE for the whole range, never once per key.
  final shouldLink = await showDialogVerb<bool>(
    context,
    (_) => const FrameNameConflictDialog(),
  );
  if (shouldLink != true) {
    onLinkDeclined?.call();
    return;
  }
  link(conflict);
}

Future<void> _renameLaneKey(
  BuildContext context,
  EditorSessionManager session,
) {
  if (!session.laneVerbs.canNameLaneKeys) {
    return Future<void>.value();
  }
  final strings = AppText.strings;
  // 🗣️F-17 (유저 2026-09-01): 「해당 키 공용 편집창 손봐서 이름변경이랑
  // 오른쪽에 유니언 타입 변경 두개 존재하도록. 물론 헤더에서 작동시
  // 유니언타입 일괄변경되는건 기존이랑 조작감 동일」. The TYPE opens on what
  // the covered keys agree on — nothing lit when they disagree, the ○ the
  // header draws for them — and a header's range is all of its members, so
  // a header's pick lands on every member at once.
  var interpolation = session.laneVerbs.laneKeyInterpolationForSelection;
  return _renameThenOfferLink<String>(
    context,
    prompt: (
      // What the covered keys already AGREE on; blank when they disagree,
      // the same thing the group header says with its `…`.
      initialName: session.laneVerbs.laneKeyNameForSelection ?? '',
      title: strings.renameKeyTitle,
      fieldLabel: strings.renameKeyField,
    ),
    fieldTrailing: (setLocal) => _keyInterpolationPills(
      selected: interpolation,
      onPicked: (picked) => setLocal(() => interpolation = picked),
    ),
    // The RANGE form is the only one called: a single key is the one-frame
    // span at the playhead, so naming one and naming five is the same verb
    // (user 2026-08-10, "선택범위로 통하는 조작이 모두 다른것들이랑 동일한
    // 로직"). The covered keys of a lane land on ONE value, which is what a
    // shared name means.
    rename: (nextName) {
      final trimmed = nextName.trim();
      return session.laneVerbs.setLaneKeyNamesForSelection(
            trimmed.isEmpty ? null : trimmed,
            interpolation: interpolation,
          )
          ? trimmed
          : null;
    },
    link: (name) => session.laneVerbs.linkLaneKeyNamesForSelection(
      name,
      interpolation: interpolation,
    ),
    // The name stood down; the type was confirmed in the same window.
    onLinkDeclined: () {
      final picked = interpolation;
      if (picked != null) {
        session.laneVerbs.setLaneKeyInterpolationsForSelection(picked);
      }
    },
  );
}

/// The key window's TYPE — the grouped-choice control (유저 2026-09-09:
/// 「여러개중 하나 선택한다거나 … 그룹으로 묶여있는 선택은 이 ui 사용하도록
/// 공용화」). Nothing is lit while the covered keys disagree.
Widget _keyInterpolationPills({
  required PropertyKeyInterpolation? selected,
  required ValueChanged<PropertyKeyInterpolation> onPicked,
}) {
  final strings = AppText.strings;
  return ExportPillStrip(
    items: [
      for (final (kind, label) in [
        (PropertyKeyInterpolation.linear, strings.keyInterpolationLinear),
        (PropertyKeyInterpolation.hold, strings.keyInterpolationHold),
      ])
        ExportPillItem(
          keyValue: 'rename-key-interpolation-${kind.name}',
          label: label,
          selected: selected == kind,
          onTap: () => onPicked(kind),
        ),
    ],
  );
}

Future<void> _renameSelectedFrame(
  BuildContext context,
  EditorSessionManager session,
) {
  if (session.selectedFrame == null || !session.frameVerbs.canRenameFrameAtCurrentFrame) {
    return Future<void>.value();
  }
  return _renameThenOfferLink<FrameId>(
    context,
    prompt: (
      initialName: session.selectedFrameName ?? '',
      title: null,
      fieldLabel: null,
    ),
    rename: session.frameVerbs.renameSelectedFrame,
    link: session.frameVerbs.linkSelectedFrame,
  );
}
