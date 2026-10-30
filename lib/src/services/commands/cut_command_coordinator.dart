import '../editing/default_cut_helpers.dart';
import '../editing/editing_session_state.dart';
import '../editing/run_id_mint.dart' show mintCutId;
import '../../core/collection_equality.dart';
import '../../models/attached_layer_mount.dart';
import '../../models/attached_layer_resolve.dart';
import '../../models/attached_mode.dart';
import '../../models/audio_clip.dart';
import '../../models/camera_instruction.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_resize_anchor.dart';
import '../../models/canvas_size.dart';
import '../../models/conte/conte_camera_room.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/cut_id.dart';
import '../../models/frame_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../../models/timeline_repeat.dart' show rederiveRunBehaviors;
import '../../models/media_asset.dart';
import '../../models/pasteboard_bounds.dart' show PasteboardSize;
import '../../models/se_name_tag.dart';
import '../../models/se_sound.dart';
import '../../models/project.dart';
import '../../models/property_track.dart' show PropertyKey;
import '../../models/project_background.dart';
import '../../models/timesheet_info.dart';
import '../../models/timesheet_sheet_kind.dart';
import '../../models/exposure_memo.dart';
import '../../models/track_id.dart';
import '../../models/track_transitions.dart';
import '../../models/transform_track.dart';
import '../brush_frame_store.dart';
import '../clipboard/layer_copy_payload.dart';
import '../command.dart' show Command, WorkAhead, oneStepOf;
import '../history_manager.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import '../reference_move_carried.dart';
import 'cut_command_input_planner.dart';
import 'convert_to_linked_cut_command.dart';
import 'convert_to_linked_cut_plan.dart';
import 'create_cut_command.dart';
import 'create_linked_cut_command.dart';
import 'dissolve_folder_command.dart';
import 'link_mirror.dart'
    show
        existenceMirrorTargets,
        headMirrorTargets,
        linkCounterpartIn,
        linkMirrorTargets,
        linkedCutSiblings,
        mirroredOrderAfterMove,
        namedTransformWrites,
        transformTrackOfRow;
import 'set_layer_attachment_command.dart';
import 'set_layer_placement_command.dart';
import 'delete_cut_command.dart';
import 'delete_layer_command.dart';
import 'duplicate_cut_command.dart';
import 'link_duplicate_layer_command.dart';
import 'unlink_layer_command.dart';
import 'rename_cut_command.dart';
import 'update_cut_durations_command.dart';
import 'reorder_cut_command.dart';
import 'resize_cut_canvas_command.dart';
import 'relink_media_asset_command.dart';
import 'rasterize_layer_reference_command.dart';
import 'update_camera_instruction_set_command.dart';
import 'update_cut_camera_command.dart';
import 'linked_cut_field_command.dart';
import 'update_cut_mark_command.dart';
import 'update_cut_conte_camera_room_command.dart';
import 'update_cut_sheet_kind_command.dart';
import 'update_cut_scene_command.dart';
import 'update_cut_staff_folds_command.dart';
import 'update_cut_staff_name_command.dart';
import 'update_cut_note_command.dart';
import 'update_track_display_command.dart';
import 'update_track_effects_command.dart';
import 'update_layer_audio_clips_command.dart';
import 'update_se_name_tag_command.dart';
import 'update_layer_reference_fx_command.dart';
import 'update_layer_se_sound_command.dart';
import 'update_layer_timeline_command.dart';
import 'update_layer_transform_enabled_command.dart';
import 'update_layer_kind_command.dart';
import 'update_layer_mark_command.dart';
import 'update_layer_name_command.dart';
import 'update_layer_effects_command.dart';
import 'update_layer_clip_command.dart';
import 'update_layer_timesheet_command.dart';
import 'update_layer_transform_command.dart';
import 'update_media_assets_command.dart';
import 'update_project_background_command.dart';
import 'set_project_pasteboard_command.dart';
import 'update_project_stage_colors_command.dart';
import 'update_timesheet_info_command.dart';
import 'update_exposure_memo_command.dart';

part 'cut_commands/cut_commands.dart';
part 'cut_commands/camera_commands.dart';
part 'cut_commands/link_commands.dart';
part 'cut_commands/track_commands.dart';
part 'cut_commands/folder_and_attachment_commands.dart';
part 'cut_commands/project_setting_commands.dart';

/// A pasted (or duplicated) layer: its id, and which cel of the copy each
/// of its cels was minted from — what the pictures follow, since they live
/// in a store keyed by the ids the paste just changed (F-62's lesson, at the
/// layer's scale) — and, by each of its blocks' handwriting ids, the one it
/// starts as a copy of (`conteHandwritingOfACopy`).
typedef PastedLayer = ({
  LayerId layerId,
  Map<FrameId, FrameId> minted,
  Map<String, String> handwriting,
});

/// A duplicated cut: its id, which row of it each source row became, and
/// which cel each source cel became — [PastedLayer]'s answer for a whole cut.
typedef DuplicatedCut = ({
  CutId cutId,
  Map<LayerId, LayerId> rows,
  Map<FrameId, FrameId> minted,
});

class CutCommandCoordinator {
  const CutCommandCoordinator({
    required this.repository,
    required this.editingSession,
    required this.historyManager,
    this.brushFrameStore,
  });

  final ProjectRepository repository;
  final EditingSessionState editingSession;
  final HistoryManager historyManager;

  /// Optional app-level brush stroke store; when present, canvas resizes
  /// translate the cut's strokes to honor the chosen anchor.
  final BrushFrameStore? brushFrameStore;

  // ── the cut commands: their own object, in their own file ───────────
  //
  // A collaborator (commands/cut_commands/cut_commands.dart, a part of this
  // library). The coordinator keeps the public commands as forwarders.
  _CutCommands get _cuts => _CutCommands(this);

  void createCut({
    required TrackId trackId,
    CanvasSize? canvasSize,
    // #18 — an EXPLICIT landing (gap parking, range selection): the index
    // to insert at, the walk-in distance into the gap as the new cut's
    // own leading gap, and an optional duration (a range names its own
    // length, the way the transition span's selection does). Null keeps
    // the classic anchor: right of the active cut, else the track's end.
    ({int? index, int leadingGapFrames, int? duration})? placement,
    CutId? cutId,
    String? name,
  }) => _cuts.createCut(
    trackId: trackId,
    canvasSize: canvasSize,
    placement: placement,
    cutId: cutId,
    name: name,
  );

