import '../models/attached_layer_resolve.dart'
    show cutWithReconciledAttachedMirrors;
import '../models/audio_clip.dart';
import '../models/camera_instruction.dart';
import '../models/canvas_size.dart';
import '../models/cut.dart';
import '../models/cut_camera.dart';
import '../models/cut_id.dart';
import '../models/cut_metadata.dart';
import '../models/export_overrides.dart';
import '../models/frame.dart';
import '../models/frame_id.dart';
import '../models/layer.dart';
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

  /// The ALWAYS-MIRROR invariant (UI-R23 #7 v2): every write leaves every
  /// synced attach row a complete mirror of its base — one own cel + link
  /// per base cel — no matter how the base gained the cel (create, move,
  /// paste, undo/redo replay, file load). Identity-preserving on no-ops,
  /// so an already-complete project passes through untouched.
  static Project _reconcileAttachedMirrors(Project project) {
    List<Track>? nextTracks;
    for (var t = 0; t < project.tracks.length; t += 1) {
      final track = project.tracks[t];
      List<Cut>? nextCuts;
      for (var c = 0; c < track.cuts.length; c += 1) {
        final cut = track.cuts[c];
        final reconciled = cutWithReconciledAttachedMirrors(cut);
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
    updateProject((project) {
      final next = updateTrackById(project, trackId, (track) {
        final cuts = [...track.cuts];
        if (index == null) {
          cuts.add(cut);
        } else {
          cuts.insert(index, cut);
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
    updateProject((project) {
      final next = updateTrackById(project, trackId, (track) {
        final cuts = [...track.cuts];
        final oldIndex = cuts.indexWhere((cut) => cut.id == cutId);
        if (oldIndex == -1) {
          throw StateError('Cut not found in track $trackId: $cutId');
        }

        final cut = cuts.removeAt(oldIndex);
        cuts.insert(newIndex, cut);
        return track.copyWith(cuts: cuts);
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

  void updateCutDuration({required CutId cutId, required int duration}) {
    updateProject((project) {
      final next = updateCutAnywhere(
        project,
        cutId,
        // Hold/repeat run edges fill ghosts TO THE CUT END, so a duration
        // change re-derives every layer here — the only rederive trigger
        // that is not a layer edit (identity for layers without specs).
        (cut) => cut.copyWith(
          duration: duration,
          layers: [
            for (final layer in cut.layers)
              rederiveRunBehaviors(layer, cutFrameCount: duration),
          ],
        ),
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

  void updateCutTransform({
    required CutId cutId,
    required TransformTrack transformTrack,
  }) {
    updateProject((project) {
      final next = updateCutAnywhere(
        project,
        cutId,
        (cut) => cut.copyWith(transformTrack: transformTrack),
      );
      if (next == null) {
        throw StateError('Cut not found: $cutId');
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
        final layers = [...cut.layers];
        if (index == null) {
          layers.add(layer);
        } else {
          layers.insert(index.clamp(0, layers.length).toInt(), layer);
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
