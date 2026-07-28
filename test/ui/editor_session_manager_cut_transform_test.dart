import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// The V track's cut-level Transform commits (R6): the same command the
/// fade handles ride, so pose keys and fades share ONE history.
void main() {
  test('updateCutTransformTrack commits one undo step and no-ops when '
      'unchanged', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutId = s.requireActiveCut.id;
    expect(s.cutById(cutId)!.transformTrack.isEmpty, isTrue);

    final posed = TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>.empty().withKey(
        0,
        CanvasPoint(x: 100, y: 50),
      ),
    );
    s.updateCutTransformTrack(cutId, posed, description: 'Key cut position');
    expect(s.cutById(cutId)!.transformTrack, posed);
    expect(s.canUndo, isTrue);

    // Committing the identical track is a no-op (no extra undo step).
    s.updateCutTransformTrack(cutId, posed);
    s.undo();
    expect(s.cutById(cutId)!.transformTrack.isEmpty, isTrue);
    expect(s.canUndo, isFalse);

    s.redo();
    expect(s.cutById(cutId)!.transformTrack, posed);
  });

  test('the fade handles and pose keys edit the SAME track without '
      'clobbering each other', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutId = s.requireActiveCut.id;

    s.setCutFade(cutId, fadeInFrames: 3, fadeOutFrames: 0);
    final faded = s.cutById(cutId)!.transformTrack;
    expect(faded.opacity.isNotEmpty, isTrue);

    s.updateCutTransformTrack(
      cutId,
      faded.copyWith(scale: PropertyTrack<double>.empty().withKey(0, 1.5)),
    );
    final combined = s.cutById(cutId)!.transformTrack;
    expect(combined.opacity, faded.opacity, reason: 'fade keys survive');
    expect(combined.scale.isNotEmpty, isTrue);

    // Re-fading rewrites ONLY the opacity lane.
    s.setCutFade(cutId, fadeInFrames: 0, fadeOutFrames: 2);
    final refaded = s.cutById(cutId)!.transformTrack;
    expect(refaded.scale.isNotEmpty, isTrue, reason: 'pose keys survive');
  });

  test('activeCutCanvasPoseSample (R9-B): the fx-gated canvas-space cut '
      'pose the editing canvas and the scrub preview wrap with', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    final cutId = s.requireActiveCut.id;

    expect(s.activeCutCanvasPoseSample(), isNull, reason: 'no keys → null');

    // An UNTOUCHED Position key stores the camera-frame center; the
    // canvas-space sample must read as identity motion (R8-③ conjugation:
    // center AND anchor land on the canvas center).
    s.updateCutTransformTrack(
      cutId,
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