  /// The cut [createCut] would make with the same words, named [cutId] (or
  /// a fresh id) — not made.
  Cut plannedCut({
    required TrackId trackId,
    CanvasSize? canvasSize,
    ({int? index, int leadingGapFrames, int? duration})? placement,
    CutId? cutId,
  }) => _cuts
      .createCutCommand(
        trackId: trackId,
        canvasSize: canvasSize,
        placement: placement,
        cutId: cutId,
      )
      .cut;
  static String nextCutNameAfter(Project project, String? referenceName) =>
      _CutCommands.nextCutNameAfter(project, referenceName);
  void resizeCutCanvas({
    required CutId cutId,
    required CanvasSize canvasSize,
    CanvasResizeAnchor anchor = CanvasResizeAnchor.topLeft,
  }) => _cuts.resizeCutCanvas(
    cutId: cutId,
    canvasSize: canvasSize,
    anchor: anchor,
  );
  Future<void> resizeCutCanvasAhead({
    required CutId cutId,
    required CanvasSize canvasSize,
    CanvasResizeAnchor anchor = CanvasResizeAnchor.topLeft,
    void Function(double done)? report,
  }) => _cuts.resizeCutCanvasAhead(
    cutId: cutId,
    canvasSize: canvasSize,
    anchor: anchor,
    report: report,
  );
  void placeCutCanvas({
    required CutId cutId,
    required CanvasSize canvasSize,
    required ({double dx, double dy}) contentOffset,
  }) => _cuts.placeCutCanvas(
    cutId: cutId,
    canvasSize: canvasSize,
    contentOffset: contentOffset,
  );
  Future<void> placeCutCanvasAhead({
    required CutId cutId,
    required CanvasSize canvasSize,
    required ({double dx, double dy}) contentOffset,
    void Function(double done)? report,
  }) => _cuts.placeCutCanvasAhead(
    cutId: cutId,
    canvasSize: canvasSize,
    contentOffset: contentOffset,
    report: report,
  );
  void renameCuts(Map<CutId, String> names) => _cuts.renameCuts(names);
  void setCutScene({required CutId cutId, required String scene}) =>
      _cuts.setCutScene(cutId: cutId, scene: scene);
  void nameCut({required CutId cutId, required String name, String? scene}) =>
      _cuts.nameCut(cutId: cutId, name: name, scene: scene);
  void commitCutDurationDrag({
    required Map<CutId, int> beforeDurations,
    required Map<CutId, int> afterDurations,
    Map<CutId, int> beforeGaps = const {},
    Map<CutId, int> afterGaps = const {},
  }) => _cuts.commitCutDurationDrag(
    beforeDurations: beforeDurations,
    afterDurations: afterDurations,
    beforeGaps: beforeGaps,
    afterGaps: afterGaps,
  );
  void updateCutNote({
    required CutId cutId,
    required int page,
    required String note,
  }) => _cuts.updateCutNote(cutId: cutId, page: page, note: note);
  void saveCutSettings({
    required List<CutId> cutIds,
    required Map<LayerMark, String> names,
    Set<LayerProcess>? openFolds,
  }) => _cuts.saveCutSettings(
    cutIds: cutIds,
    names: names,
    openFolds: openFolds,
  );
  void setCutMark({required List<CutId> cutIds, required LayerMark mark}) =>
      _cuts.setCutMark(cutIds: cutIds, mark: mark);
  void setTimesheetFormat({
    required TimesheetInfo info,
    CutId? cutId,
    TimesheetSheetKind? kind,
  }) => _projectSettings.setTimesheetFormat(
    info: info,
    cutId: cutId,
    kind: kind,
  );
  void setConteFormat({
    required TimesheetInfo info,
    required List<CutId> cutIds,
    ({ConteCameraRoom? to})? cameraRoom,
  }) => _projectSettings.setConteFormat(
    info: info,
    cutIds: cutIds,
    cameraRoom: cameraRoom,
  );
  void commitCutMoveReorder({
    required TrackId trackId,
    required List<CutId> order,
    required Map<CutId, int> beforeGaps,
    required Map<CutId, int> afterGaps,
  }) => _cuts.commitCutMoveReorder(
    trackId: trackId,
    order: order,
    beforeGaps: beforeGaps,
    afterGaps: afterGaps,
  );
  void deleteCut({required CutId cutId}) => _cuts.deleteCut(cutId: cutId);
  void deleteCuts({required List<CutId> cutIds}) =>
      _cuts.deleteCuts(cutIds: cutIds);
  DuplicatedCut duplicateCut({
    required CutId sourceCutId,
    required TrackId targetTrackId,
    String? newName,
    int? index,
  }) => _cuts.duplicateCut(
    sourceCutId: sourceCutId,
    targetTrackId: targetTrackId,
    newName: newName,
    index: index,
  );

  // ── the camera commands: their own object ───────────────────────────
  //
  // A collaborator (commands/cut_commands/camera_commands.dart, a part of this
  // library). The coordinator keeps the public commands as forwarders.
  _CameraCommands get _camera => _CameraCommands(this);

  void setCutCameraKeyframe({
    required CutId cutId,
    required int frameIndex,
    required CameraPose pose,
  }) => _camera.setCutCameraKeyframe(
    cutId: cutId,
    frameIndex: frameIndex,
    pose: pose,
  );
  void removeCutCameraKeyframe({
    required CutId cutId,
    required int frameIndex,
  }) => _camera.removeCutCameraKeyframe(cutId: cutId, frameIndex: frameIndex);
  void clearCutCamera({required CutId cutId}) =>
      _camera.clearCutCamera(cutId: cutId);
  void updateCutCamera({
    required CutId cutId,
    required CutCamera camera,
    String description = 'Edit camera keyframes',
  }) => _camera.updateCutCamera(
    cutId: cutId,
    camera: camera,
    description: description,
  );
  void updateCameraInstructionSet(CameraInstructionSet instructionSet) =>
      _camera.updateCameraInstructionSet(instructionSet);

  // `updateTrackTransform` retired with the V row's transform. The fade it
  // wrote is F.I/F.O spans on the transition row now
  // ([EditorSessionManager.updateTransitionInstructions]). The named-key
  // self-propagation this round gave it retired with it: a V row no longer
  // has transform lanes for a name to link.

  // ── the track commands: their own object ────────────────────────────
  //
  // A collaborator (commands/cut_commands/track_commands.dart, a part of this
  // library). The coordinator keeps the public commands as forwarders.
  _TrackCommands get _tracks => _TrackCommands(this);

  void updateTrackEffects({
    required TrackId trackId,
    required List<LayerEffect> effects,
    String description = 'Edit track effects',
  }) => _tracks.updateTrackEffects(
    trackId: trackId,
    effects: effects,
    description: description,
  );
  void updateTrackDisplay({
    required TrackId trackId,
    required bool fxEnabled,
    String description = 'Edit track display',
  }) => _tracks.updateTrackDisplay(
    trackId: trackId,
    fxEnabled: fxEnabled,
    description: description,
  );
  void updateLayerTransformTrack({
    required CutId cutId,
    required LayerId layerId,
    required TransformTrack transformTrack,
    String description = 'Edit layer transform',
  }) => _tracks.updateLayerTransformTrack(
    cutId: cutId,
    layerId: layerId,
    transformTrack: transformTrack,
    description: description,
  );
  TransformTrack? transformTrackHoldingName({
    required CutId cutId,
    required LayerId layerId,
    required TransformPropertyId property,
    required String name,
    Set<int> excludeFramesOnSource = const {},
  }) => _tracks.transformTrackHoldingName(
    cutId: cutId,
    layerId: layerId,
    property: property,
    name: name,
    excludeFramesOnSource: excludeFramesOnSource,
  );
  void setTrackSeOrder({
    required TrackId trackId,
    required List<LayerId> order,
  }) => _tracks.setTrackSeOrder(trackId: trackId, order: order);

