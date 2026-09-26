import '../models/attached_layer_mount.dart' show LayerAttachment;
import '../models/attached_layer_resolve.dart'
    show cutWithReconciledAttachedMirrors;
import '../models/audio_clip.dart';
import '../models/se_name_tag.dart';
import '../models/camera_instruction.dart';
import '../models/canvas_size.dart';
import '../models/covering_image_normalize.dart';
import '../models/covering_storyboard_normalize.dart';
import '../models/cut.dart';
import '../models/cut_camera.dart';
import '../models/cut_content_translation.dart' show translateCutContentModel;
import '../models/drawing_guide.dart';
import '../models/cut_id.dart';
import '../models/direction_spans_normalize.dart';
import '../models/cut_metadata.dart';
import '../models/media_viewer_bookmark.dart';
import '../models/export_overrides.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
import '../models/layer_effect.dart';
import '../models/layer_id.dart';
import '../models/layer_kind.dart';
import '../models/layer_mark.dart';
import '../models/media_asset.dart';
import '../models/exposure_memo.dart';
import '../models/timeline_repeat.dart';
import '../models/timesheet_info.dart';
import '../models/project.dart';
import '../models/reordered_by_ids.dart';
import '../models/project_background.dart';
import '../models/project_frame_rate.dart';
import '../models/stroke.dart';
import '../models/transform_track.dart';
import '../models/track.dart';
import '../models/track_id.dart';
import 'project_lookup.dart' show requireMemoBlockAt;
import 'project_tree_editor.dart';
import '../core/inserted_at.dart';
import '../core/mapped_or_same.dart';
import '../models/layer_link_registry.dart';

/// One entity kind as the repository's find-and-change law sees it: the
/// word its not-found message uses, and the `project_tree_editor` walk
/// that finds it (null when it is not there — see the ⚠️ note below).
typedef _FoundEdit<I, E> = ({
  String kind,
  Project? Function(Project project, I id, E Function(E) update) edit,
});

/// [cut] with [layer] inserted at [index] (appended when null) — the cut a
/// row joins, and the one a conte picture draws through while the row its
/// first stroke makes is not there yet.
Cut cutWithLayerInserted(Cut cut, Layer layer, int? index) => cut.copyWith(
  layers: insertedAt(
    cut.layers,
    // The cut is only known here, and its length is what the ghosts fill
    // to. See [ProjectRepository]'s `_withDerivedRunEdges`.
    rederiveRunBehaviors(layer, cutFrameCount: cut.duration),
    index,
  ),
);

class ProjectRepository {
  ProjectRepository({Project? initialProject})
    : _currentProject = initialProject == null
          ? null
          : _reconcileAttachedMirrors(initialProject);

  Project? _currentProject;

  Project? get currentProject => _currentProject;

  bool get hasProject => _currentProject != null;

  Project requireProject() {
    final project = _currentProject;
    if (project == null) {
      throw StateError('No project is loaded.');
    }
    return project;
  }

  void replaceProject(Project project) {
    _currentProject = _reconcileAttachedMirrors(project);
  }

  void clearProject() {
    _currentProject = null;
  }

  void updateProject(Project Function(Project project) update) {
    _currentProject = _reconcileAttachedMirrors(update(requireProject()));
  }

  /// Puts the link registry back to [registry] — what every link-touching
  /// command's undo owes.
  ///
  /// ⛔SIX UNDOS WROTE THIS OUT (create/dissolve folder, delete layer,
  /// delete cut, unlink, convert-to-linked). The registry is the ONE place
  /// that says which rows are the same layer seen from different cuts, so
  /// an undo that restores the rows and forgets the registry leaves the
  /// project holding links to layers that no longer exist — a state the
  /// mirror walks then read as real.
  void restoreLinkRegistry(LayerLinkRegistry registry) {
    updateProject((current) => current.copyWith(linkRegistry: registry));
  }

  // ⛔THE TWO BELOW ARE ONE LAW WRITTEN ONCE: find the entity, change it,
  // and say so when it was not there. Thirty-five mutations in this class
  // wrote that out by hand, which is why the same not-found message
  // existed in eleven spellings and one of them said `${track.id}` where
  // its neighbours said `$trackId`.
  //
  // ⚠️`project_tree_editor` returns null ON PURPOSE so the caller names the
  // error (its own doc says so, and a caller that throws before assigning
  // leaves the source untouched). These helpers ARE that name for the
  // ordinary case — they do not replace the editor. A mutation that needs
  // a different message, or that must report WHAT it removed, still calls
  // the editor itself: [removeTrack], [removeCut], [reorderCut] and
  // [deleteLayer] each do, and each says why where it does it.

