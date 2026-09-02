part of '../editor_session_manager.dart';

/// The CAMERA — the frame size, the pose at a frame, the keyframes and the
/// track that holds them, the instruction set and the block preview — as its
/// own object.
///
/// 🚨A collaborator carved out of `EditorSessionManager` (the audit's SRP cut,
/// 2026-09-02). Measured before cutting: three fields of its own and fifteen
/// session members touched (the timeline controller, the active cut, the cut
/// command coordinator). It reaches the session through `_session`.
class _Camera {
  _Camera(this._session);

  final EditorSessionManager _session;

  CutCamera get activeCutCamera => _session.requireActiveCut.camera;

  /// The camera's output frame size (the exported picture size); the camera
  /// view rect on canvas is this divided by the pose zoom.
  CanvasSize get cameraFrameSize =>
      _session._repository.requireProject().cameraSize;

  /// Sets the project's camera (shooting) frame — one undo step, no-op
  /// when unchanged. Poses are untouched: `CameraPose.zoom` is stated
  /// against this frame's width, so every cut re-frames by itself.
  void setProjectCameraSize(CanvasSize size) {
    if (size.width < 1 || size.height < 1 || size == cameraFrameSize) {
      return;
    }
    _session._historyManager.execute(
      UpdateProjectCameraSizeCommand(
        repository: _session._repository,
        cameraSize: size,
      ),
    );
    _session._notifyChanged();
  }

  /// Resolved camera pose at an arbitrary playback frame (for rendering).
  CameraPose cameraPoseAtFrame(int frameIndex) => resolveCameraPoseAt(
    camera: _session.requireActiveCut.camera,
    canvasSize: _session.requireActiveCut.canvasSize,
    frameIndex: frameIndex,
  );

  /// Resolved camera pose for any cut (play-all renders other cuts too).
  /// The camera ROW's fx switch bypasses the camera work on this render
  /// route (playback, export, storyboard thumbnails all resolve through
  /// here) — the authoring overlays keep reading the real pose.
  CameraPose cameraPoseForCut(Cut cut, int frameIndex) {
    if (_cameraFxBypassedFor(cut)) {
      return CameraPose(
        center: CanvasPoint(
          x: cut.canvasSize.width / 2,
          y: cut.canvasSize.height / 2,
        ),
      );
    }
    return resolveCameraPoseAt(
      camera: cut.camera,
      canvasSize: cut.canvasSize,
      frameIndex: frameIndex,
    );
  }

  /// Whether [cut]'s camera row has its camera work bypassed — the camera
  /// row's own transform switch (R8: persisted like every other row's).
  bool _cameraFxBypassedFor(Cut cut) {
    final camera = cut.layers.cameraLayer;
    return camera != null && !camera.transformEnabled;
  }

  /// The resolved camera pose at the current playhead frame (keyframe,
  /// interpolation, or the default pose when the cut has no camera work).
  CameraPose get cameraPoseAtCurrentFrame => resolveCameraPoseAt(
    camera: _session.requireActiveCut.camera,
    canvasSize: _session.requireActiveCut.canvasSize,
    frameIndex: _session._timelineController.currentFrameIndex,
  );

