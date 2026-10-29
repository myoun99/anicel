import '../models/attached_layer_mount.dart' show LayerAttachment;
import '../models/attached_layer_resolve.dart'
    show cutWithReconciledAttachedMirrors;
import '../models/audio_clip.dart';
import '../models/se_name_tag.dart';
import '../models/camera_instruction.dart';
import '../models/canvas_size.dart';
import '../models/conte_group.dart' show storyboardLayerForCut;
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
import '../models/project_font_file.dart';
import '../models/project_frame_rate.dart';
import '../models/stroke.dart';
import '../models/transform_track.dart';
import '../models/track_conte_laying.dart'
    show
        ConteHeadPut,
        conteFillsGiven,
        conteHeadsPut,
        cutWithoutConteFills,
        isConteFill,
        projectWithItsContesLaid,
        withConteHeadTakenOff;
import '../models/track_transitions.dart'
    show drawnFrameCountOf, transitionHandlesByCut;
import '../models/transition_geometry.dart' show CutTransitionHandles;
import '../models/track_id.dart';
import 'project_lookup.dart' show attachedMirrorGroupOf, requireMemoBlockAt;
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

/// A cut as the repository's last write settled it: the instance, the
/// のりしろ it was settled against, and the conte row that write tiled.
typedef _Settled = ({
  Cut cut,
  CutTransitionHandles handles,
  LayerId? conteRowId,
});

/// What one [ProjectRepository.asOneConteWrite]'s laying made that the
/// write's undo must take back: the rows it gave the cuts, and the heads it
/// put on rows that joined a conte.
typedef ConteWriteMade = ({Set<LayerId> fills, List<ConteHeadPut> heads});

/// [cut] with [layer] inserted at [index] (appended when null) — the cut a
/// row joins, and the one a conte picture draws through while the row its
/// first stroke makes is not there yet. The row's run edges are the
/// write's to settle (invariant 5 of [ProjectRepository]'s normalization):
/// where they fill to is the cut's drawn end, which only the project knows.
Cut cutWithLayerInserted(Cut cut, Layer layer, int? index) =>
    cut.copyWith(layers: insertedAt(cut.layers, layer, index));

class ProjectRepository {
  ProjectRepository({Project? initialProject}) {
    if (initialProject != null) {
      _currentProject = _normalized(initialProject);
    }
  }

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

  /// A project from elsewhere is settled from scratch: what the last write
  /// here remembered is about a different set of rows, whatever their ids.
  void replaceProject(Project project) {
    _settled = const {};
    if (_conteStart != null) {
      _conteStart = const {};
    }
    _currentProject = _normalized(project);
  }

  void clearProject() {
    _settled = const {};
    if (_conteStart != null) {
      _conteStart = const {};
    }
    _currentProject = null;
  }

  /// [body]'s writes as ONE write of the tracks' contes (F-343): the
  /// structure is laid once, after the last of them, against the cuts as
  /// they stood before the first — and what that laying made is what comes
  /// back: the rows it gave the cuts ([isConteFill]) and the heads it put on
  /// rows that joined a conte ([conteHeadsPut]).
  ///
  /// 🚨A step that takes a row out of every cut's conte writes cut by cut
  /// (`DeleteLayerCommand`), and its undo puts them back the same way. Laid
  /// between those writes, the structure would read a row gone from one cut
  /// that the others still hold, and give it back to that cut, empty — the
  /// delete never finishing — and an undo putting back a row it had given
  /// back already would put a second one there. One step is one write of
  /// the structure: the history runs every step through this
  /// (`ConteStepScope`).
  ///
  /// Inside another, it is that one's: the outer laying lays it.
  ConteWriteMade asOneConteWrite(void Function() body) {
    if (_conteStart != null) {
      body();
      return (fills: const {}, heads: const []);
    }
    final before = _currentProject;
    Project? written;
    _conteStart = _settled;
    try {
      body();
    } finally {
      final against = _conteStart!;
      _conteStart = null;
      if (_currentProject case final project?) {
        written = project;
        final pass = _settle(project, memo: _settled, laidAgainst: against);
        _settled = pass.settled;
        _currentProject = pass.project;
      }
    }
    final laid = _currentProject;
    return (
      fills: conteFillsGiven(before, laid),
      heads: written == null || laid == null
          ? const []
          : conteHeadsPut(before, written, laid),
    );
  }

  /// The cuts as the write before the first of an [asOneConteWrite]'s left
  /// them, while one is under way — null outside one.
  Map<CutId, _Settled>? _conteStart;