  /// What one entity kind is called in that message, and the editor that
  /// finds it — the only two things the four kinds differed in.
  static const _track = (kind: 'Track', edit: updateTrackById);
  static const _cut = (kind: 'Cut', edit: updateCutAnywhere);
  static const _layer = (kind: 'Layer', edit: updateLayerAnywhere);
  static const _frame = (kind: 'Frame', edit: updateFrameAnywhere);

  void _mutate<I, E>(_FoundEdit<I, E> entity, I id, E Function(E) update) {
    updateProject((project) {
      final next = entity.edit(project, id, update);
      if (next == null) {
        throw StateError('${entity.kind} not found: $id');
      }
      return next;
    });
  }

  /// The layer lookup that is SCOPED to one cut — a different question from
  /// [_layer]'s global one, and it says so in its own message.
  void _mutateLayerInCut(
    CutId cutId,
    LayerId layerId,
    Layer Function(Layer layer) update,
  ) {
    _mutate(_cut, cutId, (cut) {
      final next = updateLayerInCut(cut, layerId, update);
      if (next == null) {
        throw StateError('Layer not found in cut $cutId: $layerId');
      }
      return next;
    });
  }

  /// Export scope/delta state (출력 UI): PROJECT data — it travels with
  /// the film — but not a document edit, so writes land directly with no
  /// history entry (the visibility-toggle precedent).
  void updateExportOverrides(
    ExportProjectOverrides Function(ExportProjectOverrides overrides) update,
  ) {
    updateProject(
      (project) =>
          project.copyWith(exportOverrides: update(project.exportOverrides)),
    );
  }

  /// What each viewer is looking at (유저 확정 ⑤㉑): PROJECT data — a
  /// reference belongs to the work it is beside — but not a document
  /// edit, so it lands directly with no history entry, exactly like
  /// [updateExportOverrides]. Paging a reference must never be undoable.
  void updateMediaViewerBookmarks(
    MediaViewerBookmarks Function(MediaViewerBookmarks bookmarks) update,
  ) {
    updateProject(
      (project) => project.copyWith(
        mediaViewerBookmarks: update(project.mediaViewerBookmarks),
      ),
    );
  }

  /// The write-time invariants, applied to every cut on every write:
  /// 1. COVERING IMAGE rows ([cutWithCoveringImageRows]): an image
  ///    layer's stored timeline is ONE real 1-frame block at index 0 plus
  ///    a fixed end-side HOLD whose ghosts fill to the cut boundary
  ///    (D22) — runs FIRST so the mirror pass below sees the final base
  ///    timeline (an image row can be an attach base).
  /// 2. The COVERING STORYBOARD row ([cutWithCoveringStoryboardRow]): its
  ///    stored panels tile the cut exactly. Same grammar as 1, arriving
  ///    late because the row's DERIVED reader was mistaken for a guarantee
  ///    — it only hid the stored holes from the surface that makes them.
  /// 3. The ALWAYS-MIRROR invariant (UI-R23 #7 v2,
  ///    [cutWithReconciledAttachedMirrors]): every synced attach row a
  ///    complete mirror of its base — one own cel + link per base cel —
  ///    no matter how the base gained the cel (create, move, paste,
  ///    undo/redo replay, file load).
  /// 4. SPANS ON THEIR BLOCKS (R27, [cutWithSpansOnTheirBlocks]): a block
  ///    carries an instruction exactly when its row's spans ride its blocks
  ///    — a direction row's bare block takes the ＋'s span, any other row's
  ///    block puts one down.
  /// Identity-preserving on no-ops, so an already-normal project passes
  /// through untouched.
  static Project _reconcileAttachedMirrors(Project project) {
    final firstInstruction = project.cameraInstructions.defs.isEmpty
        ? null
        : project.cameraInstructions.defs.first.id;
    final tracks = mappedOrSame(project.tracks, (track) {
      final cuts = mappedOrSame(
        track.cuts,
        (cut) => _normalizedCut(cut, firstInstruction: firstInstruction),
      );
      return identical(cuts, track.cuts) ? track : track.copyWith(cuts: cuts);
    });
    return identical(tracks, project.tracks)
        ? project
        : project.copyWith(tracks: tracks);
  }

