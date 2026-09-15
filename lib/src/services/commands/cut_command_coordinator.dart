import '../editing/default_cut_helpers.dart';
import '../editing/editing_session_state.dart';
import '../../core/collection_equality.dart';
import '../../models/attached_layer_mount.dart';
import '../../models/attached_layer_resolve.dart';
import '../../models/attached_mode.dart';
import '../../models/audio_clip.dart';
import '../../models/camera_instruction.dart';
import '../../models/camera_pose.dart';
import '../../models/canvas_resize_anchor.dart';
import '../../models/canvas_size.dart';
import '../../models/cut.dart';
import '../../models/cut_camera.dart';
import '../../models/cut_id.dart';
import '../../models/layer.dart';
import '../../models/layer_effect.dart';
import '../../models/layer_folder.dart';
import '../../models/layer_id.dart';
import '../../models/layer_kind.dart';
import '../../models/layer_mark.dart';
import '../../models/media_asset.dart';
import '../../models/se_name_tag.dart';
import '../../models/project.dart';
import '../../models/property_track.dart' show PropertyKey;
import '../../models/project_background.dart';
import '../../models/timesheet_info.dart';
import '../../models/exposure_memo.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../models/transform_track.dart';
import '../brush_frame_store.dart';
import '../clipboard/layer_copy_payload.dart';
import '../command.dart' show Command, CompositeCommand;
import '../history_manager.dart';
import '../project_lookup.dart';
import '../project_repository.dart';
import 'cut_command_input_planner.dart';
import 'convert_to_linked_cut_command.dart';
import 'convert_to_linked_cut_plan.dart';
import 'create_cut_command.dart';
import 'create_folder_command.dart';
import 'create_linked_cut_command.dart';
import 'dissolve_folder_command.dart';
import 'link_mirror.dart'
    show
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
import 'paste_layer_command.dart';
import 'rename_cut_command.dart';
import 'update_cut_durations_command.dart';
import 'reorder_cut_command.dart';
import 'resize_cut_canvas_command.dart';
import 'relink_media_asset_command.dart';
import 'rasterize_layer_reference_command.dart';
import 'update_camera_instruction_set_command.dart';
import 'update_cut_camera_command.dart';
import 'update_cut_note_command.dart';
import 'update_track_display_command.dart';
import 'update_track_effects_command.dart';
import 'update_cut_thumbnail_frame_command.dart';
import 'update_layer_audio_clips_command.dart';
import 'update_se_name_tag_command.dart';
import 'update_layer_instructions_command.dart';
import 'update_layer_kind_command.dart';
import 'update_layer_mark_command.dart';
import 'update_layer_name_command.dart';
import 'update_layer_effects_command.dart';
import 'update_layer_fill_reference_command.dart';
import 'update_layer_timesheet_command.dart';
import 'update_layer_transform_command.dart';
import 'update_media_assets_command.dart';
import 'update_project_background_command.dart';
import 'update_project_stage_colors_command.dart';
import 'update_timesheet_info_command.dart';
import 'update_exposure_memo_command.dart';

