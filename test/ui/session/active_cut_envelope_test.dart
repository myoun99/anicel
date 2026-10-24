import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// THE ACTIVE-CUT ENVELOPE: every verb that edits the cut you are standing
/// on reads the same three steps — the active cut or nothing, the command,
/// then the refresh and the notification.
///
/// Written before the eleven hand-copied envelopes became one call
/// (`ActiveCutEdits`) so the merge has something to answer to: the gap
/// stand-down and the trailing notification are the two halves a
/// hand-written copy drops (the cut left/right verbs' ⛔ comment — gone with
/// them since F-455 — recorded losing exactly the second one in one
/// direction only).
void main() {
  /// The verbs of [verbsOn] that name a ROW and are written in the cut that
  /// holds it, whichever cut — or none — is active.
  const rowAddressed = {
    'setLayerMark',
    'updateLayerEffects',
    'updateCameraTrack',
  };

  /// What the camera's write lands: a turn of 30° keyed at frame 0.
  final turned = TransformTrack.empty().copyWith(
    rotation: PropertyTrack<double>().withKey(0, 30),
  );

  /// One entry per verb that wears the envelope, named so a failure says
  /// which one lost its guard or its notification.
  Map<String, void Function(EditorSessionManager)> verbsOn(
    EditorSessionManager session,
  ) {
    final layerId = session.layers.isEmpty ? null : session.layers.first.id;
    final folderId = session.layers
        .where((layer) => layer.kind == LayerKind.folder)
        .firstOrNull
        ?.id;
    final cameraId = session.layers
        .where((layer) => layer.kind == LayerKind.camera)
        .firstOrNull
        ?.id;
    return {
      'resizeActiveCutCanvas': (s) => s.cutVerbs.resizeActiveCutCanvas(
        const CanvasSize(width: 640, height: 360),
        anchor: CanvasResizeAnchor.center,
      ),
      'duplicateActiveCut': (s) => s.cutVerbs.duplicateActiveCut(),
      'deleteActiveCut': (s) => s.cutVerbs.deleteActiveCut(),
      'updateActiveCutNote': (s) => s.cutVerbs.updateActiveCutNote(page: 0, note: 'note'),
      'renameActiveCut': (s) => s.cutVerbs.renameActiveCut('X'),
      'createLinkedCutFromActiveCut': (s) =>
          s.cutVerbs.createLinkedCutFromActiveCut(),
      'setCameraKeyframeAtCurrentFrame': (s) =>
          s.camera.setCameraKeyframeAtCurrentFrame(
            CameraPose(center: CanvasPoint(x: 10, y: 10)),
          ),
      'removeCameraKeyframeAtCurrentFrame': (s) =>
          s.camera.removeCameraKeyframeAtCurrentFrame(),
      'clearActiveCutCamera': (s) => s.camera.clearActiveCutCamera(),
      if (cameraId != null)
        'updateCameraTrack': (s) =>
            s.camera.updateCameraTrack(cameraId, turned),
      if (layerId != null)
        'setLayerMark': (s) =>
            s.layerMarks.setLayerMark(layerId, const LayerMark(process: LayerProcess.key)),
      if (layerId != null)
        'updateLayerEffects': (s) => s.effectsAndFx.updateLayerEffects(layerId, const []),
      if (folderId != null) 'dissolveFolder': (s) => s.folders.dissolveFolder(folderId),
    };
  }

  test('every active-cut verb STANDS DOWN in the gap state — no crash, no '
      'cut created or destroyed, and no notification', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.cutVerbs.createCut();
    final track = session.repository.requireProject().tracks.first;
    final first = track.cuts[0].id;
    final gapFrame = track.cuts[0].duration + 1;
    session.repository.updateCutLeadingGap(
      cutId: track.cuts[1].id,
      leadingGapFrames: 4,
    );
    session.selectCut(first);
    session.layerStack.addLayerOfKind(LayerKind.folder);
    // Captured while a cut is live: in the gap there are no rows at all,
    // and the row-scoped verbs still have to stand down on a real id.
    final verbs = verbsOn(session);
    session.selectGlobalFrame(gapFrame);
    expect(session.activeCutId, isNull, reason: 'the fixture parks in a gap');

    for (final entry in verbs.entries) {
      // ↩️These stood down here as well, on a row of the cut captured
      // above. They are written in the cut that HOLDS the row now (I-73,
      // 2026-10-08): the storyboard's conte head stands over a gap too, and
      // its label and its fx are pressed there — the case below. The
      // camera's track joined them with I-89-Q23: a header graph's line of
      // a cut not stood in is edited there.
      if (rowAddressed.contains(entry.key)) {
        continue;
      }
      var notified = false;
      void listener() => notified = true;
      session.addListener(listener);
      entry.value(session);
      session.removeListener(listener);
      expect(
        notified,
        isFalse,
        reason: '${entry.key} notified from the gap state',
      );
      expect(
        session.repository.requireProject().tracks.first.cuts.length,
        2,
        reason: '${entry.key} changed the cut list from the gap state',
      );
      expect(session.activeCutId, isNull, reason: '${entry.key} left the gap');
    }
  });

  test('a row\'s label, its chain and its camera are written where the row '
      'IS — from the gap as well, where no cut is active', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.cutVerbs.createCut();
    final track = session.repository.requireProject().tracks.first;
    final first = track.cuts[0];
    session.repository.updateCutLeadingGap(
      cutId: track.cuts[1].id,
      leadingGapFrames: 4,
    );
    session.selectCut(first.id);
    final verbs = verbsOn(session);
    final layerId = session.layers.first.id;
    session.selectGlobalFrame(first.duration + 1);
    expect(session.activeCutId, isNull, reason: 'the fixture parks in a gap');

    expect(verbs.keys, containsAll(rowAddressed), reason: 'fixture');
    for (final name in rowAddressed) {
      var notified = false;
      void listener() => notified = true;
      session.addListener(listener);
      verbs[name]!(session);
      session.removeListener(listener);
      expect(notified, isTrue, reason: '$name did not notify');
      expect(session.activeCutId, isNull, reason: '$name left the gap');
    }
    final row = session.repository
        .requireProject()
        .tracks
        .first
        .cuts
        .first
        .layers
        .firstWhere((layer) => layer.id == layerId);
    expect(row.mark, const LayerMark(process: LayerProcess.key));
    expect(
      session.repository
          .requireProject()
          .tracks
          .first
          .cuts
          .first
          .camera
          .track
          .rotation
          .keyAt(0)
          ?.value,
      30,
      reason: 'the camera of the cut holding its row',
    );
  });

  test('the STRUCTURE envelope refreshes after the command and the QUIET '
      'one does not — the frame-range selection is the witness', () {
    TimelineFrameRangeSelection bandOn(EditorSessionManager session) =>
        TimelineFrameRangeSelection(
          layerId: session.layers.first.id,
          startIndex: 0,
          endIndexExclusive: 1,
        );

    final structural = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(structural.dispose);
    structural.frameRangeSelection.value = bandOn(structural);
    structural.cutVerbs.renameActiveCut('renamed');
    expect(
      structural.frameRangeSelection.value,
      isNull,
      reason: 'refreshAfterCutCommand drops the band',
    );

    final quiet = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(quiet.dispose);
    final layerId = quiet.layers.first.id;
    quiet.frameRangeSelection.value = bandOn(quiet);
    quiet.layerMarks.setLayerMark(layerId, const LayerMark(process: LayerProcess.key));
    expect(
      quiet.frameRangeSelection.value,
      isNotNull,
      reason: 'a mark is an attribute — nothing to rebuild, nothing to drop',
    );
  });

  // camera-key-edit-clears-the-frame-range (10-17): a key edited on a row's
  // lanes is one edit whichever row it is — the camera's or a layer's.
  test('a lane key edit leaves the frame-range selection standing, on the '
      'camera row as on a layer', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    final layerId = session.layers.first.id;
    final cameraId = session.layers
        .firstWhere((layer) => layer.kind == LayerKind.camera)
        .id;
    final band = TimelineFrameRangeSelection(
      layerId: layerId,
      startIndex: 0,
      endIndexExclusive: 1,
    );
    for (final (name, edit) in [
      ('a layer', () => session.laneVerbs.updateLayerTransformTrack(
        layerId,
        turned,
      )),
      ('the camera row', () => session.camera.updateCameraTrack(
        cameraId,
        turned,
      )),
    ]) {
      session.frameRangeSelection.value = band;
      edit();
      expect(session.frameRangeSelection.value, band, reason: name);
    }
    expect(
      session.requireActiveCut.camera.track.rotation.keyAt(0)?.value,
      30,
      reason: '⛔전제: the camera was written',
    );
  });

  test('every active-cut verb NOTIFIES once it has a cut to act on', () {
    final probe = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(probe.dispose);
    probe.layerStack.addLayerOfKind(LayerKind.folder);
    final names = verbsOn(probe).keys.toList();
    expect(names, hasLength(13));
    for (final name in names) {
      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      addTearDown(session.dispose);
      session.layerStack.addLayerOfKind(LayerKind.folder);
      expect(session.activeCutId, isNotNull, reason: '$name needs a live cut');
      var notified = false;
      void listener() => notified = true;
      session.addListener(listener);
      verbsOn(session)[name]!(session);
      session.removeListener(listener);
      expect(notified, isTrue, reason: '$name did not notify');
    }
  });
}