  /// The four invariants above, in their stated order, over one cut.
  static Cut _normalizedCut(Cut cut, {required String? firstInstruction}) =>
      cutWithSpansOnTheirBlocks(
        cutWithReconciledAttachedMirrors(
          cutWithCoveringStoryboardRow(cutWithCoveringImageRows(cut)),
        ),
        defaultInstructionId: firstInstruction,
      );

  void updateTimesheetInfo(TimesheetInfo info) {
    updateProject((project) => project.copyWith(timesheetInfo: info));
  }

  void updateProjectBackground(ProjectBackground background) {
    updateProject((project) => project.copyWith(background: background));
  }

  /// R3b: the stage's outer planes — the backdrop and the pasteboard, each an
  /// RGBA colour and (F-114) whether it is there at all. Null leaves that
  /// field untouched (one write serves all four, so one undo can restore
  /// them).
  void updateProjectStageColors({
    int? backdropArgb,
    bool? backdropNone,
    int? pasteboardArgb,
    bool? pasteboardNone,
  }) {
    updateProject(
      (project) => project.copyWith(
        backdropArgb: backdropArgb,
        backdropNone: backdropNone,
        pasteboardArgb: pasteboardArgb,
        pasteboardNone: pasteboardNone,
      ),
    );
  }

  /// The movie's trailing gap (UI-R20 #3).
  /// R26 #32: the project's frame rate — one axis for the whole project.
  void updateProjectFrameRate(ProjectFrameRate frameRate) {
    updateProject((project) => project.copyWith(frameRate: frameRate));
  }

  /// EXPORT-AUDIO ③: the project's audio rate — what every conform lands
  /// at and the mixer runs at.
  void updateProjectAudioSampleRate(int audioSampleRate) {
    updateProject(
      (project) => project.copyWith(audioSampleRate: audioSampleRate),
    );
  }

  /// The project's CAMERA frame (shooting frame) — the lens every cut is
  /// framed through; `CameraPose.zoom` is stated against its width.
  void updateProjectCameraSize(CanvasSize cameraSize) {
    updateProject((project) => project.copyWith(cameraSize: cameraSize));
  }

  /// EXPORT-AUDIO ④: the project's audio speed (the NTSC pull).
  void updateProjectAudioSpeed(int numerator, int denominator) {
    updateProject(
      (project) => project.copyWith(
        audioSpeedNumerator: numerator,
        audioSpeedDenominator: denominator,
      ),
    );
  }

  void updateTrailingFrames(int trailingFrames) {
    updateProject(
      (project) => project.copyWith(trailingFrames: trailingFrames),
    );
  }

  void addTrack(Track track) {
    updateProject((project) {
      return project.copyWith(tracks: [...project.tracks, track]);
    });
  }

  /// Moves the track at [fromIndex] so it sits at [toIndex] in the
  /// project's list (R5 #9 — the storyboard's V-row drag).
  ///
  /// The list order IS the composite order: `CanvasTrackStackView` paints
  /// the first covered track as the stage and the rest over it, so moving a
  /// track up the storyboard moves its picture up the stack. That is the
  /// user's decision (2026-08-09) and the reason this is a plain reorder
  /// rather than a display-only field.
  void reorderTrack({required int fromIndex, required int toIndex}) {
    updateProject((project) {
      final tracks = [...project.tracks];
      if (fromIndex < 0 ||
          fromIndex >= tracks.length ||
          toIndex < 0 ||
          toIndex >= tracks.length ||
          fromIndex == toIndex) {
        return project;
      }
      tracks.insert(toIndex, tracks.removeAt(fromIndex));
      return project.copyWith(tracks: tracks);
    });
  }

  void replaceTrack(Track track) {
    _mutate(_track, track.id, (_) => track);
  }