part 'cut_commands/cut_commands.dart';
part 'cut_commands/camera_commands.dart';
part 'cut_commands/link_commands.dart';
part 'cut_commands/track_commands.dart';
part 'cut_commands/folder_and_attachment_commands.dart';
part 'cut_commands/project_setting_commands.dart';

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
    String? name,
    CanvasSize? canvasSize,
    // #18 — an EXPLICIT landing (gap parking, range selection): the index
    // to insert at, the walk-in distance into the gap as the new cut's
    // own leading gap, and an optional duration (a range names its own
    // length, the way the transition span's selection does). Null keeps
    // the classic anchor: right of the active cut, else the track's end.
    ({int? index, int leadingGapFrames, int? duration})? placement,
  }) => _cuts.createCut(
    trackId: trackId,
    name: name,
    canvasSize: canvasSize,
    placement: placement,
  );
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
  void renameCut({required CutId cutId, required String newName}) =>
      _cuts.renameCut(cutId: cutId, newName: newName);
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
  void updateCutNote({required CutId cutId, required String note}) =>
      _cuts.updateCutNote(cutId: cutId, note: note);
  void updateCutThumbnailFrame({
    required CutId cutId,
    required int? frameIndex,
  }) => _cuts.updateCutThumbnailFrame(cutId: cutId, frameIndex: frameIndex);
  void reorderCut({
    required TrackId trackId,
    required CutId cutId,
    required int newIndex,
  }) => _cuts.reorderCut(trackId: trackId, cutId: cutId, newIndex: newIndex);
  void setCutOrder({required TrackId trackId, required List<CutId> order}) =>
      _cuts.setCutOrder(trackId: trackId, order: order);
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
  void duplicateCut({
    required CutId sourceCutId,
    required TrackId targetTrackId,
    String? newName,
  }) => _cuts.duplicateCut(
    sourceCutId: sourceCutId,
    targetTrackId: targetTrackId,
    newName: newName,
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
    double? opacity,
    bool? fxEnabled,
    String description = 'Edit track display',
  }) => _tracks.updateTrackDisplay(
    trackId: trackId,
    opacity: opacity,
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

    final layer = _requireLayer(cutId: cutId, layerId: layerId);
    if (layer.name == trimmedName) {
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
    // after deletions, and renumbering would be inventing state).
    //
    // ★Still answered RIGHT HERE, against the OLD name: ask a moment later
    // and the prefix is gone with the name it hung off.
    //
    // ⚠️A prefix is a prefix: with an owner named `B`, an attach named
    // `Bob` follows too. That is the rule as asked for — narrowing it
    // (demand a separator, demand the default shape) would put back the
    // very "my own name stopped following" surprise this removes.
    final followers = <Command>[];
    final ownerPrefix = layer.name;
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

    final rename = UpdateLayerNameCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      name: trimmedName,
    );
    historyManager.execute(
      followers.isEmpty
          ? rename
          : CompositeCommand(
              description: 'Rename layer and its default-named attaches',
              commands: [rename, ...followers],
            ),
    );
  }

  // ── the link commands: their own object ─────────────────────────────
  //
  // A collaborator (commands/cut_commands/link_commands.dart, a part of this
  // library). The coordinator keeps the public commands as forwarders.
  _LinkCommands get _links => _LinkCommands(this);

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
  ConvertToLinkedCutPlan convertToLinkedCutPreview({
    required CutId originCutId,
    required CutId targetCutId,
  }) => _links.convertToLinkedCutPreview(
    originCutId: originCutId,
    targetCutId: targetCutId,
  );
  void linkDuplicateLayer({required CutId cutId, required LayerId layerId}) =>
      _links.linkDuplicateLayer(cutId: cutId, layerId: layerId);

  // ── the folder and attachment commands: their own object ────────────
  //
  // A collaborator (commands/cut_commands/folder_and_attachment_commands.dart, a part of this
  // library). The coordinator keeps the public commands as forwarders.
  _FolderAndAttachmentCommands get _folders =>
      _FolderAndAttachmentCommands(this);

  LayerId? createFolderFromLayer({
    required CutId cutId,
    required LayerId layerId,
    String? name,
  }) => _folders.createFolderFromLayer(
    cutId: cutId,
    layerId: layerId,
    name: name,
  );
  LayerId? createAttachOrganizerFolder({
    required CutId cutId,
    required LayerId layerId,
    String? name,
  }) => _folders.createAttachOrganizerFolder(
    cutId: cutId,
    layerId: layerId,
    name: name,
  );
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
    // Deleting a FOLDER row means dissolving it: the members are rows in
    // their own right and stay where they are. (Deleting the pictures too
    // would make one Delete key destroy work the row itself never held.)
    if (layer.kind.groupsLayers) {
      dissolveFolder(cutId: cutId, folderId: layerId);
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
        LayerKind.text ||
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
    if (isAttachedLayer(layer)) {
      final emptied = cut.layers.foldersEmptiedByRemoving(
        {layerId},
        canRemove: (folder) =>
            attachOrganizerBaseOf(folder, cut.layers) != null &&
            repository.requireProject().linkRegistry.groupOf(
                  cutId: cutId,
                  layerId: folder.id,
                ) ==
                null,
      );
      if (emptied.isNotEmpty) {
        historyManager.execute(
          CompositeCommand(
            description:
                'Delete layer ${layer.name} and its empty '
                '${emptied.length == 1 ? 'folder' : 'folders'}',
            commands: [
              DeleteLayerCommand(
                repository: repository,
                cutId: cutId,
                layerId: layerId,
              ),
              for (final folder in emptied)
                DeleteLayerCommand(
                  repository: repository,
                  cutId: cutId,
                  layerId: folder.id,
                ),
            ],
          ),
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
        ),
      );
      return;
    }
    final organizerRows = [
      for (final row in cut.layers)
        if (attachOrganizerBaseOf(row, cut.layers) == layerId) row,
    ];
    historyManager.execute(
      CompositeCommand(
        description: 'Delete layer ${layer.name} and its attach layers',
        commands: [
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
      ),
    );
  }

  LayerId duplicateLayer({
    required CutId cutId,
    required LayerId sourceLayerId,
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
      insertionIndex: sourceIndex + 1,
    );
  }

  LayerId pasteLayer({
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

    historyManager.execute(
      PasteLayerCommand(
        repository: repository,
        cutId: cutId,
        layer: plan.layer,
        insertionIndex: plan.insertionIndex,
      ),
    );

    return plan.layer.id;
  }

  /// RASTERIZE (§6-f): nulls the layer's media reference — the pixels are
  /// already its cels. The asset stays in the pool (유저 2026-09-11: 「구워도
  /// 풀에 남음」). One undo step; no-op on non-reference layers.
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
    historyManager.execute(
      RasterizeLayerReferenceCommand(
        repository: repository,
        cutId: cutId,
        layerId: layerId,
      ),
    );
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

  void setLayerFillReference({
    required CutId cutId,
    required LayerId layerId,
    required bool isFillReference,
  }) => _executeIfChanged(
    subject: _requireLayerAnywhere(layerId),
    value: isFillReference,
    read: (layer) => layer.isFillReference,
    command: (_) => UpdateLayerFillReferenceCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      isFillReference: isFillReference,
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

  /// Replaces an instruction row's span map; one undo step, no-op when
  /// unchanged. An optional [note] rewrites the cut note in the SAME undo
  /// step (the creation flow auto-writes the memo shorthand — R5-⑥).
  void updateLayerInstructions({
    required CutId cutId,
    required LayerId layerId,
    required Map<int, InstructionEvent> instructions,
    String description = 'Edit instructions',
    String? note,
  }) {
    final layer = _requireLayer(cutId: cutId, layerId: layerId);
    if (layer.kind != LayerKind.instruction) {
      throw StateError('Instruction spans belong on instruction rows only.');
    }
    if (mapEquals(layer.instructions, instructions)) {
      return;
    }

    final instructionsCommand = UpdateLayerInstructionsCommand(
      repository: repository,
      cutId: cutId,
      layerId: layerId,
      instructions: instructions,
      description: description,
    );
    if (note == null || _requireCut(cutId).metadata.note == note) {
      historyManager.execute(instructionsCommand);
      return;
    }
    historyManager.execute(
      CompositeCommand(
        description: description,
        commands: [
          instructionsCommand,
          UpdateCutNoteCommand(
            repository: repository,
            cutId: cutId,
            note: note,
          ),
        ],
      ),
    );
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
    // Anywhere lookup — the SE rows are TRACK fixtures (S1·S2), not in the
    // cut's layer list (UI-R7 #4: media drops onto them dead-ended here).
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    if (layer.kind != LayerKind.se) {
      throw StateError('Audio clips belong on SE layers only.');
    }
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
    // Anywhere lookup, like the audio clips above — SE rows are TRACK
    // fixtures and the cut-scoped read throws for them.
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    if (layer.kind != LayerKind.se) {
      throw StateError('Name tags belong on SE layers only.');
    }
    if (layer.seNameTag == seNameTag) {
      return;
    }
    historyManager.execute(
      UpdateSeNameTagCommand(
        repository: repository,
        layerId: layerId,
        seNameTag: seNameTag,
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
    final commands = layerEffectsCommands(
      cutId: cutId,
      layerId: layerId,
      effects: effects,
      description: description,
    );
    if (commands.isEmpty) {
      return;
    }
    historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(description: description, commands: commands),
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
    final commands = [
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
    ];
    historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(description: description, commands: commands),
    );
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
          // structures have diverged, and folder_mirror's rule is to stand
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

  /// The value [name] ALREADY holds in one effect parameter's whole naming
  /// space — this row AND its 겸용 siblings — or null when the name is free
  /// and a rename can simply apply.
  ///
  /// The space spans cuts for the reason [effectChainWithSharedShape]
  /// relies on: linked rows are created by COPYING, so one shared effect
  /// carries the same id in every use site. Asking only the local row would
  /// call a name free while a sibling holds it, and the rename would then
  /// silently fork one name into two values.
  PropertyKey<double>? namedEffectKeyInSpace({
    required CutId cutId,
    required LayerId layerId,
    required EffectId effectId,
    required String parameterId,
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
        parameterId: parameterId,
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
  List<Command> layerEffectsCommands({
    required CutId cutId,
    required LayerId layerId,
    required List<LayerEffect> effects,
    String description = 'Edit layer effects',
  }) {
    final layer = _requireLayer(cutId: cutId, layerId: layerId);
    if (!layer.kind.hasLayerEffects) {
      throw StateError('The camera row carries no effect chain of its own.');
    }
    final mirrorsValuesToo = layer.kind.mirrorsEffects;
    final targets = linkMirrorTargets(
      repository.requireProject(),
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
          final current = _requireLayer(
            cutId: target.cutId,
            layerId: target.layerId,
          ).effects;
          final isSource = target.cutId == cutId && target.layerId == layerId;
          // The source takes the write as authored; a sibling takes only
          // the shape unless its kind mirrors values too — plus whatever
          // the named links carry.
          final next = isSource || mirrorsValuesToo
              ? authored
              : effectsWithNamedValues(
                  effectChainWithSharedShape(authored, onto: current),
                  namedChanges,
                );
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
  /// or the pool does not know [oldPath].
  void relinkMediaAsset({
    required String oldPath,
    required String newPath,
    String description = 'Relink media',
  }) {
    final project = repository.requireProject();
    if (oldPath == newPath ||
        project.mediaAssetByPath(oldPath) == null ||
        project.mediaAssetByPath(newPath) != null) {
      return;
    }
    historyManager.execute(
      RelinkMediaAssetCommand(
        repository: repository,
        oldPath: oldPath,
        newPath: newPath,
        description: description,
      ),
    );
  }

  /// RELINK-2: the batch form — several assets in ONE undo step.
  ///
  /// Not a loop over [relinkMediaAsset]: that pushes N history entries, and
  /// a user who pointed the app at the wrong folder wants one ctrl-Z rather
  /// than thirty. [CompositeCommand] already exists for exactly this.
  ///
  /// The same three guards apply per entry, plus one the single form cannot
  /// need: **two assets may not claim the same destination.** The matcher
  /// drops such collisions already, but the guard belongs here too — the
  /// pool is keyed by path, so a second asset arriving at a taken path
  /// would either be refused mid-batch (leaving half a relink in the undo
  /// stack) or silently merge two entries into one.
  void relinkMediaAssets(
    Map<String, String> moves, {
    String description = 'Relink media',
  }) {
    final project = repository.requireProject();
    final claimed = <String>{};
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
      commands.add(
        RelinkMediaAssetCommand(
          repository: repository,
          oldPath: oldPath,
          newPath: newPath,
          description: description,
        ),
      );
    }
    if (commands.isEmpty) {
      // Nothing survived the guards — no undo step for a no-op.
      return;
    }
    historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(description: description, commands: commands),
    );
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