  void renameLayer({
    required CutId cutId,
    required LayerId layerId,
    required String name,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Layer name cannot be empty.');
    }

    // ANYWHERE, as the name write itself is (`ProjectRepository`'s
    // layer-flag updates: 「track-owned SE layers must reach the same
    // commands」). ↩️A cut-scoped lookup here threw on a track's SE row —
    // found by I-48's label double click, and the menu's rename with it.
    final renamed = _requireLayerAnywhere(layerId);
    if (renamed.name == trimmedName) {
      return;
    }

    // #23 — 유저: 「주인 레이어의 이름 바꾸면 어태치레이어도 적용시키고싶음」.
    //
    // 🚨H5 (유저 2026-08-21) WIDENED the rule: 「주인 B, 어태치 **B_F**
    // 이어도 **앞부분 B라는게 같으니** 바꾸면 바뀌도록」. It used to match
    // only the GENERATED default `base.name±N` ([nextAttachedLayerName]),
    // so a rider the user had named themselves — `B_F`, `B_shadow` —
    // stopped following its owner the moment they typed it, which is when
    // the pairing is worth most.
    //
    // ⇒ THE PREFIX is the rule: an attach whose name starts with the
    // owner's OLD name follows, and whatever comes after that prefix rides
    // over verbatim. The `±N` default is now one case of this instead of
    // the only one, and nothing is renumbered (numbers go non-contiguous
    // after deletions, and renumbering would be inventing state). ⚠️A SEAT
    // move does renumber — 유저 asked for that one (I-122 · F-436 ③,
    // [attachNamesForMovedSeats]) — and keeps a deletion's gap all the same.
    //
    // ★Still answered RIGHT HERE, against the OLD name: ask a moment later
    // and the prefix is gone with the name it hung off.
    //
    // ⚠️A prefix is a prefix: with an owner named `B`, an attach named
    // `Bob` follows too. That is the rule as asked for — narrowing it
    // (demand a separator, demand the default shape) would put back the
    // very "my own name stopped following" surprise this removes.
    final followers = <Command>[];
    final ownerPrefix = renamed.name;
    for (final attached in attachedLayersOf(
      layerId,
      _requireCut(cutId).layers,
    )) {
      if (!attached.name.startsWith(ownerPrefix)) {
        continue;
      }
      final suffix = attached.name.substring(ownerPrefix.length);
      followers.add(
        UpdateLayerNameCommand(
          repository: repository,
          cutId: cutId,
          layerId: attached.id,
          name: '$trimmedName$suffix',
        ),
      );
    }

    historyManager.executeAsOneStep(
      'Rename layer and its default-named attaches',
      [
        UpdateLayerNameCommand(
          repository: repository,
          cutId: cutId,
          layerId: layerId,
          name: trimmedName,
        ),
        ...followers,
      ],
    );
  }

  // ── the link commands: their own object ─────────────────────────────
  //
  // A collaborator (commands/cut_commands/link_commands.dart, a part of this
  // library). The coordinator keeps the public commands as forwarders.
  _LinkCommands get _links => _LinkCommands(this);

  ({String name, CanvasSize canvasSize}) plannedLinkedCut({
    required CutId sourceCutId,
  }) => _links.plannedLinkedCut(sourceCutId: sourceCutId);
  void createLinkedCut({required CutId sourceCutId, String? name}) =>
      _links.createLinkedCut(sourceCutId: sourceCutId, name: name);
  void unlinkLayer({required CutId cutId, required LayerId layerId}) =>
      _links.unlinkLayer(cutId: cutId, layerId: layerId);
  void convertCutToLinked({
    required CutId originCutId,
    required CutId targetCutId,
  }) => _links.convertCutToLinked(
    originCutId: originCutId,
    targetCutId: targetCutId,
  );
  WorkAhead? convertCutToLinkedAhead({
    required CutId originCutId,
    required CutId targetCutId,
  }) => _links.convertCutToLinkedAhead(
    originCutId: originCutId,
    targetCutId: targetCutId,
  );
  ConvertToLinkedCutPlan convertToLinkedCutPreview({
    required CutId originCutId,
    required CutId targetCutId,
  }) => _links.convertToLinkedCutPreview(
    originCutId: originCutId,
    targetCutId: targetCutId,
  );
  LayerId linkDuplicateLayer({
    required CutId cutId,
    required LayerId layerId,
    required int insertionIndex,
  }) => _links.linkDuplicateLayer(
    cutId: cutId,
    layerId: layerId,
    insertionIndex: insertionIndex,
  );

  // ── the folder and attachment commands: their own object ────────────
  //
  // A collaborator (commands/cut_commands/folder_and_attachment_commands.dart, a part of this
  // library). The coordinator keeps the public commands as forwarders.
  _FolderAndAttachmentCommands get _folders =>
      _FolderAndAttachmentCommands(this);

  void dissolveFolder({required CutId cutId, required LayerId folderId}) =>
      _folders.dissolveFolder(cutId: cutId, folderId: folderId);
  List<Command> layerAttachmentCommands({
    required CutId cutId,
    required LayerAttachDrop attach,
    String description = 'Attach layer',
  }) => _folders.layerAttachmentCommands(
    cutId: cutId,
    attach: attach,
    description: description,
  );
  void setLayerAttachment({
    required CutId cutId,
    required LayerAttachDrop attach,
    String description = 'Attach layer',
  }) => _folders.setLayerAttachment(
    cutId: cutId,
    attach: attach,
    description: description,
  );