  /// The camera pose the canvas should FRAME right now — not always the
  /// ACTIVE cut's (㊲).
  ///
  /// "Which cut am I editing" and "which cut is under the playhead" are two
  /// questions, and a live scrub makes them disagree ON PURPOSE: crossing a
  /// boundary parks per move and leaves the active cut alone, because
  /// switching it per move rebuilt every panel ([_session.scrubGlobalFrame]). The
  /// camera frame read the active cut through that, so a T.U that ended
  /// zoomed kept framing the NEXT cut's pictures at the size the cut being
  /// left had finished on — and dragging the other way showed no camera
  /// work at all.
  ///
  /// Only a LIVE scrub asks the parked question: a committed parking means
  /// there is no cut here (a gap, or the V-row eye's hidden picture), and
  /// then there is nothing to frame. Null says exactly that.
  CameraPose? get displayedCameraPose {
    final parked = _session.frameScrubActive.value
        ? _session._gapGlobalFrame
        : null;
    if (parked == null) {
      return _session.activeCutOrNull == null ? null : cameraPoseAtCurrentFrame;
    }
    // 🚨[TrackFrameAxis.ownerOf] hands a gap frame to the PRECEDING cut on
    // purpose (its over-end runway) — it is an addressing rule, not a
    // containment test. [TrackFrameAxis.isGap] is the containment test, and
    // it is the same pair [selectGlobalFrame] asks, so what the drag frames
    // and what the release lands cannot disagree.
    final axis = _session.trackFrameAxis();
    final owner = axis.isGap(parked) ? null : axis.ownerOf(parked);
    if (owner == null) {
      return null;
    }
    // The RENDER route's resolver (fx bypass honoured), because the picture
    // under this rectangle came through it too: preview and camera frame
    // must not disagree about the same cut.
    return cameraPoseForCut(owner.cut, parked - owner.startFrame);
  }

  bool get hasCameraKeyframeAtCurrentFrame =>
      _session.activeCutOrNull?.camera.keyframeAt(
        _session._timelineController.currentFrameIndex,
      ) !=
      null;

  void setCameraKeyframeAtCurrentFrame(CameraPose pose) {
    final cutId = _session._editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _session._cutCommandCoordinator.setCutCameraKeyframe(
      cutId: cutId,
      frameIndex: _session._timelineController.currentFrameIndex,
      pose: pose,
    );
    _session._refreshAfterCutCommand();
    _session._notifyChanged();
  }

  void removeCameraKeyframeAtCurrentFrame() {
    final cutId = _session._editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _session._cutCommandCoordinator.removeCutCameraKeyframe(
      cutId: cutId,
      frameIndex: _session._timelineController.currentFrameIndex,
    );
    _session._refreshAfterCutCommand();
    _session._notifyChanged();
  }

  void clearActiveCutCamera() {
    final cutId = _session._editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    _session._cutCommandCoordinator.clearCutCamera(cutId: cutId);
    _session._refreshAfterCutCommand();
    _session._notifyChanged();
  }

  /// Replaces the active cut's camera track (one undo step) — the property
  /// lanes' per-property key edits route through here.
  void updateActiveCutCameraTrack(
    TransformTrack track, {
    String description = 'Edit camera keyframes',
  }) {
    final cutId = _session._editingSession.activeCutId;
    if (cutId == null) {
      return;
    }
    // "Same name, same value" INSIDE the camera's own track. A camera
    // belongs to its cut, so this naming space has no second use site to
    // reach — but two keys sharing a name on one lane still move together,
    // which is the whole link at its smallest.
    final before = _session.cutById(cutId)?.camera.track;
    _session._cutCommandCoordinator.updateCutCamera(
      cutId: cutId,
      camera: CutCamera.fromTrack(
        before == null
            ? track
            : transformTrackWithNamedValues(
                track,
                transformNamedKeyChanges(before, track),
              ),
      ),
      description: description,
    );
    _session._refreshAfterCutCommand();
    _session._notifyChanged();
  }

  /// Whether the canvas is in camera manipulation mode.
  bool get isCameraLayerActive =>
      _session.activeLayer?.kind == LayerKind.camera;

  /// What the canvas shows while the camera layer is active: the first
  /// visible drawing layer with a frame at the playhead, so there is artwork
  /// to frame. `null` when the cut has nothing drawn at this frame.
  BrushEditorSelection? get cameraBackdropSelection {
    final cut = _session.activeCutOrNull;
    if (cut == null) {
      return null;
    }
    final frameIndex = _session._timelineController.currentFrameIndex;
    for (final layer in cut.layers) {
      if (!layerKindPaintsArtwork(layer.kind) || !layer.isVisible) {
        continue;
      }
      final frame = _session._timelineController.resolveFrameForLayer(
        layer: layer,
        frameIndex: frameIndex,
      );
      if (frame == null) {
        continue;
      }
      return BrushEditorSelection(
        projectId: _session._repository.requireProject().id,
        trackId: _session.selectedTrackId,
        cutId: cut.id,
        layerId: layer.id,
        frameId: frame.id,
      );
    }
    return null;
  }

