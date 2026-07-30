import '../../controllers/default_cut_helpers.dart';
import '../../controllers/editing_session_state.dart';
import '../../core/collection_equality.dart';
import '../../models/attached_layer_resolve.dart';
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
import 'link_mirror.dart' show linkMirrorTargets;
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
import 'update_track_transform_command.dart';
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

  void createCut({
    required TrackId trackId,
    String? name,
    CanvasSize? canvasSize,
  }) {
    final project = repository.requireProject();
    final plan = planCreateCutCommandInput(project);
    final anchor = _insertionAnchorFor(project, trackId);

    historyManager.execute(
      CreateCutCommand(
        repository: repository,
        editingSession: editingSession,
        trackId: trackId,
        cutId: plan.cutId,
        layerId: plan.layerId,
        name: name ?? nextCutNameAfter(project, anchor.referenceName),
        index: anchor.index,
        canvasSize: canvasSize ?? defaultCutCanvasSize,
      ),
    );
  }

  /// Where a new cut lands on [trackId], and which name it counts from: to
  /// the RIGHT of the active cut when the active cut is on this track (the
  /// user's working position), the track's end otherwise.
  ({int? index, String? referenceName}) _insertionAnchorFor(
    Project project,
    TrackId trackId,
  ) {
    for (final track in project.tracks) {
      if (track.id != trackId) {
        continue;
      }
      final activeIndex = track.cuts.indexWhere(
        (cut) => cut.id == editingSession.activeCutId,
      );
      if (activeIndex != -1) {
        return (
          index: activeIndex + 1,
          referenceName: track.cuts[activeIndex].name,
        );
      }
      return (
        index: null,
        referenceName: track.cuts.isEmpty ? null : track.cuts.last.name,
      );
    }
    return (index: null, referenceName: null);
  }

  /// The name a new cut takes when it lands after [referenceName].
  ///
  /// The cut NAME is the cut number (UI-R7 #3: bare numbers, the sheet
  /// convention) — a free string the user may rename to anything, so this
  /// never computes a number, it OFFERS candidates and takes the first one
  /// nobody holds:
  ///
  /// 1. the reference's trailing digits, incremented (`39A` → `40`);
  /// 2. failing that — which is exactly the moment a cut is being slipped
  ///    BETWEEN two numbered ones — a letter suffix on the reference
  ///    (`39` → `39A` → `39B`), the split-cut convention Japanese sheets
  ///    use and Storyboard Pro's naming preferences generate;
  /// 3. past `Z`, the suffix takes a number (`39Z` → `39A1`).
  ///
  /// Offering candidates rather than computing is what keeps hand-written
  /// names (`39ハ`, `オープニング`) from breaking it: a name the rule cannot
  /// read is simply not a candidate it would have proposed.
  static String nextCutNameAfter(Project project, String? referenceName) {
    final taken = <String>{
      for (final track in project.tracks)
        for (final cut in track.cuts) cut.name.trim(),
    };

    final reference = referenceName?.trim() ?? '';

    // The number is the reference's FIRST digit run; whatever trails it is
    // a split marker, not part of the count ('39A' counts as 39).
    final number = RegExp(r'^(\D*)(\d+)').firstMatch(reference);
    if (number != null) {
      final candidate = '${number.group(1)!}${int.parse(number.group(2)!) + 1}';
      if (!taken.contains(candidate)) {
        return candidate;
      }
    }

    if (reference.isEmpty) {
      // Nothing to hang a suffix on (an empty track): count up from 1.
      for (var next = 1; ; next += 1) {
        final candidate = '$next';
        if (!taken.contains(candidate)) {
          return candidate;
        }
      }
    }

    // The number is spoken for, so this is a split: suffix the reference.
    // A reference that already carries a single-letter suffix continues
    // ITS series ('39A' → '39B') rather than growing a second one.
    final suffixed = RegExp(r'^(.*?)([A-Za-z])$').firstMatch(reference);
    final root = suffixed?.group(1) ?? reference;
    final firstLetter = suffixed == null
        ? 0
        : suffixed.group(2)!.toUpperCase().codeUnitAt(0) - 64;

    for (var letter = firstLetter; letter < 26; letter += 1) {
      final candidate = '$root${String.fromCharCode(65 + letter)}';
      if (!taken.contains(candidate)) {
        return candidate;
      }
    }
    // Past Z the suffix takes a number, the way Storyboard Pro's Auto
    // suffix cycles into numbered variants.
    for (var round = 1; ; round += 1) {
      for (var letter = 0; letter < 26; letter += 1) {
        final candidate = '$root${String.fromCharCode(65 + letter)}$round';
        if (!taken.contains(candidate)) {
          return candidate;
        }
      }
    }
  }

  void resizeCutCanvas({
    required CutId cutId,
    required CanvasSize canvasSize,
    CanvasResizeAnchor anchor = CanvasResizeAnchor.topLeft,
  }) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) {
      throw ArgumentError.value(
        canvasSize,
        'canvasSize',
        'Canvas size must be positive.',
      );
    }

    final cut = _requireCut(cutId);
    if (cut.canvasSize == canvasSize) {
      return;
    }

    historyManager.execute(
      ResizeCutCanvasCommand(
        repository: repository,
        cutId: cutId,
        canvasSize: canvasSize,
        anchor: anchor,
        brushFrameStore: brushFrameStore,
      ),
    );
  }

  void renameCut({required CutId cutId, required String newName}) {
    historyManager.execute(
      RenameCutCommand(repository: repository, cutId: cutId, newName: newName),
    );
  }

  /// Commits a storyboard edge drag as one undoable step: durations (end
  /// trims) and leading gaps (start slides / gap consumption) together.
  /// The fade re-anchor rewrites are gone (R4: fade keys are TRACK data
  /// on the global axis — a trim moves none of them).
  void commitCutDurationDrag({
    required Map<CutId, int> beforeDurations,
    required Map<CutId, int> afterDurations,
    Map<CutId, int> beforeGaps = const {},
    Map<CutId, int> afterGaps = const {},
  }) {
    historyManager.execute(
      UpdateCutDurationsCommand(
        repository: repository,
        before: beforeDurations,
        after: afterDurations,
        beforeGaps: beforeGaps,
        afterGaps: afterGaps,
      ),
    );
  }

  void updateCutNote({required CutId cutId, required String note}) {
    final cut = _requireCut(cutId);
    if (cut.metadata.note == note) {
      return;
    }

    historyManager.execute(
      UpdateCutNoteCommand(repository: repository, cutId: cutId, note: note),
    );
  }

  /// Pins the storyboard thumbnail to a cut-local frame (null = back to the
  /// first frame); one undo step.
  void updateCutThumbnailFrame({
    required CutId cutId,
    required int? frameIndex,
  }) {
    final cut = _requireCut(cutId);
    if (cut.metadata.thumbnailFrameIndex == frameIndex) {
      return;
    }

    historyManager.execute(
      UpdateCutThumbnailFrameCommand(
        repository: repository,
        cutId: cutId,
        frameIndex: frameIndex,
      ),
    );
  }

  void setCutCameraKeyframe({
    required CutId cutId,
    required int frameIndex,
    required CameraPose pose,
  }) {
    if (frameIndex < 0) {
      throw ArgumentError.value(
        frameIndex,
        'frameIndex',
        'Camera keyframe index must be non-negative.',
      );
    }

    final cut = _requireCut(cutId);
    if (cut.camera.keyframeAt(frameIndex) == pose) {
      return;
    }

    historyManager.execute(
      UpdateCutCameraCommand(
        repository: repository,
        cutId: cutId,
        camera: cut.camera.withKeyframe(frameIndex, pose),
        description: 'Set camera keyframe at frame ${frameIndex + 1}',
      ),
    );
  }

  void removeCutCameraKeyframe({
    required CutId cutId,
    required int frameIndex,
  }) {
    final cut = _requireCut(cutId);
    if (cut.camera.keyframeAt(frameIndex) == null) {
      return;
    }

    historyManager.execute(
      UpdateCutCameraCommand(
        repository: repository,
        cutId: cutId,
        camera: cut.camera.withoutKeyframe(frameIndex),
        description: 'Remove camera keyframe at frame ${frameIndex + 1}',
      ),
    );
  }

  void clearCutCamera({required CutId cutId}) {
    final cut = _requireCut(cutId);
    if (cut.camera.isEmpty) {
      return;
    }

    historyManager.execute(
      UpdateCutCameraCommand(
        repository: repository,
        cutId: cutId,
        camera: CutCamera.empty(),
        description: 'Clear camera keyframes',
      ),
    );
  }

  /// Replaces the cut's whole camera track in one undo step — the property
  /// lanes edit per-property keys (move/toggle/hold) that the pose-level
  /// APIs above cannot express.
  void updateCutCamera({
    required CutId cutId,
    required CutCamera camera,
    String description = 'Edit camera keyframes',
  }) {
    final cut = _requireCut(cutId);
    if (cut.camera == camera) {
      return;
    }

    historyManager.execute(
      UpdateCutCameraCommand(
        repository: repository,
        cutId: cutId,
        camera: camera,
        description: description,
      ),
    );
  }

  /// Replaces a TRACK's transform lanes in one undo step (R4: the V
  /// effects are track data on the global axis; fades key the opacity
  /// lane through the same write).
  void updateTrackTransform({
    required TrackId trackId,
    required TransformTrack transformTrack,
    String description = 'Edit track transform',
  }) {
    for (final track in repository.requireProject().tracks) {
      if (track.id == trackId) {
        if (track.transformTrack == transformTrack) {
          return;
        }
        break;
      }
    }

    historyManager.execute(
      UpdateTrackTransformCommand(
        repository: repository,
        trackId: trackId,
        transformTrack: transformTrack,
        description: description,
      ),
    );
  }

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

    historyManager.execute(
      UpdateLayerNameCommand(
        repository: repository,
        cutId: cutId,
        layerId: layerId,
        name: trimmedName,
      ),
    );
  }

  /// 겸용컷 생성 (L2): a new cut whose drawing layers share the source's
  /// cel banks with EMPTY timelines — the bank re-exposes to a new
  /// rhythm. One undo step; the new cut becomes active.
  void createLinkedCut({required CutId sourceCutId, String? name}) {
    final project = repository.requireProject();
    final sourceCut = requireCut(project, sourceCutId);
    final plan = planCreateLinkedCutCommandInput(
      project: project,
      sourceCut: sourceCut,
    );

    historyManager.execute(
      CreateLinkedCutCommand(
        repository: repository,
        editingSession: editingSession,
        sourceCutId: sourceCutId,
        newCutId: plan.newCutId,
        // A linked cut is inserted right after its source, so the source
        // is what it counts from.
        newName: name ?? nextCutNameAfter(project, sourceCut.name),
        layerIdMap: plan.layerIdMap,
        newGroupIdBySource: plan.newGroupIdBySource,
      ),
    );
  }

  /// 독립시키기 (L2): removes [layerId]'s whole attach group from its
  /// link groups and forks the shared pixels into the group's own cels.
  /// No-op when nothing in the group is linked. One undo step.
  void unlinkLayer({required CutId cutId, required LayerId layerId}) {
    final store = brushFrameStore;
    if (store == null) {
      throw StateError('unlinkLayer needs the brush frame store.');
    }
    final project = repository.requireProject();
    final cut = requireCut(project, cutId);
    final source = requireLayer(project, cutId: cutId, layerId: layerId);
    final baseId = source.attachedToLayerId ?? source.id;
    final endIndex = attachedGroupEndIndex(baseId, cut.layers);
    final startIndex = attachedGroupStartIndex(baseId, cut.layers);
    final anyLinked = cut.layers
        .sublist(startIndex, endIndex)
        .any(
          (member) =>
              project.linkRegistry.groupOf(
                cutId: cutId,
                layerId: member.id,
              ) !=
              null,
        );
    if (!anyLinked) {
      return;
    }

    historyManager.execute(
      UnlinkLayerCommand(
        repository: repository,
        brushFrameStore: store,
        cutId: cutId,
        sourceLayerId: layerId,
      ),
    );
  }

  /// 겸용 변경 (L2b): links [targetCutId] to [originCutId] after both
  /// were drawn — name-matching, 원본 승리 conflicts, 완전 미러 union.
  /// [plan] previews the effect for the confirmation dialog; the caller
  /// shows it and only then invokes this. No-op when nothing would link.
  /// One undo step. Needs the brush frame store.
  void convertCutToLinked({
    required CutId originCutId,
    required CutId targetCutId,
  }) {
    final store = brushFrameStore;
    if (store == null) {
      throw StateError('convertCutToLinked needs the brush frame store.');
    }
    final project = repository.requireProject();
    final originCut = requireCut(project, originCutId);
    final targetCut = requireCut(project, targetCutId);
    if (!convertToLinkedCutPreview(
      originCutId: originCutId,
      targetCutId: targetCutId,
    ).linksAnything) {
      return;
    }
    final plan = planConvertToLinkedCutCommandInput(
      project: project,
      originCut: originCut,
      targetCut: targetCut,
    );

    historyManager.execute(
      ConvertToLinkedCutCommand(
        repository: repository,
        brushFrameStore: store,
        originCutId: originCutId,
        targetCutId: targetCutId,
        unionLayerIdMap: plan.unionLayerIdMap,
        newGroupIdBySource: plan.newGroupIdBySource,
      ),
    );
  }

  /// The 겸용 변경 preview for the confirmation dialog (링크 목록·교체
  /// 장수·합류 수·양측 고유 레이어) — pure, no mutation.
  ConvertToLinkedCutPlan convertToLinkedCutPreview({
    required CutId originCutId,
    required CutId targetCutId,
  }) {
    final project = repository.requireProject();
    return planConvertToLinkedCut(
      project: project,
      originCut: requireCut(project, originCutId),
      targetCut: requireCut(project, targetCutId),
    );
  }

  /// 폴더 생성: folds [layerId]'s whole attach group into a new folder ROW
  /// inserted directly above the group (attach groups never split across a
  /// folder boundary; the group is a contiguous stack run — belows and
  /// their organizer folder rows included). Only the slice's TOP-LEVEL
  /// rows re-folder: attach rows inside an ORGANIZER ([연출]/[작감]…) keep
  /// their organizer, which is itself a member — inner structure survives
  /// the fold. Mirrors into 겸용 cuts. Returns the new folder layer's id
  /// in [cutId], null when the layer can't fold (non-drawing kinds).
  ///
  /// Renaming the folder afterwards is just [renameLayer] — a folder is a
  /// layer, so it needs no command of its own.
  LayerId? createFolderFromLayer({
    required CutId cutId,
    required LayerId layerId,
    String? name,
  }) {
    final project = repository.requireProject();
    final cut = requireCut(project, cutId);
    final source = requireLayer(project, cutId: cutId, layerId: layerId);
    if (source.kind != LayerKind.animation) {
      return null;
    }
    final baseId = source.attachedToLayerId ?? source.id;
    final base = requireLayer(project, cutId: cutId, layerId: baseId);
    final slice = cut.layers.sublist(
      attachedGroupStartIndex(baseId, cut.layers),
      attachedGroupEndIndex(baseId, cut.layers),
    );
    final memberIds = [
      for (final layer in slice)
        if (layer.folderId == base.folderId) layer.id,
    ];
    final plan = planCreateFolderCommandInput(
      project: project,
      cutId: cutId,
      memberLayerIds: memberIds,
    );

    historyManager.execute(
      CreateFolderCommand(
        repository: repository,
        cutId: cutId,
        name: name ?? nextFolderName(cut),
        memberLayerIds: memberIds,
        folderIdByCut: plan.folderIdByCut,
        groupId: plan.folderGroupId,
      ),
    );
    return plan.folderIdByCut[cutId];
  }

  /// 공정 폴더 생성: wraps ONE attach row in an ORGANIZER folder
  /// ([연출]/[작감]…) INSIDE its attach group. The attach relation stays
  /// direct to the base — the folder organizes and display-controls only.
  /// Siblings join through [EditorSessionManager.addAttachedLayer]'s
  /// sibling rule (adding from a row inside an organizer lands next to
  /// it). Organizers are FLAT: a row already inside one refuses (null).
  ///
  /// Deliberately PER-CUT — no 겸용 mirror, no link-group membership. The
  /// flat rule can only be checked against THIS cut, and a mirrored
  /// organizer nesting under a diverged counterpart's folder would break
  /// that cut's group span; an unlinked folder row also keeps deletes and
  /// dissolves from fanning out into other cuts' structures.
  LayerId? createAttachOrganizerFolder({
    required CutId cutId,
    required LayerId layerId,
    String? name,
  }) {
    final project = repository.requireProject();
    final cut = requireCut(project, cutId);
    final source = requireLayer(project, cutId: cutId, layerId: layerId);
    if (!isAttachedLayer(source)) {
      return null;
    }
    final currentFolder = cut.layers.folderById(source.folderId);
    if (currentFolder != null &&
        attachOrganizerBaseOf(currentFolder, cut.layers) != null) {
      return null;
    }
    final memberIds = [source.id];
    final plan = planCreateFolderCommandInput(
      project: project,
      cutId: cutId,
      memberLayerIds: memberIds,
    );
    final folderId = plan.folderIdByCut[cutId]!;
    historyManager.execute(
      CreateFolderCommand(
        repository: repository,
        cutId: cutId,
        name: name ?? nextFolderName(cut),
        memberLayerIds: memberIds,
        // Origin cut only: mirror cuts are deliberately excluded (see
        // the doc above) — the command skips any cut absent from this
        // map.
        folderIdByCut: {cutId: folderId},
        groupId: plan.folderGroupId,
      ),
    );
    return folderId;
  }

  /// 폴더 해산: releases members to the parent and removes the folder row
  /// (layers stay). Mirrors into 겸용 cuts.
  void dissolveFolder({required CutId cutId, required LayerId folderId}) {
    historyManager.execute(
      DissolveFolderCommand(
        repository: repository,
        cutId: cutId,
        folderId: folderId,
      ),
    );
  }

  /// 링크 복제 (L2): duplicates [layerId]'s whole attach group as a free
  /// group sharing the originals' cel banks (same FrameIds — the store's
  /// canonical resolution makes the pictures one). One undo step.
  void linkDuplicateLayer({required CutId cutId, required LayerId layerId}) {
    final project = repository.requireProject();
    final cut = requireCut(project, cutId);
    _requireLayer(cutId: cutId, layerId: layerId);
    final plan = planLinkDuplicateLayerCommandInput(
      project: project,
      cut: cut,
      sourceLayerId: layerId,
    );

    historyManager.execute(
      LinkDuplicateLayerCommand(
        repository: repository,
        cutId: cutId,
        sourceLayerId: layerId,
        layerIdMap: plan.layerIdMap,
        newGroupIdBySource: plan.newGroupIdBySource,
      ),
    );
  }

  void deleteLayer({required CutId cutId, required LayerId layerId}) {
    final cut = _requireCut(cutId);
    final layer = _requireLayer(cutId: cutId, layerId: layerId);
    // Deleting a FOLDER row means dissolving it: the members are rows in
    // their own right and stay where they are. (Deleting the pictures too
    // would make one Delete key destroy work the row itself never held.)
    if (layerKindGroupsLayers(layer.kind)) {
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
    if (isAttachedLayer(layer)) {
      final organizer = cut.layers.folderById(layer.folderId);
      if (organizer != null &&
          attachOrganizerBaseOf(organizer, cut.layers) != null &&
          cut.layers.directMembersOf(organizer.id).length == 1 &&
          repository
                  .requireProject()
                  .linkRegistry
                  .groupOf(cutId: cutId, layerId: organizer.id) ==
              null) {
        historyManager.execute(
          CompositeCommand(
            description: 'Delete layer ${layer.name} and its empty folder',
            commands: [
              DeleteLayerCommand(
                repository: repository,
                cutId: cutId,
                layerId: layerId,
              ),
              DeleteLayerCommand(
                repository: repository,
                cutId: cutId,
                layerId: organizer.id,
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
    if (layerKindIsFixed(sourceLayer.kind)) {
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
    if (layerKindIsFixed(payload.kind)) {
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
  /// already its cels — and unregisters the asset when this was its last
  /// referrer. One undo step; no-op on non-reference layers.
  void rasterizeLayerReference({
    required CutId cutId,
    required LayerId layerId,
    bool assetStillReferenced = false,
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
        assetStillReferenced: assetStillReferenced,
      ),
    );
  }

  /// Project-level sheet-header text; one undo step, no-op when unchanged.
  void setTimesheetInfo(TimesheetInfo info) {
    if (repository.requireProject().timesheetInfo == info) {
      return;
    }
    historyManager.execute(
      UpdateTimesheetInfoCommand(repository: repository, info: info),
    );
  }

  /// One undo step; no-op when unchanged (R10-⑥).
  void setProjectBackground(ProjectBackground background) {
    if (repository.requireProject().background == background) {
      return;
    }
    historyManager.execute(
      UpdateProjectBackgroundCommand(
        repository: repository,
        background: background,
      ),
    );
  }

  /// One undo step; no-op when unchanged. The backdrop is opaque by
  /// contract (R3b) — the alpha byte is forced here, so no caller can
  /// thin the stage's final answer.
  void setProjectBackdrop(int argb) {
    final opaque = 0xFF000000 | argb;
    if (repository.requireProject().backdropArgb == opaque) {
      return;
    }
    historyManager.execute(
      UpdateProjectStageColorsCommand(
        repository: repository,
        backdropArgb: opaque,
      ),
    );
  }

  /// One undo step; no-op when unchanged. RGBA — a thinned pasteboard
  /// reveals the backdrop (R3b; project data since the promotion, R28 #9
  /// reversed).
  void setProjectPasteboard(int argb) {
    if (repository.requireProject().pasteboardArgb == argb) {
      return;
    }
    historyManager.execute(
      UpdateProjectStageColorsCommand(
        repository: repository,
        pasteboardArgb: argb,
      ),
    );
  }

  void setLayerTimesheet({
    required CutId cutId,
    required LayerId layerId,
    required bool onTimesheet,
  }) {
    // Every kind carries the toggle now (unified layer controls): the
    // camera layer gates the sheet's printed CAM keyframe column. Anywhere
    // lookup — track-owned SE rows are not in the cut's layer list.
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    if (layer.onTimesheet == onTimesheet) {
      return;
    }

    historyManager.execute(
      UpdateLayerTimesheetCommand(
        repository: repository,
        cutId: cutId,
        layerId: layerId,
        onTimesheet: onTimesheet,
      ),
    );
  }

  void setLayerFillReference({
    required CutId cutId,
    required LayerId layerId,
    required bool isFillReference,
  }) {
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    if (layer.isFillReference == isFillReference) {
      return;
    }

    historyManager.execute(
      UpdateLayerFillReferenceCommand(
        repository: repository,
        cutId: cutId,
        layerId: layerId,
        isFillReference: isFillReference,
      ),
    );
  }

  void setLayerMark({
    required CutId cutId,
    required LayerId layerId,
    required LayerMark mark,
  }) {
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    if (layer.mark == mark) {
      return;
    }

    historyManager.execute(
      UpdateLayerMarkCommand(
        repository: repository,
        cutId: cutId,
        layerId: layerId,
        mark: mark,
      ),
    );
  }

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
    required CutId cutId,
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

  /// Replaces a layer's transform track; one undo step, no-op when
  /// unchanged. Camera layers keep their own track on the cut (the camera
  /// panel/lanes edit that one).
  void updateLayerTransformTrack({
    required CutId cutId,
    required LayerId layerId,
    required TransformTrack transformTrack,
    String description = 'Edit layer transform',
  }) {
    final layer = _requireLayer(cutId: cutId, layerId: layerId);
    if (!layerKindHasLayerTransform(layer.kind)) {
      throw StateError(
        'The camera layer transforms through the cut camera track.',
      );
    }
    if (layer.transformTrack == transformTrack) {
      return;
    }

    historyManager.execute(
      UpdateLayerTransformCommand(
        repository: repository,
        cutId: cutId,
        layerId: layerId,
        transformTrack: transformTrack,
        description: description,
      ),
    );
  }

  /// Replaces a layer's EFFECT CHAIN (R6); one undo step, no-op when
  /// unchanged.
  ///
  /// FX lanes are per-use ("레인만 각자"), so a DRAWING row's chain stays
  /// local — the same rule its transform track follows. An ADJUSTMENT row
  /// is the exception ([layerKindMirrorsEffects]): its chain is its whole
  /// content, so it MIRRORS across the 겸용 link group as one composite
  /// step — one undo puts every member back.
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
    if (!layerKindHasLayerEffects(layer.kind)) {
      throw StateError('The camera row carries no effect chain of its own.');
    }
    final targets = layerKindMirrorsEffects(layer.kind)
        ? linkMirrorTargets(
            repository.requireProject(),
            cutId: cutId,
            layerId: layerId,
          )
        : [(cutId: cutId, layerId: layerId)];
    return <Command>[
      for (final target in targets)
        if (!listEquals(
          _requireLayer(cutId: target.cutId, layerId: target.layerId).effects,
          effects,
        ))
          UpdateLayerEffectsCommand(
            repository: repository,
            cutId: target.cutId,
            layerId: target.layerId,
            effects: effects,
            description: description,
          ),
    ];
  }

  /// Replaces the project's instruction vocabulary; one undo step, no-op
  /// when unchanged.
  void updateCameraInstructionSet(CameraInstructionSet instructionSet) {
    if (repository.requireProject().cameraInstructions == instructionSet) {
      return;
    }
    historyManager.execute(
      UpdateCameraInstructionSetCommand(
        repository: repository,
        instructionSet: instructionSet,
      ),
    );
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
  void relinkMediaAsset({required String oldPath, required String newPath}) {
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
      ),
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
    if (layerKindIsFixed(layer.kind) || layerKindIsFixed(kind)) {
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
    final layer = _requireLayer(cutId: cutId, layerId: layerId);
    final entry = layer.timeline[blockStartIndex];
    if (entry == null || !entry.isDrawing) {
      throw StateError(
        'No exposure block starts at $blockStartIndex on $layerId.',
      );
    }
    if (entry.ghost) {
      throw StateError(
        'A ghost exposure is rederived, so it cannot hold a memo '
        '($layerId at $blockStartIndex).',
      );
    }

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

  /// Moves ONE cut to [newIndex] — the left/right nudge buttons' form of
  /// the order edit, stated as the resulting order so both forms share a
  /// command.
  void reorderCut({
    required TrackId trackId,
    required CutId cutId,
    required int newIndex,
  }) {
    final cuts = [for (final cut in _requireTrack(trackId).cuts) cut.id];
    final oldIndex = cuts.indexOf(cutId);
    if (oldIndex == -1) {
      throw StateError('Cut not found in track $trackId: $cutId');
    }
    cuts.insert(newIndex, cuts.removeAt(oldIndex));
    setCutOrder(trackId: trackId, order: cuts);
  }

  /// Resequences a whole track — what a cut drag that reached into a
  /// neighbour commits (a run may carry several cuts across at once).
  void setCutOrder({required TrackId trackId, required List<CutId> order}) {
    historyManager.execute(
      SetCutOrderCommand(
        repository: repository,
        trackId: trackId,
        order: order,
      ),
    );
  }

  /// R28 #14: deleting the LAST cut leaves the track empty rather than
  /// conjuring a replacement.
  ///
  /// "컷도 1개도 없는 상황 허용" — the empty track is the same state the
  /// editor already shows over a storyboard GAP (no active cut): the
  /// canvas paints its blank paper and every `requireActiveCut` consumer
  /// is behind a guard. Auto-replacing meant a delete could not actually
  /// clear the track, and the replacement was indistinguishable from a
  /// real cut in the undo stack.
  void deleteCut({required CutId cutId}) {
    historyManager.execute(
      DeleteCutCommand(
        repository: repository,
        editingSession: editingSession,
        cutId: cutId,
        brushFrameStore: brushFrameStore,
      ),
    );
  }

  /// Deletes a batch of cuts as ONE undo step; emptying the track is
  /// allowed (R28 #14).
  void deleteCuts({required List<CutId> cutIds}) {
    if (cutIds.isEmpty) {
      return;
    }
    if (cutIds.length == 1) {
      deleteCut(cutId: cutIds.single);
      return;
    }

    historyManager.execute(
      CompositeCommand(
        description: 'Delete cuts',
        commands: [
          for (final cutId in cutIds)
            DeleteCutCommand(
              repository: repository,
              editingSession: editingSession,
              cutId: cutId,
              brushFrameStore: brushFrameStore,
            ),
        ],
      ),
    );
  }

  void duplicateCut({
    required CutId sourceCutId,
    required TrackId targetTrackId,
    String? newName,
  }) {
    final project = repository.requireProject();
    final sourceCut = _requireCut(sourceCutId);
    final plan = planDuplicateCutCommandInput(
      project: project,
      sourceCut: sourceCut,
    );

    historyManager.execute(
      DuplicateCutCommand(
        repository: repository,
        editingSession: editingSession,
        sourceCutId: sourceCutId,
        targetTrackId: targetTrackId,
        newCutId: plan.newCutId,
        newName: newName ?? '${sourceCut.name} Copy',
        layerIdMap: plan.layerIdMap,
        frameIdMap: plan.frameIdMap,
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

  Track _requireTrack(TrackId trackId) {
    for (final track in repository.requireProject().tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    throw StateError('Track not found: $trackId');
  }
}