  void deleteLayer({required CutId cutId, required LayerId layerId}) {
    final cut = _requireCut(cutId);
    final layer = _requireLayer(cutId: cutId, layerId: layerId);
    if (layer.kind.groupsLayers) {
      _deleteFolderWithWhatItHolds(cutId: cutId, folder: layer);
      return;
    }
    // Attach rows are accessories — always deletable, never counted toward
    // the section floors below.
    if (!isAttachedLayer(layer)) {
      // Mirrors the session's canDeleteActiveLayer floors: camera fixed, at
      // least two SE rows (S1·S2), one instruction row and one drawing cel.
      final refused = switch (layer.kind) {
        LayerKind.camera => true,
        // A TRANSITION row is track-owned: it never appears in a cut's
        // layer list, so this floor can only be reached by a programming
        // error. Refuse rather than delete something the cut does not own.
        LayerKind.transition => true,
        LayerKind.se =>
          cut.layers.where((other) => other.kind == LayerKind.se).length <= 2,
        LayerKind.instruction =>
          cut.layers
                  .where((other) => other.kind == LayerKind.instruction)
                  .length <=
              1,
        // R28 #14: no drawing floor — the action section may empty out.
        // An adjustment row deletes freely too: nothing depends on it, and
        // deleting it simply un-filters the stack below.
        LayerKind.animation ||
        LayerKind.storyboard ||
        LayerKind.image ||
        LayerKind.folder ||
        LayerKind.adjustment => false,
      };
      if (refused) {
        return;
      }
    }

    // Deleting the LAST attach row of an ORGANIZER folder takes the
    // now-empty folder row with it (an empty organizer belongs to no
    // group and would strand outside the span) — one undo step. Only for
    // UNLINKED folder rows (organizers are created per-cut and unlinked;
    // a linked folder's delete fans out group-wide, and this cut's member
    // count says nothing about a diverged counterpart's).
    //
    // 🚨It WALKS. Nesting (유저 2026-08-29) made "the folder it was in" a
    // one-level answer to a question that now has depth: the inner folder
    // empties, and then the outer one holds nothing but the folder that is
    // already going. Measured before it was written — the outer stranded.
    //
    // ⛔An empty PLAIN folder is not swept along with them, and that is not
    // an oversight: an empty folder is a thing you can make on purpose,
    // while an empty ORGANIZER is a folder that belongs to no group and
    // sits outside every span. The sweep follows the invalidity, not the
    // emptiness.
    //
    // The row goes from every cut whose conte holds its row of the track's
    // structure (I-73, F-343 — [existenceMirrorTargets]), so every cut it
    // goes from is asked what it leaves empty there.
    if (isAttachedLayer(layer)) {
      final project = repository.requireProject();
      final emptied = [
        for (final target in existenceMirrorTargets(
          project,
          cutId: cutId,
          layerId: layerId,
        ))
          for (final folder in _organizersEmptiedBy(project, target))
            (cutId: target.cutId, folder: folder),
      ];
      if (emptied.isNotEmpty) {
        historyManager.executeAsOneStep(
          'Delete layer ${layer.name} and its empty '
          '${emptied.length == 1 ? 'folder' : 'folders'}',
          [
            DeleteLayerCommand(
              repository: repository,
              cutId: cutId,
              layerId: layerId,
              withItsConteRow: true,
            ),
            for (final gone in emptied)
              DeleteLayerCommand(
                repository: repository,
                cutId: gone.cutId,
                layerId: gone.folder.id,
              ),
          ],
        );
        return;
      }
    }

    // Deleting a BASE cascades over its attach rows AND their organizer
    // folder rows (neither can stand alone) — ONE undo step; the
    // composite undoes in reverse, restoring each layer at its captured
    // index.
    final attachedRows = attachedLayersOf(layerId, cut.layers);
    if (attachedRows.isEmpty) {
      historyManager.execute(
        DeleteLayerCommand(
          repository: repository,
          cutId: cutId,
          layerId: layerId,
          withItsConteRow: true,
        ),
      );
      return;
    }
    // ⚠️An organizer made by dropping an EMPTY folder on the group carries
    // the relation on its own row (F-139), so it is one of [attachedRows]
    // already — deleted twice, the second delete found nothing and threw.
    final organizerRows = [
      for (final row in cut.layers)
        if (row.attachedToLayerId != layerId &&
            attachOrganizerBaseOf(row, cut.layers) == layerId)
          row,
    ];
    historyManager.executeAsOneStep(
      'Delete layer ${layer.name} and its attach layers',
      [
        for (final attached in attachedRows)
          DeleteLayerCommand(
            repository: repository,
            cutId: cutId,
            layerId: attached.id,
          ),
        for (final organizer in organizerRows)
          DeleteLayerCommand(
            repository: repository,
            cutId: cutId,
            layerId: organizer.id,
          ),
        DeleteLayerCommand(
          repository: repository,
          cutId: cutId,
          layerId: layerId,
        ),
      ],
    );
  }

  /// The unlinked ORGANIZER folders of [row]'s cut that removing it leaves
  /// with nothing in them — the walk [deleteLayer] says why.
  List<Layer> _organizersEmptiedBy(
    Project project,
    ({CutId cutId, LayerId layerId}) row,
  ) {
    final layers = requireCut(project, row.cutId).layers;
    return layers.foldersEmptiedByRemoving(
      {row.layerId},
      canRemove: (folder) =>
          attachOrganizerBaseOf(folder, layers) != null &&
          project.linkRegistry.groupOf(
                cutId: row.cutId,
                layerId: folder.id,
              ) ==
              null,
    );
  }

  /// Deletes [folder] and every row it holds, as ONE undo step.
  ///
  /// 🗣️F-305 (유저 2026-10-06): 「타임라인에서 폴더 삭제할때 내용물도 함께
  /// 삭제 … 드래그로 밖으로 꺼내고 폴더삭제하는게 확실함. 폴더 삭제한단건
  /// 내용물도 삭제하고싶다는것임」.
  ///
  /// ↩️Since the folder became a layer (2026-07-23) its delete DISSOLVED it:
  /// 「the members are rows in their own right and stay where they are.
  /// (Deleting the pictures too would make one Delete key destroy work the
  /// row itself never held.)」 — that round's own reasoning, and the user's
  /// ruling is the other way: what is to be kept is dragged out first.
  ///
  /// Each row goes by its OWN delete ([deleteLayer]) — a folder inside by
  /// this walk again, a base with its attach rows, and a row the cut may not
  /// lose (its last instruction row) not at all. So what stays behind stays
  /// for the reason it would have stayed alone, and is let out to the
  /// folder's parent as the folder row goes ([dissolveFolder] — every 겸용
  /// counterpart with it; it finds nothing to do where the folder went
  /// along already, an organizer with its last row).
  void _deleteFolderWithWhatItHolds({
    required CutId cutId,
    required Layer folder,
  }) {
    List<Layer> rows() => _requireCut(cutId).layers;
    historyManager.runAsOneStep(
      'Delete folder ${folder.name} and what it holds',
      () {
        for (final held in rows().directMembersOf(folder.id)) {
          // A row before it may have taken this one along: a base, its
          // attach rows.
          if (rows().byId(held.id) != null) {
            deleteLayer(cutId: cutId, layerId: held.id);
          }
        }
        dissolveFolder(cutId: cutId, folderId: folder.id);
      },
    );
  }

  /// [sourceLayerId] copied in [cutId], at [insertionIndex] — right above
  /// its source when none is named.
  PastedLayer duplicateLayer({
    required CutId cutId,
    required LayerId sourceLayerId,
    int? insertionIndex,
  }) {
    final cut = _requireCut(cutId);
    final sourceLayer = _requireLayer(cutId: cutId, layerId: sourceLayerId);
    if (sourceLayer.kind.isFixed) {
      throw StateError('The camera layer cannot be duplicated.');
    }
    final sourceIndex = cut.layers.indexWhere(
      (layer) => layer.id == sourceLayerId,
    );
    if (sourceIndex == -1) {
      throw StateError('Layer not found in cut $cutId: $sourceLayerId');
    }

    return pasteLayer(
      cutId: cutId,
      payload: copyLayerToPayload(sourceLayer),
      insertionIndex: insertionIndex ?? sourceIndex + 1,
    );
  }

  PastedLayer pasteLayer({
    required CutId cutId,
    required LayerCopyPayload payload,
    required int insertionIndex,
  }) {
    if (payload.kind.isFixed) {
      throw StateError('The camera layer cannot be pasted.');
    }

    final project = repository.requireProject();
    final cut = _requireCut(cutId);
    final plan = planPasteLayerCommandInput(
      project: project,
      targetCut: cut,
      payload: payload,
      insertionIndex: insertionIndex,
    );

    // A pasted row is an added row: in a 겸용 cut its siblings get it too
    // (F-398).
    historyManager.execute(
      plannedAddLayerCommand(
        repository: repository,
        cutId: cutId,
        layer: plan.layer,
        insertionIndex: plan.insertionIndex,
      ),
    );

    return (
      layerId: plan.layer.id,
      minted: plan.frameIdMap,
      handwriting: plan.handwriting,
    );
  }