  /// The project's instruction vocabulary (FI/FO/PAN …, user-editable).
  CameraInstructionSet get cameraInstructionSet =>
      _session._repository.requireProject().cameraInstructions;

  /// One undo step; no-op when unchanged.
  void updateCameraInstructionSet(CameraInstructionSet instructionSet) {
    _session._cutCommandCoordinator.updateCameraInstructionSet(instructionSet);
    _session._notifyChanged();
  }

  Command? cameraKeysCommandForRange(TimelineFrameRangeSelection selection) {
    final cut = _session.activeCutOrNull;
    final cutId = _session._editingSession.activeCutId;
    if (cut == null || cutId == null) {
      return null;
    }
    var camera = cut.camera;
    var changed = false;
    for (
      var frame = selection.startIndex;
      frame < selection.endIndexExclusive;
      frame += 1
    ) {
      if (frame < 0 || camera.keyframeAt(frame) != null) {
        continue;
      }
      // Freeze the RESOLVED pose (AE behavior): keys appear, the picture
      // does not move.
      camera = camera.withKeyframe(
        frame,
        resolveCameraPoseAt(
          camera: cut.camera,
          canvasSize: cut.canvasSize,
          frameIndex: frame,
        ),
      );
      changed = true;
    }
    if (!changed) {
      return null;
    }
    return UpdateCutCameraCommand(
      repository: _session._repository,
      cutId: cutId,
      camera: camera,
      description: 'Create camera keys',
    );
  }

  /// The camera frame's aspect — what the conte's PICTURE column is shaped
  /// by, so a cell's silhouette matches the cut's.
  double get cameraFrameAspect {
    final size = cameraFrameSize;
    return size.height <= 0 ? 16 / 9 : size.width / size.height;
  }

  /// [_cameraKeysDragPreview] as a [TransformTrack], memoized by the map's
  /// identity — the getter below is read per cell during paints, and
  /// rebuilding a SplayTreeMap track per read would be O(cells·keys).
  Map<int, CameraPose>? _cameraBlockPreviewTrackSource;

  TransformTrack? _cameraBlockPreviewTrackMemo;

  TransformTrack? get _cameraBlockPreviewTrack {
    final keys = _cameraKeysDragPreview;
    if (keys == null) {
      return null;
    }
    if (!identical(keys, _cameraBlockPreviewTrackSource)) {
      _cameraBlockPreviewTrackSource = keys;
      // The pose-facade form — the exact shape the block-ride commit lands
      // (`CutCamera(keyframes: cameraShifted)`), so the preview can never
      // promise a landing the release won't keep.
      _cameraBlockPreviewTrackMemo = TransformTrack(keyframes: keys);
    }
    return _cameraBlockPreviewTrackMemo;
  }

  /// The camera track THE DISPLAY reads — the in-flight LANE-move preview,
  /// the in-flight BLOCK-ride preview (P3b-2), or the committed track. The
  /// lane provider, the union summary markers and the row's exposure states
  /// all read THIS one answer (B4, 2026-08-17), so a camera key follows any
  /// drag live instead of jumping on release — and every reader moves in
  /// the same frame.
  TransformTrack? get activeCutCameraTrack =>
      _session._laneMove._cameraLaneTrackPreview ??
      _cameraBlockPreviewTrack ??
      _session.activeCutOrNull?.camera.track;

  /// The in-flight camera-key preview the cell resolution consults
  /// (exposureStateForLayer): the camera row's cells follow the drag
  /// without the repository moving.
  Map<int, CameraPose>? _cameraKeysDragPreview;
}