  /// ⚠️Not [_mutate] with [_track]: this REMOVES, so there is no track to
  /// hand an update, and the miss shows up as a length that did not change.
  void removeTrack(TrackId trackId) {
    updateProject((project) {
      final tracks = project.tracks
          .where((track) => track.id != trackId)
          .toList(growable: false);

      if (tracks.length == project.tracks.length) {
        throw StateError('Track not found: $trackId');
      }

      return project.copyWith(tracks: tracks);
    });
  }

  void addCut({required TrackId trackId, required Cut cut}) {
    insertCut(trackId: trackId, cut: cut);
  }

  void insertCut({required TrackId trackId, required Cut cut, int? index}) {
    // A cut built elsewhere — an importer's plan, a duplicate — arrives
    // with run-edge SPECS and no ghosts. See [_withDerivedRunEdges].
    final derived = _withDerivedRunEdges(cut);
    _mutate(_track, trackId, (track) {
      // ⛔NOT [insertedAt]. That law CLAMPS, which is right for a row
      // landing in a layer list; a cut index past the end is a caller
      // that computed a position from a stale track, and the throw is
      // pinned by "throws when inserting a cut at an out-of-range index".
      final cuts = [...track.cuts];
      if (index == null) {
        cuts.add(derived);
      } else {
        cuts.insert(index, derived);
      }
      return track.copyWith(cuts: cuts);
    });
  }

  void reorderCut({
    required TrackId trackId,
    required CutId cutId,
    required int newIndex,
  }) {
    final track = requireProject().tracks
        .where((track) => track.id == trackId)
        .firstOrNull;
    if (track == null) {
      throw StateError('Track not found: $trackId');
    }
    final cuts = [...track.cuts];
    final oldIndex = cuts.indexWhere((cut) => cut.id == cutId);
    if (oldIndex == -1) {
      throw StateError('Cut not found in track $trackId: $cutId');
    }
    final moved = cuts.removeAt(oldIndex);
    cuts.insert(newIndex, moved);
    setCutOrder(trackId: trackId, order: [for (final cut in cuts) cut.id]);
  }

  /// Resequences [trackId]'s cuts to exactly [order] — the ONE cut-order
  /// mutation ([reorderCut] states the same move as an index). [order] must
  /// be a permutation of the track's cut ids; a partial or foreign list is
  /// a programming error, not a silent drop.
  void setCutOrder({required TrackId trackId, required List<CutId> order}) {
    _mutate(_track, trackId, (track) {
      return track.copyWith(
        cuts: reorderedByIds(
          track.cuts,
          order,
          idOf: (cut) => cut.id,
          orderName: 'Cut order for track $trackId',
        ),
      );
    });
  }

  /// ⚠️Not [_mutate] with [_cut]: this REMOVES, so there is nothing to hand
  /// an update — and the caller needs the cut BACK, to undo with.
  Cut removeCut({required CutId cutId}) {
    Cut? removedCut;
    updateProject((project) {
      final without = removeCutAnywhere(project, cutId);
      removedCut = without.removed;
      if (removedCut == null) {
        throw StateError('Cut not found: $cutId');
      }
      return without.project;
    });
    return removedCut!;
  }

  void renameCut({required CutId cutId, required String name}) {
    _mutate(_cut, cutId, (cut) => cut.copyWith(name: name));
  }

  void updateCutCanvasSize({
    required CutId cutId,
    required CanvasSize canvasSize,
  }) {
    _mutate(_cut, cutId, (cut) => cut.copyWith(canvasSize: canvasSize));
  }

  /// D5 (R7): a resize's ONE model write per cut — the new canvas size
  /// plus the content follow (camera keyframes, guides, text anchors and
  /// layer transform coordinates, [translateCutContentModel] — see its
  /// doc for the two offsets). One write per cut keeps the resize
  /// command's single history entry looking at coherent cuts.
  void resizeCutCanvasContent({
    required CutId cutId,
    required CanvasSize canvasSize,
    required double dx,
    required double dy,
    required double centreDx,
    required double centreDy,
  }) {
    _mutate(
      _cut,
      cutId,
      (cut) => translateCutContentModel(
        cut,
        dx: dx,
        dy: dy,
        centreDx: centreDx,
        centreDy: centreDy,
      ).copyWith(canvasSize: canvasSize),
    );
  }

  void updateCutLeadingGap({
    required CutId cutId,
    required int leadingGapFrames,
  }) {
    _mutate(
      _cut,
      cutId,
      (cut) => cut.copyWith(leadingGapFrames: leadingGapFrames),
    );
  }