  /// Takes [rows] — rows the structure gave the cuts, by
  /// [asOneConteWrite]'s answer — out of every cut that holds one, what a
  /// row filed in one is filed in going to the folder that one was in
  /// ([cutWithoutConteFills]).
  ///
  /// The undo of the step whose laying gave them owes it (`ConteStepScope`):
  /// the step's own undo takes back the row it made in its cut, and the
  /// empty ones the other cuts were given for it would keep it in the
  /// structure. ⚠️Only that undo — it is what knows they are still empty.
  void dropConteFills(Set<LayerId> rows) {
    if (rows.isEmpty) {
      return;
    }
    updateProject((project) {
      final tracks = mappedOrSame(project.tracks, (track) {
        final cuts = mappedOrSame(
          track.cuts,
          (cut) => cutWithoutConteFills(cut, rows),
        );
        return identical(cuts, track.cuts) ? track : track.copyWith(cuts: cuts);
      });
      return identical(tracks, project.tracks)
          ? project
          : project.copyWith(tracks: tracks);
    });
  }

  /// Takes off each head of [heads] — heads the structure put on rows that
  /// joined a conte, by [asOneConteWrite]'s answer — from the row it was put
  /// on ([withConteHeadTakenOff]).
  ///
  /// The undo of the step whose laying put them owes it (`ConteStepScope`):
  /// the step's own undo takes the row out of the conte, and no laying
  /// lays a row that is in none.
  void takeOffConteHeads(List<ConteHeadPut> heads) {
    for (final put in heads) {
      _mutateLayerInCut(
        put.cutId,
        put.laid.id,
        (row) => withConteHeadTakenOff(row, put),
      );
    }
  }

