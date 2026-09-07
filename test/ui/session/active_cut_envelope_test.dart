import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/camera_pose.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
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
/// hand-written copy drops (`CutVerbs._moveActiveCut`'s ⛔ comment records
/// losing exactly the second one in one direction only).
void main() {
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
    return {
      'resizeActiveCutCanvas': (s) => s.resizeActiveCutCanvas(
        const CanvasSize(width: 640, height: 360),
        anchor: CanvasResizeAnchor.center,
      ),
      'duplicateActiveCut': (s) => s.duplicateActiveCut(),
      'deleteActiveCut': (s) => s.deleteActiveCut(),
      'updateActiveCutNote': (s) => s.updateActiveCutNote('note'),
      'renameActiveCut': (s) => s.renameActiveCut('X'),
      'createLinkedCutFromActiveCut': (s) => s.createLinkedCutFromActiveCut(),
      'setCameraKeyframeAtCurrentFrame': (s) =>
          s.setCameraKeyframeAtCurrentFrame(
            CameraPose(center: CanvasPoint(x: 10, y: 10)),
          ),
      'removeCameraKeyframeAtCurrentFrame': (s) =>
          s.removeCameraKeyframeAtCurrentFrame(),
      'clearActiveCutCamera': (s) => s.clearActiveCutCamera(),
      'updateActiveCutCameraTrack': (s) =>
          s.updateActiveCutCameraTrack(TransformTrack.empty()),
      if (layerId != null)
        'setLayerMark': (s) =>
            s.setLayerMark(layerId, const LayerMark(process: LayerProcess.key)),
      if (layerId != null)
        'updateLayerEffects': (s) => s.updateLayerEffects(layerId, const []),
      if (folderId != null) 'dissolveFolder': (s) => s.dissolveFolder(folderId),
    };
  }

  test('every active-cut verb STANDS DOWN in the gap state — no crash, no '
      'cut created or destroyed, and no notification', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.createCut();
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
    structural.renameActiveCut('renamed');
    expect(
      structural.frameRangeSelection.value,
      isNull,
      reason: 'refreshAfterCutCommand drops the band',
    );

    final quiet = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(quiet.dispose);
    final layerId = quiet.layers.first.id;
    quiet.frameRangeSelection.value = bandOn(quiet);
    quiet.setLayerMark(layerId, const LayerMark(process: LayerProcess.key));
    expect(
      quiet.frameRangeSelection.value,
      isNotNull,
      reason: 'a mark is an attribute — nothing to rebuild, nothing to drop',
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