  /// Every layer of [cut] with its run-edge ghosts derived from [cut]'s
  /// own length.
  ///
  /// A run edge property is a SPEC — *this run holds*, *this run repeats* —
  /// carried by one of the run's blocks (`TimelineRunEdgeMark`), and the
  /// cells it covers are ghost exposures synthesized from it by
  /// [rederiveRunBehaviors]. The two are only ever in step because
  /// something re-derives, and every path that EDITS a timeline does.
  ///
  /// The paths that bring a cut or a layer in from OUTSIDE did not, which
  /// is a whole class of bug rather than one: an imported hold recorded
  /// its spec, printed `H` on the property tag, and covered nothing. It
  /// lives here rather than in each importer on purpose — the next
  /// importer, and the next [TimelineRunEdgeMode], are then covered by
  /// construction instead of by whoever writes them remembering to ask.
  ///
  /// Free when there is nothing to derive: [rederiveRunBehaviors] returns
  /// the same layer instance for a layer with no marks and no ghosts, so
  /// the grid's memo gates see no change.
  static Cut _withDerivedRunEdges(Cut cut) => cut.copyWith(
    layers: [
      for (final layer in cut.layers)
        rederiveRunBehaviors(layer, cutFrameCount: cut.duration),
    ],
  );

  void updateCutDuration({required CutId cutId, required int duration}) {
    _mutate(
      _cut,
      cutId,
      // Hold/repeat run edges fill ghosts TO THE CUT END, so a duration
      // change re-derives every layer — the only rederive trigger that
      // is not a layer edit.
      (cut) => _withDerivedRunEdges(cut.copyWith(duration: duration)),
    );
  }

  void updateCutGuides({required CutId cutId, required CutGuides guides}) {
    _mutate(_cut, cutId, (cut) => cut.copyWith(guides: guides));
  }

  void updateCutCamera({required CutId cutId, required CutCamera camera}) {
    _mutate(_cut, cutId, (cut) => cut.copyWith(camera: camera));
  }

  // `updateTrackTransform` retired with the V row's transform: there is no
  // track pose or fade lane to write. Layer transforms keep their own writer,
  // and the cut fade is F.I/F.O spans on the transition row now
  // ([updateTrackTransitionLayer]).

  /// The track's TRANSITION row — O.L / F.I / F.O spans on the global frame
  /// axis. Track-owned like the pose and the SE rows, and for the same
  /// reason: a span straddles a cut boundary, so a cut trim or reorder must
  /// not drag it along.
  void updateTrackTransitionLayer({
    required TrackId trackId,
    required Layer transitionLayer,
  }) {
    _mutate(
      _track,
      trackId,
      (track) => track.copyWith(transitionLayer: transitionLayer),
    );
  }

  /// The V track's EFFECT CHAIN — the V row's fx over the composited cut,
  /// keyed on the global axis like its pose.
  void updateTrackEffects({
    required TrackId trackId,
    required List<LayerEffect> effects,
  }) {
    _mutate(_track, trackId, (track) => track.copyWith(effects: effects));
  }

  /// The V track's DISPLAY properties (R9 #21): its static opacity and its
  /// fx master. Both persist — R8's rule that an fx switch is model state,
  /// applied to the one row that still kept its switch in the session.
  void updateTrackDisplay({
    required TrackId trackId,
    double? opacity,
    bool? fxEnabled,
  }) {
    _mutate(
      _track,
      trackId,
      (track) => track.copyWith(opacity: opacity, fxEnabled: fxEnabled),
    );
  }

  void updateCutMetadata({
    required CutId cutId,
    required CutMetadata metadata,
  }) {
    _mutate(_cut, cutId, (cut) => cut.copyWith(metadata: metadata));
  }

  void addLayer({required CutId cutId, required Layer layer}) {
    insertLayer(cutId: cutId, layer: layer);
  }

  /// ⚠️Not [_mutateLayerInCut]: this REMOVES, and the caller needs the
  /// layer BACK to undo with.
  Layer deleteLayer({required CutId cutId, required LayerId layerId}) {
    Layer? deletedLayer;
    _mutate(_cut, cutId, (cut) {
      final without = removeLayerFromCut(cut, layerId);
      deletedLayer = without.removed;
      if (deletedLayer == null) {
        throw StateError('Layer not found in cut $cutId: $layerId');
      }
      return without.cut;
    });
    return deletedLayer!;
  }