  void updateProject(Project Function(Project project) update) {
    _currentProject = _normalized(update(requireProject()));
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
  // the editor itself: [removeCut], [reorderCut] and [deleteLayer] each
  // do, and each says why where it does it.

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

  /// The write-time invariants. First, of every TRACK: its CONTE STRUCTURE
  /// ([projectWithItsContesLaid], F-343) — what a write did to one cut's
  /// conte made the track's, every cut's conte laid from it, and the rows
  /// it gave a 겸용 pair one layer — so the six below read every conte as it
  /// stands. Then, of every cut:
  /// 1. COVERING IMAGE rows ([cutWithCoveringImageRows]): an image
  ///    layer's stored timeline is ONE real 1-frame block at index 0 plus
  ///    a fixed end-side HOLD whose ghosts fill to the cut's drawn end
  ///    (D22) — runs FIRST so the mirror pass below sees the final base
  ///    timeline (an image row can be an attach base).
  /// 2. The COVERING STORYBOARD row ([cutWithCoveringStoryboardRow]): its
  ///    stored panels tile the cut exactly, and its last panel holds
  ///    through whatever のりしろ the cut owes (F-227). Same grammar as 1,
  ///    arriving late because the row's DERIVED reader was mistaken for a
  ///    guarantee — it only hid the stored holes from the surface that
  ///    makes them.
  /// 3. The ALWAYS-MIRROR invariant (UI-R23 #7 v2,
  ///    [cutWithReconciledAttachedMirrors]): every synced attach row a
  ///    complete mirror of its base — one own cel + link per base cel —
  ///    no matter how the base gained the cel (create, move, paste,
  ///    undo/redo replay, file load). A LINKED attach row's cel for a base
  ///    cel is its group's one (F-278), read off the other members.
  /// 4. SPANS ON THEIR BLOCKS (R27, [cutWithSpansOnTheirBlocks]): a block
  ///    carries an instruction only where its row's spans ride its blocks —
  ///    any other row's block puts one down. (A direction row's bare block
  ///    is the span that says nothing.)
  /// 5. RUN EDGES FILLED TO THE DRAWN END ([rederiveRunBehaviors]): a run
  ///    edge property is a SPEC — *this run holds*, *this run repeats* —
  ///    carried by one of the run's blocks (`TimelineRunEdgeMark`), and the
  ///    cells it covers are ghost exposures synthesized from it. The ghosts
  ///    reach the cut's DRAWN end — its conte 尺 plus the のりしろ the
  ///    track's transitions ask of it ([drawnFrameCountsOf]) — and that end
  ///    moves without the cut being touched: an O.L drawn, moved or
  ///    removed, a neighbour trimmed. This is the one place that sees every
  ///    such write, so it is here, last, where the four above have settled
  ///    the blocks the ghosts are read off.
  ///
  ///    ↩️It used to run on chosen verbs (`_withDerivedRunEdges`, on a cut
  ///    inserted from outside and on a length change) and every timeline
  ///    edit derived its own; the paths that brought a cut in from OUTSIDE
  ///    did not, and an imported hold printed `H` and covered nothing. A
  ///    write-time invariant covers the next importer by construction.
  /// 6. THE CAMERA'S KEYS ON ITS FRAMES ([cameraFollowingItsEnd], I-73 ④):
  ///    the key on a cut's last drawn frame stays on it whenever that frame
  ///    moves, and a shrink brings in every key on the frames it took — the
  ///    same drawn end as 5, moved by the same writes. Where the last frame
  ///    was is the last write's, read off what it settled. A shrink the
  ///    hand drives stops short of the other keys, so an undo that writes
  ///    the length back carries the end key back; the commands that take a
  ///    のりしろ away at once put their cameras back themselves
  ///    (`CamerasFollowTheirEnds`), and an undo that restores the whole
  ///    project starts the memo afresh and moves nothing.
  /// Identity-preserving on no-ops, so an already-normal project passes
  /// through untouched.
  Project _normalized(Project project) {
    final pass = _settle(
      project,
      memo: _settled,
      // Inside [asOneConteWrite] the structure waits for the last write.
      laidAgainst: _conteStart == null ? _settled : null,
    );
    _settled = pass.settled;
    return pass.project;
  }

  /// [draft] as a write of it would leave it — the invariants above, read
  /// against what the last write settled — with nothing written and
  /// nothing remembered.
  ///
  /// 🗣️F-227: a drag that re-lays the cuts previews through this. The
  /// のりしろ holds and the conte start an O.L asks of the cuts it joins
  /// are derived by the WRITE, from the new layout; a preview that skipped
  /// the pass showed the holds gone and the receiving cut's panels where
  /// the old のりしろ put them, then jumped on release.
  Project settledAsWritten(Project draft) => _settle(
    draft,
    memo: _settled,
    laidAgainst: _conteStart ?? _settled,
  ).project;

  /// The tracks' contes laid against [laidAgainst] — not at all when it is
  /// null — then the six invariants over every cut [memo] does not already
  /// hold settled, and the memo the next write reads.
  static ({Project project, Map<CutId, _Settled> settled}) _settle(
    Project written, {
    required Map<CutId, _Settled> memo,
    required Map<CutId, _Settled>? laidAgainst,
  }) {
    final project = laidAgainst == null
        ? written
        : _withContesLaid(written, against: laidAgainst);
    final handlesByCut = transitionHandlesByCut(project);
    final settled = <CutId, _Settled>{};
    final tracks = mappedOrSame(project.tracks, (track) {
      final cuts = mappedOrSame(track.cuts, (cut) {
        final handles = handlesByCut[cut.id]!;
        final last = memo[cut.id];
        // A cut this write did not touch, whose のりしろ did not move, is the
        // very instance the last write settled: all six hold.
        final next =
            last != null && identical(last.cut, cut) && last.handles == handles
            ? cut
            : _normalizedCut(
                cut,
                project: project,
                handles: handles,
                last: last,
              );
        settled[cut.id] = (
          cut: next,
          handles: handles,
          conteRowId: _conteRowIdOf(next),
        );
        return next;
      });
      return identical(cuts, track.cuts) ? track : track.copyWith(cuts: cuts);
    });
    return (
      project: identical(tracks, project.tracks)
          ? project
          : project.copyWith(tracks: tracks),
      settled: settled,
    );
  }

  /// [project] with each track's conte laid ([projectWithItsContesLaid]),
  /// what a write changed read against the cuts as [against] holds them.
  static Project _withContesLaid(
    Project project, {
    required Map<CutId, _Settled> against,
  }) => projectWithItsContesLaid(
    project,
    settledCut: (cutId) => against[cutId]?.cut,
  );

  /// Each cut as the last write left it, with the のりしろ its conte row and
  /// run edges were settled against — so a write settles only the cuts it
  /// changed or whose のりしろ it moved, not every cut of the project.
  Map<CutId, _Settled> _settled = const {};

  static LayerId? _conteRowIdOf(Cut cut) => storyboardLayerForCut(cut)?.id;

  /// The six invariants above, in their stated order, over one cut of
  /// [project] — the project being settled, read for the two things a cut
  /// cannot say alone: the vocabulary a direction block's drawing is named
  /// by, and a linked attach row's group — and over what the [last] write
  /// settled of it, where there was one.
  static Cut _normalizedCut(
    Cut cut, {
    required Project project,
    required CutTransitionHandles handles,
    required _Settled? last,
  }) {
    final drawnFrameCount = drawnFrameCountOf(cut, handles);
    // The conte row the last write tiled, if this is still it: its blocks
    // sit where that write put them, whatever an edit since did to its
    // first panel. A row it never saw says where it was tiled from itself.
    final previousConteStart =
        last != null && last.conteRowId == _conteRowIdOf(cut)
        ? last.handles.head
        : null;
    // Where the cut's last frame was when the last write settled it — the
    // one its camera's end key stood on.
    final previousDrawnFrameCount = last == null
        ? null
        : drawnFrameCountOf(last.cut, last.handles);
    final shaped = cutWithSpansOnTheirBlocks(
      cutWithReconciledAttachedMirrors(
        cutWithCoveringStoryboardRow(
          cutWithCoveringImageRows(cut, drawnFrameCount: drawnFrameCount),
          handles: handles,
          previousConteStart: previousConteStart,
        ),
        // A linked attach row's mirror cels are its GROUP's (F-278): the
        // other members are read off the project being settled.
        mirrorGroupOf: (attached) => attachedMirrorGroupOf(
          project,
          cutId: cut.id,
          attached: attached,
        ),
      ),
      defById: project.cameraInstructions.defById,
    );
    final layers = mappedOrSame(
      shaped.layers,
      (layer) => rederiveRunBehaviors(layer, drawnFrameCount: drawnFrameCount),
    );
    final ruled = identical(layers, shaped.layers)
        ? shaped
        : shaped.copyWith(layers: layers);
    final camera = previousDrawnFrameCount == null
        ? ruled.camera
        : cameraFollowingItsEnd(
            ruled.camera,
            lastFrame: drawnFrameCount - 1,
            previousLastFrame: previousDrawnFrameCount - 1,
          );
    return identical(camera, ruled.camera)
        ? ruled
        : ruled.copyWith(camera: camera);
  }

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

  void addCut({required TrackId trackId, required Cut cut}) {
    insertCut(trackId: trackId, cut: cut);
  }

  void insertCut({required TrackId trackId, required Cut cut, int? index}) {
    // A cut built elsewhere — an importer's plan, a duplicate — arrives
    // with run-edge SPECS and no ghosts; the write settles them where it
    // lands (invariant 5 of [_normalized]).
    _mutate(_track, trackId, (track) {
      // ⛔NOT [insertedAt]. That law CLAMPS, which is right for a row
      // landing in a layer list; a cut index past the end is a caller
      // that computed a position from a stale track, and the throw is
      // pinned by "throws when inserting a cut at an out-of-range index".
      final cuts = [...track.cuts];
      if (index == null) {
        cuts.add(cut);
      } else {
        cuts.insert(index, cut);
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

  /// Hold/repeat run edges fill to the cut's drawn end, which a length
  /// change moves — the write's own settling (invariant 5 of [_normalized])
  /// fills them again.
  void updateCutDuration({required CutId cutId, required int duration}) {
    _mutate(_cut, cutId, (cut) => cut.copyWith(duration: duration));
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

  /// The V track's DISPLAY property (R9 #21): its fx master. It persists —
  /// R8's rule that an fx switch is model state, applied to the one row
  /// that still kept its switch in the session. (↩️Its static opacity was
  /// the other, until I-73.)
  void updateTrackDisplay({
    required TrackId trackId,
    required bool fxEnabled,
  }) {
    _mutate(_track, trackId, (track) => track.copyWith(fxEnabled: fxEnabled));
  }

  /// The V row's twirls (F-360): its lanes twirled down or not, and the
  /// effect groups open inside them — the track's own, as a layer row's are
  /// its own ([updateLayer]).
  void updateTrackLanes({
    required TrackId trackId,
    required bool lanesExpanded,
    required Set<String> expandedLaneGroups,
  }) {
    _mutate(
      _track,
      trackId,
      (track) => track.copyWith(
        lanesExpanded: lanesExpanded,
        expandedLaneGroups: expandedLaneGroups,
      ),
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

  /// Writes [cutId]'s rows whole, as ONE write — for an edit whose rows
  /// change together, which the invariants above would settle otherwise
  /// between two writes of them (`SetCutLayersCommand`).
  void setCutLayers({required CutId cutId, required List<Layer> layers}) {
    _mutate(_cut, cutId, (cut) => cut.copyWith(layers: layers));
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

  void updateLayerClip({
    required CutId cutId,
    required LayerId layerId,
    required bool clipsToBelow,
  }) {
    updateLayer(
      layerId: layerId,
      update: (layer) => layer.copyWith(clipsToBelow: clipsToBelow),
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

  /// The font files registered with the project are [fonts] from here on.
  void updateFonts(List<ProjectFontFile> fonts) {
    updateProject((project) => project.copyWith(fonts: fonts));
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
            storyboardLayerForCut(cut) != null) {
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