  /// RASTERIZE (§6-f): nulls the media reference of every use of the
  /// layer's cels ([referenceLetGo], F-374-Q10) — the pixels are already
  /// their cels — once each use's reference fx's move is its own
  /// ([letReferencesGo]). The asset stays in the pool (유저 2026-09-11:
  /// 「구워도 풀에 남음」). One undo step; no-op on non-reference layers,
  /// and where a cel has to take the picture first, or the uses wait.
  void rasterizeLayerReference({
    required CutId cutId,
    required LayerId layerId,
  }) {
    final layer = requireLayer(
      repository.requireProject(),
      cutId: cutId,
      layerId: layerId,
    );
    if (layer.mediaReference == null) {
      return;
    }
    final way = referenceLetGoOf(cutId: cutId, layerId: layerId);
    if (way is ReferenceMoveCarried && !way.bakes) {
      historyManager.runAsOneStep(
        'Rasterize layer',
        () => letReferencesGo(way),
      );
    }
  }

  /// How RASTERIZE keeps where [layerId] shows its file ([referenceLetGo]),
  /// asked of the project: every use of its cels — its 겸용 link group, or
  /// the row alone ([linkMirrorTargets]) — and whether a row that wears
  /// their head and is none of them keeps keys of its own.
  ReferenceLetGo referenceLetGoOf({
    required CutId cutId,
    required LayerId layerId,
  }) {
    final project = repository.requireProject();
    final uses = linkMirrorTargets(project, cutId: cutId, layerId: layerId);
    Layer rowAt(({CutId cutId, LayerId layerId}) at) =>
        requireLayer(project, cutId: at.cutId, layerId: at.layerId);
    return referenceLetGo(
      uses: [
        for (final use in uses)
          (cut: requireCut(project, use.cutId), layer: rowAt(use)),
      ],
      othersKeepKeys:
          headMirrorTargets(
                project,
                cutId: cutId,
                layerId: layerId,
                cameraHead: true,
              )
              .where((row) => !uses.contains(row))
              .any((row) => rowAt(row).transformTrack.isNotEmpty),
    );
  }

  /// F-374-Q3 · Q10: every use's reference fx's move carried into its own
  /// transform — [way]'s tracks through the transform's one write — and the
  /// switch they share through the switch's (F-374-Q7 ①): what a rasterize
  /// does before it lets the references go, a still's or a movie's.
  void carryReferenceMoves(ReferenceMoveCarried way) {
    for (final (:use, :track, asShown: _) in way.uses) {
      updateLayerTransformTrack(
        cutId: use.cut.id,
        layerId: use.layer.id,
        transformTrack: track,
        description: 'Rasterize layer',
      );
    }
    if (way.switchOn) {
      historyManager.execute(
        UpdateLayerTransformEnabledCommand(
          repository: repository,
          layerId: way.uses.first.use.layer.id,
          transformEnabled: true,
          description: 'Rasterize layer',
        ),
      );
    }
  }

  /// [way]'s uses let go of their references once their moves are their own
  /// ([carryReferenceMoves]) — the end of a still's rasterize, keyed or
  /// baked. A movie's references go with the cels that replace its one.
  void letReferencesGo(ReferenceMoveCarried way) {
    carryReferenceMoves(way);
    for (final (:use, track: _, asShown: _) in way.uses) {
      historyManager.execute(
        RasterizeLayerReferenceCommand(
          repository: repository,
          cutId: use.cut.id,
          layerId: use.layer.id,
        ),
      );
    }
  }

  // ── the project setting commands: their own object ──────────────────
  //
  // A collaborator (commands/cut_commands/project_setting_commands.dart, a part of this
  // library). The coordinator keeps the public commands as forwarders.
  _ProjectSettingCommands get _projectSettings => _ProjectSettingCommands(this);

  void setTimesheetInfo(TimesheetInfo info) =>
      _projectSettings.setTimesheetInfo(info);
  void setProjectBackground(ProjectBackground background) =>
      _projectSettings.setProjectBackground(background);
  void setProjectBackdrop(int argb) =>
      _projectSettings.setProjectBackdrop(argb);
  void setProjectBackdropNone() => _projectSettings.setProjectBackdropNone();
  void setProjectPasteboard(int argb) =>
      _projectSettings.setProjectPasteboard(argb);
  void setProjectPasteboardNone() =>
      _projectSettings.setProjectPasteboardNone();
  void setProjectPasteboardSize(PasteboardSize size) =>
      _projectSettings.setProjectPasteboardSize(size);
  void setProjectPasteboardInUse(bool inUse) =>
      _projectSettings.setProjectPasteboardInUse(inUse);
  Future<void> cutProjectPasteboardAhead({
    PasteboardSize? size,
    bool? inUse,
    void Function(double done)? report,
  }) => _projectSettings.cutProjectPasteboardAhead(
    size: size,
    inUse: inUse,
    report: report,
  );

  /// Executes [command] only when [read] of [subject] does not already
  /// answer [value].
  ///
  /// ⛔THE GUARD IS WHY A TOGGLE THAT IS ALREADY ON LANDS NOTHING. Three
  /// setters wrote it out; without it, pressing a lit button banks an undo
  /// step that changes nothing, and the user then walks back through
  /// presses that did not do anything.
  ///
  /// ⛔EVERY SETTING HERE IS "ONE UNDO STEP, NO-OP WHEN UNCHANGED", AND
  /// FIVE WROTE IT OUT. Without the guard, a colour picker that reports
  /// the same swatch on every pointer move banks an undo step per move,
  /// and the user then walks back through presses that changed nothing.
  ///
  /// [subject] is the thing the field hangs off — a layer, a cut, the
  /// project — and it is a VALUE the caller fetches, because how you find
  /// the subject is the caller's question and the guard is this one. It
  /// reaches [command] too, so a verb that builds its command out of the
  /// subject's current state (the camera track's `withKeyframe`) needs no
  /// second lookup.
  ///
  /// Private on purpose: every part of this library reaches it, and
  /// nothing outside the library should.
  void _executeIfChanged<S, T>({
    required S subject,
    required T value,
    required T Function(S subject) read,
    required Command Function(S subject) command,
  }) {
    if (read(subject) == value) {
      return;
    }
    historyManager.execute(command(subject));
  }

  /// ⚠️Anywhere lookup: every kind carries these flags now (unified layer
  /// controls), and track-owned SE rows are not in any cut's layer list.
  Layer _requireLayerAnywhere(LayerId layerId) =>
      requireLayerAnywhere(repository.requireProject(), layerId);

  /// The SE row [layerId] names, refused for any other kind with what
  /// belongs on SE rows only ([what]) — the one guard the row's clips, its
  /// name tag and its sound are written behind (I-140).
  ///
  /// Anywhere lookup — the SE rows are TRACK fixtures (S1·S2), not in the
  /// cut's layer list (UI-R7 #4: media drops onto them dead-ended here).
  Layer _requireSeRow(LayerId layerId, String what) {
    final layer = _requireLayerAnywhere(layerId);
    if (layer.kind != LayerKind.se) {
      throw StateError('$what belong on SE layers only.');
    }
    return layer;
  }