  /// Inserts an SE row into [trackId]'s track-owned SE list (S-rows live
  /// on the track's global frame axis).
  void insertTrackSeLayer({
    required TrackId trackId,
    required Layer layer,
    int? index,
  }) {
    _mutate(_track, trackId, (track) {
      final seLayers = insertedAt(track.seLayers, layer, index);
      return track.copyWith(seLayers: seLayers);
    });
  }

  void removeTrackSeLayer({
    required TrackId trackId,
    required LayerId layerId,
  }) {
    _mutate(_track, trackId, (track) {
      return track.copyWith(
        seLayers: track.seLayers
            .where((layer) => layer.id != layerId)
            .toList(growable: false),
      );
    });
  }

  /// Resequences a cut's layers to exactly [order] and re-parents the rows
  /// named in [folderIds] — THE row-placement mutation.
  ///
  /// Order and membership move TOGETHER because one drag moves both: a row
  /// dropped between two of a folder's members lands there AND joins it,
  /// and splitting that into two writes would let an undo stop halfway,
  /// with the row sitting inside a folder it does not belong to.
  ///
  /// [order] must be a permutation of the cut's layer ids — a partial or
  /// foreign list is a programming error, not a silent drop (the cut-order
  /// rule, [setCutOrder]). A layer absent from [folderIds] keeps the
  /// membership it had.
  void setLayerPlacement({
    required CutId cutId,
    required List<LayerId> order,
    Map<LayerId, LayerId?> folderIds = const {},
  }) {
    _mutate(_cut, cutId, (cut) {
      return cut.copyWith(
        layers: [
          for (final layer in reorderedByIds(
            cut.layers,
            order,
            idOf: (layer) => layer.id,
            orderName: 'Layer order for cut $cutId',
          ))
            if (folderIds.containsKey(layer.id))
              layer.copyWith(folderId: folderIds[layer.id])
            else
              layer,
        ],
      );
    });
  }

  /// Resequences [trackId]'s SE rows to exactly [order] — the S-rows'
  /// counterpart of [setLayerPlacement]. They carry no folder membership
  /// (the track owns them flat), so order is the whole placement.
  void setTrackSeOrder({
    required TrackId trackId,
    required List<LayerId> order,
  }) {
    _mutate(_track, trackId, (track) {
      return track.copyWith(
        seLayers: reorderedByIds(
          track.seLayers,
          order,
          idOf: (layer) => layer.id,
          orderName: 'SE order for track $trackId',
        ),
      );
    });
  }

  /// Writes a row's ATTACH relationship — the pointer, the side, the timing
  /// mode, and the three fields that follow from them (its own timeline, the
  /// cell links, the run-edge behaviours).
  ///
  /// All six move together because a half-applied attachment is not a state
  /// the model has: a SYNCED row with a stored timeline, or a detached row
  /// still holding links, would each be read two ways at once.
  void setLayerAttachment({
    required LayerId layerId,
    required LayerAttachment attachment,
  }) {
    updateLayer(layerId: layerId, update: attachment.applyTo);
  }

