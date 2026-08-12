import '../../controllers/default_cut_helpers.dart';
import '../../controllers/editing_session_state.dart';
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
        mirroredOrderAfterMove;
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

  // `updateTrackTransform` retired with the V row's transform. The fade it
  // wrote is F.I/F.O spans on the transition row now
  // ([EditorSessionManager.updateTransitionInstructions]). The named-key
  // self-propagation this round gave it retired with it: a V row no longer
  // has transform lanes for a name to link.

  /// Replaces the V track's EFFECT CHAIN; one undo step, no-op when
  /// unchanged.
  ///
  /// No 겸용 mirror and no value merge, unlike [updateLayerEffects]: a track
  /// is held once (there is no second use of it to keep in step), so the
  /// chain — shape and numbers together — is simply the track's.
  void updateTrackEffects({
    required TrackId trackId,
    required List<LayerEffect> effects,
    String description = 'Edit track effects',
  }) {
    for (final track in repository.requireProject().tracks) {
      if (track.id != trackId) {
        continue;
      }
      if (listEquals(track.effects, effects)) {
        return;
      }
      break;
    }
    historyManager.execute(
      UpdateTrackEffectsCommand(
        repository: repository,
        trackId: trackId,
        effects: effects,
        description: description,
      ),
    );
  }

  /// The V track's static opacity and fx master (R9 #21) in one undo step;
  /// no-op when nothing changes.
  void updateTrackDisplay({
    required TrackId trackId,
    double? opacity,
    bool? fxEnabled,
    String description = 'Edit track display',
  }) {
    for (final track in repository.requireProject().tracks) {
      if (track.id == trackId) {
        final sameOpacity = opacity == null || track.opacity == opacity;
        final sameFx = fxEnabled == null || track.fxEnabled == fxEnabled;
        if (sameOpacity && sameFx) {
          return;
        }
        break;
      }
    }

    historyManager.execute(
      UpdateTrackDisplayCommand(
        repository: repository,
        trackId: trackId,
        opacity: opacity,
        fxEnabled: fxEnabled,
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
              project.linkRegistry.groupOf(cutId: cutId, layerId: member.id) !=
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
    if (isAttachedLayer(layer)) {
      final organizer = cut.layers.folderById(layer.folderId);
      if (organizer != null &&
          attachOrganizerBaseOf(organizer, cut.layers) != null &&
          cut.layers.directMembersOf(organizer.id).length == 1 &&
          repository.requireProject().linkRegistry.groupOf(
                cutId: cutId,
                layerId: organizer.id,
              ) ==
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

  /// How far past the canvas the pasteboard SHOWS, in canvas widths and
  /// heights. One undo step; no-op when unchanged.
  void setProjectPasteboardMargin(double margin) {
    if (repository.requireProject().pasteboardMargin == margin) {
      return;
    }
    historyManager.execute(
      UpdateProjectStageColorsCommand(
        repository: repository,
        pasteboardMargin: margin,
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
    // Anywhere lookup, like the name tag above — SE rows are TRACK
    // fixtures and the cut-scoped read throws for them, which is what
    // stood between R5 #8's converted lane edits and the project.
    final layer = requireLayerAnywhere(repository.requireProject(), layerId);
    if (!layerKindHasLayerTransform(layer.kind)) {
      throw StateError(
        'The camera layer transforms through the cut camera track.',
      );
    }
    if (layer.transformTrack == transformTrack) {
      return;
    }

    // "Same name, same value": a named key MOVED by this write drags every
    // other key of that name along — here and in the 겸용 siblings, whose
    // transform lanes are otherwise entirely their own ("레인만 각자").
    // This is the ONLY way a transform number crosses cuts.
    final changes = transformNamedKeyChanges(
      layer.transformTrack,
      transformTrack,
    );
    final commands = <Command>[
      UpdateLayerTransformCommand(
        repository: repository,
        cutId: cutId,
        layerId: layerId,
        transformTrack: transformTrackWithNamedValues(transformTrack, changes),
        description: description,
      ),
    ];
    if (!changes.isEmpty) {
      final project = repository.requireProject();
      for (final target in linkMirrorTargets(
        project,
        cutId: cutId,
        layerId: layerId,
      )) {
        if (target.cutId == cutId && target.layerId == layerId) {
          continue;
        }
        final sibling = requireLayerAnywhere(project, target.layerId);
        final next = transformTrackWithNamedValues(
          sibling.transformTrack,
          changes,
        );
        if (next == sibling.transformTrack) {
          continue;
        }
        commands.add(
          UpdateLayerTransformCommand(
            repository: repository,
            cutId: target.cutId,
            layerId: target.layerId,
            transformTrack: next,
            description: description,
          ),
        );
      }
    }

    historyManager.execute(
      commands.length == 1
          ? commands.single
          : CompositeCommand(description: description, commands: commands),
    );
  }

  /// The transform track that ALREADY holds [name] in [property]'s lane,
  /// anywhere in this row's naming space — the row itself AND its 겸용
  /// siblings. Null when the name is free, which is what tells a rename it
  /// can simply apply.
  ///
  /// The space is keyed by the LINK GROUP because a transform has no
  /// equivalent of the effect id that carries an FX naming space across
  /// cuts: sibling rows are different [LayerId]s holding the same part, and
  /// [linkMirrorTargets] is exactly that group. Returning the TRACK rather
  /// than a bool lets the joining key adopt from it — the two questions a
  /// rename asks have one answer.
  TransformTrack? transformTrackHoldingName({
    required CutId cutId,
    required LayerId layerId,
    required TransformPropertyId property,
    required String name,
    Set<int> excludeFramesOnSource = const {},
  }) {
    final project = repository.requireProject();
    for (final target in linkMirrorTargets(
      project,
      cutId: cutId,
      layerId: layerId,
    )) {
      final isSource = target.cutId == cutId && target.layerId == layerId;
      final track = requireLayerAnywhere(project, target.layerId).transformTrack;
      if (transformLaneUsesName(
        track,
        property,
        name,
        // Only the SOURCE row holds the keys a range rename is naming; a
        // sibling's keys are all "somewhere else" by construction.
        excludeFrames: isSource ? excludeFramesOnSource : const {},
      )) {
        return track;
      }
    }
    return null;
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
  /// An ADJUSTMENT row goes further ([layerKindMirrorsEffects]): its chain
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

  /// 어태치 장착·분리 as one undo step across the whole 겸용 link group.
  ///
  /// The RELATION and its MODE are structure, so they are one answer for the
  /// group. Everything derived from a timeline is not: the SYNCED links and
  /// the detach BAKE are computed per cut against THAT cut's base, because
  /// 겸용 cuts share the cel bank and re-expose it each their own way — one
  /// cut's baked timing dressed onto another is somebody else's rhythm.
  ///
  /// The MODE is decided by scanning every use at once (user 2026-08-07):
  ///
  /// > SYNCED only when the row's exposure shape matches the base's in EVERY
  /// > use; one cut disagreeing makes the whole mount FREE.
  ///
  /// That single line is what makes "an empty row mounts FREE" a consequence
  /// rather than a special case, and it errs only toward keeping work: a cut
  /// where the row has real timing of its own never has it replaced.
  List<Command> layerAttachmentCommands({
    required CutId cutId,
    required LayerAttachDrop attach,
    String description = 'Attach layer',
  }) {
    if (attach.isEmpty) {
      return const [];
    }
    final project = repository.requireProject();
    final commands = <Command>[];

    for (final layerId in attach.detachIds) {
      for (final use in _linkedRowUses(project, cutId: cutId, rowId: layerId)) {
        final cut = requireCut(project, use.cutId);
        final row = requireLayer(
          project,
          cutId: use.cutId,
          layerId: use.rowId,
        );
        if (row.attachedToLayerId == null) {
          continue;
        }
        commands.add(
          SetLayerAttachmentCommand(
            repository: repository,
            layerId: use.rowId,
            attachment: LayerAttachment.of(
              detachedLayer(
                attached: row,
                // The counterpart's OWN base in its OWN cut — the pointer
                // is per-cut even though the relation is shared.
                base: attachedBaseOf(row, cut.layers),
                cutFrameCount: cut.duration,
              ),
            ),
            description: description,
          ),
        );
      }
    }

    final sideChange = attach.sideChange;
    if (sideChange != null) {
      // Same base, other side. Everything derived from the timing stays as
      // it is — this is a direction, not a re-mount.
      for (final use in _linkedRowUses(
        project,
        cutId: cutId,
        rowId: sideChange.layerId,
      )) {
        final row = requireLayer(
          project,
          cutId: use.cutId,
          layerId: use.rowId,
        );
        if (row.attachedToLayerId == null ||
            row.attachedPlacement == sideChange.placement) {
          continue;
        }
        commands.add(
          SetLayerAttachmentCommand(
            repository: repository,
            layerId: use.rowId,
            attachment: LayerAttachment(
              attachedToLayerId: row.attachedToLayerId,
              placement: sideChange.placement,
              mode: row.attachedMode,
              timeline: row.timeline,
              baseFrameLinks: row.baseFrameLinks,
              runBehaviors: row.runBehaviors,
            ),
            description: description,
          ),
        );
      }
    }

    // ⑦: a folder drop mounts every row it carries, so this is a loop now.
    // Each rider still decides its own MODE — the 겸용 scan is per relation,
    // and two members of one folder can legitimately differ.
    for (final mount in attach.mounts) {
      final uses = _mountUses(
        project,
        cutId: cutId,
        rowId: mount.layerId,
        baseId: mount.baseId,
      );
      final mode = _mountMode(uses);
      for (final use in uses) {
        commands.add(
          SetLayerAttachmentCommand(
            repository: repository,
            layerId: use.rowId,
            attachment: attachmentForMount(
              standaloneRow: use.standalone,
              base: use.base,
              placement: mount.placement,
              mode: mode,
            ),
            description: description,
          ),
        );
      }
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
      _mountUses(
        repository.requireProject(),
        cutId: cutId,
        rowId: layerId,
        baseId: baseId,
      ),
    );
  }

  /// Every use of the relation being made: the cut asked plus each 겸용
  /// sibling where BOTH rows have counterparts, with the row in its
  /// STANDALONE form (what a mount measures — see [attachmentForMount]).
  List<({LayerId rowId, Layer standalone, Layer base})> _mountUses(
    Project project, {
    required CutId cutId,
    required LayerId rowId,
    required LayerId baseId,
  }) {
    final uses = <({LayerId rowId, Layer standalone, Layer base})>[];
    for (final use in _linkedRowUses(project, cutId: cutId, rowId: rowId)) {
      final useBaseId = use.cutId == cutId
          ? baseId
          : linkCounterpartIn(
              project,
              cutId: cutId,
              layerId: baseId,
              targetCutId: use.cutId,
            );
      if (useBaseId == null) {
        // The base does not reach that cut, so the relation cannot exist
        // there at all — not a use, and not a vote on the mode either.
        continue;
      }
      final cut = requireCut(project, use.cutId);
      final base = cut.layers.byId(useBaseId);
      final row = cut.layers.byId(use.rowId);
      if (base == null || row == null) {
        continue;
      }
      uses.add((
        rowId: use.rowId,
        standalone: detachedLayer(
          attached: row,
          base: attachedBaseOf(row, cut.layers),
          cutFrameCount: cut.duration,
        ),
        base: base,
      ));
    }
    return uses;
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

  /// Commits an attach change on its own — the Layer menu's 장착·해제, where
  /// no row moves. Empty input is a no-op rather than an empty undo entry.
  void setLayerAttachment({
    required CutId cutId,
    required LayerAttachDrop attach,
    String description = 'Attach layer',
  }) {
    final commands = layerAttachmentCommands(
      cutId: cutId,
      attach: attach,
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

  /// Every (cut, row) the same shared row reaches: this cut, plus the 겸용
  /// siblings holding a counterpart.
  List<({CutId cutId, LayerId rowId})> _linkedRowUses(
    Project project, {
    required CutId cutId,
    required LayerId rowId,
  }) {
    final uses = <({CutId cutId, LayerId rowId})>[
      (cutId: cutId, rowId: rowId),
    ];
    for (final siblingId in linkedCutSiblings(project, cutId: cutId)) {
      final counterpart = linkCounterpartIn(
        project,
        cutId: cutId,
        layerId: rowId,
        targetCutId: siblingId,
      );
      if (counterpart != null) {
        uses.add((cutId: siblingId, rowId: counterpart));
      }
    }
    return uses;
  }

  /// Resequences a track's SE rows. They live on the TRACK, so no cut and
  /// no mirror is involved — the order is the whole placement.
  void setTrackSeOrder({
    required TrackId trackId,
    required List<LayerId> order,
  }) {
    historyManager.execute(
      SetTrackSeOrderCommand(
        repository: repository,
        trackId: trackId,
        order: order,
      ),
    );
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
  double? namedEffectKeyValueInSpace({
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
      final value = namedEffectKeyValue(
        _requireLayer(cutId: target.cutId, layerId: target.layerId).effects,
        effectId: effectId,
        parameterId: parameterId,
        name: name,
        // Only the SOURCE row holds the keys a range rename is naming; a
        // sibling's keys are all "somewhere else" by construction.
        excludeFrames: isSource ? excludeFramesOnSource : const {},
      );
      if (value != null) {
        return value;
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
    if (!layerKindHasLayerEffects(layer.kind)) {
      throw StateError('The camera row carries no effect chain of its own.');
    }
    final mirrorsValuesToo = layerKindMirrorsEffects(layer.kind);
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
  void relinkMediaAsset({
    required String oldPath,
    required String newPath,
    bool recordSource = false,
    String? sourceStamp,
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
        recordSource: recordSource,
        sourceStamp: sourceStamp,
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