  void setLayerTimesheet({
    // Nullable (B5③): the storyboard rail flips TRACK fixtures' flags from
    // a gap, where no cut is active — the write is layer-addressed and
    // never reads the cut.
    required CutId? cutId,
    required LayerId layerId,
    required bool onTimesheet,
  }) => _executeIfChanged(
    subject: _requireLayerAnywhere(layerId),
    value: onTimesheet,
    read: (layer) => layer.onTimesheet,
    command: (_) => UpdateLayerTimesheetCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      onTimesheet: onTimesheet,
    ),
  );

  void setLayerClip({
    required CutId cutId,
    required LayerId layerId,
    required bool clipsToBelow,
  }) => _executeIfChanged(
    subject: _requireLayerAnywhere(layerId),
    value: clipsToBelow,
    read: (layer) => layer.clipsToBelow,
    command: (_) => UpdateLayerClipCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      clipsToBelow: clipsToBelow,
    ),
  );

  void setLayerMark({
    required CutId cutId,
    required LayerId layerId,
    required LayerMark mark,
  }) => _executeIfChanged(
    subject: _requireLayerAnywhere(layerId),
    value: mark,
    read: (layer) => layer.mark,
    command: (_) => UpdateLayerMarkCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      mark: mark,
    ),
  );

  /// Writes a direction row's spans — which ARE its blocks (R27,
  /// [LayerKind.spansRideBlocks]) — as the edit [spans] makes of the row;
  /// one undo step, no-op when it changes nothing.
  ///
  /// ⛔Not a span map in and a span map out. A map says where spans are,
  /// not which block each one was, and a direction row's span is a block
  /// with a drawing on it: [spans] edits the row itself, so the drawing
  /// goes where the span goes.
  void updateDirectionSpans({
    required CutId cutId,
    required LayerId layerId,
    required Layer Function(Layer row) spans,
    String description = 'Edit instructions',
  }) {
    final before = _requireLayer(cutId: cutId, layerId: layerId);
    if (!before.kind.spansRideBlocks) {
      throw StateError('Direction spans belong on direction rows only.');
    }
    final after = rederiveRunBehaviors(
      spans(before),
      drawnFrameCount: cutDrawnFrameCount(repository.requireProject(), cutId)!,
    );
    historyManager.executeAsOneStep(description, [
      if (after != before)
        UpdateLayerTimelineCommand(
          repository: repository,
          before: before,
          after: after,
        ),
    ]);
  }

  /// Replaces an SE layer's audio clip list; one undo step, no-op when
  /// unchanged.
  void updateLayerAudioClips({
    // Nullable (B6): the storyboard's SE instance editor unlinks sounds
    // from a TRACK fixture, which may happen with the playhead parked in a
    // gap — the write is layer-addressed and never reads the cut.
    required CutId? cutId,
    required LayerId layerId,
    required List<AudioClip> audioClips,
    String description = 'Edit audio clips',
  }) {
    final layer = _requireSeRow(layerId, 'Audio clips');
    if (listEquals(layer.audioClips, audioClips)) {
      return;
    }

    historyManager.execute(
      UpdateLayerAudioClipsCommand(
        repository: repository,
        cutId: cutId,
        layerId: layerId,
        audioClips: audioClips,
        description: description,
      ),
    );
  }

  /// Sets an SE row's on-canvas name tag (R5b); one undo step, no-op when
  /// unchanged. Null resets the row to the stacked default.
  void setSeNameTag({
    required LayerId layerId,
    required SeNameTag? seNameTag,
    String description = 'Edit SE name tag',
  }) {
    _executeIfChanged(
      subject: _requireSeRow(layerId, 'Name tags'),
      value: seNameTag,
      read: (layer) => layer.seNameTag,
      command: (_) => UpdateSeNameTagCommand(
        repository: repository,
        layerId: layerId,
        seNameTag: seNameTag,
        description: description,
      ),
    );
  }

  /// Sets an SE row's sound — its volume keys and its pan (I-140); one undo
  /// step, no-op when unchanged.
  void setSeSound({
    required LayerId layerId,
    required SeSound seSound,
    String description = 'Edit SE sound',
  }) {
    _executeIfChanged(
      subject: _requireSeRow(layerId, 'Row sounds'),
      value: seSound,
      read: (layer) => layer.seSound,
      command: (_) => UpdateLayerSeSoundCommand(
        repository: repository,
        layerId: layerId,
        seSound: seSound,
        description: description,
      ),
    );
  }

  /// Replaces a reference row's REFERENCE FX keys (F-374); one undo step,
  /// no-op when unchanged. Where the file's pixels are laid is left as it
  /// is.
  void updateLayerReferenceFx({
    required LayerId layerId,
    required TransformTrack fx,
    String description = 'Edit layer reference',
  }) {
    final layer = _requireLayerAnywhere(layerId);
    if (layer.mediaReference == null) {
      throw StateError('A reference fx belongs on a row that shows a file.');
    }
    _executeIfChanged(
      subject: layer,
      value: fx,
      read: (layer) => layer.mediaReference!.fx,
      command: (_) => UpdateLayerReferenceFxCommand(
        repository: repository,
        layerId: layerId,
        fx: fx,
        description: description,
      ),
    );
  }

  /// Replaces a layer's EFFECT CHAIN (R6); one undo step, no-op when
  /// unchanged.
  ///
  /// The chain's SHAPE — which effects a row carries, in what order, each
  /// on or off — is shared structure and mirrors across the 겸용 link
  /// group as one composite step (user 2026-08-06: "겸용컷의 경우 레이어들
  /// 완벽 미러링이잖아? 그러니 fx 리스트도 완벽 미러링되야하거든"). Only
  /// the NUMBERS stay per-use: a sibling keeps its own parameter values and
  /// keyframe tracks, so the mirror merges rather than copies
  /// ([effectChainWithSharedShape]). Sharing values across cuts is the
  /// named-union link's job.
  ///
  /// An ADJUSTMENT row goes further ([LayerKind.mirrorsEffects]): its chain
  /// is its whole content, not decoration on a picture, so values mirror
  /// too.
  void updateLayerEffects({
    required CutId cutId,
    required LayerId layerId,
    required List<LayerEffect> effects,
    String description = 'Edit layer effects',
  }) {
    historyManager.executeAsOneStep(
      description,
      layerEffectsCommands(
        cutId: cutId,
        layerId: layerId,
        effects: effects,
        description: description,
      ),
    );
  }

  /// Moves rows within a cut's stack and re-parents the ones the move
  /// changed — one undo step across the whole 겸용 link group.
  ///
  /// ORDER is shared structure, like a row's existence and kind: a row
  /// moved in one use site moves in all of them, or the two stacks drift
  /// and the NEXT insertion lands somewhere nobody chose.
  /// [mirroredOrderAfterMove] RESTATES the move for each sibling rather
  /// than copying the permutation — a sibling holds rows this cut does not.
  ///
  /// [movedIds] names the rows that TRAVELLED (the whole run, not just the
  /// row the pointer held); the mirror needs it to tell a moved row from
  /// one the move merely flowed around.
  void setLayerPlacement({
    required CutId cutId,
    required List<LayerId> order,
    Map<LayerId, LayerId?> folderIds = const {},
    Set<LayerId> movedIds = const {},
    LayerAttachDrop attach = const LayerAttachDrop(),
    String description = 'Move layers',
  }) {
    // ↩️A re-ordering of a track's conte, and a row mounted on it, used to
    // be written into every other cut's conte here, seat by seat
    // (I-73-one-head-Q2). The track's structure carries them now (F-343,
    // `trackWithItsConteLaid`): this writes the cut it was given.
    _executeMovingSeats(cutId, description, [
      ...layerPlacementCommands(
        cutId: cutId,
        order: order,
        folderIds: folderIds,
        movedIds: movedIds,
        description: description,
      ),
      // The attach change rides in the SAME undo step: it was one gesture,
      // and a move that half-happened would leave a row inside a group it
      // does not belong to.
      ...layerAttachmentCommands(
        cutId: cutId,
        attach: attach,
        description: description,
      ),
    ]);
  }

  /// Runs [commands] — a write that may move attach rows' seats — as ONE
  /// undo step, with the renames those moves owe inside it
  /// ([attachNamesForMovedSeats], I-122 · F-436 ③). The two doors that move
  /// a seat come through here: a drag's [setLayerPlacement] and the menu's
  /// [setLayerAttachment].
  void _executeMovingSeats(
    CutId cutId,
    String description,
    List<Command> commands,
  ) {
    if (commands.isEmpty) {
      return;
    }
    final before = _requireCut(cutId).layers;
    historyManager.runAsOneStep(description, () {
      commands.forEach(historyManager.execute);
      final after = _requireCut(cutId).layers;
      for (final MapEntry(key: layerId, value: name)
          in attachNamesForMovedSeats(before, after).entries) {
        historyManager.execute(
          UpdateLayerNameCommand(
            repository: repository,
            cutId: cutId,
            layerId: layerId,
            name: name,
          ),
        );
      }
    });
  }

  /// The commands one row-placement write needs, INCLUDING the 겸용 link
  /// mirror. Exposed for the same reason [layerEffectsCommands] is: a drag
  /// commits the move and the attach change it made as one undo step, and it
  /// must not lose the mirror to get them.
  List<Command> layerPlacementCommands({
    required CutId cutId,
    required List<LayerId> order,
    Map<LayerId, LayerId?> folderIds = const {},
    Set<LayerId> movedIds = const {},
    String description = 'Move layers',
  }) {
    final project = repository.requireProject();
    final commands = <Command>[
      SetLayerPlacementCommand(
        repository: repository,
        cutId: cutId,
        order: order,
        folderIds: folderIds,
        description: description,
      ),
    ];
    for (final siblingId in linkedCutSiblings(project, cutId: cutId)) {
      final sibling = requireCut(project, siblingId);
      final mirroredOrder = mirroredOrderAfterMove(
        project,
        cutId: cutId,
        sourceOrder: order,
        movedIds: movedIds,
        sibling: sibling,
      );
      if (mirroredOrder == null) {
        continue;
      }
      final mirroredFolderIds = <LayerId, LayerId?>{};
      var translatable = true;
      for (final entry in folderIds.entries) {
        final row = linkCounterpartIn(
          project,
          cutId: cutId,
          layerId: entry.key,
          targetCutId: siblingId,
        );
        if (row == null) {
          continue;
        }
        final folder = entry.value;
        if (folder == null) {
          mirroredFolderIds[row] = null;
          continue;
        }
        final mirrorFolder = linkCounterpartIn(
          project,
          cutId: cutId,
          layerId: folder,
          targetCutId: siblingId,
        );
        if (mirrorFolder == null) {
          // The folder this row joined has no counterpart there — the
          // structures have diverged, and the mirrors' rule is to stand
          // down rather than guess.
          translatable = false;
          break;
        }
        mirroredFolderIds[row] = mirrorFolder;
      }
      if (!translatable) {
        continue;
      }
      commands.add(
        SetLayerPlacementCommand(
          repository: repository,
          cutId: siblingId,
          order: mirroredOrder,
          folderIds: mirroredFolderIds,
          description: description,
        ),
      );
    }
    return commands;
  }

  /// The MODE a mount of [layerId] onto [baseId] would take — the same scan
  /// the commit makes, so the caret can say which one is coming BEFORE the
  /// release (a synced mount replaces the row's timing; silence there would
  /// be the drop doing something structural unannounced).
  AttachedMode mountModeFor({
    required CutId cutId,
    required LayerId layerId,
    required LayerId baseId,
  }) {
    return _mountMode(
      _folders.mountUses(
        repository.requireProject(),
        cutId: cutId,
        rowId: layerId,
        baseId: baseId,
      ),
    );
  }

  AttachedMode _mountMode(
    List<({LayerId rowId, Layer standalone, Layer base})> uses,
  ) {
    final agreed =
        uses.isNotEmpty &&
        uses.every(
          (use) =>
              attachedLinksForMount(row: use.standalone, base: use.base) !=
              null,
        );
    return agreed ? AttachedMode.synced : AttachedMode.free;
  }

  /// The key [name] ALREADY holds in one effect lane's whole naming
  /// space — this row AND its 겸용 siblings — or null when the name is free
  /// and a rename can simply apply.
  ///
  /// The space spans cuts for the reason [effectChainWithSharedShape]
  /// relies on: linked rows are created by COPYING, so one shared effect
  /// carries the same id in every use site. Asking only the local row would
  /// call a name free while a sibling holds it, and the rename would then
  /// silently fork one name into two values.
  PropertyKey<Object?>? namedEffectKeyInSpace({
    required CutId cutId,
    required LayerId layerId,
    required EffectId effectId,
    required String lane,
    required String name,
    Set<int> excludeFramesOnSource = const {},
  }) {
    final targets = linkMirrorTargets(
      repository.requireProject(),
      cutId: cutId,
      layerId: layerId,
    );
    for (final target in targets) {
      final isSource = target.cutId == cutId && target.layerId == layerId;
      final key = namedEffectKey(
        _requireLayer(cutId: target.cutId, layerId: target.layerId).effects,
        effectId: effectId,
        lane: lane,
        name: name,
        // Only the SOURCE row holds the keys a range rename is naming; a
        // sibling's keys are all "somewhere else" by construction.
        excludeFrames: isSource ? excludeFramesOnSource : const {},
      );
      if (key != null) {
        return key;
      }
    }
    return null;
  }

  /// The commands one effect-chain write needs — INCLUDING the 겸용컷 link
  /// mirror ("액션란은 다 공유", user 2026-07-30), which is exactly what a
  /// caller that builds its own `UpdateLayerEffectsCommand` would drop.
  ///
  /// Exposed because the R8 fx master writes a row's transform switch and
  /// its effect switches as ONE undo step, so it needs the commands rather
  /// than an executed edit — and it must not lose the mirror to get them.
  ///
  /// 🚨THE ROW IS FOUND WHERE IT LIVES (se-row-fx-write-path, F-102's law:
  /// 「글로벌트랙은 … 로컬에서도 조작은 가능」). A track-owned SE row is no
  /// cut's layer, and this looked it up in [cutId] alone — so an S row's
  /// first FX edit threw. Layer ids are unique across the project, which
  /// is why the transform path ([transformTrackOfRow]) and the repository's
  /// own writes already look anywhere; this asks the same way.
  List<Command> layerEffectsCommands({
    required CutId cutId,
    required LayerId layerId,
    required List<LayerEffect> effects,
    String description = 'Edit layer effects',
  }) {
    final layer = _requireLayerAnywhere(layerId);
    if (!layer.kind.hasLayerEffects) {
      throw StateError('The camera row carries no effect chain of its own.');
    }
    final mirrorsValuesToo = layer.kind.mirrorsEffects;
    final project = repository.requireProject();
    // The chain's SHAPE is part of the row's head, so it reaches every row
    // that wears the head — a track's conte rows among them (I-73). Its
    // VALUES cross only inside the link group: a kind that mirrors them,
    // and the named keys' 「same name, same value」.
    final linked = linkMirrorTargets(
      project,
      cutId: cutId,
      layerId: layerId,
    ).toSet();
    final targets = headMirrorTargets(
      project,
      cutId: cutId,
      layerId: layerId,
    );
    // "Same name, same value": a named key moved by this write drags every
    // other key of that name along, here and in the siblings. That is how
    // a value crosses cuts at all now that chains mirror only their shape.
    final namedChanges = namedEffectKeyChanges(layer.effects, effects);
    final authored = effectsWithNamedValues(effects, namedChanges);
    return <Command>[
      for (final target in targets)
        ...() {
          final current = _requireLayerAnywhere(target.layerId).effects;
          final isSource = target.cutId == cutId && target.layerId == layerId;
          // What crosses to another cut names that cut's rows: an effect
          // that arrives whole, and a kind's values that mirror.
          final carried = target.cutId == cutId
              ? authored
              : effectsWithRowsRenamed(
                  authored,
                  (row) => linkCounterpartIn(
                    project,
                    cutId: cutId,
                    layerId: row,
                    targetCutId: target.cutId,
                  ),
                );
          final shaped = effectChainWithSharedShape(carried, onto: current);
          // The source takes the write as authored; a sibling takes only
          // the shape unless its kind mirrors values too — plus whatever
          // the named links carry. A row that only wears the head takes
          // the shape and nothing else.
          final next = isSource
              ? authored
              : !linked.contains(target)
              ? shaped
              : mirrorsValuesToo
              ? carried
              : effectsWithNamedValues(shaped, namedChanges);
          return listEquals(current, next)
              ? const <Command>[]
              : <Command>[
                  UpdateLayerEffectsCommand(
                    repository: repository,
                    cutId: target.cutId,
                    layerId: target.layerId,
                    effects: next,
                    description: description,
                  ),
                ];
        }(),
    ];
  }

  /// Replaces the project's media pool (import/rename/remove); one undo
  /// step, no-op when unchanged. Never touches clip references.
  void updateMediaAssets(
    List<MediaAsset> mediaAssets, {
    String description = 'Edit media pool',
  }) {
    if (listEquals(repository.requireProject().mediaAssets, mediaAssets)) {
      return;
    }
    historyManager.execute(
      UpdateMediaAssetsCommand(
        repository: repository,
        mediaAssets: mediaAssets,
        description: description,
      ),
    );
  }

  /// Points the [oldPath] asset at [newPath], rewriting the pool entry and
  /// every referencing clip in ONE undo step; no-op when nothing changes
  /// or the pool does not know [oldPath]. [carriedAs], when given, is the
  /// carry the asset is from now on ([RelinkMediaAssetCommand.carriedAs]).
  ///
  /// Answers whether it relinked — what the caller's own follow-up (the
  /// fingerprints, a staged copy made for [carriedAs]) waits on.
  bool relinkMediaAsset({
    required String oldPath,
    required String newPath,
    String? carriedAs,
    String description = 'Relink media',
  }) {
    final project = repository.requireProject();
    if (oldPath == newPath ||
        project.mediaAssetByPath(oldPath) == null ||
        project.mediaAssetByPath(newPath) != null) {
      return false;
    }
    historyManager.execute(
      RelinkMediaAssetCommand(
        repository: repository,
        oldPath: oldPath,
        newPath: newPath,
        carriedAs: carriedAs,
        description: description,
      ),
    );
    return true;
  }

  /// RELINK-2: the batch form — several assets in ONE undo step.
  ///
  /// Not a loop over [relinkMediaAsset]: that pushes N history entries, and
  /// a user who pointed the app at the wrong folder wants one ctrl-Z rather
  /// than thirty. [oneStepOf] already exists for exactly this.
  ///
  /// The same three guards apply per entry, plus one the single form cannot
  /// need: **two assets may not claim the same destination.** The matcher
  /// drops such collisions already, but the guard belongs here too — the
  /// pool is keyed by path, so a second asset arriving at a taken path
  /// would either be refused mid-batch (leaving half a relink in the undo
  /// stack) or silently merge two entries into one.
  ///
  /// Answers the moves it made — what the caller's own follow-up (the
  /// fingerprints) is owed; a move the guards refused is owed nothing.
  Map<String, String> relinkMediaAssets(
    Map<String, String> moves, {
    String description = 'Relink media',
  }) {
    final project = repository.requireProject();
    final claimed = <String>{};
    final made = <String, String>{};
    final commands = <Command>[];
    for (final entry in moves.entries) {
      final oldPath = entry.key;
      final newPath = entry.value;
      if (oldPath == newPath ||
          project.mediaAssetByPath(oldPath) == null ||
          project.mediaAssetByPath(newPath) != null ||
          !claimed.add(newPath)) {
        continue;
      }
      made[oldPath] = newPath;
      commands.add(
        RelinkMediaAssetCommand(
          repository: repository,
          oldPath: oldPath,
          newPath: newPath,
          description: description,
        ),
      );
    }
    // Nothing survived the guards — no undo step for a no-op.
    historyManager.executeAsOneStep(description, commands);
    return made;
  }

  void updateLayerKind({
    required CutId cutId,
    required LayerId layerId,
    required LayerKind kind,
  }) {
    final layer = _requireLayer(cutId: cutId, layerId: layerId);
    if (layer.kind == kind) {
      return;
    }
    if (isAttachedLayer(layer)) {
      throw StateError('Attach layers keep their base\'s kind: $layerId');
    }
    if (layer.kind.isFixed || kind.isFixed) {
      throw StateError(
        'The camera layer kind is fixed; layers cannot become cameras.',
      );
    }
    if (layer.kind == LayerKind.instruction || kind == LayerKind.instruction) {
      throw StateError(
        'Instruction rows are created as such; layer kinds cannot cross '
        'into or out of instruction.',
      );
    }
    if (layer.kind == LayerKind.se) {
      final cut = _requireCut(cutId);
      // Converting an SE row away must not break the S1·S2 floor of two.
      if (cut.layers.where((other) => other.kind == LayerKind.se).length <= 2) {
        return;
      }
    }

    historyManager.execute(
      UpdateLayerKindCommand(
        repository: repository,
        cutId: cutId,
        layerId: layerId,
        kind: kind,
      ),
    );
  }

  /// Writes the memo of the exposure BLOCK starting at [blockStartIndex].
  /// An empty memo clears it, so a memo nobody wrote costs nothing on disk.
  void updateExposureMemo({
    required CutId cutId,
    required LayerId layerId,
    required int blockStartIndex,
    required ExposureMemo memo,
  }) {
    final entry = requireMemoBlockAt(
      _requireLayer(cutId: cutId, layerId: layerId),
      blockStartIndex,
    );

    final next = memo.isEmpty ? null : memo;
    if (entry.memo == next) {
      return;
    }

    historyManager.execute(
      UpdateExposureMemoCommand(
        repository: repository,
        cutId: cutId,
        layerId: layerId,
        blockStartIndex: blockStartIndex,
        memo: next,
      ),
    );
  }

  Layer _requireLayer({required CutId cutId, required LayerId layerId}) {
    return requireLayer(
      repository.requireProject(),
      cutId: cutId,
      layerId: layerId,
    );
  }

  Cut _requireCut(CutId cutId) {
    return requireCut(repository.requireProject(), cutId);
  }

}
