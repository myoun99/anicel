import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The V track's Transform commits (R4: TRACK-owned lanes on the global
/// frame axis): the same command the fade handles ride, so pose keys and
/// fades share ONE history.
void main() {
  test('updateTrackTransformTrack commits one undo step and no-ops when '
      'unchanged', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutId = s.requireActiveCut.id;
    final trackId = s.trackOwningCut(cutId)!.id;
    expect(s.transformTrackForCut(cutId).isEmpty, isTrue);

    final posed = TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>.empty().withKey(
        0,
        CanvasPoint(x: 100, y: 50),
      ),
    );
    s.updateTrackTransformTrack(
      trackId,
      posed,
      description: 'Key track position',
    );
    expect(s.transformTrackForCut(cutId), posed);
    expect(s.canUndo, isTrue);

    // Committing the identical track is a no-op (no extra undo step).
    s.updateTrackTransformTrack(trackId, posed);
    s.undo();
    expect(s.transformTrackForCut(cutId).isEmpty, isTrue);
    expect(s.canUndo, isFalse);

    s.redo();
    expect(s.transformTrackForCut(cutId), posed);
  });

  test('the fade handles and pose keys edit the SAME track without '
      'clobbering each other', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutId = s.requireActiveCut.id;
    final trackId = s.trackOwningCut(cutId)!.id;

    s.setCutFade(cutId, fadeInFrames: 3, fadeOutFrames: 0);
    final faded = s.transformTrackForCut(cutId);
    expect(faded.opacity.isNotEmpty, isTrue);

    s.updateTrackTransformTrack(
      trackId,
      faded.copyWith(scale: PropertyTrack<double>.empty().withKey(0, 1.5)),
    );
    final combined = s.transformTrackForCut(cutId);
    expect(combined.opacity, faded.opacity, reason: 'fade keys survive');
    expect(combined.scale.isNotEmpty, isTrue);

    // Re-fading rewrites ONLY the cut window's opacity keys.
    s.setCutFade(cutId, fadeInFrames: 0, fadeOutFrames: 2);
    final refaded = s.transformTrackForCut(cutId);
    expect(refaded.scale.isNotEmpty, isTrue, reason: 'pose keys survive');
  });

  test('setCutFade writes into the CUT WINDOW at the track-global offset '
      'and leaves the neighbor cut\'s fade alone', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final first = s.requireActiveCut;
    s.createCut();
    final second = s.requireActiveCut;
    expect(second.id, isNot(first.id));

    s.setCutFade(first.id, fadeInFrames: 3, fadeOutFrames: 0);
    s.setCutFade(second.id, fadeInFrames: 2, fadeOutFrames: 0);

    final track = s.transformTrackForCut(first.id);
    final secondStart = s.trackGlobalFrameOf(second.id, 0);
    expect(secondStart, first.duration, reason: 'cuts abut on the axis');
    expect(track.opacity.keyAt(0)?.value, 0.0);
    expect(track.opacity.keyAt(3)?.value, 1.0);
    expect(track.opacity.keyAt(secondStart)?.value, 0.0);
    expect(track.opacity.keyAt(secondStart + 2)?.value, 1.0);

    // Clearing the second cut's fade leaves the first cut's ramp intact —
    // window-scoped rewrite, not a lane wipe.
    s.setCutFade(second.id, fadeInFrames: 0, fadeOutFrames: 0);
    final cleared = s.transformTrackForCut(first.id);
    expect(cleared.opacity.keyAt(0)?.value, 0.0);
    expect(cleared.opacity.keyAt(3)?.value, 1.0);
    expect(cleared.opacity.keyAt(secondStart), isNull);
  });

  test('activeCutCanvasPoseSample (R9-B): the fx-gated canvas-space pose '
      'the editing canvas and the scrub preview wrap with', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutId = s.requireActiveCut.id;
    final trackId = s.trackOwningCut(cutId)!.id;

    expect(s.activeCutCanvasPoseSample(), isNull, reason: 'no keys → null');

    // An UNTOUCHED Position key stores the camera-frame center; the
    // canvas-space sample must read as identity motion (R8-③ conjugation:
    // center AND anchor land on the canvas center).
    s.updateTrackTransformTrack(
      trackId,
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(
            x: s.cameraFrameSize.width / 2,
            y: s.cameraFrameSize.height / 2,
          ),
        ),
      ),
    );
    final sample = s.activeCutCanvasPoseSample();
    final canvas = s.requireActiveCut.canvasSize;
    expect(sample, isNotNull);
    expect(
      sample!.pose.center,
      CanvasPoint(x: canvas.width / 2, y: canvas.height / 2),
    );
    expect(
      sample.anchorPoint,
      CanvasPoint(x: canvas.width / 2, y: canvas.height / 2),
    );

    // The V-row fx switch gates the sample off — the editing canvas drops
    // its wrap exactly like the playback display drops the pose.
    s.toggleCutFx(cutId);
    expect(s.activeCutCanvasPoseSample(), isNull);
    s.toggleCutFx(cutId);
    expect(s.activeCutCanvasPoseSample(), isNotNull);
  });

  test('activeCutCanvasPoseSample resolves at the cut\'s GLOBAL frame — a '
      'second cut reads the track lanes at its own offset', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final first = s.requireActiveCut;
    s.createCut();
    final second = s.requireActiveCut;
    final trackId = s.trackOwningCut(second.id)!.id;
    final start = s.trackGlobalFrameOf(second.id, 0);

    final frameCenter = CanvasPoint(
      x: s.cameraFrameSize.width / 2,
      y: s.cameraFrameSize.height / 2,
    );
    // One keyframe INSIDE the second cut's window, offset +100 on x.
    s.updateTrackTransformTrack(
      trackId,
      TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          start,
          CanvasPoint(x: frameCenter.x + 100, y: frameCenter.y),
        ),
      ),
    );

    final canvas = second.canvasSize;
    final sample = s.activeCutCanvasPoseSample(frameIndex: 0);
    expect(sample, isNotNull);
    expect(
      sample!.pose.center,
      CanvasPoint(x: canvas.width / 2 + 100, y: canvas.height / 2),
      reason: 'local frame 0 = global $start — the key must be read there',
    );

    // The FIRST cut sits before the key; resolveAt clamps to the first
    // key, so it reads the same pose — but through ITS global frames.
    s.selectCut(first.id);
    expect(s.activeCutCanvasPoseSample(frameIndex: 0), isNotNull);
  });

  test('activeCutEditingFadeOpacity (R9-C): the editing canvas fade wash '
      'follows the fx switch — fx always reflects, bypass restores 1', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutId = s.requireActiveCut.id;

    expect(s.activeCutEditingFadeOpacity(), 1, reason: 'no fade keyed');

    s.setCutFade(cutId, fadeInFrames: 4, fadeOutFrames: 0);
    expect(s.activeCutEditingFadeOpacity(frameIndex: 0), 0.0);
    expect(s.activeCutEditingFadeOpacity(frameIndex: 2), closeTo(0.5, 1e-9));
    expect(s.activeCutEditingFadeOpacity(frameIndex: 4), 1.0);

    s.toggleCutFx(cutId);
    expect(
      s.activeCutEditingFadeOpacity(frameIndex: 0),
      1,
      reason: 'fx bypass lifts the wash',
    );
  });
}
