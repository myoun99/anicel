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
import '../models/drawing_guide.dart';
import '../models/cut_id.dart';
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
import '../models/project_background.dart';
import '../models/project_frame_rate.dart';
import '../models/stroke.dart';
import '../models/transform_track.dart';
import '../models/track.dart';
import '../models/track_id.dart';
import 'project_tree_editor.dart';

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
  ///    layer's stored block always equals the cut length — runs FIRST so
  ///    the mirror pass below sees the final base timeline (an image row
  ///    can be an attach base).
  /// 2. The COVERING STORYBOARD row ([cutWithCoveringStoryboardRow]): its
  ///    stored panels tile the cut exactly. Same grammar as 1, arriving
  ///    late because the row's DERIVED reader was mistaken for a guarantee
  ///    — it only hid the stored holes from the surface that makes them.
  /// 3. The ALWAYS-MIRROR invariant (UI-R23 #7 v2,
  ///    [cutWithReconciledAttachedMirrors]): every synced attach row a
  ///    complete mirror of its base — one own cel + link per base cel —
  ///    no matter how the base gained the cel (create, move, paste,
  ///    undo/redo replay, file load).
  /// Identity-preserving on no-ops, so an already-normal project passes
  /// through untouched.
  static Project _reconcileAttachedMirrors(Project project) {
    List<Track>? nextTracks;
    for (var t = 0; t < project.tracks.length; t += 1) {
      final track = project.tracks[t];
      List<Cut>? nextCuts;
      for (var c = 0; c < track.cuts.length; c += 1) {
        final cut = track.cuts[c];
        final reconciled = cutWithReconciledAttachedMirrors(
          cutWithCoveringStoryboardRow(cutWithCoveringImageRows(cut)),
        );
        if (identical(reconciled, cut)) {
          continue;
        }
        (nextCuts ??= [...track.cuts])[c] = reconciled;
      }
      if (nextCuts == null) {
        continue;
      }
      (nextTracks ??= [...project.tracks])[t] = track.copyWith(cuts: nextCuts);
    }
    return nextTracks == null ? project : project.copyWith(tracks: nextTracks);
  }

  void updateTimesheetInfo(TimesheetInfo info) {
    updateProject((project) => project.copyWith(timesheetInfo: info));
  }

  void updateProjectBackground(ProjectBackground background) {
    updateProject((project) => project.copyWith(background: background));
  }

  /// R3b: the stage's outer planes — the opaque backdrop, the RGBA
  /// pasteboard and how far the pasteboard shows. Null leaves that side
  /// untouched (one write serves all three, so one undo can restore them).
  void updateProjectStageColors({
    int? backdropArgb,
    int? pasteboardArgb,
    double? pasteboardMargin,
  }) {
    updateProject(
      (project) => project.copyWith(
        backdropArgb: backdropArgb,
        pasteboardArgb: pasteboardArgb,
        pasteboardMargin: pasteboardMargin,
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
    updateProject((project) {
      final next = updateTrackById(project, track.id, (_) => track);
      if (next == null) {
        throw StateError('Track not found: ${track.id}');
      }
      return next;
    });
  }

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
    updateProject((project) {
      final next = updateTrackById(project, trackId, (track) {
        final cuts = [...track.cuts];
        if (index == null) {
          cuts.add(derived);
        } else {
          cuts.insert(index, derived);
        }
        return track.copyWith(cuts: cuts);
      });
      if (next == null) {
        throw StateError('Track not found: $trackId');
      }
      return next;
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
    updateProject((project) {
      final next = updateTrackById(project, trackId, (track) {
        final byId = {for (final cut in track.cuts) cut.id: cut};
        if (order.length != track.cuts.length ||
            order.toSet().length != order.length ||
            !order.every(byId.containsKey)) {
          throw StateError(
            'Cut order for track $trackId must be a permutation of its cuts.',
          );
        }
        return track.copyWith(cuts: [for (final id in order) byId[id]!]);
      });
      if (next == null) {
        throw StateError('Track not found: $trackId');
      }
      return next;
    });
  }

  Cut removeCut({required CutId cutId}) {
    Cut? removedCut;

    updateProject((project) {
      final tracks = project.tracks
          .map((track) {
            final cutIndex = track.cuts.indexWhere((cut) => cut.id == cutId);
            if (cutIndex == -1) {
              return track;
            }

            removedCut = track.cuts[cutIndex];
            final cuts = [...track.cuts]..removeAt(cutIndex);

            return track.copyWith(cuts: cuts);
          })
          .toList(growable: false);

      if (removedCut == null) {
        throw StateError('Cut not found: $cutId');
      }

      return project.copyWith(tracks: tracks);
    });

    return removedCut!;
  }

  void renameCut({required CutId cutId, required String name}) {
    updateProject((project) {
      final next = updateCutAnywhere(
        project,
        cutId,
        (cut) => cut.copyWith(name: name),
      );
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
  }

  void updateCutCanvasSize({
    required CutId cutId,
    required CanvasSize canvasSize,
  }) {
    updateProject((project) {
      final next = updateCutAnywhere(
        project,
        cutId,
        (cut) => cut.copyWith(canvasSize: canvasSize),
      );
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
  }

  void updateCutLeadingGap({
    required CutId cutId,
    required int leadingGapFrames,
  }) {
    updateProject((project) {
      final next = updateCutAnywhere(
        project,
        cutId,
        (cut) => cut.copyWith(leadingGapFrames: leadingGapFrames),
      );
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
  }

  /// Every layer of [cut] with its run-edge ghosts derived from [cut]'s
  /// own length.
  ///
  /// A run behaviour is a SPEC — *this run holds*, *this run repeats* —
  /// and the cells it covers are ghost exposures synthesized from it by
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
  /// the same layer instance for a layer with no specs and no ghosts, so
  /// the grid's memo gates see no change.
  static Cut _withDerivedRunEdges(Cut cut) => cut.copyWith(
    layers: [
      for (final layer in cut.layers)
        rederiveRunBehaviors(layer, cutFrameCount: cut.duration),
    ],
  );

  void updateCutDuration({required CutId cutId, required int duration}) {
    updateProject((project) {
      final next = updateCutAnywhere(
        project,
        cutId,
        // Hold/repeat run edges fill ghosts TO THE CUT END, so a duration
        // change re-derives every layer — the only rederive trigger that
        // is not a layer edit.
        (cut) => _withDerivedRunEdges(cut.copyWith(duration: duration)),
      );
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
  }

  void updateCutGuides({required CutId cutId, required CutGuides guides}) {
    updateProject((project) {
      final next = updateCutAnywhere(
        project,
        cutId,
        (cut) => cut.copyWith(guides: guides),
      );
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
  }

  void updateCutCamera({required CutId cutId, required CutCamera camera}) {
    updateProject((project) {
      final next = updateCutAnywhere(
        project,
        cutId,
        (cut) => cut.copyWith(camera: camera),
      );
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
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
    updateProject((project) {
      var found = false;
      final next = project.copyWith(
        tracks: [
          for (final track in project.tracks)
            if (track.id == trackId)
              (() {
                found = true;
                return track.copyWith(transitionLayer: transitionLayer);
              })()
            else
              track,
        ],
      );
      if (!found) {
        throw StateError('Track not found: $trackId');
      }
      return next;
    });
  }

  /// The V track's EFFECT CHAIN — the V row's fx over the composited cut,
  /// keyed on the global axis like its pose.
  void updateTrackEffects({
    required TrackId trackId,
    required List<LayerEffect> effects,
  }) {
    updateProject((project) {
      var found = false;
      final next = project.copyWith(
        tracks: [
          for (final track in project.tracks)
            if (track.id == trackId)
              (() {
                found = true;
                return track.copyWith(effects: effects);
              })()
            else
              track,
        ],
      );
      if (!found) {
        throw StateError('Track not found: $trackId');
      }
      return next;
    });
  }

  /// The V track's DISPLAY properties (R9 #21): its static opacity and its
  /// fx master. Both persist — R8's rule that an fx switch is model state,
  /// applied to the one row that still kept its switch in the session.
  void updateTrackDisplay({
    required TrackId trackId,
    double? opacity,
    bool? fxEnabled,
  }) {
    updateProject((project) {
      var found = false;
      final next = project.copyWith(
        tracks: [
          for (final track in project.tracks)
            if (track.id == trackId)
              (() {
                found = true;
                return track.copyWith(opacity: opacity, fxEnabled: fxEnabled);
              })()
            else
              track,
        ],
      );
      if (!found) {
        throw StateError('Track not found: $trackId');
      }
      return next;
    });
  }

  void updateCutMetadata({
    required CutId cutId,
    required CutMetadata metadata,
  }) {
    updateProject((project) {
      final next = updateCutAnywhere(
        project,
        cutId,
        (cut) => cut.copyWith(metadata: metadata),
      );
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
  }

  void addLayer({required CutId cutId, required Layer layer}) {
    insertLayer(cutId: cutId, layer: layer);
  }

  Layer deleteLayer({required CutId cutId, required LayerId layerId}) {
    Layer? deletedLayer;

    updateProject((project) {
      final next = updateCutAnywhere(project, cutId, (cut) {
        final index = cut.layers.indexWhere((layer) => layer.id == layerId);
        if (index == -1) {
          return cut;
        }

        deletedLayer = cut.layers[index];
        final layers = [...cut.layers]..removeAt(index);
        return cut.copyWith(layers: layers);
      });
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      if (deletedLayer == null) {
        throw StateError('Layer not found in cut $cutId: $layerId');
      }
      return next;
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
    updateProject((project) {
      final next = updateTrackById(project, trackId, (track) {
        final seLayers = [...track.seLayers];
        if (index == null) {
          seLayers.add(layer);
        } else {
          seLayers.insert(index.clamp(0, seLayers.length).toInt(), layer);
        }
        return track.copyWith(seLayers: seLayers);
      });
      if (next == null) {
        throw StateError('Track not found: $trackId');
      }
      return next;
    });
  }

  void removeTrackSeLayer({
    required TrackId trackId,
    required LayerId layerId,
  }) {
    updateProject((project) {
      final next = updateTrackById(project, trackId, (track) {
        return track.copyWith(
          seLayers: track.seLayers
              .where((layer) => layer.id != layerId)
              .toList(growable: false),
        );
      });
      if (next == null) {
        throw StateError('Track not found: $trackId');
      }
      return next;
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
    updateProject((project) {
      final next = updateCutAnywhere(project, cutId, (cut) {
        final byId = {for (final layer in cut.layers) layer.id: layer};
        if (order.length != cut.layers.length ||
            order.toSet().length != order.length ||
            !order.every(byId.containsKey)) {
          throw StateError(
            'Layer order for cut $cutId must be a permutation of its layers.',
          );
        }
        return cut.copyWith(
          layers: [
            for (final id in order)
              if (folderIds.containsKey(id))
                byId[id]!.copyWith(folderId: folderIds[id])
              else
                byId[id]!,
          ],
        );
      });
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
  }

  /// Resequences [trackId]'s SE rows to exactly [order] — the S-rows'
  /// counterpart of [setLayerPlacement]. They carry no folder membership
  /// (the track owns them flat), so order is the whole placement.
  void setTrackSeOrder({
    required TrackId trackId,
    required List<LayerId> order,
  }) {
    updateProject((project) {
      final next = updateTrackById(project, trackId, (track) {
        final byId = {for (final layer in track.seLayers) layer.id: layer};
        if (order.length != track.seLayers.length ||
            order.toSet().length != order.length ||
            !order.every(byId.containsKey)) {
          throw StateError(
            'SE order for track $trackId must be a permutation of its rows.',
          );
        }
        return track.copyWith(seLayers: [for (final id in order) byId[id]!]);
      });
      if (next == null) {
        throw StateError('Track not found: $trackId');
      }
      return next;
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
    updateProject((project) {
      final next = updateCutAnywhere(project, cutId, (cut) {
        // The cut is only known here, and its length is what the ghosts
        // fill to. See [_withDerivedRunEdges].
        final derived = rederiveRunBehaviors(
          layer,
          cutFrameCount: cut.duration,
        );
        final layers = [...cut.layers];
        if (index == null) {
          layers.add(derived);
        } else {
          layers.insert(index.clamp(0, layers.length).toInt(), derived);
        }
        return cut.copyWith(layers: layers);
      });
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
  }

  void replaceLayer({required Layer layer}) {
    updateLayer(layerId: layer.id, update: (_) => layer);
  }

  void updateLayer({
    required LayerId layerId,
    required Layer Function(Layer layer) update,
  }) {
    updateProject((project) {
      final next = updateLayerAnywhere(project, layerId, update);
      if (next == null) {
        throw StateError('Layer not found: $layerId');
      }
      return next;
    });
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
    required CutId cutId,
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

  void updateLayerInstructions({
    required CutId cutId,
    required LayerId layerId,
    required Map<int, InstructionEvent> instructions,
  }) {
    updateProject((project) {
      final next = updateCutAnywhere(project, cutId, (cut) {
        final updatedCut = updateLayerInCut(
          cut,
          layerId,
          (layer) => layer.copyWith(instructions: instructions),
        );
        if (updatedCut == null) {
          throw StateError('Layer not found in cut $cutId: $layerId');
        }
        return updatedCut;
      });
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
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
    required CutId cutId,
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

  void updateLayerKind({
    required CutId cutId,
    required LayerId layerId,
    required LayerKind kind,
  }) {
    updateProject((project) {
      final next = updateCutAnywhere(project, cutId, (cut) {
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
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
  }

  void addFrame({required LayerId layerId, required Frame frame}) {
    updateProject((project) {
      final next = updateLayerAnywhere(
        project,
        layerId,
        (layer) => layer.copyWith(frames: [...layer.frames, frame]),
      );
      if (next == null) {
        throw StateError('Layer not found: $layerId');
      }
      return next;
    });
  }

  void updateFrame({
    required FrameId frameId,
    required Frame Function(Frame frame) update,
  }) {
    updateProject((project) {
      final next = updateFrameAnywhere(project, frameId, update);
      if (next == null) {
        throw StateError('Frame not found: $frameId');
      }
      return next;
    });
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
    updateProject((project) {
      final next = updateCutAnywhere(project, cutId, (cut) {
        final updatedCut = updateLayerInCut(cut, layerId, (layer) {
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
          return layer.copyWith(
            timeline: {
              ...layer.timeline,
              blockStartIndex: entry.copyWith(memo: () => memo),
            },
          );
        });
        if (updatedCut == null) {
          throw StateError('Layer not found in cut $cutId: $layerId');
        }
        return updatedCut;
      });
      if (next == null) {
        throw StateError('Cut not found: $cutId');
      }
      return next;
    });
  }

  void addStroke({required FrameId frameId, required Stroke stroke}) {
    updateProject((project) {
      final next = updateFrameAnywhere(
        project,
        frameId,
        (frame) => frame.copyWith(strokes: [...frame.strokes, stroke]),
      );
      if (next == null) {
        throw StateError('Frame not found: $frameId');
      }
      return next;
    });
  }
}
