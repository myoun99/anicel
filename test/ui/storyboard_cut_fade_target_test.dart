import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_metadata.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/export/export_plan.dart';
import 'package:anicel/src/ui/storyboard_cut_fade_policy.dart';

/// R3b: the fade is TRANSPARENCY toward the project BACKDROP — the
/// per-cut FO/WO target died with the wash (a white-out is a white
/// backdrop, or a white cut on a lower track). The bake lands on
/// [Project.backdropArgb] wherever a fade thins the frame away or a pose
/// uncovers the ground. R4 moved the fade/pose lanes onto the TRACK, so
/// the fixtures key the track and the bake looks the cut's track up
/// through the session.
void main() {
  Cut cut() => Cut(
    id: const CutId('fade-cut'),
    name: 'Fade Cut',
    duration: 12,
    canvasSize: const CanvasSize(width: 8, height: 8),
    layers: const [],
  );

  /// A session whose only cut is the 8×8 fixture and whose TRACK carries
  /// [transformTrack] — the bake resolves the lanes through the session.
  EditorSessionManager sessionWith(
    TransformTrack transformTrack, {
    int backdropArgb = 0xFF000000,
  }) {
    final base = createDefaultProject().copyWith(backdropArgb: backdropArgb);
    return EditorSessionManager(
      initialProject: base.copyWith(
        tracks: [
          base.tracks.first.copyWith(
            cuts: [cut()],
            transformTrack: transformTrack,
          ),
        ],
      ),
    );
  }

  TransformTrack fadeOut11() => trackTransformWithCutFade(
    TransformTrack.empty(),
    startFrame: 0,
    duration: 12,
    fadeInFrames: 0,
    fadeOutFrames: 11,
  );

  test('CutMetadata carries no fade target any more — legacy keys are '
      'ignored on read, never re-written', () {
    expect(const CutMetadata.empty().toJson().containsKey('fadeTarget'), false);
    final restored = CutMetadata.fromJson({
      'note': 'kept',
      'fadeTarget': 'white',
    });
    expect(restored.note, 'kept');
    expect(restored.toJson().containsKey('fadeTarget'), false);
  });

  testWidgets('the MP4 bake fades to the project BACKDROP — black by '
      'default, and any custom floor the same way (the old WO, said as a '
      'backdrop)', (tester) async {
    await tester.runAsync(() async {
      Future<(int, int, int)> centerPixelUnder(int backdropArgb) async {
        final session = sessionWith(fadeOut11(), backdropArgb: backdropArgb);
        final image = await ExportFrameRenderer(session: session)
            .renderCompositeForVideo(
              ExportFrameTask(cut: session.requireActiveCut, frameIndex: 11),
              ExportSizeMode.canvas,
            );
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final centerOffset =
            ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
        image.dispose();
        session.dispose();
        return (
          bytes!.getUint8(centerOffset),
          bytes.getUint8(centerOffset + 1),
          bytes.getUint8(centerOffset + 2),
        );
      }

      // The final frame sits at fade 0: fully the backdrop.
      expect(await centerPixelUnder(0xFF000000), (0, 0, 0));
      expect(await centerPixelUnder(0xFFFFFFFF), (255, 255, 255));
      expect(await centerPixelUnder(0xFF102030), (0x10, 0x20, 0x30));
    });
  });

  testWidgets('the MP4 bake applies the TRACK pose (V lanes) over the '
      'output space — uncovered ground is the backdrop, and a full fade '
      'lands the whole frame there', (tester) async {
    await tester.runAsync(() async {
      Future<(int, int, int)> pixelOf(
        TransformTrack transformTrack,
        int frameIndex,
        int x,
      ) async {
        final session = sessionWith(
          transformTrack,
          backdropArgb: 0xFF102030,
        );
        final image = await ExportFrameRenderer(session: session)
            .renderCompositeForVideo(
              ExportFrameTask(
                cut: session.requireActiveCut,
                frameIndex: frameIndex,
              ),
              ExportSizeMode.canvas,
            );
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final offset = ((image.height ~/ 2) * image.width + x) * 4;
        image.dispose();
        session.dispose();
        return (
          bytes!.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }

      // Slide the finished 8×8 frame half a canvas right (center 4,4 →
      // 8,4): the uncovered left half shows the BACKDROP ground, the
      // right half the picture (compare against the unposed render rather
      // than assuming its color).
      final posed = TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 8, y: 4),
        ),
      );
      final ground = await pixelOf(posed, 0, 1);
      expect(
        ground,
        (0x10, 0x20, 0x30),
        reason: 'uncovered output = the backdrop',
      );
      final moved = await pixelOf(posed, 0, 6);
      final original = await pixelOf(TransformTrack.empty(), 0, 2);
      expect(moved, original, reason: 'the picture shifted +4 px intact');

      // Pose + full fade-out: the whole frame thins away to the backdrop
      // — the ground where the pose uncovered it, and THROUGH the picture
      // where it did not.
      final posedFaded = fadeOut11().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 8, y: 4),
        ),
      );
      expect(await pixelOf(posedFaded, 11, 1), (0x10, 0x20, 0x30));
      expect(await pixelOf(posedFaded, 11, 6), (0x10, 0x20, 0x30));
    });
  });
}