  /// Moves a layer into (or out of, with null) a folder row.
  void updateLayerFolderId({
    required CutId cutId,
    required LayerId layerId,
    required LayerId? folderId,
  }) {
    updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(folderId: folderId),
    );
  }

  void insertLayer({required CutId cutId, required Layer layer, int? index}) {
    _mutate(_cut, cutId, (cut) => cutWithLayerInserted(cut, layer, index));
  }

  void replaceLayer({required Layer layer}) {
    updateLayer(layerId: layer.id, update: (_) => layer);
  }

  void updateLayer({
    required LayerId layerId,
    required Layer Function(Layer layer) update,
  }) {
    _mutate(_layer, layerId, update);
  }

  // The layer-flag updates below route through the ANYWHERE lookup (cut
  // layers + the tracks' SE rows): layer ids are globally unique, and
  // track-owned SE layers must reach the same commands. The cutId
  // parameter stays for API stability but no longer scopes the search.

  void updateLayerName({
    required CutId cutId,
    required LayerId layerId,
    required String name,
  }) {
    updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(name: name),
    );
  }

  void updateLayerTimesheet({
    // Unread — the write is layer-addressed; null from gap-state flips of
    // track fixtures (B5③).
    required CutId? cutId,
    required LayerId layerId,
    required bool onTimesheet,
  }) {
    updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(onTimesheet: onTimesheet),
    );
  }

  void updateLayerFillReference({
    required CutId cutId,
    required LayerId layerId,
    required bool isFillReference,
  }) {
    updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(isFillReference: isFillReference),
    );
  }

  void updateLayerMark({
    required CutId cutId,
    required LayerId layerId,
    required LayerMark mark,
  }) {
    updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(mark: mark),
    );
  }

  void updateCameraInstructionSet(CameraInstructionSet instructionSet) {
    updateProject(
      (project) => project.copyWith(cameraInstructions: instructionSet),
    );
  }

  void updateMediaAssets(List<MediaAsset> mediaAssets) {
    updateProject((project) => project.copyWith(mediaAssets: mediaAssets));
  }

  void updateLayerTransformTrack({
    required CutId cutId,
    required LayerId layerId,
    required TransformTrack transformTrack,
  }) {
    updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(transformTrack: transformTrack),
    );
  }

  void updateLayerEffects({
    required CutId cutId,
    required LayerId layerId,
    required List<LayerEffect> effects,
  }) {
    updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(effects: effects),
    );
  }

  void updateLayerAudioClips({
    // Unread — the write is layer-addressed; null from gap-state edits of
    // track fixtures (B6).
    required CutId? cutId,
    required LayerId layerId,
    required List<AudioClip> audioClips,
  }) {
    updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(audioClips: audioClips),
    );
  }

  /// The SE row's on-canvas name tag (R5b). Null resets it to the stacked
  /// default, so the sentinel copyWith is what carries the write.
  void updateLayerSeNameTag({
    required LayerId layerId,
    required SeNameTag? seNameTag,
  }) {
    updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(seNameTag: seNameTag),
    );
  }

  /// ⚠️Not [_mutateLayerInCut]: the check reads the CUT (no second
  /// storyboard row), so the closure needs what that helper does not hand
  /// it. One site — not three — so the helper stays as it is.
  void updateLayerKind({
    required CutId cutId,
    required LayerId layerId,
    required LayerKind kind,
  }) {
    _mutate(_cut, cutId, (cut) {
      final updatedCut = updateLayerInCut(cut, layerId, (layer) {
        if (kind == LayerKind.storyboard &&
            layer.kind != LayerKind.storyboard &&
            cut.layers.any((other) => other.kind == LayerKind.storyboard)) {
          throw StateError('Cut $cutId already has a storyboard layer.');
        }
        return layer.copyWith(kind: kind);
      });
      if (updatedCut == null) {
        throw StateError('Layer not found in cut $cutId: $layerId');
      }
      return updatedCut;
    });
  }

  void addFrame({required LayerId layerId, required Frame frame}) {
    _mutate(
      _layer,
      layerId,
      (layer) => layer.copyWith(frames: [...layer.frames, frame]),
    );
  }

  void updateFrame({
    required FrameId frameId,
    required Frame Function(Frame frame) update,
  }) {
    _mutate(_frame, frameId, update);
  }

  /// Writes the memo of the exposure BLOCK starting at [blockStartIndex].
  ///
  /// Addressed by block start rather than by frame: the memo belongs to the
  /// exposure, so re-exposing the same drawing elsewhere carries its own.
  void updateExposureMemo({
    required CutId cutId,
    required LayerId layerId,
    required int blockStartIndex,
    required ExposureMemo? memo,
  }) {
    _mutateLayerInCut(cutId, layerId, (layer) {
      final entry = requireMemoBlockAt(layer, blockStartIndex);
      return layer.copyWith(
        timeline: {
          ...layer.timeline,
          blockStartIndex: entry.copyWith(memo: () => memo),
        },
      );
    });
  }

  void addStroke({required FrameId frameId, required Stroke stroke}) {
    _mutate(
      _frame,
      frameId,
      (frame) => frame.copyWith(strokes: [...frame.strokes, stroke]),
    );
  }
}
